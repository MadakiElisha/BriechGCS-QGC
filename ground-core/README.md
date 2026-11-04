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
| Fixed assets from `config/assets.yaml`; last state, link (online/offline from edge.status and the last will), last-seen per source; vehicles from QGC | `coordinator/registry.py` |
| Detections to objects: pass-through, one object per (source, track id), capped at 500 | `coordinator/fusion.py` |
| Routing, fan-out, outgoing schema check, 2 s heartbeat with drop counters | `coordinator/app.py` |
| `/ws/v1/operator` (token, then hello, then snapshot, then changes; bounded queue per client), snapshot upload and download, `/healthz` | `coordinator/api_operator.py` |

**Before the handover to Miracle, change nothing in `bus.py`,
`schemas.py` or `schemas/` without asking**: the guarantees in section 10 of
the handoff depend on them.

## Left to build (handoff order)

| # | Piece | Status |
|---|---|---|
| 1 | Tests, one file per module | done: `tests/`, run in CI |
| 2 | Heartbeat and staleness | heartbeat done (every 2 s, `schemas/heartbeat.schema.json`); unhealthy after 15 s of silence still to do (last-seen is tracked) |
| 3 | Rate limit `object.update` to 2/s per object | to do. Today every detection with a position produces one |
| 4 | Fusion with a constant-velocity filter and gating | to do. Replace `Fusion.ingest` |
| 5 | Zones and alerts | to do. `snapshot.alerts` is always empty |
| 6 | Suggestions | to do |
| 7 | `operator.action` audit log, `GET /api/v1/audit/verify` | actions are checked, logged and kept in memory; audit to do |
| 8 | Persistence | to do. Restarting loses objects and vehicles; assets come back from retained MQTT |

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

## Endpoints

| Endpoint | Auth | |
|---|---|---|
| `GET /ws/v1/operator` | `Authorization: Bearer <operator token>`, checked before the upgrade (401) | First message must be `hello` (close 4400; 4408 if none within 5 s). Then `snapshot`, then `asset.state`, `object.update`, `heartbeat`. Accepts `vehicle.state` and `operator.action`. |
| `POST /api/v1/snapshots` | device token | One JPEG (`image/jpeg`), at most 300 KB. Returns `201 {"snapshot_id": "snap-…"}` |
| `GET /api/v1/snapshots/{id}` | operator token | The JPEG |
| `GET /healthz` | none | `ok` |
