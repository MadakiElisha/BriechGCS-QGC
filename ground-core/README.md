# Coordinator (ground-core)

Python service between the MQTT broker and QGC. It checks every message
against `schemas/`, keeps the last state of every asset and vehicle, turns
detections into objects, and pushes changes to every connected QGC over one
WebSocket each.

## Run it

From the repo root (needs Python 3.10+ and Docker for the broker):

```sh
make -C ops setup        # virtualenv, dev CA and certificate, MQTT logins, tokens
make -C ops broker       # Mosquitto on mqtts://localhost:8883
make -C ops coordinator  # this service, wss://localhost:8443/ws/v1/operator
make -C ops publisher    # fake tower-01 (another terminal)
make -C ops probe        # stand-in QGC client (another terminal)
make -C ops test         # schema checks and unit tests
```

## What is built

| Piece | File |
|---|---|
| Settings from environment variables; secrets from `NAME` or `NAME_FILE` | `coordinator/config.py` |
| Message checks against `schemas/` | `coordinator/schemas.py` |
| MQTT in over TLS; drops by reason: `size`, `json`, `topic`, `schema`, `type`, `src` | `coordinator/bus.py` |
| Fixed assets from `config/assets.yaml`; last state, link (online/offline from edge.status, the last will, and 15 s of silence), last-seen per source; vehicles from QGC | `coordinator/registry.py` |
| Detections to objects: constant-velocity filter per object, gating, cross-tower merge, lost after 10 s and removed after 60 s, capped at 500 | `coordinator/fusion.py` |
| Distances and point-in-polygon in metres around a point | `coordinator/geo.py` |
| Watch zones from `config/zones.yaml` | `coordinator/zones.py` |
| One alert per (object, zone) while it is open; decisions; expiry after 120 s; capped at 100 | `coordinator/alerts.py` |
| Which drone to send: rule-based, never one that would land below the 30 % reserve | `coordinator/suggest.py` |
| Hash-chained audit log in SQLite | `coordinator/audit.py` |
| Saved objects and alerts in SQLite, restored on start | `coordinator/store.py` |
| Routing, fan-out, outgoing schema check, 2 s heartbeat with drop counters, `object.update` at most 2/s per object, a 0.1 s ticker for expiry, silence and saving | `coordinator/app.py` |
| `/ws/v1/operator` (token, then hello, then snapshot, then changes; bounded queue per client), snapshot upload and download, zones, audit, `/healthz` | `coordinator/api_operator.py` |

**Before the handover to Miracle, change nothing in `bus.py`,
`schemas.py` or `schemas/` without asking**: the guarantees in section 10 of
the handoff depend on them.

## Handoff rows (lead's coordinator work)

| # | Piece | Status | Checked by |
|---|---|---|---|
| 1 | Tests, one file per module | done, run in CI | `tests/` |
| 2 | Heartbeat and staleness | done: heartbeat every 2 s; a source silent for 15 s is marked `link=offline` and broadcast, and comes back `online` when heard | `test_app.py::test_silent_tower_goes_offline_and_comes_back` |
| 3 | `object.update` at most 2/s per object | done: a newer update replaces the held one (counted as `drop_rate_object`) and is sent when the 0.5 s is up | `test_scenarios.py::test_object_updates_never_exceed_two_per_second` |
| 4 | Fusion with a constant-velocity filter and gating | done: gate is `max(10 m, 3 sigma)` on the predicted position; a camera never merges its own two tracks | `test_fusion.py`, `test_scenarios.py::test_two_towers_one_person_one_object` |
| 5 | Zones and alerts | done; `GET /api/v1/zones`. Late detections never raise an alert. An approved alert is `resolved` once its object has been outside the zone for 30 s or its track is lost, so a return raises a new alert | `test_alerts.py`, `test_zones.py`, `test_scenarios.py::test_walk_into_zone_raises_one_alert_within_a_second` |
| 6 | Suggestions | done: proposal and alternatives on `alert.new`; a drone needs a position, battery, a report under 10 s old, and `can_take_task` not false | `test_suggest.py` |
| 7 | Audit log, `GET /api/v1/audit/verify` | done: `alert.new`, `alert.update` and every `operator.action` are chained | `test_audit.py` |
| 8 | Persistence | done: objects and alerts saved every 2 s when changed, and on shutdown; vehicles come back from QGC within a second, assets from retained MQTT | `test_scenarios.py::test_restart_keeps_tracks_and_alerts` |

Set `BRIECH_DATA_DIR=memory` to run without the audit log and saved state
(the audit endpoints then answer 503).

## Settings

| Variable | Default | |
|---|---|---|
| `BRIECH_MQTT_HOST`, `BRIECH_MQTT_PORT` | `localhost`, `8883` | |
| `BRIECH_MQTT_CA` | system store | CA that signed the broker certificate |
| `BRIECH_MQTT_USERNAME` | `coordinator` | |
| `BRIECH_MQTT_PASSWORD[_FILE]` | | |
| `BRIECH_MQTT_TLS` | `true` | `false` only for a throwaway test broker |
| `BRIECH_HTTP_HOST`, `BRIECH_HTTP_PORT` | `0.0.0.0`, `8443` | |
| `BRIECH_TLS_CERT`, `BRIECH_TLS_KEY` | unset: plain ws:// with a warning | |
| `BRIECH_OPERATOR_TOKENS[_FILE]` | none: QGC cannot connect | comma or newline separated |
| `BRIECH_DEVICE_TOKENS[_FILE]` | none | `device-id=token` per line, for snapshot uploads |
| `BRIECH_ASSETS_FILE` | `config/assets.yaml` | |
| `BRIECH_SCHEMA_DIR` | `../schemas` | |
| `BRIECH_SNAPSHOT_DIR` | `var/snapshots` | |
| `BRIECH_CLIENT_QUEUE_SIZE` | `500` | per QGC client; oldest dropped and counted |
| `BRIECH_HEARTBEAT_S` | `2` | |
| `BRIECH_ZONES_FILE` | `config/zones.yaml` | missing file: no zones, no alerts |
| `BRIECH_DATA_DIR` | `var` | `audit.sqlite` and `state.sqlite`; `memory` keeps nothing |
| `BRIECH_ADMIN_TOKENS[_FILE]` | none: audit endpoints refuse everyone | separate from operator tokens |
| `BRIECH_ASSET_SILENT_S` | `15` | silence before a source is marked offline |

## Endpoints

| Endpoint | Auth | |
|---|---|---|
| `GET /ws/v1/operator` | `Authorization: Bearer <operator token>`, checked before the upgrade (401) | First message must be `hello` (close 4400; 4408 if none within 5 s). Then `snapshot`, then `asset.state`, `object.update`, `alert.new`, `alert.update`, `heartbeat`. Accepts `vehicle.state` and `operator.action`. |
| `POST /api/v1/snapshots` | device token | One JPEG (`image/jpeg`), at most 300 KB. Returns `201 {"snapshot_id": "snap-…"}` |
| `GET /api/v1/snapshots/{id}` | operator token | The JPEG |
| `GET /api/v1/zones` | operator token | `{"zones": [...]}` |
| `GET /api/v1/audit?after=N&limit=M` | admin token | Audit entries after sequence `N` |
| `GET /api/v1/audit/verify` | admin token | `200 {"ok": true, "entries": n, "first_broken": null}`, or `409` with the first broken sequence |
| `GET /healthz` | none | `ok` |
