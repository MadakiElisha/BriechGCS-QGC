# BriechUAS custom build

`custom/` turns QGroundControl into **BriechUAS**: QGC's stock Fly and Plan
views, plus the Briech **Modern** view and the **Fleet** layer (towers,
detections, alerts and fleet-wide safety commands from the Briech
coordinator). QGC's build picks this folder up automatically when it exists.
Everything Briech-specific in the app lives here. Edits to stock QGC files are
the exception, and each one is listed in `briech-docs/UPSTREAM.md`.

## Build

Full steps, pinned versions and known problems: [`briech-docs/BUILD.md`](../briech-docs/BUILD.md).
In short, with Qt 6.10.1 (including **qtwebsockets**; **qtquick3d** is optional)
and MSVC 2022, Ninja and CMake 3.25+ set up:

```sh
cmake -S . -B build/Release -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=<Qt>/6.10.1/<kit>
cmake --build build/Release
```

The app is `build/Release/Release/BriechUAS.exe` on Windows. Measure
performance in Release only; Debug Qt is many times slower.

## Run

1. Start the app with Qt (and GStreamer, for video) on `PATH`. Its default UDP
   14550 link connects to any PX4 or ArduPilot vehicle, real or simulated.
2. For simulated drones: `sim/px4-sitl.sh up 3` (Docker), see `sim/README.md`.
3. For the Fleet layer, start the ground side (broker, coordinator, fake tower):
   see `ops/README.md` and `ground-core/README.md`. Then quit the app and run
   `python3 ops/scripts/qgc-fleet-settings.py`, which writes the `[Fleet]`
   settings (coordinator URL, operator token, CA file) into the app's settings
   file, and start the app again.

With Fleet off (the default) the app behaves like stock QGC with the Modern
view. Turning Fleet off at runtime closes the coordinator link and stops all
Fleet work.

## Folder map

| Path | What it is |
|---|---|
| `CMakeLists.txt` | Sources, Qt modules and the optional Quick3D check. Edited by hand. |
| `custom.qrc` | Every QML, JS and image file the app loads. A new file must be listed here, or it is missing at run time. |
| `cmake/CustomOverrides.cmake` | App name, package id (`com.briechuas.groundcontrol`; do not change it), icons. |
| `src/CustomPlugin.*` | Entry point. Registers the Briech and Fleet types and singletons with QML, and wires Fleet to QGC's vehicles and MAVLink traffic. |
| `src/Briech*.{h,cc}` | Modern view helpers: airspace data (OpenAIP, key sent in a header), simulation launcher, detection, energy prediction, safety monitor. |
| `src/Fleet/` | Fleet C++. `FleetLink*`: WebSocket to the coordinator on a worker thread. `FleetProtocol`: message parsing. `FleetModels`: assets, detections, alerts for QML. `FleetVehicleReporter`/`FleetVehicleState`: reports QGC's vehicles once a second. `FleetDispatch`/`FleetOperatorActions`: approve, HOLD ALL, RETURN ALL, with pre-checks. `FleetDataAge`: per-vehicle data age. `FleetAudit`: local hash-chained action log. `FleetSettings`: the `[Fleet]` settings. |
| `src/FlyView*.qml`, `src/CustomGuidedActionsController.qml` | Overrides of stock Fly view pieces, loaded in place of QGC's own (see `CustomOverrideInterceptor` in `CustomPlugin.cc`). |
| `src/AutoPilotPlugin/`, `src/FirmwarePlugin/` | Custom autopilot and firmware plugin hooks. |
| `qml/Briech/Modern/` | The Modern view (`BriechModernView.qml`) and its parts. |
| `qml/Briech/Fleet/` | Fleet QML. `FleetLayer.qml` is the one file the Modern view loads; it holds the panel, alerts, safety controls, offline banner and map layers. `Fleet3DView.qml` (opened with the panel's 3D button) shows the active drone's roll, pitch and heading: in 3D (`FlightGhostScene.qml`, only when the build has Qt Quick 3D) or with the 2D attitude indicator. `FleetManagementPage.qml` is the FLEET page. `FleetFormat.js` has the shared formatting and data-age helpers. |
| `res/` | Theme (`BriechTheme.qml`), attitude indicator, fonts, logos and icons. |
| `test/Fleet/` | Qt Test suites for the Fleet C++. They build on their own, without QGC (see BUILD.md). |
| `android/`, `deploy/` | Platform packaging overrides. |

## Rules for changes here

- **Real data only.** Show `--` when a value is missing. Never show placeholder
  data as live.
- **Data age is always shown.** A vehicle turns amber after 3 s without a
  report and grey (stale) after 10 s; a tower goes stale after 15 s.
- **Don't change stock behaviour.** Keep stock Fly and Plan behaviour unchanged. No new top-level windows.
  Avoid editing files outside `custom/`, `ops/`, `ground-core/`, `schemas/`,
  `sim/` and `briech-docs/`. When an edit there is unavoidable, record it in
  `briech-docs/UPSTREAM.md`.
- **The fleet layer never sits in the flight path.** Flying, HOLD ALL and
  RETURN ALL go straight to the vehicles over MAVLink and work with the
  coordinator down.
- **No secrets in git, and never log full URLs.** API keys go in headers.
- **Keep QML bindings cheap.** Don't read `vehicle.coordinate` or values bound
  to `mavlinkStatusChanged` in JavaScript bindings: each read creates a
  wrapper that stays connected to the vehicle. Thousands of them froze the UI
  in flight. Copy the values into plain number properties, as
  `BriechModernView.qml` does (`liveLatitude`, `sampleLinkStats`).
