#!/usr/bin/env python3
"""Stand-in QGC client: connects to the coordinator's operator WebSocket and prints what arrives.

    python sim/probe.py --ca ops/certs/ca.crt --token-file ops/secrets/operator.tokens

It does what FleetLink does on connect (bearer token, then hello, then reads
the snapshot) and prints one line per message after that. Every message
received is checked against schemas/ and flagged INVALID if it fails.

--vehicles N also sends a vehicle.state with N fake drones every second, the
way FleetVehicleReporter will, so a second probe started later shows them in
its snapshot.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import ssl
import sys
import time
from pathlib import Path

import aiohttp

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "ground-core"))

from coordinator.schemas import MessageValidator, utc_now_iso  # noqa: E402


def _clock(ts: str) -> str:
    return ts[11:23] if len(ts) >= 23 else ts


def describe(msg: dict) -> str:
    t, d = msg.get("type"), msg.get("data", {})
    if t == "snapshot":
        lines = [f"snapshot: {len(d['assets'])} assets, {len(d['vehicles'])} vehicles, "
                 f"{len(d['objects'])} objects, {len(d['alerts'])} alerts"]
        lines += ["  " + describe({"type": "asset.state", "data": a}) for a in d["assets"]]
        lines += [f"  vehicle {v['vehicle_id']} {v['name']} {v['mode']} last_seen={v.get('last_seen_ts')}"
                  for v in d["vehicles"]]
        lines += ["  " + describe({"type": "object.update", "data": o}) for o in d["objects"]]
        return "\n".join(lines)
    if t == "asset.state":
        return (f"asset.state {d['asset_id']} link={d.get('link', '?')} health={d.get('health', '?')} "
                f"last_seen={d.get('last_seen_ts', '-')}")
    if t == "object.update":
        p = d["pos"]
        return (f"object.update {d['object_id']} {d['class']} {d['confidence']:.2f} "
                f"{p['lat']:.6f},{p['lon']:.6f} ±{p['error_m']}m seen_by={','.join(d['seen_by'])}")
    if t == "heartbeat":
        drops = {k: v for k, v in d.get("counters", {}).items() if k.startswith("drop_") and v}
        return f"heartbeat #{d['seq']} uptime={d['uptime_s']}s clients={d.get('counters', {}).get('clients')} " \
               f"drops={drops or 'none'}"
    if t in ("alert.new", "alert.update"):
        return f"{t} {d.get('alert_id')} {d.get('status', '')} {d.get('reason', '')}".rstrip()
    return f"{t} {json.dumps(d)[:200]}"


def fake_vehicles(count: int, seq: int) -> dict:
    vehicles = []
    for i in range(1, count + 1):
        vehicles.append({
            "vehicle_id": i, "name": f"SIM-{i:02d}",
            "pos": {"lat": 6.5240 + 0.001 * i, "lon": 3.3790, "alt_rel_m": 60.0},
            "heading_deg": (seq * 5 + i * 30) % 360, "groundspeed_ms": 8.0, "battery_pct": max(0, 95 - seq // 60),
            "mode": "Hold", "armed": True, "flying": True, "link_quality_pct": 100, "can_take_task": True,
        })
    return {"vehicles": vehicles}


async def send_vehicles(ws, validator, count: int, operator: str) -> None:
    seq = 0
    while not ws.closed:
        msg = {"v": 1, "type": "vehicle.state", "id": f"vs-{operator}-{seq:06d}", "ts": utc_now_iso(),
               "src": operator, "data": fake_vehicles(count, seq)}
        assert validator.check(msg) is None, validator.check(msg)
        await ws.send_str(json.dumps(msg))
        seq += 1
        await asyncio.sleep(1.0)


async def run(args) -> int:
    validator = MessageValidator(REPO / "schemas")
    token = Path(args.token_file).read_text().split()[0] if args.token_file else args.token
    if not token:
        print("need --token-file or --token", file=sys.stderr)
        return 2
    ssl_ctx = None
    if args.url.startswith("wss://"):
        ssl_ctx = ssl.create_default_context(cafile=args.ca)

    hello = {"v": 1, "type": "hello", "id": f"h-{args.operator}-{int(time.time())}", "ts": utc_now_iso(),
             "src": args.operator, "data": {"operator_id": args.operator, "client": "probe"}}
    received = 0
    async with aiohttp.ClientSession() as session:
        try:
            ws = await session.ws_connect(args.url, headers={"Authorization": f"Bearer {token}"}, ssl=ssl_ctx)
        except aiohttp.WSServerHandshakeError as exc:
            print(f"refused: HTTP {exc.status}", file=sys.stderr)
            return 1
        except aiohttp.ClientError as exc:
            print(f"cannot connect: {exc}", file=sys.stderr)
            return 1
        print(f"connected to {args.url} as {args.operator}", flush=True)
        await ws.send_str(json.dumps(hello))
        sender = asyncio.create_task(send_vehicles(ws, validator, args.vehicles, args.operator)) if args.vehicles else None
        deadline = time.monotonic() + args.seconds if args.seconds else None
        try:
            while True:
                timeout = max(0.0, deadline - time.monotonic()) if deadline else None
                try:
                    raw = await ws.receive(timeout=timeout)
                except asyncio.TimeoutError:
                    break
                if raw.type != aiohttp.WSMsgType.TEXT:
                    print(f"closed: code {ws.close_code} {raw.extra or ''}".rstrip(), flush=True)
                    return 1
                msg = json.loads(raw.data)
                received += 1
                error = validator.check(msg)
                if msg.get("type") == "heartbeat" and args.hide_heartbeat:
                    pass
                else:
                    prefix = "INVALID " if error else ""
                    print(f"{_clock(msg.get('ts', ''))} {prefix}{describe(msg)}", flush=True)
                    if error:
                        print(f"  {error}", flush=True)
                if args.count and received >= args.count:
                    break
        finally:
            if sender:
                sender.cancel()
            await ws.close()
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--url", default="wss://localhost:8443/ws/v1/operator")
    ap.add_argument("--ca", default=str(REPO / "ops" / "certs" / "ca.crt"))
    ap.add_argument("--token-file", default=str(REPO / "ops" / "secrets" / "operator.tokens"))
    ap.add_argument("--token", help="operator token (prefer --token-file: arguments show up in ps)")
    ap.add_argument("--operator", default="op-probe")
    ap.add_argument("--vehicles", type=int, default=0, help="send a fake vehicle.state with N drones every second")
    ap.add_argument("--hide-heartbeat", action="store_true")
    ap.add_argument("--count", type=int, default=0, help="exit after N messages")
    ap.add_argument("--seconds", type=float, default=0, help="exit after N seconds")
    args = ap.parse_args()
    if args.token:
        args.token_file = None
    sys.exit(asyncio.run(run(args)))


if __name__ == "__main__":
    main()
