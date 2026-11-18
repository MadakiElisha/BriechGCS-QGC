#!/usr/bin/env python3
"""Checks that simulated drones are up and ready, the way QGC sees them.

    python sim/sim_check.py                    # drones 1..10 (make -C ops sim-10)
    python sim/sim_check.py --ids 3-5 --timeout 120

Listens where QGC listens (UDP 14550: every drone from sim/px4-sitl.sh sends
its GCS stream there) and waits until each expected system id has sent a
HEARTBEAT from a PX4 autopilot, a position (GLOBAL_POSITION_INT with a
non-zero latitude), and reports STANDBY (ready to arm). Prints one line per
drone. Exit 0 when all are ready within --timeout, 1 otherwise.

The nightly CI job runs it after `make -C ops sim-10`, then flies all ten with
sim/fly_mission.py. QGC must not be running on the same machine (it holds
UDP 14550); use --port 14540 to listen on the drones' onboard stream instead.
"""

from __future__ import annotations

import argparse
import sys
import time

from pymavlink import mavutil


def parse_ids(text: str) -> list[int]:
    ids: list[int] = []
    for part in text.split(","):
        if "-" in part:
            first, last = (int(x) for x in part.split("-", 1))
            ids.extend(range(first, last + 1))
        elif part.strip():
            ids.append(int(part))
    return ids


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--ids", default="1-10", help="system ids, e.g. 1-10 or 3,4,5 (default 1-10)")
    ap.add_argument("--port", type=int, default=14550)
    ap.add_argument("--timeout", type=float, default=180.0, help="seconds to wait for every drone")
    args = ap.parse_args()

    expected = parse_ids(args.ids)
    link = mavutil.mavlink_connection(f"udpin:0.0.0.0:{args.port}", source_system=246, dialect="common")
    seen: dict[int, dict] = {i: {"heartbeat": False, "pos": None, "standby": False} for i in expected}

    def ready(state: dict) -> bool:
        return state["heartbeat"] and state["pos"] is not None and state["standby"]

    print(f"waiting up to {args.timeout:.0f} s for drones {args.ids} on UDP {args.port}", flush=True)
    start = time.monotonic()
    next_report = 0.0
    while time.monotonic() - start < args.timeout:
        msg = link.recv_match(type=["HEARTBEAT", "GLOBAL_POSITION_INT"], blocking=True, timeout=1)
        if msg is not None:
            sysid = msg.get_srcSystem()
            state = seen.get(sysid)
            if state is not None:
                if msg.get_type() == "HEARTBEAT" and msg.autopilot == mavutil.mavlink.MAV_AUTOPILOT_PX4:
                    state["heartbeat"] = True
                    state["standby"] = msg.system_status == mavutil.mavlink.MAV_STATE_STANDBY
                elif msg.get_type() == "GLOBAL_POSITION_INT" and msg.lat != 0:
                    state["pos"] = (msg.lat / 1e7, msg.lon / 1e7)
        if all(ready(s) for s in seen.values()):
            break
        now = time.monotonic()
        if now >= next_report:
            done = sum(ready(s) for s in seen.values())
            print(f"  {now - start:5.0f} s: {done}/{len(expected)} ready", flush=True)
            next_report = now + 15

    elapsed = time.monotonic() - start
    for sysid, state in seen.items():
        pos = f"{state['pos'][0]:.6f}, {state['pos'][1]:.6f}" if state["pos"] else "--"
        verdict = "READY" if ready(state) else "NOT READY"
        print(f"drone {sysid:3d}: heartbeat {'yes' if state['heartbeat'] else 'no ':3s}  "
              f"standby {'yes' if state['standby'] else 'no ':3s}  position {pos:24s}  {verdict}", flush=True)
    missing = [i for i, s in seen.items() if not ready(s)]
    if missing:
        print(f"FAIL: {len(missing)} of {len(expected)} not ready after {elapsed:.0f} s: {missing}")
        return 1
    print(f"PASS: all {len(expected)} drones ready after {elapsed:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
