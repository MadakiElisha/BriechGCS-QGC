#!/usr/bin/env python3
"""Fake edge computer and tower adapter: publishes what a real tower would, from a scenario file.

    python sim/fake_fleet.py --scenario sim/scenarios/tower-walk.yaml \
        --ca ops/certs/ca.crt --password-file ops/secrets/mqtt/tower-01.password

Publishes, as the scenario's source id (which is also the MQTT login):

* edge.status (retained) on briech/v1/edge/<id>/status, with an offline
  edge.status as the MQTT last will, so a kill -9 leaves "offline" retained;
* asset.state (retained) on briech/v1/asset/<id>/state;
* detection on briech/v1/edge/<id>/detection for each scripted object.

Every message is checked against schemas/ before it is sent; an invalid one
stops the script, because the fake publisher is held to the same contract as
a real device. Run it with the ground-core virtualenv's Python.
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import signal
import ssl
import sys
import threading
import time
from pathlib import Path

import paho.mqtt.client as mqtt
import yaml

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "ground-core"))

from coordinator.schemas import MessageValidator, utc_now_iso  # noqa: E402

METRES_PER_DEG_LAT = 111_320.0


def topic(kind: str, source: str, leaf: str) -> str:
    return f"briech/v1/{kind}/{source}/{leaf}"


def envelope(msg_type: str, msg_id: str, source: str, data: dict) -> dict:
    return {"v": 1, "type": msg_type, "id": msg_id, "ts": utc_now_iso(), "src": source, "data": data}


def edge_status(source: str, seq: int, state: str, scenario: dict, uptime_s: float) -> dict:
    data = {"state": state}
    if state != "offline":
        data.update(model_version=scenario.get("model_version", "fake"), uptime_s=round(uptime_s, 1),
                    fps=scenario.get("fps", 10.0), queue_len=0)
    return envelope("edge.status", f"s-{source}-{seq:06d}", source, data)


def asset_state(source: str, seq: int, scenario: dict) -> dict:
    asset = scenario.get("asset", {})
    data = {"asset_id": source, "health": asset.get("health", "ok")}
    for key in ("pos", "camera_heading_deg", "mains_power", "battery_pct", "temp_c"):
        if key in asset:
            data[key] = asset[key]
    return envelope("asset.state", f"as-{source}-{seq:06d}", source, data)


def object_position(obj: dict, t: float) -> tuple[float, float]:
    """Where a scripted object is t seconds after it appears: straight line at constant velocity."""
    lat0, lon0 = obj["start"]["lat"], obj["start"]["lon"]
    v = obj.get("velocity", {})
    north = v.get("north_ms", 0.0) * t
    east = v.get("east_ms", 0.0) * t
    lat = lat0 + north / METRES_PER_DEG_LAT
    lon = lon0 + east / (METRES_PER_DEG_LAT * math.cos(math.radians(lat0)))
    return round(lat, 7), round(lon, 7)


def detection(source: str, seq: int, obj: dict, t: float) -> dict:
    lat, lon = object_position(obj, t)
    data = {
        "class": obj.get("class", "person"),
        "confidence": obj.get("confidence", 0.9),
        "track_id": obj["track_id"],
        "geo": {"lat": lat, "lon": lon, "error_m": obj.get("error_m", 6.0)},
        # A box that drifts across the frame, so it looks alive in a viewer.
        "bbox": {"x": round(0.1 + 0.8 * ((t / 60.0) % 1.0), 3), "y": 0.5, "w": 0.05, "h": 0.14},
    }
    return envelope("detection", f"d-{source}-{seq:06d}", source, data)


def load_scenario(path: Path) -> dict:
    scenario = yaml.safe_load(path.read_text())
    if not scenario.get("source"):
        raise SystemExit(f"{path}: scenario needs a source id")
    return scenario


class Publisher:
    def __init__(self, args, scenario: dict, validator: MessageValidator):
        self.source = scenario["source"]
        self.scenario = scenario
        self.validator = validator
        self.connected = threading.Event()
        self._first_connect_done = threading.Event()
        self.refused: str | None = None
        self.sent = 0

        client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                             client_id=f"fake-{self.source}", protocol=mqtt.MQTTv311)
        client.username_pw_set(self.source, Path(args.password_file).read_text().strip())
        if not args.no_tls:
            client.tls_set(ca_certs=args.ca, cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
        will = self.checked(edge_status(self.source, 0, "offline", scenario, 0))
        will["id"] = f"s-{self.source}-will"
        client.will_set(topic("edge", self.source, "status"), json.dumps(will), qos=1, retain=True)
        client.on_connect = self._on_connect
        client.on_disconnect = lambda *a: self.connected.clear()
        self.client = client

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            self.refused = str(reason_code)
        else:
            self.connected.set()
        self._first_connect_done.set()

    def checked(self, msg: dict) -> dict:
        error = self.validator.check(msg)
        if error is not None:
            raise SystemExit(f"fake_fleet built an invalid message, fix the scenario or the script: {error}")
        return msg

    def publish(self, topic_name: str, msg: dict, retain: bool = False, qos: int = 0) -> None:
        self.client.publish(topic_name, json.dumps(self.checked(msg), separators=(",", ":")), qos=qos, retain=retain)
        self.sent += 1

    def connect(self, host: str, port: int) -> None:
        self.client.connect_async(host, port, keepalive=10)
        self.client.loop_start()
        if not self._first_connect_done.wait(10):
            raise SystemExit(f"no answer from the broker at {host}:{port}")
        if self.refused:
            raise SystemExit(f"broker refused login {self.source}: {self.refused}")
        print(f"connected to {host}:{port} as {self.source}", flush=True)

    def run(self, duration_s: float) -> None:
        sc = self.scenario
        status_every = sc.get("status_every_s", 5.0)
        state_every = sc.get("state_every_s", 2.0)
        objects = sc.get("objects", [])
        seq = itertools.count(1)
        start = time.monotonic()
        next_status = next_state = 0.0
        next_det = {o["track_id"]: o.get("start_s", 0.0) for o in objects}
        stop = threading.Event()
        signal.signal(signal.SIGINT, lambda *a: stop.set())
        signal.signal(signal.SIGTERM, lambda *a: stop.set())

        while not stop.is_set():
            now = time.monotonic() - start
            if duration_s and now >= duration_s:
                break
            if self.connected.is_set():
                if now >= next_status:
                    self.publish(topic("edge", self.source, "status"),
                                 edge_status(self.source, next(seq), "online", sc, now), retain=True, qos=1)
                    next_status = now + status_every
                if now >= next_state:
                    self.publish(topic("asset", self.source, "state"), asset_state(self.source, next(seq), sc),
                                 retain=True, qos=1)
                    next_state = now + state_every
                for obj in objects:
                    tid = obj["track_id"]
                    t = now - obj.get("start_s", 0.0)
                    stop_s = obj.get("stop_s")
                    if now >= next_det[tid] and t >= 0 and (stop_s is None or now < stop_s):
                        self.publish(topic("edge", self.source, "detection"), detection(self.source, next(seq), obj, t))
                        next_det[tid] = now + obj.get("every_s", 0.5)
            stop.wait(0.05)

        # A clean stop says offline itself; only a crash leaves it to the last will.
        self.publish(topic("edge", self.source, "status"),
                     edge_status(self.source, next(seq), "offline", sc, 0), retain=True, qos=1)
        time.sleep(0.3)
        self.client.disconnect()
        self.client.loop_stop()
        print(f"stopped after {self.sent} messages", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--scenario", type=Path, default=REPO / "sim" / "scenarios" / "tower-walk.yaml")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--port", type=int, default=8883)
    ap.add_argument("--ca", default=str(REPO / "ops" / "certs" / "ca.crt"), help="CA certificate for the broker")
    ap.add_argument("--no-tls", action="store_true", help="plain MQTT, for a test broker only")
    ap.add_argument("--password-file", help="MQTT password file (default ops/secrets/mqtt/<source>.password)")
    ap.add_argument("--duration", type=float, default=0, help="seconds to run; 0 runs until stopped")
    args = ap.parse_args()

    scenario = load_scenario(args.scenario)
    if args.password_file is None:
        args.password_file = str(REPO / "ops" / "secrets" / "mqtt" / f"{scenario['source']}.password")
    validator = MessageValidator(REPO / "schemas")
    pub = Publisher(args, scenario, validator)
    pub.connect(args.host, args.port)
    pub.run(args.duration)


if __name__ == "__main__":
    main()
