# Spikes

A spike is a short, timeboxed test of something we do not know yet (handoff,
section 13). Each entry: what we tried, the answer, and what we decided.
Numbers are measured, not estimated; the method is given with each one.

| # | Question | Owner | Status |
|---|---|---|---|
| S1 | Does the repo build cleanly on two machines with Qt Quick 3D and WebSockets? | Miracle | One machine done; second machine open |
| S2 | How does QGC with the Modern view behave with 10 vehicles? | Miracle | Done |
| S3 | Stock Viewer3D, or our own small 3D window? | Miracle | Decided: our own window (stock not measured) |
| S4 | How accurate is our geolocation? | George | Open |
| S5 | Ten PX4 SIH instances on one machine, driven by a script? | George | Done (see `sim/README.md`) |
| S9 | Licences for the detector model, datasets and Qt modules | George / lead | Open |

S6 to S8 and S10 to S12 are tracked by the lead.

## How we measure UI responsiveness

A "stall" is the time QGC's main thread takes to answer a no-op window message
(`WM_NULL` sent with `SendMessageTimeout` every 100 ms). The main thread runs
all QML and UI work, so a slow answer is a freeze as the operator sees it. We
report the number of answers slower than 150 ms, the worst, and the mean.
Always measure a **Release** build: Debug Qt is many times slower.

## S1: build on two machines

**Tried:** a full build on one machine: Windows 11, MSVC 2022 Build Tools,
Qt 6.10.1 with qtquick3d and qtwebsockets, CMake 3.31 (the copy shipped with
VS), Ninja, GStreamer 1.24.13.

**Answer so far:** it builds in Debug and Release. Qt Quick 3D is found
(`BRIECH_FLEET_3D` on), and WebSockets is linked. Two problems were found and
written into `briech-docs/BUILD.md`:

- CMake 4.5.0-rc1 fails on zstd.
- `FindGStreamer.cmake` wants an exact version (`-DGStreamer_FIND_VERSION`).

**Open:** a fresh clone on a second machine. CI (`custom-build.yml`) now builds
`custom/`, and its first green run counts as the second machine.

## S2: QGC with ten vehicles

**Tried (2026-11-10):**

- **Setup:** ten PX4 SIH drones in Docker (S5) and the BriechUAS Release
  build, with Fleet on, the coordinator connected and the fake tower
  publishing. Machine: Windows 11, 16 logical cores, 16 GB.
- **Hover:** eight drones took off and hovered.
- **Flight:** the same eight flew 150 m square missions at 30 to 100 m with
  `sim/fly_mission.py`, returned and landed.
- **Operator use:** an operator used the app during the runs: switched
  pages, zoomed the map, and approved an alert.

**Answer:**

| Run | Length | Stalls ≥ 150 ms | Worst | Mean | QGC memory |
|---|---|---|---|---|---|
| 8 hovering, FLY page | 180 s | 0 | 96 ms | 3.0 ms | 855 MB |
| 8 hovering, FLY page and operator use | 600 s | 0 | 132 ms | 2.6 ms | 850 → 821 MB |
| 8 flying missions, then landing | 300 s | 1 | 841 ms | 2.5 ms | 837 → 813 MB |

- **CPU:** QGC used about 1.0 to 1.2 cores throughout.
- **The one stall** came while all eight drones landed and disarmed within
  seconds of each other. It matches, to within a second, a burst of stock QGC
  spoken announcements (Windows audio warnings in the log). It is probably
  that, but this is not proven.
- **No memory growth.** Before the freeze fix (see below) the UI froze for
  1 to 10 s in flight and hung within about 2 minutes.
- **Fleet with ten vehicles:**
  - The FLEET page lists all ten.
  - Data age works per vehicle: a paused drone's container turns amber at
    3 s and grey and STALE at 10 s, on the cards, the roster and the map tags.
  - An alert approval reached the right vehicle (BRCH-6, orbit), and the
    outcome came back "confirmed". The local audit log and the coordinator
    log agree.

**Decided:**

- **No update-rate cut needed.** The fix was in our own QML.
- **Value-type rule.** Bindings must not read `vehicle.coordinate`, or values
  that change on every MAVLink message, in JavaScript. Each read creates a
  value-type wrapper that stays connected to the vehicle, and thousands of
  them made every position update and every garbage collection slow. The
  Modern view now copies the position into plain numbers once per report and
  samples link statistics once a second. This rule is in `custom/README.md`.
- **Single-vehicle assumptions:** none found in Fleet.
- **Map tags overlap** at the default zoom when drones are about 33 m apart.
  This is cosmetic and left as is.

**HOLD ALL and RETURN ALL with eight drones flying** (definition of done):

| Coordinator | Command | Sent to | Result | Local audit |
|---|---|---|---|---|
| Up | HOLD ALL | the 8 flying (1 and 2 on the ground left out) | all 8 in HOLD | 8 command + 8 confirmed |
| Up | RETURN ALL | 8 | all 8 in RTL, landed at home | 8 + 8 |
| Down (offline banner shown) | HOLD ALL | 8 | all 8 in HOLD | 8 + 8 |
| Down | RETURN ALL | 8 | all 8 in RTL, landed at home | 8 + 8 |

