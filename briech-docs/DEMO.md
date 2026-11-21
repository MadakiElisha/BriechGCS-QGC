# Release demo: the definition of done, live

A script for showing every box of the handoff's definition of done in about
20 minutes, using only what is in the repository. Record it (screen and
voice) for the release candidate. Each step says what to run, what the
audience should see, and where the proof lives if someone asks later.

Everything is simulated. Nothing here flies a real aircraft.

## Before the audience arrives (10 minutes)

On Windows, from the repo root in Git Bash (on Linux or macOS, the `make`
targets in `ops/README.md` do the same):

```sh
# 1. Broker (Docker Desktop must be running)
docker compose -f ops/docker-compose.yml up -d broker

# 2. Coordinator, in its own terminal (the default config: zone and tower at Briech home)
cd ground-core && R=../ops && \
BRIECH_MQTT_HOST=localhost BRIECH_MQTT_CA=$R/certs/ca.crt \
BRIECH_MQTT_PASSWORD_FILE=$R/secrets/mqtt/coordinator.password \
BRIECH_TLS_CERT=$R/certs/server.crt BRIECH_TLS_KEY=$R/certs/server.key \
BRIECH_OPERATOR_TOKENS_FILE=$R/secrets/operator.tokens \
BRIECH_DEVICE_TOKENS_FILE=$R/secrets/device.tokens \
.venv/Scripts/python -m coordinator

# 3. Ten simulated drones (system ids 1..10). If two drones already run as
#    ids 1 and 2 (for example the px4-1 / px4-2 containers), add only 3..10
#    instead, or two vehicles share an id: FIRST_ID=3 sim/px4-sitl.sh up 8
sim/px4-sitl.sh up 10
ground-core/.venv/Scripts/python sim/sim_check.py --ids 1-10 --port 14540   # all READY

# 4. BriechUAS (Release build), Modern UI, Fleet on
```

Close other heavy programs, and set Windows sleep to Never: a sleeping PC
stops Docker and leaves QGC's UDP link deaf (seen on 2026-11-21).

## The eleven boxes

| # | Box | Show | Audience sees | Proof on file |
|---|---|---|---|---|
| 1 | A fresh clone builds on two machines with the pinned Qt, following only BUILD.md | This PC's build, and the green **Custom Plugin Build** on `main` in GitHub Actions (Linux, from a clean runner) | Two independent builds | CI history; `briech-docs/BUILD.md`. A second human-run PC is still to be recorded. |
| 2 | `make -C ops dev-up` and `make -C ops sim-10` work | GitHub Actions: the **dev-up** job and the **sim-nightly / ten-drones** job | dev-up: snapshot, tower online, tracks. ten-drones: 10 READY, 10 armed, all landed | PR #40's runs; every push (dev-up) and every night (sim-10) |
| 3 | Ten drones, coloured by data age, QGC responsive | FLY with the ten drones; open the FLEET panel; `docker pause briech-sitl-5` for 15 s, then `docker unpause briech-sitl-5` | BRCH-5 turns amber after 3 s and grey/STALE after 10 s, then recovers; the map stays smooth | `briech-docs/spikes.md` S2 (0 stalls over 10 minutes) |
| 4 | A scripted detection becomes an alert with a snapshot and a suggested drone | `ground-core/.venv/Scripts/python sim/fake_fleet.py --scenario sim/scenarios/twenty-sightings.yaml --snapshot sim/sample-snapshot.jpg --duration 300` | 20 tracks; about 45 s in, the first **north-fence** alert, then 7 more; a "New alert" toast and a FLEET badge; click it: the alert panel with the **camera picture** and the **proposed drone** | `tests/test_scenarios.py` (8 alerts, 20 tracks); PR #39 (snapshots, SHA-256 in the audit) |
| 5 | Approve sends the command to the right vehicle; the outcome comes back and is logged; a refusal or no response is shown | Take off the proposed drone first; in the alert panel press **APPROVE (A)** and confirm | The drone flies to the alert (orbit); the panel shows APPROVED and the vehicle's status; FLEET, LOCAL AUDIT shows decision, command and outcome | Local audit file `fleet-audit.jsonl`; PR #30 |
| 6 | Hold all and Return all work with the coordinator switched off | With drones airborne, stop the coordinator (Ctrl+C); press **HOLD ALL**, then **RETURN ALL** | Every airborne drone holds, then returns; outcomes "confirmed" | `briech-docs/REGRESSION.md` C3 (audit 71 to 74, 2026-11-19); 8 of 8 on 2026-11-10 |
| 7 | With the coordinator down, the offline banner shows and flying is unaffected; with Fleet off, QGC behaves as before | Still with the coordinator stopped: point at the banner; restart it: reconnects by itself. Then DISABLE Fleet: Fleet UI gone, normal flying | Banner within about 10 s; automatic reconnect; with Fleet off, nothing of Fleet and no coordinator traffic | `briech-docs/REGRESSION.md` sections B and C |
| 8 | The 3D view follows the drone and matches QGC's indicator; without Quick 3D the 2D indicator appears | FLEET panel, **3D**; run `ground-core/.venv/Scripts/python sim/attitude_check.py --vehicle 3` | The 3D drone rolls -20, pitches +12 and turns 90 degrees right with the attitude indicator | CI: **Custom Plugin Build (no Quick 3D)**, "attitude view: 2D fallback" (PR #38) |
| 9 | Every message from every sender validates against `schemas/` in CI | GitHub Actions: **fleet-cpp** (`outgoing_messages_match_schemas`, 2,172 QGC messages) and **replay** (the whole stack) | Green checks | PRs #34 and #35 |
| 10 | Audit verify passes on a clean log and reports the first broken entry on a tampered one | FLEET page, LOCAL AUDIT, **VERIFY** | "chain OK, N entries" | Coordinator tests `test_audit.py` (tampering found); CI replay step "audit chain verifies" |
| 11 | Every P0 item in section 12 is closed | `briech-docs/UPSTREAM.md` and PR #32 | The list, all fixed | PR #32 |

## After the demo

```sh
sim/px4-sitl.sh down
docker compose -f ops/docker-compose.yml down
```

Stop the coordinator with Ctrl+C. Write the date, the build commit and
anything that went wrong into `briech-docs/REGRESSION.md`'s results table.
