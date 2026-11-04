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
sim/px4-sitl.sh status
sim/px4-sitl.sh down
```

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

Still to do for S5: run it with 10, record CPU and QGC frame rate, and drive
the drones from MAVSDK.
