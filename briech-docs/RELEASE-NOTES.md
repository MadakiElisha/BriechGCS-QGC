# Release notes

## v0.1.0-rc1 (draft, not tagged)

The first release candidate of the Briech fleet ground station: QGroundControl
(Qt 6.10.1) with the Briech Modern UI, the Fleet layer, and the ground
services (broker, coordinator, simulators). Simulation only: see "Not for
flight" below.

### What it does

- **One map for a fleet.** Every connected drone and tower, coloured by how
  fresh its data is: amber after 3 s, grey and STALE after 10 s. Missing
  values show `--`, never invented numbers.
- **Detections, tracks and alerts.** Towers publish detections over MQTT
  (TLS, one login per device, each device limited to its own topics). The
  coordinator checks every message against `schemas/`, merges sightings
  into tracks, and raises one alert when a watched class enters a zone,
  with a suggested drone.
- **The alert panel.** The camera picture (or why there is none),
  what/where/when, the proposed drone with ETA and battery after, warnings
  shown before deciding, the time left, and APPROVE / REJECT (keys A, R,
  Esc). A "New alert" toast and a FLEET badge make sure alerts are seen.
- **Commands go straight to the drones.** Approve, HOLD ALL and RETURN ALL
  are sent by QGC over MAVLink, never through the coordinator. Each outcome
  (confirmed, refused, no response) is shown and recorded.
- **Audit.** Every decision, command and outcome goes into a hash-chained
  local log (and the coordinator's, checkable at `/api/v1/audit/verify`).
  A decision also records which alert picture was on screen: its id and
  the SHA-256 of the bytes shown.
- **Attitude view.** The selected drone's roll, pitch and heading in 3D,
  or in 2D on machines without Qt Quick 3D.
- **Safer PLAN uploads.** The button names the target drone. A plan that
  starts more than 5 km away needs two deliberate confirmations. The
  built-in simulator is never started without asking.
- **Briech look for every dialog** in the Modern UI. The Legacy UI is
  unchanged.
- **Fleet off means stock QGC.** No Fleet UI and no coordinator traffic.
- **Ready for the field hardware** (not yet run on it): the edge pipeline
  reads a live camera (USB, Jetson CSI, RTSP); systemd units run the
  coordinator and each tower's pipeline on boot and restart them; a script
  makes the WireGuard VPN the towers use, so the broker is never open to the
  internet. See `ops/README.md`, "Field deployment".

### How it is proven

| Check | Where |
|---|---|
| Builds on Linux, with and without Qt Quick 3D, and the UI loads | CI: Custom Plugin Build (two variants) with the UI smoke test |
| Every message QGC sends is valid (2,172 generated cases) | CI: fleet-cpp, `outgoing_messages_match_schemas` |
| The whole ground stack end to end (11 checks) | CI: ground-core `replay`, every push |
| `make -C ops dev-up` | CI: ground-core `dev-up`, every push |
| Ten drones flown and landed | CI: sim-nightly `ten-drones`, nightly |
| Coordinator logic (188 tests), edge publisher | CI: ground-core `test`, `edge` |
| Fleet off, coordinator down, HOLD ALL / RETURN ALL | `briech-docs/REGRESSION.md` (manual, with logs) |
| Ten drones in the Release app, 0 stalls over 10 minutes | `briech-docs/spikes.md`, S2 |
| The whole definition of done, live | `briech-docs/DEMO.md` |

### Known limitations

- **Box 1** is recorded on one PC plus Linux CI. A second person's PC,
  following only BUILD.md, is still to be recorded.
- **After this PC sleeps**, Docker stops and QGC's UDP link can go deaf
  until the app is restarted. The data-age display shows it (STALE), but
  nothing reconnects by itself. Keep the ground station awake.
- **Not themed:** native file pickers (drawn by Windows), stock menus such as
  the map right-click menu, and the stock pages hosted in the Modern UI
  (ANALYZE, VEHICLE, Settings).
- **An occasional crash at start-up** with ten vehicles connected (2 of
  about 10 launches, 2026-11-10). It is not reproduced under the debugger.
  The suspect is stock audio announcements.
- The picture's SHA-256 is in the local audit only. Sending it to the
  coordinator needs an optional schema field, which is proposed but not
  agreed.
- **Not yet run on a Raspberry Pi or a Jetson.** The units pass
  `systemd-analyze verify`, the VPN configs parse, and the live camera path
  was run end to end from an RTSP stream on Windows. TensorRT for the
  detector is still to do, on the Jetson itself.
- **Geolocation accuracy** of real detections is not measured (spike S4).
  The edge test video's position is invented.

### Not for flight

Simulation and private permitted areas only, until spike **S12** (aviation
and data-protection rules) is answered in writing. The vehicle types (S6),
links (S7), battery drain per airframe (S8), video (S10) and MAVLink signing
(S11) are open with the lead.

### Waiting on decisions

- Rewrite git history to remove a personal path in old `b3/` commits
  (everyone with a clone must agree).
- The OpenAIP tile overlay: bring it back properly, or drop it.
- The optional schema field for the picture's SHA-256 in `operator.action`.
