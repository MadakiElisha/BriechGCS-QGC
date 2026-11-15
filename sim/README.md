# sim: test rig

Level 1 of the simulation plan: fake devices and a stand-in QGC, so the
broker, the coordinator and the QGC fleet layer can be built before any
real hardware or model exists.

| Script | What it is |
|---|---|
| `fake_fleet.py` | A fake tower and edge computer. Publishes `edge.status` (retained, with an offline last will), `asset.state` (retained) and `detection` from a scenario file. Every message is checked against `schemas/` before sending. |
| `probe.py` | A stand-in QGC client. Connects to `/ws/v1/operator` with the operator token, sends `hello`, prints the `snapshot` and one line per message after it, and flags any message that breaks its schema. `--vehicles N` also reports N fake drones every second. |
| `scenarios/*.yaml` | Scenario files: the source id, its position, and the objects it sees with start point and velocity. |

Run with the ground-core virtualenv (`make -C ops setup` makes it):

```sh
make -C ops broker
make -C ops coordinator                              # terminal 1
make -C ops publisher                                # terminal 2
make -C ops probe                                    # terminal 3
make -C ops probe PROBE_ARGS="--vehicles 3"          # also report fake drones
make -C ops publisher SCENARIO=other.yaml
```

## Handoff check 2

1. The probe prints a `snapshot`, then `object.update` lines (and an
   `asset.state` every 2 s and a `heartbeat` every 2 s).
2. Find the publisher and `kill -9` it. The probe prints
   `asset.state tower-01 link=offline` at once, and the broker keeps the
   retained offline status:

   ```sh
   kill -9 "$(pgrep -f fake_fleet.py)"
   ```

## Simulated PX4 drones (level 2, spike S5)

`px4-sitl.sh` starts N PX4 SIH drones in Docker (the image the app's
simulation button uses), system ids 1..N, homes about 33 m apart, all sending
MAVLink to UDP 14550 on this machine:

```sh
sim/px4-sitl.sh up 3       # drones 1, 2, 3
sim/px4-sitl.sh up 10      # the ten-drone fleet (spike S5; make -C ops sim-10)
FIRST_ID=3 sim/px4-sitl.sh up 8   # drones 3..10, next to two already running
sim/px4-sitl.sh status
sim/px4-sitl.sh down
```

On Windows run it from Git Bash. The script sets `MSYS_NO_PATHCONV=1`
itself: without it Git Bash turned `--entrypoint /bin/sh` into a Windows path
and no container started.

QGC needs nothing extra: its default auto-connect UDP 14550 link picks up
every system id. Tried on 2026-11-04 (macOS, Docker Desktop 29.x): three
drones appeared in QGC within 13 s. Stop the app's own single simulator
(`briech-px4-sitl`, system id 250) first, or it shows as a fourth vehicle.

Fly them (simulation only): `fly_mission.py` uploads a mission to each
drone (take off, a 150 m square, return to launch; each square turned 120
degrees and 10 m higher than the last), arms them, starts them and watches
until all have landed:

```sh
ground-core/.venv/bin/pip install -r sim/requirements.txt   # once
ground-core/.venv/bin/python sim/fly_mission.py
ground-core/.venv/bin/python sim/fly_mission.py --vehicles 2 --size 300 --watch 60
```

It talks to the drones on UDP 14540 (PX4's onboard port), so QGC on 14550
stays connected and shows the flights. If a drone reports `Preflight Fail`
for baro, compass or battery after a cold start of several simulators, its
simulated sensors timed out: `docker restart briech-sitl-<n>` fixes it.

To check QGC's attitude displays (the Fleet 3D view and the attitude
indicators) against a known attitude, `attitude_check.py` takes one drone up
and holds it at roll -20, pitch +12 and then a 90-degree right turn in
OFFBOARD, before switching it to HOLD:

```sh
ground-core/.venv/bin/python sim/attitude_check.py --vehicle 3
```

On Windows the virtualenv's Python is `ground-core/.venv/Scripts/python`.
`--vehicles` picks drones, so drones you did not start can stay on the ground
(`--vehicles 3,4,5,6,7,8,9,10`). The script refuses a drone that is already
armed.

### Ten drones (spike S5), 2026-11-10

Windows 11, 16 logical cores, 16 GB, Docker Desktop (WSL 2 VM with 3.8 GB),
BriechUAS Release build, broker, coordinator and fake tower running.

- Ten SIH drones ran on one machine: two started by hand
  (`tools/simulation/run-px4-sitl-docker.sh`, ids 1 and 2) and eight with
  `FIRST_ID=3 sim/px4-sitl.sh up 8`. All ten appeared in QGC within a few
  seconds on the default UDP 14550 link.
- Each container used about 40 MB and 27% of one core at idle.
- `fly_mission.py --vehicles 3,...,10` flew eight 150 m squares at 30 to
  100 m, returned and landed them all.
- After a `commander land`, three of eight drones refused to arm again
  ("Resolve system health failures first", the `system` arming check).
  `docker restart briech-sitl-<n>` cleared it. Check first with
  `docker exec briech-sitl-<n> sh -c 'cd /root/.local/share/px4/rootfs && /opt/px4/bin/px4-commander check'`.
- MAVSDK was not tried: `fly_mission.py` (pymavlink) covers what we need.

QGC with the ten drones (main-thread stall meter, Release): see
`briech-docs/spikes.md`, S2.

## Sample waypoints

`sample-waypoints.kml` is a set of sample waypoints exported from QGC (KML,
UTF-16). It was at the repository root as `wps (1).kml` and moved here
(handoff section 12, P0). Kept as sample data for simulation tests.
