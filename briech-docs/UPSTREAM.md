# Upstream QGC files changed by Briech

Our code belongs in `custom/`. Every change to a file outside `custom/` is a
"stock-file edit": it is the likeliest place for a merge conflict when we pull
in upstream QGroundControl. List every one here, with the reason, in the same
pull request that makes the change.

- Baseline: upstream QGC as of `8886fd7e4^` (the parent of the first Briech commit).
- Last checked: 2026-10-28, branch `miracle/fleet-baseline`.
- Regenerate the list with:

  ```sh
  git diff --name-status 8886fd7e4^ HEAD -- . ':!custom' ':!b' ':!b2' ':!b3' ':!briech-docs'
  ```

Status key: **keep** = needed and intended; **review** = may be avoidable or
movable into `custom/`; **fix** = a known problem.

## Application shell and views

| File | Change | Why | Status |
|---|---|---|---|
| `src/UI/MainWindow.qml` | Briech toolbar, `briechModernView` Loader, `showBriechModernView()`, Modern view open by default, frameless window with resize grips, settings/analyze/vehicle page helpers | Mounts the Briech Modern view; the stock view switcher lives here | keep. **fix**: resize grips at lines 832-835 log `ReferenceError: modelData is not defined` (24 warnings at startup), so edge resizing probably does not work |
| `src/UI/toolbar/SelectViewDropdown.qml` | Adds the "Briech Modern" entry | Lets the operator reach the Modern view | keep |
| `src/FlyView/FlyView.qml` | Custom fly layer only visible with an active vehicle | Briech overlay should not show with no vehicle | review |
| `src/QmlControls/PlanView.qml` | Narrower right panel | Briech layout | review |
| `src/QmlControls/PlanViewRightPanel.qml` | About 140 lines of restyling | Briech look in stock Plan | review |
| `src/AnalyzeView/AnalyzeView.qml` | `showAnalyzePage(url)` | Modern view sidebar opens a specific analyze page | keep |
| `src/Vehicle/VehicleSetup/SetupView.qml` | `showFirmwarePanel()` | Modern view sidebar opens firmware setup | keep |

## Styling of stock controls (fonts, upper case, colours)

| File | Change | Status |
|---|---|---|
| `src/QmlControls/GeoFenceEditor.qml`, `MissionItemEditor.qml`, `RallyPointEditorHeader.qml`, `RallyPointItemEditor.qml`, `SectionHeader.qml`, `QGCComboBox.qml` | Barlow Condensed, upper-case labels, Briech colours | review: these also restyle stock Plan, so stock QGC no longer looks stock |
| `src/QmlControls/QGCPalette.cc` | `brandingPurple` set to black | review: `CustomPlugin::paletteOverride` already overrides `brandingPurple`, so this edit may be unnecessary |
| `src/QmlControls/ScreenToolsController.cc` | Default font family prefers Barlow | keep |
| `src/QGCApplication.cc/.h` | Loads the Barlow and Share Tech Mono fonts; exposes `geoFontFamily` to QML | keep |
| `qgcresources.qrc`, `resources/` | Barlow fonts, Briech logos replacing QGC logos | keep |

## Behaviour changes

| File | Change | Why | Status |
|---|---|---|---|
| `src/MissionManager/PlanMasterController.cc/.h` | `importKmlWaypoints()` | Import KML placemarks as waypoints | keep |
| `src/Utilities/Geo/KMLHelper.cc` | Repairs UTF-8 files that declare UTF-16 | Third-party planners write such files | keep |
| `src/QmlControls/MissionItemMapVisual.qml` | `required property var object` | Qt 6 delegate rules | keep (worth sending upstream) |
| `src/PositionManager/PositionManager.h` | GCS position accuracy limit 100 m to **5000 m** | Accepts coarse ground-station positions (commit `03585e0a0`) | **review**: safety-relevant, as QGC now trusts a GCS position up to 5 km off |

## Build and packaging

| File | Change | Why | Status |
|---|---|---|---|
| `src/CMakeLists.txt` | Links the Windows SDK `um/x64` directory when present | `runtimeobject.lib` not found on some machines | keep |
| `src/MAVLink/LibEvents/CMakeLists.txt` | libevents pinned to `077677a` instead of `main` | Upstream `main` is a moving target | keep; re-check on each upstream merge |
| `cmake/CustomOptions.cmake` | App and organisation names, macOS icon | Branding | **review**: `custom/cmake/CustomOverrides.cmake` already sets the name (`BriechUAS`, while this file says `BriechGroundControl`), so this edit may be redundant |
| `cmake/install/Install.cmake` | Installs Qt SerialPort explicitly on Windows | Installed app failed to start without it | keep |
| `deploy/` (installer script, iOS plists, Linux appdata and icons, Windows icon) | Branding | Packaging | keep |
| `Makefile` | **An accidental line at the end**: `The file /Users/mac/BriechGCS-QGC/build/Debug/QGroundControl does not exist.` (commit `8886fd7e4`) | Shell output pasted in by mistake | **fix**: delete the line; it breaks `make docker` |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle version | Android build | review |
| `android/.gradle/...` | Gradle cache files committed | By accident | **fix**: remove from git, add to `.gitignore` |
| `custom-example/` | Deleted | Replaced by `custom/` | keep. Note that `.github/actions/custom-build` still copies `custom-example`, so CI custom builds now fail outright |

## Tools and repository root

| File | Change | Status |
|---|---|---|
| `tools/simulation/*`, `tools/README.md`, `tools/generate-app-icons.ps1` | PX4 SIH and ArduCopter SITL scripts, icon generator | keep; the handoff moves simulation into `sim/` later |
| `MODERN_VIEW_HANDOFF.md` | Root-level handoff notes containing personal paths | fix: move into `briech-docs/` without personal paths (section 12, P1) |
| `wps (1).kml` | Sample waypoints at the root | fix: move into `sim/` (section 12, P0, George) |
| `b/`, `b2/`, `b3/` | Committed CMake build output, with a personal path in `b3/` | fix: stop tracking (section 12, P0, George) |

## Windows build notes found while checking

- `.github/build-config.json` pins Windows GStreamer to exactly `1.22.12`, and
  `cmake/find-modules/FindGStreamer.cmake` requires an exact match. Machines
  with GStreamer 1.24.13 must configure with
  `-DGStreamer_FIND_VERSION=1.24.13` until the team picks one version.
- CMake 4.5.0-rc1 fails on zstd 1.5.7 (`No CMAKE_ASM_COMPILER could be found`).
  The CMake 3.31 that ships with Visual Studio 2022 works.
