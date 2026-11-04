# Message schemas, version 1

One JSON Schema (draft 2020-12) per message that crosses a boundary. These
files are the contract: the coordinator, the fake publisher, the edge
publishers and FleetLink all follow them, and CI checks every example.

**Version 1 freezes on Friday 6 November 2026.** After that, adding an
optional field is fine. Removing or renaming a field, or changing what one
means, needs version 2 and all three of us agreeing first. A schema changes in
the same pull request as the code that sends the message and the code that
reads it.

| File | Message | From → to | Road |
|---|---|---|---|
| `edge.status.schema.json` | `edge.status` | edge → coordinator | MQTT `briech/v1/edge/<id>/status`, retained, last will |
| `asset.state.schema.json` | `asset.state` | tower adapter → coordinator → QGC | MQTT `briech/v1/asset/<id>/state` (retained), then WebSocket |
| `detection.schema.json` | `detection` | edge → coordinator | MQTT `briech/v1/edge/<id>/detection` |
| `hello.schema.json` | `hello` | QGC → coordinator | WebSocket, first message |
| `snapshot.schema.json` | `snapshot` | coordinator → QGC | WebSocket, once per connection |
| `vehicle.state.schema.json` | `vehicle.state` | QGC → coordinator | WebSocket, every 1 s |
| `object.update.schema.json` | `object.update` | coordinator → QGC | WebSocket |
| `alert.new.schema.json`, `alert.update.schema.json` | `alert.new`, `alert.update` | coordinator → QGC | WebSocket |
| `operator.action.schema.json` | `operator.action` | QGC → coordinator | WebSocket |
| `heartbeat.schema.json` | `heartbeat` | coordinator → QGC | WebSocket, every 2 s |
| `envelope.schema.json` | the wrapper every message shares | | |
| `common.schema.json` | shared pieces: timestamp, positions, asset, vehicle, object, alert | | |

## Conventions the schemas enforce

- `ts` is UTC ISO 8601 ending in `Z`; senders include milliseconds.
- Positions are WGS84 degrees. Altitude always says which kind
  (`alt_rel_m` or `alt_amsl_m`); a bare `alt` is rejected.
- A ground position always carries `error_m` greater than zero. A detection
  with no honest position leaves `geo` out rather than making one up.
- Heading 0 to under 360, battery a whole percent, confidence 0 to 1.
- Unknown fields are ignored everywhere, so adding an optional field never
  breaks a receiver. Unknown message types are dropped and counted.
- Messages stay under 4 KB (the MQTT bus drops anything bigger). `snapshot`
  is the one exception.

## Examples

`examples/<type>.valid[.<case>].json` must pass its schema and
`examples/<type>.invalid.<reason>.json` must fail it. Every type has at
least one of each; `ground-core/tests/test_schemas.py` checks all of them.
FleetLink's C++ test is meant to load the same files.

Check them locally:

```sh
make -C ops test
```