The local hash chain verified afterwards (67 entries).

**Found and fixed: RETURN ALL went out one drone at a time.** FleetDispatch
used `Vehicle::guidedModeRTL()`. For PX4, QGC implements that with
`FirmwarePlugin::_setFlightModeAndValidate`, which waits on the UI thread
for the mode change: 100 ms sleeps, up to 1.3 s per try, 3 tries.

- **Effect on a fleet:** each drone waited for the one before it. With
  eight answering drones the last got RTL 7.8 s after the first. A silent
  drone (lost link) would add up to 3.9 s for every drone after it, with the
  UI stalled meanwhile.
- **Fix:** FleetDispatch now calls `setFlightMode(rtlFlightMode())`. That
  sends the same MAV_CMD_DO_SET_MODE through QGC's retrying command queue
  without waiting.
- **After:** all eight commands left within 5 ms, and every drone confirmed
  within 1.0 s.

**Open:**

- Check the stall during landing with QGC's audio muted. If it goes, it is
  stock behaviour and stays as is.
- **Intermittent crash.** BriechUAS has exited with "QGC: unhandled SEH"
  about 10 to 30 s after start, while ten vehicles were connecting: 2 of
  about 10 plain launches. Five launches under the debugger did not crash,
  so there is no stack yet.
  - **What the log shows:** each time, a burst of stock audio warnings
    (`QAudioSink::start: QIODevice is not readable`, and once `AudioOutput:
    Text queue exceeded maximum size`) from ten "connected to vehicle"
    announcements at once.
  - **Suspect:** stock QGC's audio output. Not proven.

## S3: stock Viewer3D or our own 3D window

**Tried (2026-11-10):**

- **What existed:** the Modern view's "3D VIEW" button opens a 2D canvas
  drawing of the mission route that turns with heading only (no roll or
  pitch). A panel embedding the stock Viewer3D, QGC's OpenStreetMap city
  viewer, was defined in `BriechModernView.qml` but never used.
- **What we built:** our own small window (`Fleet3DView.qml` and
  `FlightGhostScene.qml`, handoff section 8). It uses the stock model's
  rotation conventions, a quad built from Quick3D primitives (well under
  2,000 triangles), one light, no shadows, and a Loader that creates the
  scene only while the view is open.
- **The check:** `sim/attitude_check.py --vehicle 3` held a simulated drone
  at roll -20 (left), pitch +12 (nose up), then heading +90 (right turn).
  Screenshots in each phase agreed across:
  - the 3D view: left side down, nose up, view turned clockwise;
  - its ROLL / PITCH / HDG readout;
  - the Modern HUD and QGC's heading readouts: -20, 12, and 357 to 086.
- **Cost:** BriechUAS Release, ten drones connected, one hovering at 29 m.
  The app CPU was sampled over 20 to 30 s, twice in each state:

  | | App CPU (share of one core) | GPU 3D engine | Memory |
  |---|---|---|---|
  | Attitude view closed | 124% and 134% | 36% and 37% | 969 to 984 MB |
  | Attitude view open (3D) | 139% and 146% | 30% and 31% | 986 MB |

  The open 3D view costs about 12 to 15% of one core. Its GPU use is lost in
  the map's own load: the GPU reading was lower with the view open.

**Not measured:** the stock Viewer3D. It replaces the whole map with an
OpenStreetMap city scene, needs an OSM file loaded first, and its drone
model (DJI F450 meshes, 7 MB for the four arms alone) is far over the
handoff's budget of about 20,000 triangles.

**Decided:**

- **Our window, not the stock Viewer3D.** The stock viewer is a different
  tool, a full-screen city view, and its model alone breaks the triangle
  budget.
- **The 2D indicator is the floor.** It appears when Quick3D is missing,
  when the scene fails to load, or when the operator picks 2D (saved in
  `Fleet/prefer3D`).

**Found on the way:** the pitch ladder and horizon line of the Briech 2D
attitude indicators (`BriechAttitudeIndicator.qml` and the Modern HUD) used a
pitch scale about 4.3 times smaller than the sky/ground background. The
background uses QGC's own scale, pitch × height / 45. In a pitched climb or
dive the ladder therefore read near-level while the background had moved off
the dial, and the indicator's white horizon line did not move at all. Both
were fixed to the background's scale.

**Open:**

- A build without Qt Quick 3D has not been run. The 3D file is loaded by URL
  only when `quick3DAvailable` is true, so it is never parsed in such a
  build.
- The pop-out window was left out (one top-level window; the handoff cuts it
  first).

## S5: ten PX4 SIH drones on one machine

**Done.** Commands, numbers and the one known problem (drones that refuse to
re-arm after landing) are in `sim/README.md`. The drones were driven with
pymavlink (`sim/fly_mission.py`), not MAVSDK. That covers missions, arming and
watching, so MAVSDK was not needed.
