#!/usr/bin/env python3
"""Fly a square mission on each simulated PX4 drone: upload, arm, start, watch.

    python sim/fly_mission.py                      # every drone found, until all have landed
    python sim/fly_mission.py --vehicles 1,3 --size 200 --watch 60

For SIMULATION ONLY (sim/px4-sitl.sh). Each drone gets its own mission:
take off, a square of --size metres with one corner at its start point, then
return to launch. Drone k's square is turned k x 120 degrees and flown
--alt-step metres higher than drone k-1, so the paths separate.

How it talks to the drones: PX4 sends each drone's onboard MAVLink stream to
UDP 14540 on this machine. This script listens there, learns each drone's
return address from its packets (as QGC does on 14550), and sends to each
drone separately. QGC stays connected throughout and shows the flights.
"""

from __future__ import annotations

import argparse
import math
import socket
import sys
import time
from collections import defaultdict

from pymavlink.dialects.v20 import common as mavlink

GCS_SYSID = 245
GCS_COMPID = mavlink.MAV_COMP_ID_MISSIONPLANNER
METRES_PER_DEG = 111_320.0

# PX4 custom_mode: main mode in bits 16-23, sub mode in bits 24-31.
PX4_MAIN = {1: "MANUAL", 2: "ALTCTL", 3: "POSCTL", 4: "AUTO", 5: "ACRO", 6: "OFFBOARD", 7: "STAB"}
PX4_AUTO = {1: "READY", 2: "TAKEOFF", 3: "HOLD", 4: "MISSION", 5: "RTL", 6: "LAND", 8: "FOLLOW", 9: "PRECLAND"}


def px4_mode(custom_mode: int) -> str:
    main, sub = (custom_mode >> 16) & 0xFF, (custom_mode >> 24) & 0xFF
    if main == 4:
        return "AUTO." + PX4_AUTO.get(sub, str(sub))
    return PX4_MAIN.get(main, f"MODE{main}")


class Vehicle:
    def __init__(self, sysid: int):
        self.sysid = sysid
        self.armed = False
        self.mode = "?"
        self.lat = self.lon = None
        self.alt_rel = 0.0
        self.wp = -1
        self.landed_state = 0


