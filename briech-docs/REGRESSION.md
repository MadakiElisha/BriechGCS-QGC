# Regression checklist

The handoff's definition of done asks: *"With the coordinator down, QGC shows
the offline banner and flying is unaffected. With Fleet.enabled off, QGC
behaves exactly as before."* This file is how we show that, every time it
matters, in the same way.

Run it:

- before tagging a release or a release candidate;
- after merging upstream QGC;
- after a change to the Modern view's mount points (the Fleet Loader, the
  FLEET page) or to `CustomPlugin.cc`.

Use a **Release** build and the **Modern UI** (the Legacy UI is not checked
here). Write the result in the table at the end, one row per run. A box is
ticked only when it was seen, not when it is expected.

## A. Automatic checks (CI, every push)

Before the manual part, the PR's CI must be green on these:

| Check | Where | What it proves |
|---|---|---|
| Custom Plugin Build, `full` and `no-quick3d` | `custom-build.yml` | The app builds, packages, starts, and its Modern view loads with no missing QML module or type (`custom/test/ui-smoke.sh`), with and without Qt Quick 3D. |
| `fleet-cpp` | `fleet-cpp.yml` | Fleet C++ tests, and every message QGC sends is valid against `schemas/`. |
| `ground-core` `test`, `replay`, `edge` | `ground-core.yml` | Coordinator logic, the whole ground stack end to end, the edge publisher. |

## B. Fleet off: QGC behaves as before

How Fleet off is built (`custom/src/CustomPlugin.cc`): with `Fleet/enabled`
false, the coordinator link and its worker thread are stopped, data-age
tracking is off, the vehicle reporter sends nothing (it only runs while the
link is connected), and the Fleet layer's Loader is inactive, so none of the
Fleet QML exists. What remains of Fleet is the FLEET page's "FLEET IS OFF"
notice.

Setup: one simulated drone (`sim/px4-sitl.sh up 1`, or the app's own
simulator). Turn Fleet off with DISABLE on the Fleet panel, or start with
`Fleet/enabled=false`.

