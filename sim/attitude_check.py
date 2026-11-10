#!/usr/bin/env python3
"""Hold one simulated drone at known attitudes, to check QGC's attitude displays.

    python sim/attitude_check.py --vehicle 3
    python sim/attitude_check.py --vehicle 3 --on-phase "echo {phase}"

For SIMULATION ONLY (sim/px4-sitl.sh). The drone takes off to --alt metres,
switches to OFFBOARD and is held at these attitudes in turn:

    level        roll 0,    pitch 0,    heading as it was
    roll_left    roll -20,  pitch 0
    level
    pitch_up     roll 0,    pitch +12
    level
    turn_right   roll 0,    pitch 0,    heading +90
    level

then switches to HOLD. Compare the Fleet attitude view (3D and 2D) with
QGC's own attitude indicator during each phase: the left wing goes down,
the nose goes up, and the heading turns clockwise by 90 degrees (section 8
of the handoff). --on-phase runs a command (without waiting for it) in the
middle of each phase, with {phase} replaced by the phase name; use it to take
screenshots.

Talks to the drone on UDP 14540 like fly_mission.py, so QGC on 14550 stays
connected.
"""

from __future__ import annotations

import argparse
import math
import shlex
import subprocess
import sys
import time

from fly_mission import Link, command, result_name
from pymavlink.dialects.v20 import common as mavlink

PX4_OFFBOARD = 6
PX4_AUTO, PX4_AUTO_LOITER = 4, 3

PHASES = [
    ("level", 0.0, 0.0, 0.0, 3.0),
    ("roll_left", -20.0, 0.0, 0.0, 4.0),
    ("level", 0.0, 0.0, 0.0, 3.0),
    ("pitch_up", 0.0, 12.0, 0.0, 3.0),
    ("level", 0.0, 0.0, 0.0, 3.0),
    ("turn_right", 0.0, 0.0, 90.0, 6.0),
    ("level", 0.0, 0.0, 90.0, 2.0),
]


def quaternion(roll_deg: float, pitch_deg: float, yaw_deg: float) -> list[float]:
    """NED attitude (roll right-wing-down, pitch nose-up, yaw clockwise from north) as w, x, y, z."""
    r, p, y = (math.radians(a) / 2 for a in (roll_deg, pitch_deg, yaw_deg))
    cr, sr, cp, sp, cy, sy = math.cos(r), math.sin(r), math.cos(p), math.sin(p), math.cos(y), math.sin(y)
    return [cr * cp * cy + sr * sp * sy,
            sr * cp * cy - cr * sp * sy,
            cr * sp * cy + sr * cp * sy,
            cr * cp * sy - sr * sp * cy]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--vehicle", type=int, required=True, help="system id of the simulated drone")
    ap.add_argument("--port", type=int, default=14540)
    ap.add_argument("--alt", type=float, default=25.0, help="takeoff height, metres")
    ap.add_argument("--hover-thrust", type=float, default=0.5, help="collective thrust that holds height (PX4 MPC_THR_HOVER)")
    ap.add_argument("--on-phase", help="command to start in the middle of each phase; {phase} is replaced")
    args = ap.parse_args()
    sysid = args.vehicle

    link = Link(args.port)
    link.poll(3.0)
    v = link.vehicles.get(sysid)
    if v is None or v.lat is None:
        print(f"drone {sysid} not found on UDP {args.port}. Is sim/px4-sitl.sh up?")
        return 1

    if not v.armed:
        link.send(sysid, "param_set", sysid, 1, b"MIS_TAKEOFF_ALT", args.alt, mavlink.MAV_PARAM_TYPE_REAL32)
        link.poll(0.5)
        result = command(link, sysid, mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 1)
        print(f"arm -> {result_name(result)}", flush=True)
        if result != mavlink.MAV_RESULT_ACCEPTED:
            return 1
        result = command(link, sysid, mavlink.MAV_CMD_NAV_TAKEOFF, 0, 0, 0, math.nan, math.nan, math.nan, math.nan)
        print(f"takeoff -> {result_name(result)}", flush=True)
        if result != mavlink.MAV_RESULT_ACCEPTED:
            return 1
    end = time.monotonic() + 60
    while link.vehicles[sysid].alt_rel < args.alt - 2:
        link.poll(0.5)
        if time.monotonic() > end:
            print(f"did not reach {args.alt - 2:.0f} m (at {link.vehicles[sysid].alt_rel:.1f} m)")
            return 1
    print(f"at {link.vehicles[sysid].alt_rel:.1f} m", flush=True)

    att = link.wait(sysid, {"ATTITUDE"}, 3.0)
    if att is None:
        print("no ATTITUDE message")
        return 1
    yaw0 = math.degrees(att.yaw)

    started = time.monotonic()

    def setpoint(roll: float, pitch: float, yaw: float) -> None:
        thrust = min(0.9, args.hover_thrust / (math.cos(math.radians(roll)) * math.cos(math.radians(pitch))))
        link.send(sysid, "set_attitude_target", int((time.monotonic() - started) * 1000) & 0xFFFFFFFF,
                  sysid, 1, 0b00000111, quaternion(roll, pitch, yaw), 0, 0, 0, thrust)

    # PX4 accepts OFFBOARD only while setpoints are already streaming.
    for _ in range(20):
        setpoint(0, 0, yaw0)
        link.poll(0.05)
    result = command(link, sysid, mavlink.MAV_CMD_DO_SET_MODE, mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, PX4_OFFBOARD, 0)
    print(f"offboard -> {result_name(result)}", flush=True)
    if result != mavlink.MAV_RESULT_ACCEPTED:
        return 1

    try:
        for name, roll, pitch, dyaw, seconds in PHASES:
            print(f"{time.strftime('%H:%M:%S')} {name}: roll {roll:+.0f}, pitch {pitch:+.0f}, "
                  f"heading {((yaw0 + dyaw) % 360):.0f}", flush=True)
            phase_end = time.monotonic() + seconds
            hooked = False
            while time.monotonic() < phase_end:
                setpoint(roll, pitch, yaw0 + dyaw)
                link.poll(0.05)  # about 20 setpoints a second
                if args.on_phase and not hooked and time.monotonic() > phase_end - seconds / 2:
                    subprocess.Popen(shlex.split(args.on_phase.replace("{phase}", name), posix=False))
                    hooked = True
    finally:
        result = command(link, sysid, mavlink.MAV_CMD_DO_SET_MODE, mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                         PX4_AUTO, PX4_AUTO_LOITER)
        print(f"hold -> {result_name(result)}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