class Link:
    """One UDP socket, many drones: each reply goes to the address that drone last sent from."""

    def __init__(self, port: int):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", port))
        self.sock.settimeout(0.05)
        self._parsers: dict[tuple, mavlink.MAVLink] = {}
        self.addr: dict[int, tuple] = {}
        self.vehicles: dict[int, Vehicle] = {}
        self._target = None
        self.out = mavlink.MAVLink(self, srcSystem=GCS_SYSID, srcComponent=GCS_COMPID)
        self._next_heartbeat = 0.0
        self._pending: dict[int, list] = defaultdict(list)

    def write(self, buf: bytes) -> None:  # pymavlink sends through this
        self.sock.sendto(buf, self._target)

    def send(self, sysid: int, name: str, *args) -> None:
        self._target = self.addr[sysid]
        getattr(self.out, name + "_send")(*args)

    def poll(self, seconds: float = 0.05) -> None:
        end = time.monotonic() + seconds
        while True:
            try:
                data, addr = self.sock.recvfrom(65535)
            except socket.timeout:
                data = None
            if data:
                parser = self._parsers.get(addr)
                if parser is None:
                    parser = self._parsers[addr] = mavlink.MAVLink(None)
                    parser.robust_parsing = True
                for msg in parser.parse_buffer(data) or []:
                    self._handle(msg, addr)
            now = time.monotonic()
            if now >= self._next_heartbeat:
                self._next_heartbeat = now + 1.0
                for sysid in self.addr:
                    self.send(sysid, "heartbeat", mavlink.MAV_TYPE_GCS, mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
            if now >= end:
                return

    def _handle(self, msg, addr) -> None:
        if msg.get_type() == "BAD_DATA" or msg.get_srcComponent() != 1:
            return
        sysid = msg.get_srcSystem()
        self.addr[sysid] = addr
        v = self.vehicles.setdefault(sysid, Vehicle(sysid))
        t = msg.get_type()
        if t == "HEARTBEAT" and msg.type != mavlink.MAV_TYPE_GCS:
            v.armed = bool(msg.base_mode & mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
            v.mode = px4_mode(msg.custom_mode)
        elif t == "GLOBAL_POSITION_INT":
            v.lat, v.lon, v.alt_rel = msg.lat / 1e7, msg.lon / 1e7, msg.relative_alt / 1000.0
        elif t == "MISSION_CURRENT":
            v.wp = msg.seq
        elif t == "EXTENDED_SYS_STATE":
            v.landed_state = msg.landed_state
        elif t == "STATUSTEXT":
            print(f"  drone {sysid} says: {msg.text}", flush=True)
        self._pending[sysid].append(msg)

    def wait(self, sysid: int, types: set[str], timeout: float, match=lambda m: True):
        """The next message of one of these types from this drone, or None."""
        self._pending[sysid].clear()
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            self.poll(0.05)
            for msg in self._pending[sysid]:
                if msg.get_type() in types and match(msg):
                    self._pending[sysid].clear()
                    return msg
            self._pending[sysid].clear()
        return None


def offset(lat: float, lon: float, north_m: float, east_m: float) -> tuple[float, float]:
    return (lat + north_m / METRES_PER_DEG,
            lon + east_m / (METRES_PER_DEG * math.cos(math.radians(lat))))


def build_mission(lat: float, lon: float, alt: float, size: float, turn_deg: float) -> list[tuple]:
    """(command, lat, lon, alt) items: takeoff, three far corners of a square, back over start, RTL."""
    c, s = math.cos(math.radians(turn_deg)), math.sin(math.radians(turn_deg))
    corners = [(size, 0.0), (size, size), (0.0, size), (0.0, 0.0)]
    items = [(mavlink.MAV_CMD_NAV_TAKEOFF, lat, lon, alt)]
    for n, e in corners:
        wlat, wlon = offset(lat, lon, n * c - e * s, n * s + e * c)
        items.append((mavlink.MAV_CMD_NAV_WAYPOINT, wlat, wlon, alt))
    items.append((mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH, 0.0, 0.0, 0.0))
    return items


def upload(link: Link, sysid: int, items: list[tuple]) -> None:
    link.send(sysid, "mission_count", sysid, 1, len(items), mavlink.MAV_MISSION_TYPE_MISSION)
    retries = 0
    while True:
        msg = link.wait(sysid, {"MISSION_REQUEST_INT", "MISSION_REQUEST", "MISSION_ACK"}, 2.0)
        if msg is None:
            retries += 1
            if retries > 3:
                raise RuntimeError("no answer to the mission upload")
            link.send(sysid, "mission_count", sysid, 1, len(items), mavlink.MAV_MISSION_TYPE_MISSION)
            continue
        if msg.get_type() == "MISSION_ACK":
            if msg.type != mavlink.MAV_MISSION_ACCEPTED:
                raise RuntimeError(f"drone {sysid} refused the mission: {mavlink.enums['MAV_MISSION_RESULT'][msg.type].name}")
            return
        cmd, lat, lon, alt = items[msg.seq]
        # Commands without a position (RTL) go in the mission frame, as QGC sends them; PX4 refuses them otherwise.
        frame = (mavlink.MAV_FRAME_MISSION if cmd == mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH
                 else mavlink.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT)
        link.send(sysid, "mission_item_int", sysid, 1, msg.seq, frame,
                  cmd, 0, 1, 0, 0, 0, float("nan"), int(lat * 1e7), int(lon * 1e7), alt,
                  mavlink.MAV_MISSION_TYPE_MISSION)


def command(link: Link, sysid: int, cmd: int, *params: float) -> int:
    p = list(params) + [0.0] * (7 - len(params))
    for attempt in range(3):
        link.send(sysid, "command_long", sysid, 1, cmd, attempt, *p)
        ack = link.wait(sysid, {"COMMAND_ACK"}, 2.0, lambda m: m.command == cmd)
        if ack is not None:
            return ack.result
    return -1


def result_name(result: int) -> str:
    return "NO ANSWER" if result < 0 else mavlink.enums["MAV_RESULT"][result].name


def status_line(link: Link, ids: list[int], counts: dict[int, int]) -> str:
    parts = []
    for i in ids:
        v = link.vehicles[i]
        wp = f"wp {v.wp + 1}/{counts[i]}" if v.wp >= 0 else "wp -"
        parts.append(f"drone {i}: {v.mode:<13} {'ARMED' if v.armed else 'disarmed':<8} alt {v.alt_rel:5.1f} m {wp}")
    return " | ".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--port", type=int, default=14540)
    ap.add_argument("--vehicles", help="system ids, e.g. 1,2,3 (default: every drone found)")
    ap.add_argument("--size", type=float, default=150.0, help="side of the square, metres")
    ap.add_argument("--alt", type=float, default=30.0, help="first drone's height above takeoff, metres")
    ap.add_argument("--alt-step", type=float, default=10.0)
    ap.add_argument("--watch", type=float, default=0, help="seconds to watch; 0 watches until all have landed")
    ap.add_argument("--no-start", action="store_true", help="upload only; do not arm or start")
    args = ap.parse_args()

    link = Link(args.port)
    print(f"listening on UDP {args.port} for drones...", flush=True)
    link.poll(3.0)
    found = sorted(s for s, v in link.vehicles.items() if v.lat is not None)
    ids = [int(x) for x in args.vehicles.split(",")] if args.vehicles else found
    missing = [i for i in ids if i not in found]
    if not ids or missing:
        print(f"drones with a position: {found or 'none'}; missing: {missing or 'none'}. Is sim/px4-sitl.sh up?")
        return 1

    counts = {}
    for k, sysid in enumerate(ids):
        v = link.vehicles[sysid]
        if v.armed:
            print(f"drone {sysid} is already armed ({v.mode}); leaving it alone")
            return 1
        alt = args.alt + k * args.alt_step
        items = build_mission(v.lat, v.lon, alt, args.size, k * 120.0)
        upload(link, sysid, items)
        counts[sysid] = len(items)
        print(f"drone {sysid}: mission uploaded ({len(items)} items, {args.size:.0f} m square at {alt:.0f} m, "
              f"turned {k * 120} deg)", flush=True)

    if args.no_start:
        return 0

    for sysid in ids:
        result = command(link, sysid, mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 1)
        print(f"drone {sysid}: arm -> {result_name(result)}", flush=True)
        if result != mavlink.MAV_RESULT_ACCEPTED:
            return 1
        result = command(link, sysid, mavlink.MAV_CMD_MISSION_START, 0, 0)
        print(f"drone {sysid}: mission start -> {result_name(result)}", flush=True)
        if result != mavlink.MAV_RESULT_ACCEPTED:
            return 1

    started = time.monotonic()
    next_print = 0.0
    airborne_seen = False
    while True:
        link.poll(0.2)
        now = time.monotonic()
        if any(link.vehicles[i].armed for i in ids):
            airborne_seen = True
        if now >= next_print:
            print(status_line(link, ids, counts), flush=True)
            next_print = now + 5.0
        if args.watch and now - started >= args.watch:
            print("stopped watching; the drones carry on and land at home when done", flush=True)
            return 0
        if airborne_seen and now - started > 10 and not any(link.vehicles[i].armed for i in ids):
            print(status_line(link, ids, counts))
            print("all drones have landed and disarmed", flush=True)
            return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nstopped watching; the drones carry on with their missions")
