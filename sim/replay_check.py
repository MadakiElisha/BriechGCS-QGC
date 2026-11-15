#!/usr/bin/env python3
"""Scenario replay against the real stack: broker, coordinator, fake tower, operator client.

    python sim/replay_check.py --url wss://localhost:8444/ws/v1/operator \\
        --admin-token-file <file>          # optional: also check the audit chain

Needs a running broker and coordinator (ops/scripts/replay-check.sh starts
both, and is what CI runs). This script starts the fake tower itself
(sim/fake_fleet.py, sim/scenarios/tower-walk.yaml) so it controls when the
tower appears and when it is killed, then checks, each with a time limit:

  1. a new operator gets a snapshot first
  2. tower-01 comes online (asset.state link=online)
  3. its detections arrive as object.update tracks
  4. a person walking into north-fence raises exactly one alert.new
  5. an approval (operator.action, as QGC sends it) comes back as alert.update approved
  6. a second operator's snapshot shows the reported vehicles and the approved alert
  7. kill -9 of the tower: asset.state link=offline (the broker's last will)
  8. no drop counter in the heartbeat moved, except the expected rate limit
  9. GET /api/v1/audit/verify: the hash chain is intact (with --admin-token-file)

Every message received is checked against schemas/; one invalid message fails
the run. Exit 0 when every step passes.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import ssl
import subprocess
import sys
import time
from pathlib import Path

import aiohttp

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "ground-core"))
sys.path.insert(0, str(REPO / "sim"))

from coordinator.schemas import MessageValidator, utc_now_iso  # noqa: E402
from probe import fake_vehicles  # noqa: E402

ZONE = "north-fence"
TOWER = "tower-01"
# Expected: the coordinator replaces object updates above 2 per second per track.
ALLOWED_DROPS = {"drop_rate_object"}


class Operator:
    """One operator WebSocket, collecting every message with its arrival time."""

    def __init__(self, name: str, args, validator: MessageValidator, session: aiohttp.ClientSession):
        self.name, self.args, self.validator, self.session = name, args, validator, session
        self.messages: list[tuple[float, dict]] = []
        self.invalid: list[str] = []
        self.ws = None
        self._reader = None

    async def connect(self, token: str, ssl_ctx) -> None:
        self.ws = await self.session.ws_connect(self.args.url, headers={"Authorization": f"Bearer {token}"},
                                                ssl=ssl_ctx, heartbeat=None)
        await self.send("hello", {"operator_id": self.name, "client": "probe", "client_version": "replay-check"})
        self._reader = asyncio.create_task(self._read())

    async def send(self, msg_type: str, data: dict) -> None:
        msg = {"v": 1, "type": msg_type, "id": f"{self.name}-{msg_type}-{time.monotonic_ns()}",
               "ts": utc_now_iso(), "src": f"qgc-{self.name}", "data": data}
        error = self.validator.check(msg)
        assert error is None, f"replay_check built an invalid message: {error}"
        await self.ws.send_str(json.dumps(msg))

    async def _read(self) -> None:
        async for raw in self.ws:
            if raw.type != aiohttp.WSMsgType.TEXT:
                break
            msg = json.loads(raw.data)
            if (error := self.validator.check(msg)) is not None:
                self.invalid.append(error)
            self.messages.append((time.monotonic(), msg))

    def find(self, pred, since: float = 0.0) -> list[dict]:
        return [m for t, m in self.messages if t >= since and pred(m)]

    async def wait_for(self, pred, timeout: float, since: float = 0.0) -> dict | None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if found := self.find(pred, since):
                return found[0]
            if self.ws.closed:
                return None
            await asyncio.sleep(0.1)
        return None

    async def close(self) -> None:
        if self.ws is not None:
            await self.ws.close()
        if self._reader is not None:
            self._reader.cancel()


def is_type(t: str, **fields):
    return lambda m: m.get("type") == t and all(m["data"].get(k) == v for k, v in fields.items())


class Report:
    def __init__(self):
        self.failed = 0

    def step(self, ok: bool, text: str, detail: str = "") -> bool:
        print(f"{'PASS' if ok else 'FAIL'}  {text}" + (f"  ({detail})" if detail else ""), flush=True)
        self.failed += 0 if ok else 1
        return ok


async def run(args) -> int:
    validator = MessageValidator(REPO / "schemas")
    token = Path(args.token_file).read_text().split()[0]
    ssl_ctx = ssl.create_default_context(cafile=args.ca)
    report = Report()
    publisher = None
    log = open(args.publisher_log, "w") if args.publisher_log else subprocess.DEVNULL

    async with aiohttp.ClientSession() as session:
        first = Operator("op-replay", args, validator, session)
        second = Operator("op-replay-2", args, validator, session)
        try:
            # 1. snapshot first
            await first.connect(token, ssl_ctx)
            snap = await first.wait_for(lambda m: True, 10)
            report.step(snap is not None and snap["type"] == "snapshot", "operator gets a snapshot first",
                        snap and snap["type"])

            # The fake tower, started here so the times below are ours.
            started = time.monotonic()
            publisher = subprocess.Popen(
                [sys.executable, "-u", str(REPO / "sim" / "fake_fleet.py"), "--scenario", str(args.scenario),
                 "--host", args.mqtt_host, "--ca", args.ca],
                stdout=log, stderr=subprocess.STDOUT)

            # 2. tower online
            online = await first.wait_for(is_type("asset.state", asset_id=TOWER, link="online"), 20, started)
            report.step(online is not None, f"{TOWER} comes online", f"after {time.monotonic() - started:.1f} s")

            # 3. tracks
            track = await first.wait_for(lambda m: m["type"] == "object.update" and TOWER in m["data"]["seen_by"],
                                         20, started)
            report.step(track is not None, "detections arrive as object.update",
                        track and track["data"]["object_id"])

            # 4. one alert for the zone
            alert = await first.wait_for(is_type("alert.new", zone_id=ZONE), args.alert_timeout, started)
            report.step(alert is not None, f"a person in {ZONE} raises an alert",
                        alert and f"{alert['data']['alert_id']} after {time.monotonic() - started:.1f} s")
            if alert is None:
                return finish(report, first, second)
            alert_id = alert["data"]["alert_id"]

            # 5. QGC reports its vehicles and approves; the coordinator answers.
            await first.send("vehicle.state", fake_vehicles(3, 0))
            approved_at = time.monotonic()
            await first.send("operator.action", {
                "action_id": f"act-{alert_id}-1", "operator_id": "op-replay", "phase": "decision",
                "alert_id": alert_id, "decision": "approve", "vehicle_id": 1, "command": "goto"})
            update = await first.wait_for(is_type("alert.update", alert_id=alert_id, status="approved"), 10,
                                          approved_at)
            report.step(update is not None, "approval comes back as alert.update approved",
                        update and f"operator {update['data'].get('operator_id')}")

            # 6. a second operator sees the same picture
            await second.connect(token, ssl_ctx)
            snap2 = await second.wait_for(lambda m: m["type"] == "snapshot", 10)
            vehicles = sorted(v["vehicle_id"] for v in snap2["data"]["vehicles"]) if snap2 else []
            snap_alert = next((a for a in snap2["data"]["alerts"] if a["alert_id"] == alert_id), None) if snap2 else None
            report.step(vehicles == [1, 2, 3] and snap_alert is not None and snap_alert["status"] == "approved",
                        "a second operator's snapshot has the vehicles and the approved alert",
                        f"vehicles {vehicles}, alert {snap_alert and snap_alert['status']}")

            # 4b. still exactly one alert for the zone (not one per sighting)
            await asyncio.sleep(args.settle)
            news = first.find(is_type("alert.new", zone_id=ZONE), started)
            report.step(len(news) == 1, f"exactly one alert.new for {ZONE}", f"{len(news)} received")

            # 7. kill -9 the tower: the broker's last will marks it offline
            killed = time.monotonic()
            publisher.kill()
            publisher.wait(10)
            offline = await first.wait_for(is_type("asset.state", asset_id=TOWER, link="offline"), 20, killed)
            report.step(offline is not None, f"kill -9 of {TOWER}: asset.state link=offline",
                        f"after {time.monotonic() - killed:.1f} s" if offline else "")

            # 8. drop counters, from a heartbeat sent after everything above
            beat = await first.wait_for(lambda m: m["type"] == "heartbeat", 10, time.monotonic())
            counters = beat["data"].get("counters", {}) if beat else {}
            drops = {k: v for k, v in counters.items() if k.startswith("drop_") and v and k not in ALLOWED_DROPS}
            report.step(beat is not None and not drops, "no unexpected drops in the heartbeat counters",
                        f"{drops}" if drops else f"mqtt_in={counters.get('mqtt_in')}, "
                        f"allowed {ALLOWED_DROPS & set(counters)}")

            # 9. the audit chain
            if args.admin_token_file:
                admin = Path(args.admin_token_file).read_text().split()[0]
                base = args.url.replace("wss://", "https://").split("/ws/")[0]
                async with session.get(f"{base}/api/v1/audit/verify", ssl=ssl_ctx,
                                       headers={"Authorization": f"Bearer {admin}"}) as resp:
                    result = await resp.json()
                report.step(resp.status == 200 and result.get("ok") is True and result.get("entries", 0) >= 1,
                            "audit chain verifies", f"HTTP {resp.status}, {result}")

            # Every message, both operators
            invalid = first.invalid + second.invalid
            report.step(not invalid, "every message received is valid against schemas/",
                        f"{len(first.messages) + len(second.messages)} messages"
                        + (f"; first problem: {invalid[0]}" if invalid else ""))
        except aiohttp.ClientError as exc:
            report.step(False, "operator connection", str(exc))
        finally:
            if publisher is not None and publisher.poll() is None:
                publisher.kill()
                publisher.wait(10)
            await first.close()
            await second.close()
    return finish(report, first, second)


def finish(report: Report, *operators: Operator) -> int:
    if report.failed:
        print(f"\n{report.failed} step(s) failed. Last messages the first operator received:")
        for _, m in operators[0].messages[-8:]:
            print(f"  {m.get('type')} {json.dumps(m.get('data'))[:160]}")
        return 1
    print("\nscenario replay passed")
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--url", default="wss://localhost:8444/ws/v1/operator")
    ap.add_argument("--ca", default=str(REPO / "ops" / "certs" / "ca.crt"))
    ap.add_argument("--token-file", default=str(REPO / "ops" / "secrets" / "operator.tokens"))
    ap.add_argument("--admin-token-file", help="admin token for GET /api/v1/audit/verify (step 9)")
    ap.add_argument("--mqtt-host", default="localhost")
    ap.add_argument("--scenario", type=Path, default=REPO / "sim" / "scenarios" / "tower-walk.yaml")
    ap.add_argument("--alert-timeout", type=float, default=60, help="seconds for the zone alert (about 20 s expected)")
    ap.add_argument("--settle", type=float, default=5, help="seconds to watch for duplicate alerts")
    ap.add_argument("--publisher-log", help="file for the fake tower's output")
    sys.exit(asyncio.run(run(ap.parse_args())))


if __name__ == "__main__":
    main()