| # | Do | Expect |
|---|---|---|
| B1 | Start the app with Fleet off. | The Modern view opens as usual. No Fleet panel, banner, alert queue or map tags. |
| B2 | Look at the log (`QT_LOGGING_RULES="Briech.FleetLink.debug=true"`). | No `connecting to` lines from `Briech.FleetLink`. QGC does not contact the coordinator. |
| B3 | Open the FLEET page. | "FLEET IS OFF" and the ENABLE FLEET button; nothing else. |
| B4 | FLY: connect the drone, arm, take off, land (the left-hand CONNECT, ARM, TAKEOFF, LAND buttons). | Same as before Fleet existed: the vehicle connects, the commands work, telemetry shows. |
| B5 | FLY: PAUSE, then RTL. | The drone holds, then returns. No freeze (Fleet's own RETURN ALL fix is not involved). |
| B6 | PLAN: make a short mission, upload it, fly it from FLY. | Upload succeeds; the drone flies the mission. |
| B7 | ANALYZE and VEHICLE pages. | Open and work as before. |
| B8 | Missing data. | Values with no data show `--`, never made-up numbers. |
| B9 | Turn Fleet on (ENABLE FLEET), then off again (DISABLE). | On: the panel appears and the link connects or shows its retry state. Off: everything Fleet disappears again, with no restart needed. |

## C. Fleet on, coordinator down

Setup: Fleet on, the coordinator stopped (or `Fleet/url` pointing nowhere),
one or more simulated drones flying.

| # | Do | Expect |
|---|---|---|
| C1 | Wait 10 s after the coordinator goes away. | The offline banner appears. The link shows retrying, with growing delays (1, 2, 4 … 30 s). |
| C2 | Fly as in B4 and B5. | Unaffected. |
| C3 | HOLD ALL, then RETURN ALL. | Every drone obeys (tested 8 of 8 on 2026-11-10). The outcomes are in the local audit log (`fleet-audit.jsonl`). |
| C4 | Start the coordinator again. | QGC reconnects by itself, without a restart; the banner goes. |

## Results

| Date | Build (commit) | Who | A | B | C | Notes |
|---|---|---|---|---|---|---|
| 2026-11-18 | `d9be59cd5` (Release, Windows 11) | Miracle, with Claude reading logs | Pass (CI green on the PRs in this build) | **Partly**: B1, B2, B3, B4, B9 seen; B5 to B8 not seen | Not run | Details below. Found and fixed: the PLAN upload problems (#41). |
| 2026-11-19 | `43f5607cd` (Release, Windows 11) | Miracle, with Claude reading logs | Pass (all CI green on `main`) | Not re-run | **Pass**: C1 to C4 | Details below. Also verified #41 (upload confirmations) and #43 (dialogs: Briech look in Modern, stock in Legacy). |
| 2026-11-23 | `e34303ff0` (`main`, Release, Windows 11) | Miracle, with Claude reading logs and screenshots | Pass (all CI green on `main`) | **Pass**: B5 to B9 | **Pass**: C1 (banner seen) and C4 | Details below. Section B is now complete across the three runs. One start-up crash in two launches (known, see the release notes). |

### 2026-11-18, section B (Fleet off)

- **B1, B3:** with Fleet off, there was no Fleet panel, map tags or badge on
  FLY, and FLEET showed "FLEET IS OFF".
- **B2:** the coordinator saw `op-001 disconnected` at 17:38:13 when Fleet
  was turned off. The app's log (`Briech.FleetLink` debug on) has **no
  connection attempt** until Fleet was turned on again at 17:43:58, and the
  app held **0** TCP connections to port 8443.
- **B4:** BRCH-1 (PX4 SIH): ARM, TAKEOFF and RTL with Fleet off. PX4 reported
  `Armed`, `navigation mode: Return`.
- **B9:** Fleet on again connected at once (17:43:58), with no restart.
  Clicking FLEET while Fleet is off asks "Turn on the Fleet layer?" first.
- **Not seen in this run:** B5 (PAUSE, then RTL, timed for a freeze), B6 (a
  PLAN mission uploaded and flown with Fleet off), B7 (ANALYZE, VEHICLE), and
  B8 (`--` for missing values).
- **Found:** the sample KML (about 195 km from the drones) went to the active
  drone only, while the map showed the other drone's mission. PX4 accepted it
  (`MIS_DIST_1WP` = 10 km) and the drone headed north. Fixed in #41 (named
  upload target, far-plan warning, no silent simulator start).

### 2026-11-19, section C (coordinator down)

- **C1:** the coordinator was stopped at 13:09:17. The app retried with
  growing delays, about 33 s between attempts at the end (30 s cap with
  jitter), as the log shows. The offline banner was not separately checked
  (no screenshot); check it on the next run.
- **C2, C3:** BRCH-1 airborne. **HOLD ALL**: audit seq 71/72, command hold,
  outcome **confirmed** ("command accepted"). **RETURN ALL**: seq 73/74,
  command return, outcome **confirmed** ("flight mode Safe Recovery"). BRCH-1
  landed and disarmed. All of this happened with no coordinator.
- **C4:** the coordinator restarted at 13:12:06. The app reconnected **by
  itself** at 13:12:14, with no restart.

### 2026-11-23, sections B and C

Two simulated drones (PX4 SIH, `px4-1` and `px4-2`), the default config
(zone and tower at Briech home), the app built from `main` at `e34303ff0`.

- **Start-up:** the first launch closed about 10 s in, while the drones
  connected (`QGC: unhandled SEH`, just after `QAudioSink::start: QIODevice is
  not readable`). The second launch ran for the whole session. This is the
  known occasional start-up crash in `RELEASE-NOTES.md`.
- **B5:** with Fleet off, PAUSE in flight, then RTL: the drone held, then
  returned and landed, with no freeze (Miracle, at the screen).
- **B6:** with Fleet off (the app's log has no `Briech.FleetLink` line for the
  first 586 s), a 4-waypoint PLAN mission was uploaded to BRCH-2 and flown:
  WP 4/4, COMPLETE, 280 m covered, landed and disarmed.
- **B7:** ANALYZE and VEHICLE opened and worked (Miracle, at the screen).
- **B8:** with no next waypoint, the top bar showed `DIST WP --` and
  `TIME --`, not numbers.
- **B9:** ENABLE at 586 s; connected, `hello` sent, at 588 s.
- **C1:** the coordinator was stopped at 09:15:46. Within 13 s the panel
  showed "COORDINATOR OFFLINE · CONNECTING" with "Flying, HOLD ALL and RETURN
  ALL still work", and FLEET · OFFLINE on the map button. The link retried
  after 1.0, 1.6 and 3.9 s. Both drones kept 0 s data age and a 99 % link.
- **C4:** the coordinator was started again at 09:16:13; the app reconnected
  by itself (attempt 4) and the coordinator logged `operator op-001 connected`.

### Still to run

Nothing in sections B and C. Box 1 of the definition of done (a second
person's PC, following only `BUILD.md`) is still to be recorded.
