# Briech UAS Modern View Handoff

Date: 2026-09-08  
Workspace: `C:\Users\Godsmiracle\Desktop\BriechGCS-QGC`

## Goal

Continue development of the Briech UAS custom QGroundControl Modern UI. The design cue is:

`https://chinaza007.github.io/test/briech_uas_qgc_final.html`

The app should keep real QGC/vehicle functionality. Do not replace live data with static demo values.

## Current Dirty Files

These files currently contain the Modern UI work:

- `custom/qml/Briech/Modern/BriechModernView.qml`
- `custom/qml/Briech/Modern/PlanViewModern.qml`
- `custom/res/BriechAttitudeIndicator.qml`
- `custom/src/FlyViewCustomLayer.qml`
- `custom/custom.qrc`
- `custom/logo.png`

Do not revert these unless explicitly requested.

## Verified Build Command

Use the Visual Studio developer environment before building:

```bat
cmd.exe /c 'call "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 && cmake --build C:/Users/Godsmiracle/Desktop/BriechGCS-QGC/build/Desktop_Qt_6_10_1_MSVC2022_64bit-Debug --target all'
```

Last known result: build passed and linked `Debug\BriechUAS.exe`.

## Useful QML Check

```powershell
& 'C:\Qt\6.10.1\msvc2022_64\bin\qmllint.exe' custom/qml/Briech/Modern/BriechModernView.qml 2>&1 | Select-String -Pattern 'Error:|error:|Invalid property assignment|Cannot assign|Unable to assign|Unable to find|Expected token|Syntax|Cannot access value|is not a type|color expected'
```

Last known result: no blocking errors from the targeted scan.

## What Has Been Implemented

### Fly View

- Modern Fly uses the legacy/QGC map surface instead of a separate custom map look.
- Map is not intentionally darkened anymore.
- HUD was improved with a circular attitude indicator style.
- Header now includes:
  - vehicle status
  - message icon
  - altitude
  - groundspeed
  - heading
  - GPS status
  - battery
  - flight mode
- Message icon is white and uses the legacy vehicle messages asset.
- Vehicle message popup was added to Modern Fly.
- Modern command rail has real actions:
  - connect/disconnect
  - arm/disarm
  - takeoff
  - pause
  - land
  - RTL
  - center
  - fit mission
- Command functions call real `activeVehicle` methods, not mock behavior.
- Command pending state exists and waits for vehicle state confirmation.
- Vehicle command warnings are captured from the vehicle message stream.
- If the Cube rejects arm, for example `Hardware safety switch` or `PreArm`, Modern shows it as a `VEHICLE WARNING`.
- Premium flight alert cards exist for:
  - battery warning
  - wind warning
  - vehicle command/prearm warning
- Map layer drawer exists with:
  - default
  - satellite
  - street
  - terrain
  - hybrid
  - watermark toggle
  - airspace tiles toggle
  - map settings shortcut
- Diagnostics drawer exists.
- Animated watermark layer exists using `qrc:/Briech/res/logoWatermark.png`.

### Plan View

- Plan/Fly map sync work was previously done so Fly and Plan should share center/zoom/map type behavior.
- Plan metrics now avoid static `DRAFT`/`READY` wording where possible.
- Plan view uses the modern shell while preserving real QGC plan controller data.

### Analyze View

Analyze page was moved closer to the HTML reference:

- left rail for log/session controls
- center telemetry chart
- right mission summary/checklist
- live telemetry summary cards
- live session events instead of hardcoded recent missions
- log status from `LogDownloadController`
- telemetry histories from active vehicle samples:
  - altitude
  - groundspeed
  - battery
- insight cards based on:
  - vehicle readiness
  - MAVLink link quality
  - vibration/battery observations
  - latest vehicle warning

Important: Analyze should not show fake static missions. Keep it live-data only.

### Vehicle View

Vehicle page now shows deeper live panels:

- `VEHICLE IDENTITY`
- `LIVE CAPABILITIES`
- `POWER`
- `LINK`
- `GPS / POSITION`
- `COMMAND AVAILABILITY`
- `READINESS`
- `LIVE SYSTEMS`
- `GUIDED ACTIONS`
- `SETUP STATUS`
- `SETUP ACCESS`

It was also changed to use a scroll container because screenshots showed the page content being pushed/clipped vertically.

## Important Recent Screenshot Findings

User provided screenshots on 2026-09-05:

- Fly view looked generally acceptable.
- Analyze was much closer to the reference design.
- Vehicle had a clear layout bug:
  - very large empty top area
  - panels pushed toward the bottom
  - bottom rows clipped by the Windows taskbar/status area

Latest patch after that:

- Vehicle header row got fixed min/max height.
- Vehicle lower grid stopped using full-height stretch.
- Vehicle content was wrapped in a vertical `ScrollView`.
- Build passed after this patch.

## Current Design Direction

Use the reference HTML style:

- dark tactical GCS shell
- thin gold accents
- compact dense header
- small uppercase labels
- monospace/condensed typography
- sharp 2px radius panels
- glass/dark translucent panels
- no bulky rounded card-heavy dashboard look
- map remains primary on Fly
- UI panels remain sharp above the map

Avoid:

- fake demo values
- static placeholder missions
- excessive empty hero space
- one-off panel colors
- darkening or tinting the legacy map itself
- giant marketing-style sections

## Key Functions Added/Changed

In `custom/qml/Briech/Modern/BriechModernView.qml`:

- `vehiclePowerModel()`
- `vehicleLinkModel()`
- `vehicleGpsModel()`
- `vehicleCommandStateModel()`
- `recordVehicleWarning(message)`
- `modernFlightAlerts()`
- `dismissModernFlightAlert(key, kind)`
- `missionSummaryText()`
- `recentMissionModel()`
- mission timeline helpers:
  - `missionTimelineAvailable()`
  - `missionTimelineLiveIndex()`
  - `missionRemainingDistanceMeters()`
  - `missionEtaSeconds()`
  - `missionBatteryAtHomePercent()`

Shared visual tokens were added near the top:

- `modernGlass`
- `modernGlassStrong`
- `modernGlassSoft`
- `modernHairline`
- `modernGoldHairline`
- `modernGoldFill`

## Important Real Vehicle Behavior

The user's Cube flight controller produced:

`Arm/Disarm(MAV_CMD_COMPONENT_ARM_DISARM) command failed`

and:

`Arm: Hardware safety switch`

This is a real autopilot rejection, not a UI bug. The UI should surface it clearly, but should not bypass QGC/PX4/ArduPilot safety checks.

## Next Recommended Work

1. Run the app and inspect Vehicle after the scroll/fixed-height patch.
2. If Vehicle still has too much top empty space, remove the full-height behavior inside the Vehicle `ScrollView` wrapper and make the top summary denser.
3. Do a screenshot-driven polish pass:
   - Fly
   - Analyze
   - Vehicle
   - Plan
4. Make Analyze more useful:
   - show actual log names when available from `LogDownloadController.model`
   - add selectable session/log rows
   - add message severity counts
5. Tighten Vehicle:
   - make the first screen show most important status without scrolling
   - keep setup panels scrollable below
   - improve prearm blocker visibility
6. Continue QML warning cleanup only when warnings are actionable.

## Final Notes For Next LLM

- This is a QGroundControl/QML project, not React.
- The pasted HTML is a design cue only.
- Keep map and vehicle logic real.
- Prefer small patches and rebuild often.
- Use `apply_patch` for manual edits.
- Do not use destructive git commands.
- The current working tree is intentionally dirty.
