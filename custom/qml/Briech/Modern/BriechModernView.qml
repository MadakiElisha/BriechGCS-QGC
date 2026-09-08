pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap
import QGroundControl.FlyView
import QGroundControl.Viewer3D
import Custom.Widgets 1.0

Item {
    id: root
    anchors.fill: parent
    clip: true

    property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var _planMasterController: modernPlanController
    property var _missionController: modernPlanController.missionController
    property var _visualItems: _missionController.visualItems
    property color gold: BriechTheme.goldAccent
    property color bg: BriechTheme.bgPrimary
    property color panel: BriechTheme.panelBg
    property color panel2: BriechTheme.panelBg2
    property color border: BriechTheme.borderColor
    property color dim: BriechTheme.mutedColor
    property color text: BriechTheme.textColor
    property color ok: BriechTheme.okColor
    property color warn: BriechTheme.warnColor
    property color err: BriechTheme.errColor
    property color blue: BriechTheme.blueColor
    property color modernGlass: Qt.rgba(8 / 255, 10 / 255, 14 / 255, 0.72)
    property color modernGlassStrong: Qt.rgba(8 / 255, 10 / 255, 14 / 255, 0.88)
    property color modernGlassSoft: Qt.rgba(15 / 255, 18 / 255, 24 / 255, 0.58)
    property color modernHairline: Qt.rgba(1, 1, 1, 0.075)
    property color modernGoldHairline: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.18)
    property color modernGoldFill: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.075)
    property string activeModernSection: "fly"
    property string selectedMapKind: "default"
    property string selectedRiskZone: ""
    property var riskZones: []
    property var airportRiskZones: []
    property var weatherAlerts: []
    property url riskDataSourceUrl: ""
    property string riskDataSourceTemplate: ""
    property string airportRiskDataSourceTemplate: ""
    property bool filterRiskZonesToMap: true
    property int riskZoneViewportRevision: 0
    property string openAipToken: QGroundControl.settingsManager.appSettings.openaipToken.rawValue || ""
    property bool liveGcsLocationReceived: false
    property bool modernSettingsOpen: false
    property bool modernConnectPanelOpen: false
    property bool modernVehicleMessagesOpen: false
    property bool modernMapToolsOpen: false
    property bool modernDiagnosticsOpen: false
    property bool modernWatermarkEnabled: true
    property string lastRiskDataUrl: ""
    property string lastAirportRiskDataUrl: ""
    property bool openAipTileOverlayEnabled: true
    property int airspaceTileRevision: 0
    property string airspaceCountryCode: "NG"
    property bool loadCountryAirspace: true

    onRiskZoneViewportRevisionChanged: validateSelectedRiskZone()
    property bool _mapTypeInitialized: false
    property int missionScrubIndex: 0
    property bool payloadPanelOpen: false
    property string payloadView: "video"
    property string payloadVideoMode: "EO"
    property int payloadZoomIndex: 0
    property real payloadZoomLevel: 1
    property real batteryPercent: NaN
    property real riskPulse: 0
    property string pendingVehicleAction: ""
    property double pendingVehicleActionStartedAt: 0
    property var defaultCenter: QtPositioning.coordinate(9.0765, 7.3986)
    property var overlayCenter: activeVehicle && activeVehicle.coordinate.isValid ? activeVehicle.coordinate : (QGroundControl.flightMapPosition.isValid ? QGroundControl.flightMapPosition : defaultCenter)
    property var speedHistory: []
    property var altitudeHistory: []
    property var batteryHistory: []
    property string modernAlertClock: Qt.formatTime(new Date(), "hh:mm:ss")
    property string dismissedBatteryWarningKey: ""
    property string dismissedWindWarningKey: ""
    property string lastVehicleWarningMessage: ""
    property string lastVehicleWarningKey: ""
    property string dismissedVehicleWarningKey: ""
    property string lastVehicleWarningTime: ""
    property var modernNavSections: [
        { label: "FLY", key: "fly", icon: "/qmlimages/PaperPlane.svg" },
        { label: "PLAN", key: "plan", icon: "/qmlimages/Plan.svg" },
        { label: "ANALYZE", key: "analyze", icon: "/qmlimages/Analyze.svg" },
        { label: "VEHICLE", key: "vehicle", icon: "/qmlimages/Gears.svg" }
    ]
    property var missionCoordinates: []
    property bool missionTimelineInspectionMode: false

    PlanMasterController {
        id: modernPlanController
        flyView: true

        Component.onCompleted: {
            modernPlanController.start()
            root.syncMissionCoordinates()
        }
    }

    BriechAirspaceManager {
        id: riskDataManager
        apiKey: root.openAipToken
        apiKeyHeader: "x-openaip-api-key"

        onZonesChanged: function(zones) { root.setRiskZones(zones) }
        onWeatherAlertsChanged: function(weatherAlerts) { root.setWeatherAlerts(weatherAlerts) }
        onFailed: function(message) {
            root.pushToast(qsTr("Risk Data"), message, "warn", 3200)
        }
        onDeferred: function(delayMs) {
            riskMapRefreshTimer.interval = Math.max(1000, delayMs)
            riskMapRefreshTimer.restart()
        }
    }

    BriechAirspaceManager {
        id: airportDataManager
        apiKey: root.openAipToken
        apiKeyHeader: "x-openaip-api-key"
        minRequestIntervalMs: 30000

        onZonesChanged: function(zones) { root.setAirportRiskZones(zones) }
        onFailed: function(message) {
            root.pushToast(qsTr("Airport Data"), message, "warn", 3000)
        }
        onDeferred: function(delayMs) {
            airportRiskMapRefreshTimer.interval = Math.max(1000, delayMs)
            airportRiskMapRefreshTimer.restart()
        }
    }

    ListModel {
        id: toastModel
    }

    function telemetryValue(fact, fallback) {
        return fact ? fact.valueString : fallback
    }

    function numericFactValue(fact, fallback) {
        if (!fact) {
            return fallback
        }
        const value = Number(fact.rawValue)
        return isNaN(value) ? fallback : value
    }

    function currentBatteryPercent() {
        if (activeVehicle && activeVehicle.batteries && activeVehicle.batteries.count > 0) {
            let lowest = NaN
            for (let i = 0; i < activeVehicle.batteries.count; i++) {
                const battery = activeVehicle.batteries.get(i)
                const percent = battery && battery.percentRemaining ? Number(battery.percentRemaining.rawValue) : NaN
                if (!isNaN(percent) && (isNaN(lowest) || percent < lowest)) {
                    lowest = percent
                }
            }
            if (!isNaN(lowest)) {
                return lowest
            }
        }
        return NaN
    }

    function batteryPercentText() {
        const percent = currentBatteryPercent()
        return isNaN(percent) ? "--" : Math.round(percent) + "%"
    }

    function distanceMetersBetween(fromCoordinate, toCoordinate) {
        if (!fromCoordinate || !toCoordinate || !fromCoordinate.isValid || !toCoordinate.isValid) {
            return 0
        }
        return fromCoordinate.distanceTo(toCoordinate)
    }

    function missionTimelineAvailable() {
        return missionCoordinates.length > 0 && !!_missionController && _missionController.missionItemCount > 0
    }

    function missionTimelineIndexForSequence(sequenceNumber) {
        if (!_visualItems || missionCoordinates.length === 0) {
            return -1
        }
        let missionIndex = 0
        for (let i = 0; i < _visualItems.count; i++) {
            const item = _visualItems.get(i)
            if (!isTimelineMissionItem(item)) {
                continue
            }
            if (item.sequenceNumber >= sequenceNumber) {
                return missionIndex
            }
            missionIndex++
        }
        return missionCoordinates.length
    }

    function currentMissionTimelineIndex() {
        if (!missionTimelineAvailable()) {
            return -1
        }
        const sequenceNumber = _missionController.currentMissionIndex
        if (sequenceNumber < 0) {
            return 0
        }
        return missionTimelineIndexForSequence(sequenceNumber)
    }

    function missionTimelineComplete() {
        if (!missionTimelineAvailable()) {
            return false
        }
        const sequenceNumber = _missionController.currentMissionIndex
        return sequenceNumber >= 0 && sequenceNumber >= _missionController.missionItemCount
    }

    function missionTimelineLiveIndex() {
        if (!missionTimelineAvailable()) {
            return 0
        }
        const liveIndex = currentMissionTimelineIndex()
        if (liveIndex < 0) {
            return 0
        }
        return Math.max(0, Math.min(liveIndex, missionCoordinates.length - 1))
    }

    function missionTimelineDisplayedIndex() {
        if (!missionTimelineAvailable()) {
            return 0
        }
        if (missionTimelineInspectionMode) {
            return Math.max(0, Math.min(missionScrubIndex, missionCoordinates.length - 1))
        }
        return missionTimelineLiveIndex()
    }

    function missionTimelineNextIndex() {
        if (!missionTimelineAvailable() || missionTimelineComplete()) {
            return -1
        }
        const liveIndex = missionTimelineLiveIndex()
        return liveIndex < missionCoordinates.length - 1 ? liveIndex + 1 : -1
    }

    function missionTimelineSequenceText() {
        if (!missionTimelineAvailable()) {
            return "SEQ --"
        }
        const sequenceNumber = _missionController.currentMissionIndex
        return sequenceNumber >= 0 ? qsTr("SEQ %1").arg(sequenceNumber) : qsTr("SEQ STAGED")
    }

    function missionWaypointProgressText() {
        if (!missionTimelineAvailable()) {
            return "WP -- / --"
        }
        const liveIndex = missionTimelineLiveIndex()
        if (missionTimelineComplete()) {
            return qsTr("WP %1 / %2").arg(missionCoordinates.length).arg(missionCoordinates.length)
        }
        return qsTr("WP %1 / %2").arg(Math.min(liveIndex + 1, missionCoordinates.length)).arg(missionCoordinates.length)
    }

    function missionCurrentWaypointLabel() {
        if (!missionTimelineAvailable()) {
            return "--"
        }
        if (missionTimelineComplete()) {
            return qsTr("COMPLETE")
        }
        return qsTr("WP %1").arg(missionTimelineLiveIndex() + 1)
    }

    function missionNextWaypointLabel() {
        const nextIndex = missionTimelineNextIndex()
        return nextIndex >= 0 ? qsTr("WP %1").arg(nextIndex + 1) : "--"
    }

    function missionTimelineStatusText() {
        if (!missionTimelineAvailable()) {
            return qsTr("NO MISSION")
        }
        if (missionTimelineComplete()) {
            return qsTr("COMPLETE")
        }
        if (_missionController.currentMissionIndex < 0) {
            return qsTr("STAGED")
        }
        return missionTimelineInspectionMode ? qsTr("INSPECT") : qsTr("ACTIVE")
    }

    function missionRemainingDistanceMeters() {
        if (!missionTimelineAvailable()) {
            return NaN
        }
        if (missionTimelineComplete()) {
            return 0
        }

        const liveIndex = missionTimelineLiveIndex()
        let remainingDistance = 0
        const firstTarget = missionCoordinateAt(liveIndex)
        const liveVehicleCoordinate = activeVehicle && activeVehicle.coordinate && activeVehicle.coordinate.isValid
            ? activeVehicle.coordinate
            : QtPositioning.coordinate()

        if (liveVehicleCoordinate.isValid && firstTarget && firstTarget.isValid) {
            remainingDistance += distanceMetersBetween(liveVehicleCoordinate, firstTarget)
        }

        for (let i = liveIndex; i < missionCoordinates.length - 1; i++) {
            remainingDistance += distanceMetersBetween(missionCoordinates[i], missionCoordinates[i + 1])
        }

        return remainingDistance
    }

    function missionEtaSeconds() {
        const remainingDistance = missionRemainingDistanceMeters()
        const groundSpeed = activeVehicle ? numericFactValue(activeVehicle.groundSpeed, NaN) : NaN
        if (isNaN(remainingDistance) || isNaN(groundSpeed) || groundSpeed <= 0.5) {
            return NaN
        }
        return remainingDistance / groundSpeed
    }

    function formatMissionDistance(meters) {
        if (isNaN(meters)) {
            return "--"
        }
        if (meters >= 1000) {
            return (meters / 1000).toFixed(meters >= 10000 ? 0 : 1) + " km"
        }
        return Math.round(meters) + " m"
    }

    function formatMissionEta(seconds) {
        if (isNaN(seconds) || seconds < 0) {
            return "--"
        }
        const totalSeconds = Math.round(seconds)
        const hours = Math.floor(totalSeconds / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const secs = totalSeconds % 60
        if (hours > 0) {
            return qsTr("%1h %2m").arg(hours).arg(minutes)
        }
        if (minutes > 0) {
            return qsTr("%1m %2s").arg(minutes).arg(secs)
        }
        return qsTr("%1s").arg(secs)
    }

    function missionBatteryAtHomePercent() {
        if (!missionTimelineAvailable() || !activeVehicle) {
            return NaN
        }
        const currentPercent = currentBatteryPercent()
        const homeCoordinate = activeVehicle.homePosition && activeVehicle.homePosition.isValid
            ? activeVehicle.homePosition
            : QtPositioning.coordinate()
        const flownMeters = activeVehicle.flightDistance ? Number(activeVehicle.flightDistance.rawValue) : NaN
        if (isNaN(currentPercent) || !homeCoordinate.isValid || isNaN(flownMeters) || flownMeters < 500 || batteryHistory.length < 2) {
            return NaN
        }

        const firstPercent = Number(batteryHistory[0])
        const lastPercent = Number(batteryHistory[batteryHistory.length - 1])
        const usedPercent = firstPercent - lastPercent
        if (isNaN(usedPercent) || usedPercent < 2) {
            return NaN
        }

        const percentPerMeter = usedPercent / flownMeters
        if (!(percentPerMeter > 0)) {
            return NaN
        }

        const remainingMissionDistance = missionRemainingDistanceMeters()
        if (isNaN(remainingMissionDistance)) {
            return NaN
        }

        const missionEndCoordinate = missionCoordinates.length > 0
            ? missionCoordinateAt(missionCoordinates.length - 1)
            : QtPositioning.coordinate()
        const returnDistance = missionEndCoordinate && missionEndCoordinate.isValid
            ? distanceMetersBetween(missionEndCoordinate, homeCoordinate)
            : (activeVehicle.coordinate && activeVehicle.coordinate.isValid ? distanceMetersBetween(activeVehicle.coordinate, homeCoordinate) : 0)

        const estimate = currentPercent - (percentPerMeter * (remainingMissionDistance + returnDistance))
        if (isNaN(estimate)) {
            return NaN
        }
        return Math.max(0, Math.min(100, estimate))
    }

    function missionBatteryAtHomeEstimateText() {
        const estimate = missionBatteryAtHomePercent()
        return isNaN(estimate) ? "--" : Math.round(estimate) + "%"
    }

    function vehicleHasHealthChecks() {
        return !!activeVehicle && !!activeVehicle.healthAndArmingCheckReport && activeVehicle.healthAndArmingCheckReport.supported
    }

    function guidedActionsEnabled() {
        if (!activeVehicle) {
            return false
        }
        const options = QGroundControl.corePlugin.options
        if (ScreenTools.isDebug || !options.guidedActionsRequireRCRSSI) {
            return true
        }
        return activeVehicle.rcRSSI > 0 && activeVehicle.rcRSSI <= 100
    }

    function checklistPassed() {
        if (!activeVehicle) {
            return false
        }
        const appSettings = QGroundControl.settingsManager.appSettings
        const checklistAvailable = appSettings.useChecklist.rawValue
            && QGroundControl.corePlugin.options.preFlightChecklistUrl.toString().length > 0
        if (!checklistAvailable || !appSettings.enforceChecklist.rawValue) {
            return true
        }
        return activeVehicle.checkListState === Vehicle.CheckListPassed
    }

    function healthAllowsArm() {
        return !!activeVehicle
            && checklistPassed()
            && (!activeVehicle.healthAndArmingCheckReport.supported || activeVehicle.healthAndArmingCheckReport.canArm)
    }

    function healthAllowsTakeoff() {
        return !!activeVehicle
            && checklistPassed()
            && (!activeVehicle.healthAndArmingCheckReport.supported || activeVehicle.healthAndArmingCheckReport.canTakeoff)
    }

    function vehicleCanArm() {
        if (!activeVehicle) {
            return false
        }
        if (activeVehicle.armed) {
            return true
        }
        return guidedActionsEnabled() && healthAllowsArm()
    }

    function vehicleReadyText() {
        if (!activeVehicle) {
            return qsTr("Disconnected")
        }
        if (activeVehicle.armed) {
            if (activeVehicle.landing) {
                return qsTr("Landing")
            }
            if (activeVehicle.flying) {
                return qsTr("Flying")
            }
            return qsTr("Armed")
        }
        return vehicleCanArm() ? qsTr("Ready") : qsTr("Not Ready")
    }

    function vehicleStatusText() {
        if (!activeVehicle) {
            return qsTr("Disconnected - Click to manually connect")
        }
        if (pendingVehicleAction !== "") {
            return qsTr("BRCH-%1 - %2 COMMAND PENDING").arg(activeVehicle.id).arg(pendingVehicleAction.toUpperCase())
        }
        return qsTr("BRCH-%1 - %2 - %3").arg(activeVehicle.id).arg(activeVehicle.flightMode).arg(vehicleReadyText())
    }

    function gpsStatusText() {
        if (!activeVehicle || !activeVehicle.gps) {
            return "--"
        }
        const lockValue = activeVehicle.gps.lock ? Number(activeVehicle.gps.lock.rawValue) : 0
        const satCount = activeVehicle.gps.count ? activeVehicle.gps.count.valueString : "--"
        const hdop = activeVehicle.gps.hdop ? activeVehicle.gps.hdop.valueString : "--"

        if (lockValue >= 3) {
            return qsTr("3D/%1").arg(satCount)
        }
        if (lockValue === 2) {
            return qsTr("2D/%1").arg(satCount)
        }
        if (lockValue > 0) {
            return qsTr("LOCK/%1").arg(satCount)
        }
        if (hdop !== "--") {
            return qsTr("HDOP %1").arg(hdop)
        }
        return qsTr("NO FIX")
    }

    function hasVideoSignal() {
        return QGroundControl.videoManager.hasVideo || QGroundControl.videoManager.isStreamSource || QGroundControl.videoManager.isUvc || QGroundControl.videoManager.decoding
    }

    function viewer3DReady() {
        return QGroundControl.settingsManager.viewer3DSettings.enabled.rawValue
    }

    function hasNavigationTarget() {
        return (activeVehicle && activeVehicle.coordinate.isValid) || QGroundControl.flightMapPosition.isValid || defaultCenter.isValid
    }

    function headingText() {
        if (!activeVehicle || !activeVehicle.heading) {
            return "--"
        }
        const heading = Number(activeVehicle.heading.rawValue)
        return isNaN(heading) ? "--" : Math.round(heading).toString()
    }

    function normalizedHeadingText() {
        if (!activeVehicle || !activeVehicle.heading) {
            return "---"
        }
        const heading = Number(activeVehicle.heading.rawValue)
        if (isNaN(heading)) {
            return "---"
        }
        const normalized = ((Math.round(heading) % 360) + 360) % 360
        return ("000" + normalized).slice(-3)
    }

    function headingDegreesValue() {
        if (!activeVehicle || !activeVehicle.heading) {
            return 0
        }
        const heading = Number(activeVehicle.heading.rawValue)
        return isNaN(heading) ? 0 : heading
    }

    function hudRollAngle() {
        return activeVehicle ? numericFactValue(activeVehicle.roll, 0) : 0
    }

    function hudPitchAngle() {
        return activeVehicle ? numericFactValue(activeVehicle.pitch, 0) : 0
    }

    function hudClimbRateText() {
        return activeVehicle ? telemetryValue(activeVehicle.climbRate, "--") : "--"
    }

    function hudSpeedLabel() {
        if (!activeVehicle) {
            return "IAS"
        }
        const airspeed = numericFactValue(activeVehicle.airSpeed, NaN)
        return !isNaN(airspeed) && airspeed > 0.1 ? "IAS" : "GS"
    }

    function hudSpeedText() {
        if (!activeVehicle) {
            return "--"
        }
        const airspeed = numericFactValue(activeVehicle.airSpeed, NaN)
        if (!isNaN(airspeed) && airspeed > 0.1) {
            return telemetryValue(activeVehicle.airSpeed, "--")
        }
        return telemetryValue(activeVehicle.groundSpeed, "--")
    }

    function altitudeText() {
        return activeVehicle ? telemetryValue(activeVehicle.altitudeRelative, "--") : "--"
    }

    function groundSpeedText() {
        return activeVehicle ? telemetryValue(activeVehicle.groundSpeed, "--") : "--"
    }

    function flightModeText() {
        return activeVehicle ? activeVehicle.flightMode : "--"
    }

    function flightTimeText() {
        return activeVehicle && activeVehicle.flightTime ? activeVehicle.flightTime.valueString : "--"
    }

    function flightDistanceText() {
        return activeVehicle && activeVehicle.flightDistance ? activeVehicle.flightDistance.valueString : "--"
    }

    function hobbsText() {
        if (!activeVehicle || !activeVehicle.hobbsMeter) {
            return "--"
        }
        return String(activeVehicle.hobbsMeter).length > 0 ? activeVehicle.hobbsMeter : "--"
    }

    function messageCountText() {
        return activeVehicle ? String(activeVehicle.messageCount || 0) : "0"
    }

    function vehicleMessageIconColor() {
        if (!activeVehicle) {
            return root.dim
        }
        if (activeVehicle.messageTypeError) {
            return root.err
        }
        if (activeVehicle.messageTypeWarning) {
            return root.warn
        }
        return root.text
    }

    function batteryPackCountText() {
        if (!activeVehicle || !activeVehicle.batteries) {
            return "0"
        }
        const count = activeVehicle.batteries.count || 0
        return count === 1 ? qsTr("1 PACK") : qsTr("%1 PACKS").arg(count)
    }

    function gpsDetailText() {
        if (!activeVehicle || !activeVehicle.gps) {
            return "--"
        }
        const satCount = activeVehicle.gps.count ? activeVehicle.gps.count.valueString : "--"
        const hdop = activeVehicle.gps.hdop ? activeVehicle.gps.hdop.valueString : "--"
        return qsTr("%1 SAT | HDOP %2").arg(satCount).arg(hdop)
    }

    function prearmStatusText() {
        if (!activeVehicle) {
            return qsTr("No vehicle linked")
        }
        if (lastVehicleWarningMessage.length > 0
                && (lastVehicleWarningMessage.toLowerCase().indexOf("prearm") !== -1
                    || lastVehicleWarningMessage.toLowerCase().indexOf("hardware safety") !== -1
                    || lastVehicleWarningMessage.toLowerCase().indexOf("not armable") !== -1)) {
            return lastVehicleWarningMessage
        }
        if (activeVehicle.prearmError && String(activeVehicle.prearmError).length > 0) {
            return activeVehicle.prearmError
        }
        if (vehicleCanArm()) {
            return qsTr("Checks clear")
        }
        return qsTr("Waiting for readiness")
    }

    function readinessProblemCount() {
        if (!vehicleHasHealthChecks() || !activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode) {
            return 0
        }
        return activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode.count || 0
    }

    function readinessProblemsText() {
        const count = readinessProblemCount()
        if (count <= 0) {
            return qsTr("No active blockers")
        }
        return count === 1 ? qsTr("1 active issue") : qsTr("%1 active issues").arg(count)
    }

    function setupComponentsModel() {
        if (!activeVehicle || !activeVehicle.autopilotPlugin) {
            return null
        }
        return activeVehicle.autopilotPlugin.vehicleComponents
    }

    function setupComponentCount() {
        const model = setupComponentsModel()
        return model ? (model.count || 0) : 0
    }

    function setupComponentCompleteCount() {
        const model = setupComponentsModel()
        if (!model) {
            return 0
        }
        let completed = 0
        for (let index = 0; index < model.count; index++) {
            const component = model.get(index)
            if (component && (!component.requiresSetup || component.setupComplete)) {
                completed++
            }
        }
        return completed
    }

    function setupProgressText() {
        const total = setupComponentCount()
        if (total <= 0) {
            return "--"
        }
        return qsTr("%1/%2").arg(setupComponentCompleteCount()).arg(total)
    }

    function vibrationPeakValue() {
        if (!activeVehicle || !activeVehicle.vibration) {
            return NaN
        }
        const x = numericFactValue(activeVehicle.vibration.xAxis, NaN)
        const y = numericFactValue(activeVehicle.vibration.yAxis, NaN)
        const z = numericFactValue(activeVehicle.vibration.zAxis, NaN)
        const values = [x, y, z].filter(function(value) { return !isNaN(value) })
        if (values.length === 0) {
            return NaN
        }
        return Math.max.apply(Math, values)
    }

    function vibrationStatusText() {
        const peak = vibrationPeakValue()
        if (isNaN(peak)) {
            return "--"
        }
        if (peak >= 60) {
            return qsTr("HIGH %1").arg(peak.toFixed(1))
        }
        if (peak >= 30) {
            return qsTr("ELEV %1").arg(peak.toFixed(1))
        }
        return qsTr("NOM %1").arg(peak.toFixed(1))
    }

    function vibrationClipText() {
        if (!activeVehicle || !activeVehicle.vibration) {
            return "--"
        }
        const c1 = numericFactValue(activeVehicle.vibration.clipCount1, 0)
        const c2 = numericFactValue(activeVehicle.vibration.clipCount2, 0)
        const c3 = numericFactValue(activeVehicle.vibration.clipCount3, 0)
        return qsTr("%1/%2/%3").arg(c1).arg(c2).arg(c3)
    }

    function historyAverage(values) {
        if (!values || values.length === 0) {
            return NaN
        }
        let total = 0
        let count = 0
        for (let i = 0; i < values.length; i++) {
            const value = Number(values[i])
            if (!isNaN(value)) {
                total += value
                count++
            }
        }
        return count > 0 ? total / count : NaN
    }

    function historyMin(values) {
        if (!values || values.length === 0) {
            return NaN
        }
        let result = NaN
        for (let i = 0; i < values.length; i++) {
            const value = Number(values[i])
            if (!isNaN(value) && (isNaN(result) || value < result)) {
                result = value
            }
        }
        return result
    }

    function historyMax(values) {
        if (!values || values.length === 0) {
            return NaN
        }
        let result = NaN
        for (let i = 0; i < values.length; i++) {
            const value = Number(values[i])
            if (!isNaN(value) && (isNaN(result) || value > result)) {
                result = value
            }
        }
        return result
    }

    function telemetryAverageText(values, decimals, suffix) {
        const average = historyAverage(values)
        return isNaN(average) ? "--" : average.toFixed(decimals) + suffix
    }

    function telemetryRangeText(values, decimals, suffix) {
        const low = historyMin(values)
        const high = historyMax(values)
        if (isNaN(low) || isNaN(high)) {
            return "--"
        }
        return low.toFixed(decimals) + suffix + " - " + high.toFixed(decimals) + suffix
    }

    function logEntryCount() {
        return LogDownloadController && LogDownloadController.model ? (LogDownloadController.model.count || 0) : 0
    }

    function logStatusText() {
        if (LogDownloadController.downloadingLogs) {
            return qsTr("Downloading logs")
        }
        if (LogDownloadController.requestingList) {
            return qsTr("Refreshing log list")
        }
        const count = logEntryCount()
        if (!activeVehicle) {
            return qsTr("Awaiting vehicle")
        }
        if (count <= 0) {
            return qsTr("No logs listed yet")
        }
        return count === 1 ? qsTr("1 log available") : qsTr("%1 logs available").arg(count)
    }

    function logStateTone() {
        if (LogDownloadController.downloadingLogs || LogDownloadController.requestingList) {
            return root.gold
        }
        return logEntryCount() > 0 ? root.ok : root.dim
    }

    function mapTypeKeywords(kind) {
        switch (String(kind || "").toLowerCase()) {
        case "street":
            return ["street", "road", "map"]
        case "satellite":
            return ["satellite", "sat"]
        case "terrain":
            return ["terrain", "topo", "topographic"]
        case "hybrid":
            return ["hybrid"]
        case "default":
            return [String(QGroundControl.settingsManager.flightMapSettings.mapType.rawValue || QGroundControl.settingsManager.flightMapSettings.mapType.value || "").toLowerCase()]
        default:
            return [String(kind || "").toLowerCase()]
        }
    }

    function findModernMapType(kind) {
        if (!modernMap || !modernMap.mapReady || !modernMap.supportedMapTypes) {
            return null
        }
        const keywords = mapTypeKeywords(kind)
        for (let i = 0; i < modernMap.supportedMapTypes.length; i++) {
            const candidate = modernMap.supportedMapTypes[i]
            const candidateName = String(candidate.name || "").toLowerCase()
            for (let keywordIndex = 0; keywordIndex < keywords.length; keywordIndex++) {
                if (keywords[keywordIndex] !== "" && candidateName.indexOf(keywords[keywordIndex]) !== -1) {
                    return candidate
                }
            }
        }
        return null
    }

    function setModernMapKind(kind) {
        if (!modernMap || !modernMap.mapReady) {
            return
        }
        const candidate = findModernMapType(kind)
        if (candidate) {
            modernMap.activeMapType = candidate
            selectedMapKind = kind
            pushToast(qsTr("Map"), qsTr("%1 map selected.").arg(String(kind).toUpperCase()), "info", 1600)
        } else {
            selectedMapKind = "default"
            pushToast(qsTr("Map"), qsTr("Requested map type is not available in the current provider."), "warn", 2400)
        }
    }

    function modernMapLayerModel() {
        return [
            { label: "DEFAULT", key: "default", active: selectedMapKind === "default", available: !!modernMap && modernMap.mapReady },
            { label: "SATELLITE", key: "satellite", active: selectedMapKind === "satellite", available: findModernMapType("satellite") !== null },
            { label: "STREET", key: "street", active: selectedMapKind === "street", available: findModernMapType("street") !== null },
            { label: "TERRAIN", key: "terrain", active: selectedMapKind === "terrain", available: findModernMapType("terrain") !== null },
            { label: "HYBRID", key: "hybrid", active: selectedMapKind === "hybrid", available: findModernMapType("hybrid") !== null }
        ]
    }

    function modernDiagnosticsModel() {
        return [
            { label: "MAP", value: modernMap && modernMap.mapReady ? "READY" : "LOADING", tone: modernMap && modernMap.mapReady ? root.ok : root.warn },
            { label: "MAP TYPE", value: selectedMapKind.toUpperCase(), tone: root.gold },
            { label: "VEHICLE", value: activeVehicle ? ("BRCH-" + activeVehicle.id) : "NONE", tone: activeVehicle ? root.ok : root.dim },
            { label: "VIDEO", value: hasVideoSignal() ? "LIVE" : "IDLE", tone: hasVideoSignal() ? root.ok : root.dim },
            { label: "3D", value: viewer3DReady() ? "READY" : "OFF", tone: viewer3DReady() ? root.ok : root.dim },
            { label: "AIRSPACE", value: airspaceStatusText(), tone: airspaceStateColor() },
            { label: "LOGS", value: logStatusText(), tone: logStateTone() },
            { label: "WATERMARK", value: modernWatermarkEnabled ? "ON" : "OFF", tone: modernWatermarkEnabled ? root.gold : root.dim }
        ]
    }

    function vehicleIdentityModel() {
        return [
            { label: "MAV ID", value: activeVehicle ? String(activeVehicle.id) : "--", tone: root.text },
            { label: "FIRMWARE", value: activeVehicle ? String(activeVehicle.firmwareTypeString || activeVehicle.firmwareType || "--") : "--", tone: root.text },
            { label: "TYPE", value: activeVehicle ? String(activeVehicle.vehicleTypeString || activeVehicle.vehicleType || "--") : "--", tone: root.text },
            { label: "MODE", value: flightModeText(), tone: root.ok }
        ]
    }

    function vehicleCapabilityModel() {
        return [
            { label: "GUIDED", value: activeVehicle && activeVehicle.guidedModeSupported ? "YES" : "NO", tone: activeVehicle && activeVehicle.guidedModeSupported ? root.ok : root.dim },
            { label: "TAKEOFF", value: activeVehicle && activeVehicle.takeoffVehicleSupported ? "YES" : "NO", tone: activeVehicle && activeVehicle.takeoffVehicleSupported ? root.ok : root.dim },
            { label: "PAUSE", value: activeVehicle && activeVehicle.pauseVehicleSupported ? "YES" : "NO", tone: activeVehicle && activeVehicle.pauseVehicleSupported ? root.ok : root.dim },
            { label: "RTL", value: activeVehicle && activeVehicle.rtlFlightMode ? "YES" : "NO", tone: activeVehicle && activeVehicle.rtlFlightMode ? root.ok : root.dim },
            { label: "FIXED WING", value: activeVehicle && activeVehicle.fixedWing ? "YES" : "NO", tone: activeVehicle && activeVehicle.fixedWing ? root.gold : root.dim },
            { label: "MULTIROTOR", value: activeVehicle && activeVehicle.multiRotor ? "YES" : "NO", tone: activeVehicle && activeVehicle.multiRotor ? root.gold : root.dim }
        ]
    }

    function vehiclePowerModel() {
        const percent = currentBatteryPercent()
        return [
            { label: "BATTERY", value: batteryPercentText(), tone: isNaN(percent) ? root.dim : (percent <= 30 ? root.err : root.ok) },
            { label: "PACKS", value: batteryPackCountText(), tone: root.text },
            { label: "USED", value: batteryUsedText(), tone: root.gold },
            { label: "HOME EST", value: missionBatteryAtHomeEstimateText(), tone: missionBatteryAtHomeEstimateText() === "--" ? root.dim : root.ok }
        ]
    }

    function vehicleLinkModel() {
        return [
            { label: "QUALITY", value: linkQualityText(), tone: isNaN(linkQualityValue()) ? root.dim : (linkQualityValue() < 90 ? root.warn : root.ok) },
            { label: "LOSS", value: activeVehicle ? String(activeVehicle.mavlinkLossCount || 0) : "--", tone: root.text },
            { label: "MESSAGES", value: messageCountText(), tone: Number(messageCountText()) > 0 ? root.warn : root.ok },
            { label: "RC", value: activeVehicle ? String(activeVehicle.rcRSSI || "--") : "--", tone: guidedActionsEnabled() ? root.ok : root.warn }
        ]
    }

    function vehicleGpsModel() {
        return [
            { label: "GPS", value: gpsStatusText(), tone: gpsStatusText() === "NO FIX" ? root.warn : root.ok },
            { label: "DETAIL", value: gpsDetailText(), tone: root.text },
            { label: "COORD", value: activeVehicle && activeVehicle.coordinate.isValid ? activeVehicle.coordinate.latitude.toFixed(6) + ", " + activeVehicle.coordinate.longitude.toFixed(6) : "--", tone: root.text },
            { label: "HOME", value: activeVehicle && activeVehicle.homePosition && activeVehicle.homePosition.isValid ? "SET" : "--", tone: activeVehicle && activeVehicle.homePosition && activeVehicle.homePosition.isValid ? root.ok : root.dim }
        ]
    }

    function vehicleCommandStateModel() {
        return [
            { label: "ARM", value: vehicleCanArm() ? "AVAILABLE" : "BLOCKED", tone: vehicleCanArm() ? root.ok : root.warn },
            { label: "TAKEOFF", value: vehicleCanTakeoff() ? "AVAILABLE" : "BLOCKED", tone: vehicleCanTakeoff() ? root.ok : root.dim },
            { label: "LAND", value: vehicleCanLand() ? "AVAILABLE" : "BLOCKED", tone: vehicleCanLand() ? root.ok : root.dim },
            { label: "RTL", value: vehicleCanRTL() ? "AVAILABLE" : "BLOCKED", tone: vehicleCanRTL() ? root.ok : root.dim }
        ]
    }

    function analyzeSessionSummaryModel() {
        return [
            { label: "FLIGHT TIME", value: flightTimeText(), tone: root.text },
            { label: "DISTANCE", value: flightDistanceText(), tone: root.text },
            { label: "HOBBS", value: hobbsText(), tone: root.text },
            { label: "EVENT MSGS", value: messageCountText(), tone: Number(messageCountText()) > 0 ? root.warn : root.ok },
            { label: "READINESS", value: vehicleReadyText(), tone: vehicleCanArm() ? root.ok : root.warn },
            { label: "AIRSPACE", value: root.visibleRiskZones().length + " ZONES", tone: root.gold }
        ]
    }

    function analyzeTelemetrySummaryModel() {
        return [
            { label: "ALT AVG", value: telemetryAverageText(root.altitudeHistory, 1, " m"), tone: root.text },
            { label: "ALT RANGE", value: telemetryRangeText(root.altitudeHistory, 1, " m"), tone: root.text },
            { label: "SPD AVG", value: telemetryAverageText(root.speedHistory, 1, " m/s"), tone: root.text },
            { label: "SPD RANGE", value: telemetryRangeText(root.speedHistory, 1, " m/s"), tone: root.text },
            { label: "BATT AVG", value: telemetryAverageText(root.batteryHistory, 0, "%"), tone: root.ok },
            { label: "BATT RANGE", value: telemetryRangeText(root.batteryHistory, 0, "%"), tone: root.warn }
        ]
    }

    function batteryUsedText() {
        if (!batteryHistory || batteryHistory.length < 2) {
            return "--"
        }
        const first = Number(batteryHistory[0])
        const last = Number(batteryHistory[batteryHistory.length - 1])
        if (isNaN(first) || isNaN(last)) {
            return "--"
        }
        return Math.max(0, Math.round(first - last)) + "%"
    }

    function linkQualityValue() {
        if (!activeVehicle) {
            return NaN
        }
        const lossPercent = Number(activeVehicle.mavlinkLossPercent)
        return isNaN(lossPercent) ? NaN : Math.round(Math.max(0, Math.min(100, 100 - lossPercent)))
    }

    function linkQualityText() {
        const value = linkQualityValue()
        return isNaN(value) ? "--" : value + "%"
    }

    function missionDescriptorText() {
        if (activeVehicle) {
            return qsTr("BRCH-%1 / %2").arg(activeVehicle.id).arg(activeVehicle.coordinate.isValid ? qsTr("Live Session") : qsTr("Link Pending"))
        }
        return qsTr("No active mission")
    }

    function sessionStatusText() {
        if (!activeVehicle) {
            return "NO DATA"
        }
        return readinessProblemCount() > 0 ? "CHECK" : "NOMINAL"
    }

    function sessionStatusTone(status) {
        switch (status) {
        case "CHECK":
            return root.warn
        case "NO DATA":
            return root.dim
        default:
            return root.ok
        }
    }

    function missionSummaryText() {
        const wpCount = missionCoordinates.length
        const battery = batteryPercentText()
        const mode = flightModeText()
        return qsTr("%1 | mode %2 | mission points %3 | battery %4 | airspace zones %5")
            .arg(activeVehicle ? ("BRCH-" + activeVehicle.id) : qsTr("Unavailable"))
            .arg(mode)
            .arg(wpCount)
            .arg(battery)
            .arg(visibleRiskZones().length)
    }

    function sessionChecklistModel() {
        return [
            { label: qsTr("Telemetry samples: %1").arg(speedHistory.length), tone: speedHistory.length > 1 ? root.ok : root.dim },
            { label: qsTr("GPS: %1").arg(gpsStatusText()), tone: gpsStatusText() === "NO FIX" ? root.warn : root.ok },
            { label: qsTr("Battery: %1").arg(batteryPercentText()), tone: isNaN(currentBatteryPercent()) ? root.dim : (currentBatteryPercent() <= 30 ? root.err : root.ok) },
            { label: qsTr("Packet delivery: %1").arg(linkQualityText()), tone: isNaN(linkQualityValue()) ? root.dim : (linkQualityValue() < 90 ? root.warn : root.ok) },
            { label: qsTr("Visible airspace zones: %1").arg(visibleRiskZones().length), tone: root.gold }
        ]
    }

    function recentMissionModel() {
        const items = []
        if (activeVehicle) {
            items.push({
                title: qsTr("ACTIVE VEHICLE"),
                detail: qsTr("%1 | %2 | %3 WP").arg(flightModeText()).arg(flightTimeText()).arg(missionCoordinates.length),
                status: vehicleReadyText().toUpperCase(),
                tone: vehicleCanArm() ? root.ok : root.warn
            })
        }
        if (lastVehicleWarningMessage.length > 0) {
            items.push({
                title: qsTr("LAST VEHICLE WARNING"),
                detail: lastVehicleWarningMessage,
                status: lastVehicleWarningTime.length > 0 ? lastVehicleWarningTime : qsTr("LIVE"),
                tone: root.warn
            })
        }
        if (logEntryCount() > 0) {
            items.push({
                title: qsTr("ONBOARD LOGS"),
                detail: qsTr("%1 listed | %2").arg(logEntryCount()).arg(logStatusText()),
                status: qsTr("READY").toUpperCase(),
                tone: logStateTone()
            })
        }
        if (visibleRiskZones().length > 0) {
            items.push({
                title: qsTr("AIRSPACE WATCH"),
                detail: qsTr("%1 visible zones").arg(visibleRiskZones().length),
                status: qsTr("LIVE"),
                tone: root.gold
            })
        }
        return items
    }

    function analyzeInsightCards() {
        return [
            {
                title: "VEHICLE READINESS",
                body: activeVehicle ? readinessProblemsText() : qsTr("Connect a vehicle to inspect live readiness and prearm status."),
                badge: sessionStatusText(),
                tone: sessionStatusTone(sessionStatusText())
            },
            {
                title: "LINK STATUS",
                body: activeVehicle
                    ? qsTr("MAVLink packet delivery is %1 with %2 lost messages recorded in this connection.").arg(linkQualityText()).arg(activeVehicle.mavlinkLossCount)
                    : qsTr("Connect a vehicle to inspect MAVLink packet delivery and message loss."),
                badge: linkQualityText(),
                tone: isNaN(linkQualityValue()) ? root.dim : (linkQualityValue() < 90 ? root.warn : root.ok)
            },
            {
                title: "AIRFRAME OBSERVATION",
                body: activeVehicle
                    ? qsTr("Vibration status: %1. Observed battery change since this view started: %2.").arg(vibrationStatusText()).arg(batteryUsedText())
                    : qsTr("Connect a vehicle to inspect vibration and observed battery change."),
                badge: isNaN(vibrationPeakValue()) ? "NO DATA" : vibrationStatusText().toUpperCase(),
                tone: isNaN(vibrationPeakValue()) ? root.dim : (vibrationPeakValue() >= 60 ? root.warn : root.ok)
            },
            {
                title: "LAST VEHICLE WARNING",
                body: lastVehicleWarningMessage.length > 0 ? lastVehicleWarningMessage : qsTr("No vehicle warnings captured in this Modern session."),
                badge: lastVehicleWarningMessage.length > 0 ? "CHECK" : "CLEAR",
                tone: lastVehicleWarningMessage.length > 0 ? root.warn : root.ok
            }
        ]
    }

    function analyzeMarkerText() {
        if (missionCoordinates.length > 0) {
            const index = Math.max(0, Math.min(missionScrubIndex, missionCoordinates.length - 1))
            return qsTr("WP%1").arg(index + 1)
        }
        if (speedHistory.length > 0 || altitudeHistory.length > 0 || batteryHistory.length > 0) {
            return qsTr("LIVE")
        }
        return ""
    }

    function analyzeMarkerRatio() {
        if (missionCoordinates.length > 1) {
            return Math.max(0, Math.min(1, missionScrubIndex / (missionCoordinates.length - 1)))
        }
        return speedHistory.length > 0 || altitudeHistory.length > 0 || batteryHistory.length > 0 ? 1 : NaN
    }

    function vehicleCanTakeoff() {
        return !!activeVehicle
            && guidedActionsEnabled()
            && !activeVehicle.flying
            && activeVehicle.takeoffVehicleSupported
            && healthAllowsTakeoff()
    }

    function vehicleCanDisarm() {
        return !!activeVehicle
            && guidedActionsEnabled()
            && activeVehicle.armed
            && !activeVehicle.flying
    }

    function vehicleCanLand() {
        return !!activeVehicle
            && guidedActionsEnabled()
            && activeVehicle.armed
            && activeVehicle.guidedModeSupported
            && !activeVehicle.fixedWing
            && activeVehicle.flightMode !== activeVehicle.landFlightMode
    }

    function vehicleCanRTL() {
        return !!activeVehicle
            && guidedActionsEnabled()
            && activeVehicle.armed
            && activeVehicle.guidedModeSupported
            && activeVehicle.flying
            && activeVehicle.flightMode !== activeVehicle.rtlFlightMode
            && activeVehicle.flightMode !== activeVehicle.smartRTLFlightMode
    }

    function vehicleCanPause() {
        return !!activeVehicle
            && guidedActionsEnabled()
            && activeVehicle.armed
            && activeVehicle.pauseVehicleSupported
            && activeVehicle.flying
            && activeVehicle.flightMode !== activeVehicle.pauseFlightMode
            && !(activeVehicle.fixedWing && activeVehicle.landing)
    }

    function telemetryModel() {
        return [
            { k: "ALT", v: altitudeText(), u: "m" },
            { k: "GS", v: groundSpeedText(), u: "m/s" },
            { k: "HDG", v: headingText(), u: "deg" },
            { k: "GPS", v: gpsStatusText(), u: "" },
            { k: "BATT", v: batteryPercentText(), u: "" },
            { k: "MODE", v: flightModeText(), u: "" }
        ]
    }

    function telemetrySlotKey(index) {
        switch (index) {
        case 0: return "ALT"
        case 1: return "GS"
        case 2: return "HDG"
        case 3: return "GPS"
        case 4: return "BATT"
        case 5: return "MODE"
        default: return "--"
        }
    }

    function telemetrySlotValue(index) {
        switch (index) {
        case 0: return altitudeText()
        case 1: return groundSpeedText()
        case 2: return headingText()
        case 3: return gpsStatusText()
        case 4: return batteryPercentText()
        case 5: return flightModeText()
        default: return "--"
        }
    }

    function telemetrySlotUnit(index) {
        switch (index) {
        case 0: return "m"
        case 1: return "m/s"
        case 2: return "deg"
        default: return ""
        }
    }

    function telemetrySlotValueColor(index) {
        switch (index) {
        case 4:
            return isNaN(currentBatteryPercent()) ? root.dim : (currentBatteryPercent() > 30 ? root.ok : root.err)
        case 5:
            return root.ok
        default:
            return root.text
        }
    }

    function flyActionModel() {
        const commandReady = pendingVehicleAction === ""
        return [
            { t: activeVehicle ? "DISC" : "CONNECT", s: activeVehicle ? "X" : "L", a: activeVehicle ? "disconnect" : "connect", visible: true, enabled: commandReady },
            { t: pendingVehicleAction === "arm" ? "ARM..." : (pendingVehicleAction === "disarm" ? "DISARM..." : (activeVehicle && activeVehicle.armed ? "DISARM" : "ARM")), s: activeVehicle && activeVehicle.armed ? "D" : "A", a: activeVehicle && activeVehicle.armed ? "disarm" : "arm", visible: true, enabled: commandReady && (activeVehicle && activeVehicle.armed ? vehicleCanDisarm() : vehicleCanArm()) },
            { t: pendingVehicleAction === "takeoff" ? "TAKEOFF..." : "TAKEOFF", s: "T", a: "takeoff", visible: true, enabled: commandReady && vehicleCanTakeoff() },
            { t: pendingVehicleAction === "pause" ? "PAUSE..." : "PAUSE", s: "P", a: "pause", visible: true, enabled: commandReady && vehicleCanPause() },
            { t: pendingVehicleAction === "land" ? "LAND..." : "LAND", s: "L", a: "land", visible: true, enabled: commandReady && vehicleCanLand() },
            { t: pendingVehicleAction === "rtl" ? "RTL..." : "RTL", s: "R", a: "rtl", visible: true, enabled: commandReady && vehicleCanRTL() },
            { t: "CENTER", s: "C", a: "center", visible: hasNavigationTarget(), enabled: hasNavigationTarget() },
            { t: "FIT", s: "F", a: "fit", visible: missionCoordinates.length > 1, enabled: missionCoordinates.length > 1 }
        ]
    }

    function appendSample(series, sample, maxCount) {
        const next = series.slice()
        next.push(sample)
        while (next.length > maxCount) {
            next.shift()
        }
        return next
    }

    function refreshTelemetrySamples() {
        if (!activeVehicle) {
            speedHistory = []
            altitudeHistory = []
            batteryHistory = []
            batteryPercent = NaN
            return
        }

        const speed = numericFactValue(activeVehicle.groundSpeed, 0)
        const altitude = numericFactValue(activeVehicle.altitudeRelative, 0)
        const battery = currentBatteryPercent()

        speedHistory = appendSample(speedHistory, speed, 40)
        altitudeHistory = appendSample(altitudeHistory, altitude, 40)
        if (!isNaN(battery)) {
            batteryHistory = appendSample(batteryHistory, battery, 40)
        }
        batteryPercent = battery
    }

    function pushToast(title, message, tone, durationMs) {
        toastModel.append({
            title: title,
            message: message,
            tone: tone || "info",
            expiresAt: Date.now() + (durationMs || 3500)
        })
        toastSweepTimer.start()
    }

    function formatVehicleMessageHtml(message) {
        if (!message || String(message).length === 0) {
            return ""
        }
        let formatted = String(message)
        formatted = formatted.replace(new RegExp("<#E>", "g"), "color: " + root.err + "; font: 9pt monospace;")
        formatted = formatted.replace(new RegExp("<#I>", "g"), "color: " + root.warn + "; font: 9pt monospace;")
        formatted = formatted.replace(new RegExp("<#N>", "g"), "color: " + root.text + "; font: 9pt monospace;")
        return formatted
    }

    function setRiskDataSource(url) {
        riskDataSourceTemplate = url || ""
        refreshRiskDataForMap()
    }

    function setAirportRiskDataSource(url) {
        airportRiskDataSourceTemplate = url || ""
        refreshAirportRiskDataForMap()
    }

    function openAipRiskDataSource() {
        if (!openAipToken || openAipToken.length === 0) {
            return ""
        }
        const encodedToken = encodeURIComponent(openAipToken)
        if (loadCountryAirspace && airspaceCountryCode.length > 0) {
            return "https://api.core.openaip.net/api/airspaces?page=1&limit=1000&approved=true&country="
                + encodeURIComponent(airspaceCountryCode) + "&apiKey=" + encodedToken
        }
        return "https://api.core.openaip.net/api/airspaces?page=1&limit=1000&approved=true&bbox={bbox}&apiKey=" + encodedToken
    }

    function openAipAirportDataSource() {
        if (!openAipToken || openAipToken.length === 0) {
            return ""
        }
        const encodedToken = encodeURIComponent(openAipToken)
        if (loadCountryAirspace && airspaceCountryCode.length > 0) {
            return "https://api.core.openaip.net/api/airports?page=1&limit=1000&country="
                + encodeURIComponent(airspaceCountryCode) + "&apiKey=" + encodedToken
        }
        return "https://api.core.openaip.net/api/airports?page=1&limit=1000&bbox={bbox}&apiKey=" + encodedToken
    }

    function loadDefaultRealRiskData() {
        if (riskDataSourceTemplate === "") {
            const openAipSource = openAipRiskDataSource()
            if (openAipSource !== "") {
                setRiskDataSource(openAipSource)
            }
        }

        if (airportRiskDataSourceTemplate === "") {
            const openAipAirportSource = openAipAirportDataSource()
            if (openAipAirportSource !== "") {
                setAirportRiskDataSource(openAipAirportSource)
            }
        }
    }

    function startupMapCenter() {
        if (QGroundControl.flightMapPosition.isValid) {
            return QGroundControl.flightMapPosition
        }
        if (activeVehicle && activeVehicle.coordinate.isValid) {
            return activeVehicle.coordinate
        }
        if (QGroundControl.qgcPositionManger.gcsPosition && QGroundControl.qgcPositionManger.gcsPosition.isValid) {
            return QGroundControl.qgcPositionManger.gcsPosition
        }
        if (modernMap && modernMap.gcsPosition && modernMap.gcsPosition.isValid) {
            return modernMap.gcsPosition
        }
        return defaultCenter
    }

    function applyLiveGcsLocation(coordinate) {
        if (!coordinate || !coordinate.isValid || activeVehicle) {
            return
        }
        const firstLiveFix = !liveGcsLocationReceived
        liveGcsLocationReceived = true
        if (firstLiveFix && modernMap && modernMap.mapReady && !QGroundControl.flightMapPosition.isValid) {
            modernMap.center = coordinate
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 14)
            QGroundControl.flightMapPosition = coordinate
        }
        riskZoneViewportRevision++
        airspaceTileRevision++
        if (riskDataSourceUsesMap()) {
            riskMapRefreshTimer.restart()
        }
        if (firstLiveFix) {
            pushToast(qsTr("Location"), qsTr("Ground station location acquired."), "ok", 2200)
        }
    }

    function gcsLocationText() {
        const coordinate = QGroundControl.qgcPositionManger.gcsPosition
        if (coordinate && coordinate.isValid) {
            return coordinate.latitude.toFixed(5) + ", " + coordinate.longitude.toFixed(5)
        }
        return "WAITING"
    }

    function mapCenterText() {
        if (modernMap && modernMap.center && modernMap.center.isValid) {
            return modernMap.center.latitude.toFixed(5) + ", " + modernMap.center.longitude.toFixed(5)
        }
        return defaultCenter.latitude.toFixed(5) + ", " + defaultCenter.longitude.toFixed(5)
    }

    function airspaceStatusText() {
        if (!openAipToken || openAipToken.length === 0) {
            return "NO KEY"
        }
        if (riskDataManager.status === "ready" || airportDataManager.status === "ready") {
            return visibleRiskZones().length + " ZONES"
        }
        if (airspaceTileOverlayActive()) {
            return "TILES ON"
        }
        if (riskDataManager.status === "loading" || airportDataManager.status === "loading") {
            return "LOADING"
        }
        if (riskDataManager.status === "error" || airportDataManager.status === "error") {
            return "ERROR"
        }
        return "IDLE"
    }

    function airspaceErrorText() {
        const messages = []
        if (riskDataManager.status === "error" && riskDataManager.lastError !== "") {
            messages.push("Airspace: " + riskDataManager.lastError)
        }
        if (airportDataManager.status === "error" && airportDataManager.lastError !== "") {
            messages.push("Airports: " + airportDataManager.lastError)
        }
        return messages.join("\n")
    }

    function airspaceStateColor() {
        if (!openAipToken || openAipToken.length === 0) {
            return root.warn
        }
        if (visibleRiskZones().length > 0) {
            return root.ok
        }
        if (riskDataManager.status === "loading" || airportDataManager.status === "loading") {
            return root.warn
        }
        if ((riskDataManager.status === "error" || airportDataManager.status === "error") && !root.airspaceTileOverlayActive()) {
            return root.err
        }
        return root.airspaceTileOverlayActive() ? root.gold : root.dim
    }

    function airspaceBadgeText() {
        if (!openAipToken || openAipToken.length === 0) {
            return "AIRSPACE KEY"
        }
        if (riskDataManager.status === "ready" || airportDataManager.status === "ready") {
            return visibleRiskZones().length > 0 ? "AIRSPACE LIVE" : "NO AIRSPACE"
        }
        if (airspaceTileOverlayActive()) {
            return "AIRSPACE TILE"
        }
        if (riskDataManager.status === "loading" || airportDataManager.status === "loading") {
            return "AIRSPACE..."
        }
        if (riskDataManager.status === "error" || airportDataManager.status === "error") {
            return "AIRSPACE ERR"
        }
        return "AIRSPACE IDLE"
    }

    function batteryRemainingMinutesValue() {
        if (!activeVehicle || !activeVehicle.batteries || activeVehicle.batteries.count <= 0) {
            return NaN
        }

        for (let i = 0; i < activeVehicle.batteries.count; i++) {
            const battery = activeVehicle.batteries.get(i)
            if (!battery) {
                continue
            }

            const candidates = [ "timeRemaining", "timeRemainingStr" ]
            for (let j = 0; j < candidates.length; j++) {
                const name = candidates[j]
                if (!battery[name]) {
                    continue
                }
                const fact = battery[name]
                const raw = Number(fact.rawValue !== undefined ? fact.rawValue : fact.value)
                if (!isNaN(raw) && raw > 0) {
                    return raw > 300 ? raw / 60 : raw
                }
                const textValue = String(fact.valueString || fact.value || "")
                const match = textValue.match(/([0-9]+(?:\.[0-9]+)?)/)
                if (match) {
                    const parsed = Number(match[1])
                    if (!isNaN(parsed) && parsed > 0) {
                        return parsed
                    }
                }
            }
        }
        return NaN
    }

    function batteryAlertKey() {
        const percent = currentBatteryPercent()
        const minutes = batteryRemainingMinutesValue()
        if (isNaN(percent) && isNaN(minutes)) {
            return ""
        }
        return "battery:" + (isNaN(percent) ? "--" : Math.round(percent)) + ":" + (isNaN(minutes) ? "--" : Math.round(minutes))
    }

    function batteryAlertDetailText() {
        const percent = currentBatteryPercent()
        const minutes = batteryRemainingMinutesValue()
        if (!isNaN(percent) && !isNaN(minutes)) {
            return qsTr("%1% - Estimated %2 min remaining").arg(Math.round(percent)).arg(Math.round(minutes))
        }
        if (!isNaN(percent)) {
            return qsTr("%1% remaining - monitor reserve").arg(Math.round(percent))
        }
        return !isNaN(minutes) ? qsTr("Estimated %1 min remaining").arg(Math.round(minutes)) : ""
    }

    function batteryWarningActive() {
        const percent = currentBatteryPercent()
        const minutes = batteryRemainingMinutesValue()
        return (!isNaN(minutes) && minutes <= 20) || (!isNaN(percent) && percent <= 25)
    }

    function windAlertKey() {
        const alert = activeWindAlert()
        if (!alert) {
            return ""
        }
        return "wind:" + String(alert.id || alert.label || alert.message || alert.type || "active")
    }

    function windAlertDetailText() {
        const alert = activeWindAlert()
        if (!alert) {
            return ""
        }
        const speed = alert.speed || alert.windSpeed || alert.value || alert.gust || ""
        const unit = alert.unit || alert.units || "m/s"
        const segment = alert.segment || alert.routeSegment || alert.leg || ""
        if (speed !== "" && segment !== "") {
            return qsTr("%1 %2 on segment %3 - Monitor").arg(speed).arg(unit).arg(segment)
        }
        return alert.message || alert.description || qsTr("Live weather alert active - Monitor")
    }

    function modernFlightAlerts() {
        const alerts = []
        if (lastVehicleWarningKey.length > 0 && dismissedVehicleWarningKey !== lastVehicleWarningKey) {
            alerts.push({
                key: lastVehicleWarningKey,
                kind: "vehicle",
                title: qsTr("VEHICLE WARNING"),
                detail: lastVehicleWarningMessage,
                time: lastVehicleWarningTime.length > 0 ? lastVehicleWarningTime : modernAlertClock,
                tone: root.warn
            })
        }

        const batteryKey = batteryAlertKey()
        if (batteryWarningActive() && batteryKey !== "" && dismissedBatteryWarningKey !== batteryKey) {
            alerts.push({
                key: batteryKey,
                kind: "battery",
                title: qsTr("BATTERY WARNING"),
                detail: batteryAlertDetailText(),
                time: modernAlertClock,
                tone: root.warn
            })
        }

        const windKey = windAlertKey()
        if (windKey !== "" && dismissedWindWarningKey !== windKey) {
            const alert = activeWindAlert()
            alerts.push({
                key: windKey,
                kind: "wind",
                title: alert && alert.label ? String(alert.label).toUpperCase() : qsTr("WIND SHEAR DETECTED"),
                detail: windAlertDetailText(),
                time: modernAlertClock,
                tone: root.warn
            })
        }
        return alerts
    }

    function dismissModernFlightAlert(key, kind) {
        if (kind === "battery") {
            dismissedBatteryWarningKey = key
        } else if (kind === "wind") {
            dismissedWindWarningKey = key
        } else if (kind === "vehicle") {
            dismissedVehicleWarningKey = key
        }
    }

    function recordVehicleWarning(message) {
        const plainLines = String(message || "")
            .replace(/<br\s*\/?>/gi, "\n")
            .replace(/<\/p>/gi, "\n")
            .replace(/<[^>]*>/g, " ")
            .split("\n")
        let cleanMessage = ""
        for (let i = 0; i < plainLines.length; i++) {
            const candidate = plainLines[i].replace(/\s+/g, " ").trim()
            const loweredCandidate = candidate.toLowerCase()
            if (candidate.length > 0
                    && (loweredCandidate.indexOf("command failed") !== -1
                        || loweredCandidate.indexOf("prearm") !== -1
                        || loweredCandidate.indexOf("hardware safety") !== -1
                        || loweredCandidate.indexOf("not armable") !== -1
                        || loweredCandidate.indexOf("critical") !== -1
                        || loweredCandidate.indexOf("error") !== -1
                        || loweredCandidate.indexOf("warning") !== -1)) {
                cleanMessage = candidate
                break
            }
        }
        if (cleanMessage.length > 180) {
            cleanMessage = cleanMessage.slice(0, 177) + "..."
        }
        if (cleanMessage.length === 0) {
            return
        }
        const lowered = cleanMessage.toLowerCase()
        const relevant = lowered.indexOf("command failed") !== -1
            || lowered.indexOf("prearm") !== -1
            || lowered.indexOf("hardware safety") !== -1
            || lowered.indexOf("not armable") !== -1
            || lowered.indexOf("critical") !== -1
            || lowered.indexOf("error") !== -1
            || lowered.indexOf("warning") !== -1
        if (!relevant) {
            return
        }
        lastVehicleWarningMessage = cleanMessage
        lastVehicleWarningTime = modernAlertClock
        lastVehicleWarningKey = "vehicle:" + cleanMessage + ":" + lastVehicleWarningTime
        dismissedVehicleWarningKey = ""
    }

    function saveOpenAipToken(token) {
        const cleanToken = String(token || "").trim()
        QGroundControl.settingsManager.appSettings.openaipToken.rawValue = cleanToken
        openAipToken = cleanToken
        if (riskDataSourceTemplate === "" || riskDataSourceTemplate.indexOf("api.core.openaip.net") !== -1) {
            riskDataSourceTemplate = ""
            airportRiskDataSourceTemplate = ""
            loadDefaultRealRiskData()
        }
        pushToast(qsTr("Settings"), cleanToken.length > 0 ? qsTr("OpenAIP key saved.") : qsTr("OpenAIP key cleared."), "ok", 2200)
        airspaceTileRevision++
    }

    function boundsForCenter(center, radiusDegrees) {
        if (!center || !center.isValid) {
            return null
        }
        const radius = radiusDegrees || 0.25
        return {
            north: center.latitude + radius,
            south: center.latitude - radius,
            east: center.longitude + radius,
            west: center.longitude - radius,
            center: center
        }
    }

    function mapBounds(paddingRatio) {
        if (!modernMap || !modernMap.mapReady || modernMap.width <= 0 || modernMap.height <= 0) {
            if (activeVehicle && activeVehicle.coordinate.isValid) {
                return boundsForCenter(activeVehicle.coordinate, 0.25)
            }
            if (QGroundControl.flightMapPosition.isValid) {
                return boundsForCenter(QGroundControl.flightMapPosition, 0.25)
            }
            return boundsForCenter(defaultCenter, 0.25)
        }

        const padX = modernMap.width * (paddingRatio || 0)
        const padY = modernMap.height * (paddingRatio || 0)
        const corners = [
            modernMap.toCoordinate(Qt.point(-padX, -padY), false),
            modernMap.toCoordinate(Qt.point(modernMap.width + padX, -padY), false),
            modernMap.toCoordinate(Qt.point(-padX, modernMap.height + padY), false),
            modernMap.toCoordinate(Qt.point(modernMap.width + padX, modernMap.height + padY), false)
        ]

        let north = -90
        let south = 90
        let east = -180
        let west = 180
        let found = false
        for (let i = 0; i < corners.length; i++) {
            const coordinate = corners[i]
            if (coordinate && coordinate.isValid) {
                north = Math.max(north, coordinate.latitude)
                south = Math.min(south, coordinate.latitude)
                east = Math.max(east, coordinate.longitude)
                west = Math.min(west, coordinate.longitude)
                found = true
            }
        }
        if (!found) {
            return boundsForCenter(defaultCenter, 0.25)
        }
        return {
            north: north,
            south: south,
            east: east,
            west: west,
            center: QtPositioning.coordinate((north + south) / 2, (east + west) / 2)
        }
    }

    function coordinateInBounds(coordinate, bounds) {
        if (!coordinate || !coordinate.isValid || !bounds) {
            return false
        }
        return coordinate.latitude <= bounds.north
            && coordinate.latitude >= bounds.south
            && coordinate.longitude <= bounds.east
            && coordinate.longitude >= bounds.west
    }

    function zoneIntersectsBounds(zone, bounds) {
        if (!bounds || !zone) {
            return true
        }
        if (coordinateInBounds(zone.center, bounds)) {
            return true
        }
        for (let i = 0; i < zone.path.length; i++) {
            if (coordinateInBounds(zone.path[i], bounds)) {
                return true
            }
        }
        const zoneRect = zoneBounds([zone])
        if (!zoneRect || !zoneRect.topLeft || !zoneRect.bottomRight) {
            return false
        }
        const zoneNorth = zoneRect.topLeft.latitude
        const zoneSouth = zoneRect.bottomRight.latitude
        const zoneWest = zoneRect.topLeft.longitude
        const zoneEast = zoneRect.bottomRight.longitude
        return !(zoneEast < bounds.west || zoneWest > bounds.east || zoneSouth > bounds.north || zoneNorth < bounds.south)
    }

    function visibleRiskZones() {
        const revision = riskZoneViewportRevision
        const zones = activeRiskZones()
        if (!filterRiskZonesToMap) {
            return zones
        }
        const bounds = mapBounds(0.25)
        if (!bounds) {
            return zones
        }
        return zones.filter(function(zone) { return zoneIntersectsBounds(zone, bounds) })
    }

    function formatCoordinateValue(value) {
        return Number(value).toFixed(3)
    }

    function riskDataUrlForMap() {
        return dataUrlForMap(riskDataSourceTemplate)
    }

    function airportRiskDataUrlForMap() {
        return dataUrlForMap(airportRiskDataSourceTemplate)
    }

    function dataUrlForMap(template) {
        if (!template) {
            return ""
        }
        const bounds = mapBounds(0.25)
        if (!bounds) {
            return template
        }
        return String(template)
            .replace(/\{north\}/g, formatCoordinateValue(bounds.north))
            .replace(/\{south\}/g, formatCoordinateValue(bounds.south))
            .replace(/\{east\}/g, formatCoordinateValue(bounds.east))
            .replace(/\{west\}/g, formatCoordinateValue(bounds.west))
            .replace(/\{lat\}/g, formatCoordinateValue(bounds.center.latitude))
            .replace(/\{lon\}/g, formatCoordinateValue(bounds.center.longitude))
            .replace(/\{bbox\}/g, [
                formatCoordinateValue(bounds.west),
                formatCoordinateValue(bounds.south),
                formatCoordinateValue(bounds.east),
                formatCoordinateValue(bounds.north)
            ].join(","))
    }

    function riskDataSourceUsesMap() {
        return dataSourceUsesMap(riskDataSourceTemplate) || dataSourceUsesMap(airportRiskDataSourceTemplate)
    }

    function dataSourceUsesMap(template) {
        if (!template) {
            return false
        }
        return template.indexOf("{bbox}") !== -1
            || template.indexOf("{north}") !== -1
            || template.indexOf("{south}") !== -1
            || template.indexOf("{east}") !== -1
            || template.indexOf("{west}") !== -1
            || template.indexOf("{lat}") !== -1
            || template.indexOf("{lon}") !== -1
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function airspaceTileOverlayActive() {
        return openAipTileOverlayEnabled && openAipToken && openAipToken.length > 0
    }

    function longitudeToTileX(longitude, zoom) {
        const tileCount = Math.pow(2, zoom)
        return Math.floor((longitude + 180) / 360 * tileCount)
    }

    function latitudeToTileY(latitude, zoom) {
        const safeLatitude = clamp(latitude, -85.05112878, 85.05112878)
        const radians = safeLatitude * Math.PI / 180
        const tileCount = Math.pow(2, zoom)
        return Math.floor((1 - Math.log(Math.tan(radians) + 1 / Math.cos(radians)) / Math.PI) / 2 * tileCount)
    }

    function tileXToLongitude(x, zoom) {
        return x / Math.pow(2, zoom) * 360 - 180
    }

    function tileYToLatitude(y, zoom) {
        const value = Math.PI * (1 - 2 * y / Math.pow(2, zoom))
        const radians = Math.atan((Math.exp(value) - Math.exp(-value)) / 2)
        return radians * 180 / Math.PI
    }

    function openAipTileUrl(zoom, x, y) {
        const subdomains = ["a", "b", "c"]
        const subdomain = subdomains[Math.abs((x + y + zoom) % subdomains.length)]
        return "https://" + subdomain + ".api.tiles.openaip.net/api/data/openaip/"
            + zoom + "/" + x + "/" + y + ".png?apiKey=" + encodeURIComponent(openAipToken)
    }

    function openAipTileModel() {
        const revision = airspaceTileRevision
        if (!airspaceTileOverlayActive() || !modernMap || !modernMap.mapReady) {
            return []
        }

        const bounds = mapBounds(0.05)
        if (!bounds) {
            return []
        }

        const zoom = clamp(Math.floor(modernMap.zoomLevel), 3, 12)
        const tileCount = Math.pow(2, zoom)
        let xMin = clamp(longitudeToTileX(bounds.west, zoom), 0, tileCount - 1)
        let xMax = clamp(longitudeToTileX(bounds.east, zoom), 0, tileCount - 1)
        let yMin = clamp(latitudeToTileY(bounds.north, zoom), 0, tileCount - 1)
        let yMax = clamp(latitudeToTileY(bounds.south, zoom), 0, tileCount - 1)

        if (xMax < xMin) {
            const tempX = xMin
            xMin = xMax
            xMax = tempX
        }
        if (yMax < yMin) {
            const tempY = yMin
            yMin = yMax
            yMax = tempY
        }

        const maxTilesPerAxis = 5
        const centerX = clamp(longitudeToTileX(bounds.center.longitude, zoom), 0, tileCount - 1)
        const centerY = clamp(latitudeToTileY(bounds.center.latitude, zoom), 0, tileCount - 1)
        if (xMax - xMin + 1 > maxTilesPerAxis) {
            xMin = clamp(centerX - 2, 0, tileCount - 1)
            xMax = clamp(xMin + maxTilesPerAxis - 1, 0, tileCount - 1)
        }
        if (yMax - yMin + 1 > maxTilesPerAxis) {
            yMin = clamp(centerY - 2, 0, tileCount - 1)
            yMax = clamp(yMin + maxTilesPerAxis - 1, 0, tileCount - 1)
        }

        const tileSize = 256 * Math.pow(2, modernMap.zoomLevel - zoom)
        const tiles = []
        for (let x = xMin; x <= xMax; x++) {
            for (let y = yMin; y <= yMax; y++) {
                tiles.push({
                    id: zoom + "/" + x + "/" + y + "/" + revision,
                    x: x,
                    y: y,
                    z: zoom,
                    size: tileSize,
                    coordinate: QtPositioning.coordinate(tileYToLatitude(y, zoom), tileXToLongitude(x, zoom)),
                    url: openAipTileUrl(zoom, x, y)
                })
            }
        }
        return tiles
    }

    function refreshRiskDataForMap(force) {
        const resolvedUrl = riskDataUrlForMap()
        if (resolvedUrl === "" || (!force && resolvedUrl === lastRiskDataUrl && riskDataManager.status === "ready")) {
            return
        }
        lastRiskDataUrl = resolvedUrl
        riskDataSourceUrl = resolvedUrl
        riskDataManager.loadFromUrl(resolvedUrl)
    }

    function refreshAirportRiskDataForMap(force) {
        const resolvedUrl = airportRiskDataUrlForMap()
        if (resolvedUrl === "" || (!force && resolvedUrl === lastAirportRiskDataUrl && airportDataManager.status === "ready")) {
            return
        }
        lastAirportRiskDataUrl = resolvedUrl
        airportDataManager.loadFromUrl(resolvedUrl)
    }

    function updateMissionWaypoint(index, coordinate) {
        const missionItem = missionVisualItemAtMissionIndex(index)
        if (!missionItem || !coordinate || !coordinate.isValid) {
            return
        }
        missionItem.coordinate = coordinate
        _missionController.setCurrentPlanViewSeqNum(missionItem.sequenceNumber, false)
        syncMissionCoordinates()
        missionScrubIndex = index
        pushToast(qsTr("Waypoint %1").arg(index + 1), qsTr("Waypoint repositioned."), "info", 2400)
    }

    function syncMissionScrubIndexToLive() {
        if (!missionTimelineAvailable()) {
            missionScrubIndex = 0
            missionTimelineInspectionMode = false
            return
        }
        missionScrubIndex = missionTimelineLiveIndex()
    }

    function focusMissionWaypoint(index, announce) {
        if (missionCoordinates.length === 0) {
            return
        }
        const safeIndex = Math.max(0, Math.min(index, missionCoordinates.length - 1))
        missionScrubIndex = safeIndex
        missionTimelineInspectionMode = safeIndex !== missionTimelineLiveIndex()
        const coordinate = missionCoordinateAt(safeIndex)
        const missionItem = missionVisualItemAtMissionIndex(safeIndex)
        if (missionItem) {
            _missionController.setCurrentPlanViewSeqNum(missionItem.sequenceNumber, false)
        }
        if (modernMap.mapReady && coordinate.isValid) {
            modernMap.center = coordinate
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 15)
        }
        if (announce !== false) {
            pushToast(qsTr("Mission"), qsTr("Waypoint %1 focused on the map.").arg(safeIndex + 1), "info", 2200)
        }
    }

    function openPayload(view) {
        payloadView = view
        payloadPanelOpen = true
        if (view === "3d") {
            pushToast(qsTr("Payload"), qsTr("3D view opened."), "info", 2200)
        } else {
            pushToast(qsTr("Payload"), qsTr("Video feed opened."), "info", 2200)
        }
    }

    function closePayload() {
        payloadPanelOpen = false
    }

    function setPayloadMode(mode) {
        payloadVideoMode = mode
    }

    function cyclePayloadZoom() {
        const zoomLevels = [1, 2, 4, 8]
        payloadZoomIndex = (payloadZoomIndex + 1) % zoomLevels.length
        payloadZoomLevel = zoomLevels[payloadZoomIndex]
    }

    function missionCoordinateAt(index) {
        if (index < 0) {
            return missionCoordinates[0]
        }
        if (index >= missionCoordinates.length) {
            return missionCoordinates[missionCoordinates.length - 1]
        }
        return missionCoordinates[index]
    }

    function isTimelineMissionItem(item) {
        return item && item.specifiesCoordinate && !item.homePosition && !item.isStandaloneCoordinate && item.coordinate && item.coordinate.isValid
    }

    function missionVisualItemAtMissionIndex(index) {
        if (!_visualItems) {
            return null
        }
        let missionIndex = 0
        for (let i = 0; i < _visualItems.count; i++) {
            const item = _visualItems.get(i)
            if (isTimelineMissionItem(item)) {
                if (missionIndex === index) {
                    return item
                }
                missionIndex++
            }
        }
        return null
    }

    function syncMissionCoordinates() {
        if (!_visualItems) {
            missionCoordinates = []
            missionScrubIndex = 0
            missionTimelineInspectionMode = false
            return
        }
        const coordinates = []
        for (let i = 0; i < _visualItems.count; i++) {
            const item = _visualItems.get(i)
            if (isTimelineMissionItem(item)) {
                coordinates.push(item.coordinate)
            }
        }
        missionCoordinates = coordinates
        if (missionCoordinates.length === 0) {
            missionScrubIndex = 0
            missionTimelineInspectionMode = false
            return
        }
        if (missionScrubIndex >= missionCoordinates.length) {
            missionScrubIndex = Math.max(0, missionCoordinates.length - 1)
        }
        if (!missionTimelineInspectionMode) {
            syncMissionScrubIndexToLive()
        }
    }

    Component {
        id: planViewComponent
        PlanViewModern {
            anchors.fill: parent
            onExitRequested: root.activateModernSection("fly")
        }
    }

    Component {
        id: analyzeViewComponent

        Rectangle {
            color: "#05070a"

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 276
                    Layout.fillHeight: true
                    color: root.modernGlassStrong
                    border.color: root.modernGoldHairline
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12

                        ModernSettingsAction {
                            Layout.fillWidth: true
                            label: "< EXIT ANALYZE"
                            tone: root.text
                            onClicked: root.activeModernSection = "fly"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Repeater {
                                model: [
                                    { label: "MISSION", value: root.missionDescriptorText(), tone: root.text },
                                    { label: "LINK", value: root.linkQualityText(), tone: root.ok },
                                    { label: "EVENTS", value: root.messageCountText(), tone: root.gold }
                                ]

                                delegate: Rectangle {
                                    id: analyzeRailMetric
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 42
                                    color: root.modernGlassSoft
                                    border.color: root.modernHairline
                                    border.width: 1

                                    Column {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 10
                                        spacing: 2

                                        Text {
                                            text: analyzeRailMetric.modelData.label
                                            color: root.dim
                                            font.pixelSize: 8
                                            font.letterSpacing: 1
                                            font.family: "monospace"
                                        }

                                        Text {
                                            text: analyzeRailMetric.modelData.value
                                            color: analyzeRailMetric.modelData.tone
                                            font.pixelSize: 13
                                            font.bold: true
                                            font.family: "Barlow Condensed"
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "LOG ANALYSIS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1
                                font.family: "monospace"
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 112
                                color: root.modernGlass
                                border.color: root.modernGoldHairline
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.logStatusText().toUpperCase()
                                        color: root.text
                                        font.pixelSize: 18
                                        font.bold: true
                                        font.family: "Barlow Condensed"
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "BIN, TLOG, ULOG, CSV"
                                        color: root.dim
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                    }

                                    ModernSettingsAction {
                                        Layout.fillWidth: true
                                        label: "OPEN LOG TOOLS"
                                        tone: root.blue
                                        onClicked: mainWindow.showAnalyzeTool()
                                    }
                                }
                            }

                            Text {
                                text: "LOG TOOLS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1
                                font.family: "monospace"
                            }

                            ModernSettingsAction {
                                Layout.fillWidth: true
                                label: "MISSION LOGS"
                                tone: root.text
                                onClicked: mainWindow.showAnalyzeTool()
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            Text {
                                text: "LIVE SESSION EVENTS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1
                                font.family: "monospace"
                            }

                            Repeater {
                                model: root.recentMissionModel()

                                delegate: Rectangle {
                                    id: recentMissionCard
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 88
                                    color: root.modernGlassSoft
                                    border.color: root.modernHairline
                                    border.width: 1

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        Row {
                                            width: parent.width

                                            Text {
                                                text: recentMissionCard.modelData.title
                                                color: "#f8fafc"
                                                font.pixelSize: 18
                                                font.bold: true
                                                font.family: "Barlow Condensed"
                                            }

                                            Text {
                                                anchors.right: parent.right
                                                text: recentMissionCard.modelData.status
                                                color: recentMissionCard.modelData.tone
                                                font.pixelSize: 11
                                                font.bold: true
                                                font.family: "monospace"
                                            }
                                        }

                                        Text {
                                            text: recentMissionCard.modelData.detail
                                            color: root.dim
                                            font.pixelSize: 9
                                            font.family: "monospace"
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 88
                                visible: root.recentMissionModel().length === 0
                                color: root.modernGlassSoft
                                border.color: root.modernHairline
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    text: root.activeVehicle ? "No session events have been captured yet." : "Connect a vehicle to populate live session events."
                                    color: root.dim
                                    font.pixelSize: 10
                                    font.family: ScreenTools.normalFontFamily
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredWidth: 210
                            Layout.preferredHeight: 26
                            color: root.modernGoldFill
                            border.color: root.modernGoldHairline
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Rectangle {
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: root.ok
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: root.activeVehicle ? "LIVE SESSION REVIEW" : "AWAITING VEHICLE DATA"
                                    color: root.gold
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                }
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: [
                                { label: "FLIGHT TIME", value: root.flightTimeText(), tone: root.text },
                                { label: "BATT DELTA", value: root.batteryUsedText(), tone: root.gold },
                                { label: "PACKET DELIVERY", value: root.linkQualityText(), tone: root.ok },
                                { label: "AIRSPACE", value: root.visibleRiskZones().length + " ZONES", tone: root.gold }
                            ]

                            delegate: Rectangle {
                                id: topAnalyzeMetric
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                color: root.modernGlass
                                border.color: root.modernHairline
                                border.width: 1

                                Column {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 12
                                    spacing: 2

                                    Text {
                                        text: topAnalyzeMetric.modelData.label
                                        color: root.dim
                                        font.pixelSize: 8
                                        font.letterSpacing: 1
                                        font.family: "monospace"
                                    }

                                    Text {
                                        text: topAnalyzeMetric.modelData.value
                                        color: topAnalyzeMetric.modelData.tone
                                        font.pixelSize: 16
                                        font.bold: true
                                        font.family: "Barlow Condensed"
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.columnSpan: 4
                            Layout.preferredHeight: 152
                            color: root.modernGlass
                            border.color: root.modernGoldHairline
                            border.width: 1

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: "ALT / SPEED / BATT TELEMETRY"
                                    color: root.dim
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.family: "monospace"
                                }

                                Canvas {
                                    id: analyzeTelemetryChart
                                    width: parent.width
                                    height: 108

                                    function normalizedValue(series, idx, minV, maxV) {
                                        if (!series || series.length === 0) {
                                            return 0.5
                                        }
                                        const safeIndex = Math.max(0, Math.min(series.length - 1, idx))
                                        const value = Number(series[safeIndex])
                                        if (isNaN(value) || Math.abs(maxV - minV) < 0.0001) {
                                            return 0.5
                                        }
                                        return (value - minV) / (maxV - minV)
                                    }

                                    function drawSeries(ctx, series, color, minV, maxV) {
                                        if (!series || series.length === 0) {
                                            return
                                        }
                                        ctx.beginPath()
                                        for (let i = 0; i < series.length; i++) {
                                            const x = (i / Math.max(1, series.length - 1)) * width
                                            const normalized = normalizedValue(series, i, minV, maxV)
                                            const y = 10 + (1.0 - normalized) * (height - 20)
                                            if (i === 0) {
                                                ctx.moveTo(x, y)
                                            } else {
                                                ctx.lineTo(x, y)
                                            }
                                        }
                                        ctx.strokeStyle = color
                                        ctx.lineWidth = 2
                                        ctx.stroke()
                                    }

                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.reset()
                                        ctx.fillStyle = "#090d13"
                                        ctx.fillRect(0, 0, width, height)

                                        ctx.strokeStyle = "rgba(170,179,193,0.14)"
                                        ctx.lineWidth = 1
                                        for (let row = 1; row <= 3; row++) {
                                            const y = row * (height / 4)
                                            ctx.beginPath()
                                            ctx.moveTo(0, y)
                                            ctx.lineTo(width, y)
                                            ctx.stroke()
                                        }

                                        const altMin = root.historyMin(root.altitudeHistory)
                                        const altMax = root.historyMax(root.altitudeHistory)
                                        const spdMin = root.historyMin(root.speedHistory)
                                        const spdMax = root.historyMax(root.speedHistory)
                                        const battMin = root.historyMin(root.batteryHistory)
                                        const battMax = root.historyMax(root.batteryHistory)

                                        drawSeries(ctx, root.altitudeHistory, "#4f97ff", isNaN(altMin) ? 0 : altMin, isNaN(altMax) ? 1 : altMax)
                                        drawSeries(ctx, root.speedHistory, "#00b15d", isNaN(spdMin) ? 0 : spdMin, isNaN(spdMax) ? 1 : spdMax)
                                        drawSeries(ctx, root.batteryHistory, "#cfa642", isNaN(battMin) ? 0 : battMin, isNaN(battMax) ? 100 : battMax)

                                        const markerRatio = root.analyzeMarkerRatio()
                                        const markerText = root.analyzeMarkerText()
                                        if (!isNaN(markerRatio) && markerText.length > 0) {
                                            const markerX = width * markerRatio
                                            ctx.strokeStyle = "#c98b1c"
                                            ctx.lineWidth = 2
                                            ctx.beginPath()
                                            ctx.moveTo(markerX, 0)
                                            ctx.lineTo(markerX, height)
                                            ctx.stroke()
                                            ctx.fillStyle = "#c98b1c"
                                            ctx.font = "bold 10px monospace"
                                            ctx.textAlign = markerRatio > 0.9 ? "right" : "left"
                                            ctx.fillText(markerText, markerRatio > 0.9 ? markerX - 8 : markerX + 8, 14)
                                        }
                                    }

                                    Connections {
                                        target: root
                                        function onSpeedHistoryChanged() { analyzeTelemetryChart.requestPaint() }
                                        function onAltitudeHistoryChanged() { analyzeTelemetryChart.requestPaint() }
                                        function onBatteryHistoryChanged() { analyzeTelemetryChart.requestPaint() }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.columnSpan: 4
                            Layout.preferredHeight: 86
                            color: root.modernGlass
                            border.color: root.modernHairline
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: "LIVE TELEMETRY SUMMARY"
                                    color: root.gold
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.family: "monospace"
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 6
                                    columnSpacing: 8

                                    Repeater {
                                        model: root.analyzeTelemetrySummaryModel()

                                        delegate: Rectangle {
                                            id: telemetrySummaryCard
                                            required property var modelData

                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 42
                                            color: root.modernGlassSoft
                                            border.color: root.modernHairline
                                            border.width: 1

                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 2

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: telemetrySummaryCard.modelData.label
                                                    color: root.dim
                                                    font.pixelSize: 8
                                                    font.bold: true
                                                    font.family: "monospace"
                                                }

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: telemetrySummaryCard.modelData.value
                                                    color: telemetrySummaryCard.modelData.tone
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                    font.family: "monospace"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.analyzeInsightCards()

                            delegate: Rectangle {
                                id: insightCard
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.columnSpan: 4
                                Layout.preferredHeight: 74
                                color: root.modernGlass
                                border.color: root.modernHairline
                                border.width: 1

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 12
                                    spacing: 8

                                    Row {
                                        width: parent.width

                                        Text {
                                            text: insightCard.modelData.title
                                            color: "#f8fafc"
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.family: "monospace"
                                        }

                                        Item { width: Math.max(6, parent.width - badgeRect.x - badgeRect.width) }

                                        Rectangle {
                                            id: badgeRect
                                            width: badgeText.implicitWidth + 16
                                            height: 20
                                            color: Qt.rgba(insightCard.modelData.tone.r, insightCard.modelData.tone.g, insightCard.modelData.tone.b, 0.12)
                                            border.color: insightCard.modelData.tone
                                            border.width: 1

                                            Text {
                                                id: badgeText
                                                anchors.centerIn: parent
                                                text: insightCard.modelData.badge
                                                color: insightCard.modelData.tone
                                                font.pixelSize: 9
                                                font.bold: true
                                                font.family: "monospace"
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        text: insightCard.modelData.body
                                        color: root.dim
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.columnSpan: 4 }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 304
                    Layout.fillHeight: true
                    color: root.modernGlassStrong
                    border.color: root.modernGoldHairline
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Text {
                            text: "MISSION SUMMARY"
                            color: root.gold
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1
                            font.family: "monospace"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 102
                            color: root.modernGoldFill
                            border.color: root.modernGoldHairline
                            border.width: 1

                            Text {
                                anchors.fill: parent
                                anchors.margins: 12
                                text: root.missionSummaryText()
                                color: root.text
                                wrapMode: Text.WordWrap
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                        }

                        Text {
                            text: "SESSION CHECKS"
                            color: root.gold
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1
                            font.family: "monospace"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: root.sessionChecklistModel()

                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: modelData.tone
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                            color: root.modernGlass
                            border.color: root.modernHairline
                            border.width: 1

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: "LOG STATUS"
                                    color: root.dim
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                }

                                Text {
                                    text: root.logStatusText()
                                    color: root.logStateTone()
                                    font.pixelSize: 16
                                    font.bold: true
                                    font.family: "Barlow Condensed"
                                }

                                Text {
                                    text: qsTr("%1 onboard logs listed").arg(root.logEntryCount())
                                    color: root.text
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                }

                                ModernSettingsAction {
                                    width: parent.width
                                    label: "OPEN LOG TOOLS"
                                    tone: root.blue
                                    onClicked: mainWindow.showAnalyzeTool()
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    Component {
        id: vehicleViewComponent

        Rectangle {
            color: "#05070a"

            ScrollView {
                id: vehicleScroll
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Item {
                    width: vehicleScroll.availableWidth
                    height: vehicleColumn.implicitHeight + 28

                    ColumnLayout {
                        id: vehicleColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    Layout.minimumHeight: 54
                    Layout.maximumHeight: 54
                    Layout.fillHeight: false
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 4
                        Layout.preferredHeight: 54
                        Layout.minimumHeight: 54
                        Layout.maximumHeight: 54
                        color: root.ok
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "VEHICLE"
                            color: root.ok
                            font.pixelSize: 10
                            font.bold: true
                            font.family: ScreenTools.normalFontFamily
                            font.letterSpacing: 2
                        }

                        Text {
                            text: "Vehicle Configuration"
                            color: "#f8fafc"
                            font.pixelSize: 20
                            font.bold: true
                            font.family: ScreenTools.normalFontFamily
                        }

                        Text {
                            text: root.activeVehicle ? "Live vehicle setup and readiness state" : "No active vehicle. Link a vehicle to unlock setup panels."
                            color: root.dim
                            font.pixelSize: 11
                            font.family: ScreenTools.normalFontFamily
                        }
                    }

                    ModernSettingsAction {
                        Layout.preferredWidth: 120
                        label: root.activeVehicle ? "OPEN SETUP" : "COMM LINKS"
                        tone: root.ok
                        onClicked: {
                            if (root.activeVehicle) {
                                mainWindow.showVehicleConfig()
                            } else {
                                root.openCommLinksSettings()
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: [
                            { label: "LINK", value: root.activeVehicle ? "ONLINE" : "OFFLINE" },
                            { label: "READY", value: root.vehicleReadyText() },
                            { label: "SETUP", value: root.setupProgressText() },
                            { label: "GPS", value: root.gpsStatusText() }
                        ]

                        delegate: Rectangle {
                            id: vehicleCard
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 62
                            color: root.modernGlass
                            border.color: root.modernHairline
                            border.width: 1
                            radius: 2

                            Column {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                spacing: 6

                                Text {
                                    text: vehicleCard.modelData.label
                                    color: root.dim
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                }

                                Text {
                                    text: vehicleCard.modelData.value
                                    color: "#f8fafc"
                                    font.pixelSize: 18
                                    font.bold: true
                                    font.family: "Barlow Condensed"
                                }
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 10

                    ModernDataPanel {
                        Layout.fillWidth: true
                        title: "VEHICLE IDENTITY"
                        model: root.vehicleIdentityModel()
                    }

                    ModernDataPanel {
                        Layout.fillWidth: true
                        title: "LIVE CAPABILITIES"
                        model: root.vehicleCapabilityModel()
                    }

                    ModernDataPanel {
                        Layout.fillWidth: true
                        title: "POWER"
                        model: root.vehiclePowerModel()
                    }

                    ModernDataPanel {
                        Layout.fillWidth: true
                        title: "LINK"
                        model: root.vehicleLinkModel()
                    }

                    ModernDataPanel {
                        Layout.fillWidth: true
                        title: "GPS / POSITION"
                        model: root.vehicleGpsModel()
                    }

                    ModernDataPanel {
                        Layout.fillWidth: true
                        title: "COMMAND AVAILABILITY"
                        model: root.vehicleCommandStateModel()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: !!root.activeVehicle && !root.vehicleCanArm()
                    color: root.modernGlassStrong
                    border.color: root.warn
                    border.width: 1
                    radius: 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 3.5
                            color: root.warn
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "PREARM BLOCKER"
                                color: root.warn
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.prearmStatusText()
                                color: root.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Barlow Condensed"
                                elide: Text.ElideRight
                            }
                        }

                        ModernSettingsAction {
                            Layout.preferredWidth: 104
                            label: "OPEN CHECKS"
                            tone: root.warn
                            onClicked: mainWindow.showVehicleConfig()
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    Layout.minimumHeight: implicitHeight
                    Layout.fillHeight: false
                    columns: 3
                    columnSpacing: 12
                    rowSpacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 280
                        color: root.modernGlass
                        border.color: root.modernGoldHairline
                        border.width: 1
                        radius: 2

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            Text {
                                text: "READINESS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "monospace"
                            }

                            Repeater {
                                model: [
                                    { label: "STATE", value: root.vehicleReadyText(), tone: root.vehicleCanArm() ? root.ok : root.warn },
                                    { label: "PREARM", value: root.prearmStatusText(), tone: root.vehicleCanArm() ? root.ok : root.warn },
                                    { label: "CHECKS", value: root.readinessProblemsText(), tone: root.readinessProblemCount() > 0 ? root.warn : root.ok },
                                    { label: "SENSORS", value: root.activeVehicle ? (root.activeVehicle.allSensorsHealthy ? "HEALTHY" : "ATTN") : "--", tone: root.activeVehicle && root.activeVehicle.allSensorsHealthy ? root.ok : root.warn }
                                ]

                                delegate: Rectangle {
                                    id: readinessRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    color: root.modernGlassSoft
                                    border.color: root.modernHairline
                                    border.width: 1
                                    radius: 2

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        text: readinessRow.modelData.label
                                        color: root.dim
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.rightMargin: 12
                                        text: readinessRow.modelData.value
                                        color: readinessRow.modelData.tone
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: "monospace"
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 1 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 280
                        color: root.modernGlass
                        border.color: root.modernGoldHairline
                        border.width: 1
                        radius: 2

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            Text {
                                text: "LIVE SYSTEMS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "monospace"
                            }

                            Repeater {
                                model: [
                                    { label: "BATTERY", value: root.batteryPercentText() + " | " + root.batteryPackCountText(), tone: root.ok },
                                    { label: "GPS DETAIL", value: root.gpsDetailText(), tone: root.text },
                                    { label: "VIBRATION", value: root.vibrationStatusText(), tone: root.warn },
                                    { label: "CLIP COUNTS", value: root.vibrationClipText(), tone: root.text },
                                    { label: "FLIGHT TIME", value: root.flightTimeText(), tone: root.text },
                                    { label: "EVENT MSGS", value: root.messageCountText(), tone: Number(root.messageCountText()) > 0 ? root.warn : root.ok }
                                ]

                                delegate: Rectangle {
                                    id: systemsRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    color: root.modernGlassSoft
                                    border.color: root.modernHairline
                                    border.width: 1
                                    radius: 2

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        text: systemsRow.modelData.label
                                        color: root.dim
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.rightMargin: 12
                                        text: systemsRow.modelData.value
                                        color: systemsRow.modelData.tone
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: "monospace"
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 1 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 220
                        color: root.modernGlass
                        border.color: root.modernGoldHairline
                        border.width: 1
                        radius: 2

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            Text {
                                text: "GUIDED ACTIONS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "monospace"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ModernSettingsAction { Layout.fillWidth: true; label: root.pendingVehicleAction === "arm" ? "ARM..." : "ARM"; tone: root.ok; enabled: root.pendingVehicleAction === "" && !!root.activeVehicle && !root.activeVehicle.armed && root.vehicleCanArm(); onClicked: root.armVehicle() }
                                ModernSettingsAction { Layout.fillWidth: true; label: root.pendingVehicleAction === "takeoff" ? "TAKEOFF..." : "TAKEOFF"; tone: root.gold; enabled: root.pendingVehicleAction === "" && root.vehicleCanTakeoff(); onClicked: root.takeoffVehicle() }
                                ModernSettingsAction { Layout.fillWidth: true; label: root.pendingVehicleAction === "rtl" ? "RTL..." : "RTL"; tone: root.blue; enabled: root.pendingVehicleAction === "" && root.vehicleCanRTL(); onClicked: root.rtlVehicle() }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ModernSettingsAction { Layout.fillWidth: true; label: root.pendingVehicleAction === "pause" ? "PAUSE..." : "PAUSE"; tone: root.blue; enabled: root.pendingVehicleAction === "" && root.vehicleCanPause(); onClicked: root.pauseVehicle() }
                                ModernSettingsAction { Layout.fillWidth: true; label: root.pendingVehicleAction === "land" ? "LAND..." : "LAND"; tone: root.warn; enabled: root.pendingVehicleAction === "" && root.vehicleCanLand(); onClicked: root.landVehicle() }
                                ModernSettingsAction { Layout.fillWidth: true; label: root.pendingVehicleAction === "disarm" ? "DISARM..." : "DISARM"; tone: root.err; enabled: root.pendingVehicleAction === "" && root.vehicleCanDisarm(); onClicked: root.disarmVehicle() }
                            }

                            Item { Layout.preferredHeight: 1 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 220
                        color: root.modernGlass
                        border.color: root.modernGoldHairline
                        border.width: 1
                        radius: 2

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            Text {
                                text: "SETUP STATUS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "monospace"
                            }

                            Repeater {
                                model: root.setupComponentsModel()

                                delegate: Rectangle {
                                    id: setupRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    color: root.modernGlassSoft
                                    border.color: setupRow.modelData.setupComplete ? root.ok : root.warn
                                    border.width: 1
                                    radius: 2

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        text: String(setupRow.modelData.name).toUpperCase()
                                        color: root.text
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: "monospace"
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.rightMargin: 12
                                        text: setupRow.modelData.setupComplete ? "READY" : "SETUP"
                                        color: setupRow.modelData.setupComplete ? root.ok : root.warn
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: "monospace"
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                visible: root.setupComponentCount() === 0
                                color: root.modernGlassSoft
                                border.color: root.modernHairline
                                border.width: 1
                                radius: 2

                                Text {
                                    anchors.centerIn: parent
                                    text: root.activeVehicle ? "Vehicle components have not populated yet." : "Connect a vehicle to inspect setup components."
                                    color: root.dim
                                    font.pixelSize: 10
                                    width: parent.width - 24
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: ScreenTools.normalFontFamily
                                }
                            }

                            Item { Layout.preferredHeight: 1 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 184
                        Layout.columnSpan: 2
                        color: root.modernGlass
                        border.color: root.modernGoldHairline
                        border.width: 1
                        radius: 2

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            Text {
                                text: "SETUP ACCESS"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "monospace"
                            }

                            Repeater {
                                model: [
                                    { label: "APPLICATION SETTINGS", action: "settings" },
                                    { label: "VEHICLE CONFIG", action: "vehicle" },
                                    { label: "COMM LINKS", action: "links" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 42
                                    color: root.modernGlassSoft
                                    border.color: root.modernHairline
                                    border.width: 1
                                    radius: 2

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        text: modelData.label
                                        color: root.text
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: "monospace"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            switch (modelData.action) {
                                            case "settings":
                                                root.openFullSettings()
                                                break
                                            case "vehicle":
                                                mainWindow.showVehicleConfig()
                                                break
                                            case "links":
                                                root.openCommLinksSettings()
                                                break
                                            }
                                        }
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 1 }
                        }
                    }
                }

                    }
                }
            }
        }
    }

    function offsetCoordinate(latitudeOffset, longitudeOffset) {
        if (!overlayCenter || !overlayCenter.isValid) {
            return QtPositioning.coordinate()
        }
        return QtPositioning.coordinate(overlayCenter.latitude + latitudeOffset, overlayCenter.longitude + longitudeOffset)
    }

    function updateSelectedMapKindFromActiveType() {
        if (!modernMap.activeMapType || !modernMap.activeMapType.name) {
            selectedMapKind = "default"
            return
        }
        const activeName = modernMap.activeMapType.name.toLowerCase()
        if (activeName.indexOf("hybrid") !== -1) {
            selectedMapKind = "hybrid"
        } else if (activeName.indexOf("satellite") !== -1) {
            selectedMapKind = "satellite"
        } else if (activeName.indexOf("terrain") !== -1 || activeName.indexOf("topo") !== -1) {
            selectedMapKind = "terrain"
        } else if (activeName.indexOf("street") !== -1 || activeName.indexOf("road") !== -1 || activeName.indexOf("map") !== -1) {
            selectedMapKind = "street"
        } else {
            selectedMapKind = "default"
        }
    }

    function initializeModernMapType() {
        if (!modernMap.mapReady || _mapTypeInitialized) {
            return
        }
        _mapTypeInitialized = true
        const startupCenter = startupMapCenter()
        if (startupCenter && startupCenter.isValid) {
            modernMap.center = startupCenter
            modernMap.zoomLevel = QGroundControl.flightMapZoom
            QGroundControl.flightMapPosition = startupCenter
        }
        updateSelectedMapKindFromActiveType()
        loadDefaultRealRiskData()
        pushToast(qsTr("Modern GCS"), qsTr("Map and telemetry layers are ready."), "ok", 3200)
    }

    function fitModernMission() {
        if (modernMap.mapReady && missionCoordinates.length > 1) {
            const bounds = zoneBounds([{ path: missionCoordinates }])
            if (bounds) {
                modernMap.setVisibleRegion(bounds)
            }
            pushToast(qsTr("Mission"), qsTr("View fitted to the current mission envelope."), "info", 2400)
        }
    }

    function riskZoneTone(kind) {
        switch (kind) {
        case "nfz":
            return root.err
        case "restricted":
            return root.warn
        case "advisory":
            return root.blue
        case "radar":
            return "#a855f7"
        case "geofence":
            return root.gold
        default:
            return root.gold
        }
    }

    function riskZoneFill(kind) {
        switch (kind) {
        case "nfz":
            return "#33ef4444"
        case "restricted":
            return "#2bf59e0b"
        case "advisory":
            return "#203b82f6"
        case "radar":
            return "#24a855f7"
        case "geofence":
            return "#16c9a84c"
        default:
            return "#22c9a84c"
        }
    }

    function normalizeZoneKind(kind) {
        return String(kind || "zone").toLowerCase()
    }

    function zoneLabel(zone) {
        if (zone.label) {
            return zone.label
        }
        const kind = normalizeZoneKind(zone.kind)
        if (kind === "nfz") {
            return "NFZ"
        }
        return kind.toUpperCase()
    }

    function normalizeCoordinate(coordinate) {
        if (!coordinate) {
            return QtPositioning.coordinate()
        }
        if (coordinate.isValid !== undefined) {
            return coordinate
        }
        if (coordinate.latitude !== undefined && coordinate.longitude !== undefined) {
            return QtPositioning.coordinate(Number(coordinate.latitude), Number(coordinate.longitude), Number(coordinate.altitude || 0))
        }
        if (coordinate.lat !== undefined && coordinate.lon !== undefined) {
            return QtPositioning.coordinate(Number(coordinate.lat), Number(coordinate.lon), Number(coordinate.alt || 0))
        }
        if (coordinate.length >= 2) {
            return QtPositioning.coordinate(Number(coordinate[0]), Number(coordinate[1]), Number(coordinate[2] || 0))
        }
        return QtPositioning.coordinate()
    }

    function normalizeZonePath(zone) {
        const sourcePath = zone.path || zone.coordinates || zone.polygon || []
        const path = []
        for (let i = 0; i < sourcePath.length; i++) {
            const coordinate = normalizeCoordinate(sourcePath[i])
            if (coordinate.isValid) {
                path.push(coordinate)
            }
        }
        return path
    }

    function zoneCenter(path, fallbackCenter) {
        const fallback = normalizeCoordinate(fallbackCenter)
        if (fallback.isValid) {
            return fallback
        }
        if (path.length === 0) {
            return QtPositioning.coordinate()
        }
        let lat = 0
        let lon = 0
        for (let i = 0; i < path.length; i++) {
            lat += path[i].latitude
            lon += path[i].longitude
        }
        return QtPositioning.coordinate(lat / path.length, lon / path.length)
    }

    function normalizedRiskZone(zone, index) {
        if (!zone || zone.active === false || zone.enabled === false) {
            return null
        }
        const path = normalizeZonePath(zone)
        if (path.length < 3) {
            return null
        }
        const kind = normalizeZoneKind(zone.kind || zone.type || zone.category)
        const borderColor = zone.borderColor || zone.color || riskZoneTone(kind)
        return {
            id: zone.id || (kind + "-" + index),
            kind: kind,
            label: zoneLabel({ label: zone.label || zone.name, kind: kind }),
            path: path,
            center: zoneCenter(path, zone.center),
            fillColor: zone.fillColor || riskZoneFill(kind),
            borderColor: borderColor,
            textColor: zone.textColor || borderColor,
            severity: zone.severity || "advisory",
            source: zone.source || "api"
        }
    }

    function normalizedZonesFrom(sourceZones) {
        const zones = []
        for (let i = 0; i < sourceZones.length; i++) {
            const zone = normalizedRiskZone(sourceZones[i], i)
            if (zone) {
                zones.push(zone)
            }
        }
        return zones
    }

    function activeAirspaceZones() {
        return normalizedZonesFrom(riskZones)
    }

    function activeAirportRiskZones() {
        return normalizedZonesFrom(airportRiskZones)
    }

    function activeRiskZones() {
        return activeAirspaceZones().concat(activeAirportRiskZones())
    }

    function riskZoneControls() {
        const zones = visibleRiskZones()
        const controls = []
        const seen = {}
        for (let i = 0; i < zones.length; i++) {
            const kind = zones[i].kind
            if (!seen[kind]) {
                seen[kind] = { label: zones[i].label, key: kind, tone: zones[i].borderColor, count: 0 }
                controls.push(seen[kind])
            }
            seen[kind].count++
        }
        if (controls.length === 0 && airspaceTileOverlayActive()) {
            return [
                { label: "NFZ", key: "nfz", tone: root.err, count: 0 },
                { label: "RESTRICTED", key: "restricted", tone: root.warn, count: 0 },
                { label: "ADVISORY", key: "advisory", tone: root.blue, count: 0 },
                { label: "RADAR", key: "radar", tone: "#a855f7", count: 0 }
            ]
        }
        return controls
    }

    function zoneBounds(zones) {
        let minLat = 90
        let maxLat = -90
        let minLon = 180
        let maxLon = -180
        let found = false
        for (let i = 0; i < zones.length; i++) {
            for (let j = 0; j < zones[i].path.length; j++) {
                const coordinate = zones[i].path[j]
                minLat = Math.min(minLat, coordinate.latitude)
                maxLat = Math.max(maxLat, coordinate.latitude)
                minLon = Math.min(minLon, coordinate.longitude)
                maxLon = Math.max(maxLon, coordinate.longitude)
                found = true
            }
        }
        if (!found) {
            return null
        }
        const latPad = Math.max((maxLat - minLat) * 0.18, 0.005)
        const lonPad = Math.max((maxLon - minLon) * 0.18, 0.005)
        return QtPositioning.rectangle(
            QtPositioning.coordinate(maxLat + latPad, minLon - lonPad),
            QtPositioning.coordinate(minLat - latPad, maxLon + lonPad))
    }

    function riskZoneOpacity(kind) {
        if (!selectedRiskZone || selectedRiskZone === kind) {
            return 1.0
        }
        return 0.28
    }

    function riskZonePulseOpacity(kind) {
        const pulse = 0.88 + 0.12 * ((Math.sin(riskPulse) + 1) / 2)
        return riskZoneOpacity(kind) * pulse
    }

    function riskZoneBorderWidth(kind) {
        return selectedRiskZone === kind ? 3 : 2
    }

    function selectRiskZone(kind) {
        if (kind === "fleet") {
            selectedRiskZone = "fleet"
            centerOnVehicle()
            pushToast(qsTr("Fleet"), qsTr("Fleet focus active."), "info", 2200)
            return
        }
        const zones = visibleRiskZones().filter(function(zone) { return zone.kind === kind })
        if (zones.length === 0) {
            if (airspaceTileOverlayActive()) {
                selectedRiskZone = selectedRiskZone === kind ? "" : kind
                pushToast(qsTr("Airspace"), qsTr("%1 tile layer is visible; vector zone data is not available here yet.").arg(kind.toUpperCase()), "info", 2600)
                return
            }
            pushToast(qsTr("Risk Zone"), qsTr("No active %1 zone is available.").arg(kind.toUpperCase()), "warn", 2200)
            return
        }
        selectedRiskZone = kind
        const bounds = zoneBounds(zones)
        if (modernMap.mapReady && bounds) {
            modernMap.setVisibleRegion(bounds)
        } else if (zones[0].center.isValid) {
            modernMap.center = zones[0].center
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 13)
        }
        pushToast(qsTr("Risk Zone"), qsTr("%1 active zone focused.").arg(zones[0].label), "warn", 2600)
    }

    function setRiskZones(zones) {
        riskZones = zones || []
        validateSelectedRiskZone()
    }

    function setAirportRiskZones(zones) {
        airportRiskZones = zones || []
        validateSelectedRiskZone()
    }

    function validateSelectedRiskZone() {
        if (selectedRiskZone && selectedRiskZone !== "fleet" && visibleRiskZones().filter(function(zone) { return zone.kind === selectedRiskZone }).length === 0) {
            selectedRiskZone = ""
        }
    }

    function clearRiskZones() {
        riskZones = []
        airportRiskZones = []
        selectedRiskZone = selectedRiskZone === "fleet" ? selectedRiskZone : ""
    }

    function upsertRiskZone(zone) {
        if (!zone || !zone.id) {
            return
        }
        const zones = riskZones.slice()
        for (let i = 0; i < zones.length; i++) {
            if (zones[i].id === zone.id) {
                zones[i] = zone
                setRiskZones(zones)
                return
            }
        }
        zones.push(zone)
        setRiskZones(zones)
    }

    function removeRiskZone(zoneId) {
        setRiskZones(riskZones.filter(function(zone) { return zone.id !== zoneId }))
    }

    function setWeatherAlerts(alerts) {
        weatherAlerts = alerts || []
    }

    function activeWeatherAlerts() {
        return weatherAlerts.filter(function(alert) { return alert && alert.active !== false && alert.enabled !== false })
    }

    function activeWindAlert() {
        const alerts = activeWeatherAlerts()
        for (let i = 0; i < alerts.length; i++) {
            const key = String(alerts[i].type || alerts[i].category || alerts[i].label || "").toLowerCase()
            if (key.indexOf("wind") !== -1 || key.indexOf("shear") !== -1) {
                return alerts[i]
            }
        }
        return null
    }

    Timer {
        interval: 60
        running: true
        repeat: true
        onTriggered: root.riskPulse += 0.18
    }

    function syncFlyMapFromSharedState() {
        if (!modernMap || !modernMap.mapReady) {
            return
        }
        if (QGroundControl.flightMapPosition.isValid && !coordinatesClose(modernMap.center, QGroundControl.flightMapPosition)) {
            modernMap.center = QGroundControl.flightMapPosition
        }
        if (Math.abs(modernMap.zoomLevel - QGroundControl.flightMapZoom) > 0.01) {
            modernMap.zoomLevel = QGroundControl.flightMapZoom
        }
        updateSelectedMapKindFromActiveType()
        riskZoneViewportRevision++
        airspaceTileRevision++
    }

    function coordinatesClose(a, b) {
        return a && b && a.isValid && b.isValid
            && Math.abs(a.latitude - b.latitude) < 0.000001
            && Math.abs(a.longitude - b.longitude) < 0.000001
    }

    function activateModernSection(section) {
        activeModernSection = section
        if (section !== "fly") {
            payloadPanelOpen = false
        }
        if (section === "fly") {
            Qt.callLater(syncFlyMapFromSharedState)
        }
        if (section !== "fly") {
            pushToast(qsTr("Modern %1").arg(section.toUpperCase()), qsTr("Workspace opened."), "info", 2200)
        }
    }

    function centerOnVehicle() {
        if (activeVehicle && activeVehicle.coordinate.isValid) {
            modernMap.center = activeVehicle.coordinate
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 16)
        } else if (modernMap.gcsPosition.isValid) {
            modernMap.center = modernMap.gcsPosition
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 14)
        } else if (defaultCenter.isValid) {
            modernMap.center = defaultCenter
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 12)
        }
        QGroundControl.flightMapPosition = modernMap.center
        QGroundControl.flightMapZoom = modernMap.zoomLevel
    }

    function confirmVehicleAction(title, message, action) {
        if (!activeVehicle) {
            mainWindow.showMessageDialog(qsTr("No Vehicle"), qsTr("Connect to a vehicle before using this action."))
            return
        }
        mainWindow.showMessageDialog(title, message, Dialog.Yes | Dialog.No, action)
    }

    function beginPendingVehicleAction(action) {
        if (pendingVehicleAction !== "") {
            return false
        }
        pendingVehicleAction = action
        pendingVehicleActionStartedAt = Date.now()
        pendingVehicleActionTimer.start()
        return true
    }

    function finishPendingVehicleAction(success, message) {
        if (pendingVehicleAction === "") {
            return
        }
        pendingVehicleAction = ""
        pendingVehicleActionStartedAt = 0
        pendingVehicleActionTimer.stop()
        if (!success) {
            recordVehicleWarning(message)
        }
        pushToast(qsTr("Vehicle Command"), message, success ? "ok" : "warn", success ? 2200 : 4200)
    }

    function pendingVehicleActionSatisfied() {
        if (!activeVehicle) {
            return false
        }
        switch (pendingVehicleAction) {
        case "arm": return activeVehicle.armed
        case "disarm": return !activeVehicle.armed
        case "takeoff": return activeVehicle.flying
        case "land": return activeVehicle.landing || activeVehicle.flightMode === activeVehicle.landFlightMode
        case "rtl": return activeVehicle.flightMode === activeVehicle.rtlFlightMode || activeVehicle.flightMode === activeVehicle.smartRTLFlightMode
        case "pause": return activeVehicle.flightMode === activeVehicle.pauseFlightMode
        default: return false
        }
    }

    function pendingVehicleActionSuccessText() {
        switch (pendingVehicleAction) {
        case "arm": return qsTr("Vehicle armed.")
        case "disarm": return qsTr("Vehicle disarmed.")
        case "takeoff": return qsTr("Takeoff state confirmed.")
        case "land": return qsTr("Landing mode confirmed.")
        case "rtl": return qsTr("Return-to-launch mode confirmed.")
        case "pause": return qsTr("Pause mode confirmed.")
        default: return qsTr("Vehicle state confirmed.")
        }
    }

    function updatePendingVehicleAction() {
        if (pendingVehicleAction === "") {
            pendingVehicleActionTimer.stop()
            return
        }
        if (!activeVehicle) {
            finishPendingVehicleAction(false, qsTr("Vehicle disconnected before the command was confirmed."))
            return
        }
        if (pendingVehicleActionSatisfied()) {
            finishPendingVehicleAction(true, pendingVehicleActionSuccessText())
            return
        }
        if (Date.now() - pendingVehicleActionStartedAt >= 20000) {
            finishPendingVehicleAction(false, qsTr("No confirming vehicle-state update was received. Check vehicle messages before retrying."))
        }
    }

    function armVehicle() {
        if (!activeVehicle) {
            mainWindow.showMessageDialog(qsTr("No Vehicle"), qsTr("Connect to a vehicle before using this action."))
            return
        }
        if (activeVehicle.armed) {
            pushToast(qsTr("Vehicle"), qsTr("Vehicle is already armed."), "info", 1800)
            return
        }
        if (!vehicleCanArm()) {
            mainWindow.showMessageDialog(qsTr("Arm Unavailable"), qsTr("The enforced checklist, health checks, or required RC link checks are not passing."))
            return
        }
        confirmVehicleAction(qsTr("Arm Vehicle"), qsTr("Arm the active vehicle?"), function() {
            if (!activeVehicle || activeVehicle.armed || !vehicleCanArm() || !beginPendingVehicleAction("arm")) {
                return
            }
            activeVehicle.armed = true
            pushToast(qsTr("Vehicle Command"), qsTr("Arm command sent; awaiting vehicle state."), "info", 2200)
        })
    }

    function disarmVehicle() {
        if (!activeVehicle) {
            mainWindow.showMessageDialog(qsTr("No Vehicle"), qsTr("Connect to a vehicle before using this action."))
            return
        }
        if (!activeVehicle.armed) {
            pushToast(qsTr("Vehicle"), qsTr("Vehicle is already disarmed."), "info", 1800)
            return
        }
        if (activeVehicle.flying) {
            mainWindow.showMessageDialog(qsTr("Disarm Unavailable"), qsTr("Disarm is blocked while the vehicle is airborne. Use Land or RTL first."))
            return
        }
        confirmVehicleAction(qsTr("Disarm Vehicle"), qsTr("Disarm the active vehicle?"), function() {
            if (!vehicleCanDisarm() || !beginPendingVehicleAction("disarm")) {
                return
            }
            activeVehicle.armed = false
            pushToast(qsTr("Vehicle Command"), qsTr("Disarm command sent; awaiting vehicle state."), "info", 2200)
        })
    }

    function takeoffVehicle() {
        if (!vehicleCanTakeoff()) {
            mainWindow.showMessageDialog(qsTr("Takeoff Unavailable"), qsTr("Takeoff requires a connected vehicle, passing preflight checks, and firmware takeoff support."))
            return
        }
        const takeoffAltitude = activeVehicle.minimumTakeoffAltitudeMeters()
        confirmVehicleAction(qsTr("Takeoff"), qsTr("Take off and hold at the vehicle minimum takeoff altitude (%1 m)?").arg(Number(takeoffAltitude).toFixed(1)), function() {
            if (!vehicleCanTakeoff() || !beginPendingVehicleAction("takeoff")) {
                return
            }
            if (activeVehicle.guidedTakeoffSupported) {
                activeVehicle.guidedModeTakeoff(takeoffAltitude)
            } else {
                activeVehicle.startTakeoff()
            }
            pushToast(qsTr("Vehicle Command"), qsTr("Takeoff command sent; awaiting flight state."), "info", 2200)
        })
    }

    function landVehicle() {
        if (!vehicleCanLand()) {
            mainWindow.showMessageDialog(qsTr("Land Unavailable"), qsTr("Land requires an armed guided vehicle, is unavailable for fixed-wing vehicles here, and is hidden when Land mode is already active."))
            return
        }
        confirmVehicleAction(qsTr("Land"), qsTr("Command land now?"), function() {
            if (!vehicleCanLand() || !beginPendingVehicleAction("land")) {
                return
            }
            activeVehicle.guidedModeLand()
            pushToast(qsTr("Vehicle Command"), qsTr("Land command sent; awaiting landing mode."), "info", 2200)
        })
    }

    function rtlVehicle() {
        if (!vehicleCanRTL()) {
            mainWindow.showMessageDialog(qsTr("RTL Unavailable"), qsTr("Return to launch is only available while the active vehicle is armed and guided commands are supported."))
            return
        }
        confirmVehicleAction(qsTr("Return To Launch"), qsTr("Command return to launch?"), function() {
            if (!vehicleCanRTL() || !beginPendingVehicleAction("rtl")) {
                return
            }
            activeVehicle.guidedModeRTL(false)
            pushToast(qsTr("Vehicle Command"), qsTr("RTL command sent; awaiting flight mode."), "info", 2200)
        })
    }

    function pauseVehicle() {
        if (!vehicleCanPause()) {
            mainWindow.showMessageDialog(qsTr("Pause Unavailable"), qsTr("Pause is only available on connected vehicles that support guided pause."))
            return
        }
        confirmVehicleAction(qsTr("Pause"), qsTr("Pause at current position?"), function() {
            if (!vehicleCanPause() || !beginPendingVehicleAction("pause")) {
                return
            }
            activeVehicle.guidedModeChangeAltitude(0, true)
            pushToast(qsTr("Vehicle Command"), qsTr("Pause command sent; awaiting hold mode."), "info", 2200)
        })
    }

    function disconnectVehicle() {
        if (activeVehicle) {
            activeVehicle.closeVehicle()
            pushToast(qsTr("Vehicle"), qsTr("Connection closed."), "warn", 2200)
        }
    }

    function openFullSettings() {
        if (mainWindow && mainWindow.showSettingsTool) {
            mainWindow.showSettingsTool()
        }
    }

    function openCommLinksSettings() {
        modernConnectPanelOpen = true
    }

    function closeCommLinksPanel() {
        modernConnectPanelOpen = false
    }

    function hasManualLinkConfigurations() {
        const linkConfigs = QGroundControl.linkManager.linkConfigurations
        for (let i = 0; i < linkConfigs.count; i++) {
            const linkConfig = linkConfigs.get(i)
            if (linkConfig && !linkConfig.dynamic && !linkConfig.isAutoConnect) {
                return true
            }
        }
        return false
    }

    Timer {
        id: telemetryTimer
        interval: 1000
        repeat: true
        running: root.activeModernSection === "fly" && !!root.activeVehicle
        onTriggered: root.refreshTelemetrySamples()
    }

    Timer {
        id: modernAlertClockTimer
        interval: 1000
        repeat: true
        running: root.activeModernSection === "fly"
        triggeredOnStart: true
        onTriggered: root.modernAlertClock = Qt.formatTime(new Date(), "hh:mm:ss")
    }

    Timer {
        id: pendingVehicleActionTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: root.updatePendingVehicleAction()
    }

    Timer {
        id: riskMapRefreshTimer
        interval: 4000
        repeat: false
        onTriggered: {
            root.refreshRiskDataForMap()
            root.refreshAirportRiskDataForMap()
        }
    }

    Timer {
        id: airportRiskMapRefreshTimer
        interval: 5000
        repeat: false
        onTriggered: root.refreshAirportRiskDataForMap()
    }

    Timer {
        id: riskPeriodicRefreshTimer
        interval: 300000
        repeat: true
        running: root.riskDataSourceTemplate !== "" || root.airportRiskDataSourceTemplate !== ""
        onTriggered: {
            root.refreshRiskDataForMap()
            root.refreshAirportRiskDataForMap()
        }
    }

    Connections {
        target: root._missionController
        ignoreUnknownSignals: true
        function onVisualItemsChanged() { root.syncMissionCoordinates() }
        function onNewItemsFromVehicle() { root.syncMissionCoordinates() }
        function onCurrentPlanViewSeqNumChanged() { root.syncMissionCoordinates() }
        function onCurrentMissionIndexChanged() {
            if (!root.missionTimelineInspectionMode) {
                root.syncMissionScrubIndexToLive()
            }
        }
        function onMissionItemCountChanged() {
            root.syncMissionCoordinates()
            if (!root.missionTimelineInspectionMode) {
                root.syncMissionScrubIndexToLive()
            }
        }
    }

    Connections {
        target: root._visualItems
        ignoreUnknownSignals: true
        function onCountChanged() { root.syncMissionCoordinates() }
    }

    Connections {
        target: QGroundControl.qgcPositionManger
        ignoreUnknownSignals: true
        function onGcsPositionChanged(gcsPosition) {
            root.applyLiveGcsLocation(gcsPosition)
        }
    }

    Connections {
        target: QGroundControl.settingsManager.appSettings.openaipToken
        ignoreUnknownSignals: true
        function onRawValueChanged() {
            root.openAipToken = QGroundControl.settingsManager.appSettings.openaipToken.rawValue || ""
            if (root.riskDataSourceTemplate === "" || root.riskDataSourceTemplate.indexOf("api.core.openaip.net") !== -1 || root.airportRiskDataSourceTemplate.indexOf("api.core.openaip.net") !== -1) {
                root.riskDataSourceTemplate = ""
                root.airportRiskDataSourceTemplate = ""
                root.loadDefaultRealRiskData()
            }
        }
    }

    Connections {
        target: QGroundControl.settingsManager.flightMapSettings.mapType
        ignoreUnknownSignals: true
        function onRawValueChanged() {
            if (root.activeModernSection === "fly") {
                Qt.callLater(root.initializeModernMapType)
                Qt.callLater(root.syncFlyMapFromSharedState)
            }
        }
    }

    Connections {
        target: QGroundControl
        ignoreUnknownSignals: true
        function onFlightMapPositionChanged() {
            if (root.activeModernSection === "fly") {
                root.syncFlyMapFromSharedState()
            }
        }
        function onFlightMapZoomChanged() {
            if (root.activeModernSection === "fly") {
                root.syncFlyMapFromSharedState()
            }
        }
    }

    Connections {
        target: QGroundControl.multiVehicleManager
        ignoreUnknownSignals: true
        function onActiveVehicleChanged() {
            if (root.pendingVehicleAction !== "") {
                root.finishPendingVehicleAction(false, qsTr("Active vehicle changed before command confirmation."))
            }
            if (root.activeVehicle) {
                root.modernConnectPanelOpen = false
            }
            root.syncMissionCoordinates()
            root.syncMissionScrubIndexToLive()
        }
    }

    Repeater {
        model: root._visualItems
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onCoordinateChanged() { root.syncMissionCoordinates() }
            function onSpecifiesCoordinateChanged() { root.syncMissionCoordinates() }
        }
    }

    Timer {
        id: toastSweepTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: {
            for (let i = toastModel.count - 1; i >= 0; i--) {
                if (toastModel.get(i).expiresAt <= Date.now()) {
                    toastModel.remove(i)
                }
            }
            if (toastModel.count === 0) {
                stop()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    Component.onCompleted: {
        refreshTelemetrySamples()
        activeModernSection = "fly"
        Qt.callLater(syncFlyMapFromSharedState)
        Qt.callLater(loadDefaultRealRiskData)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "#040507"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.gold
                opacity: 0.85
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Image {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    source: "qrc:/Briech/res/logoBlack.png"
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    text: "BRIECH UAS"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 20
                    font.letterSpacing: 2
                    font.family: "Barlow Condensed"
                }

                Text {
                    text: "Ground Control Station"
                    color: root.gold
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    font.family: "Barlow Condensed"
                    font.bold: true
                }

                Item { Layout.fillWidth: true }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: root.modernGlassStrong

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: root.activeVehicle ? 248 : 282
                    Layout.fillHeight: true
                    color: "transparent"
                    border.color: root.modernHairline
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 4
                            color: root.activeVehicle ? root.ok : "#333842"
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.vehicleStatusText()
                            color: root.text
                            elide: Text.ElideRight
                            font.pixelSize: 16
                            font.bold: true
                            font.family: "Barlow Condensed"
                        }

                        Rectangle {
                            Layout.preferredWidth: visible ? 28 : 0
                            Layout.preferredHeight: 24
                            visible: root.activeVehicle && Number(root.messageCountText()) > 0
                            radius: 4
                            color: root.modernVehicleMessagesOpen ? "#1b2230" : "transparent"
                            border.color: root.modernVehicleMessagesOpen ? root.gold : "transparent"
                            border.width: root.modernVehicleMessagesOpen ? 1 : 0

                            QGCColoredImage {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: "qrc:/res/VehicleMessages.png"
                                color: "#ffffff"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: -2
                                anchors.topMargin: -2
                                width: 8
                                height: 8
                                radius: 4
                                visible: root.activeVehicle && (root.activeVehicle.messageTypeError || root.activeVehicle.messageTypeWarning)
                                color: root.vehicleMessageIconColor()
                                border.color: "#05070a"
                                border.width: 1
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.modernVehicleMessagesOpen = !root.modernVehicleMessagesOpen
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.activeVehicle
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.openCommLinksSettings()
                    }
                }

                Repeater {
                    model: root.activeVehicle ? 6 : 0

                    delegate: Rectangle {
                        required property int index
                        property int telemetryIndex: index
                        Layout.preferredWidth: Math.max(72, label.implicitWidth + value.implicitWidth + unit.implicitWidth + 18)
                        Layout.fillHeight: true
                        color: "transparent"
                        border.color: root.modernHairline
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                id: label
                                text: root.telemetrySlotKey(parent.parent.telemetryIndex)
                                color: root.dim
                                font.pixelSize: 12
                                font.family: "Barlow Condensed"
                                font.bold: true
                            }

                            Text {
                                id: value
                                text: root.telemetrySlotValue(parent.parent.telemetryIndex)
                                color: root.telemetrySlotValueColor(parent.parent.telemetryIndex)
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "Barlow Condensed"
                            }

                            Text {
                                id: unit
                                text: root.telemetrySlotUnit(parent.parent.telemetryIndex)
                                color: root.dim
                                font.pixelSize: 12
                                font.family: ScreenTools.normalFontFamily
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    Layout.preferredWidth: 440
                    Layout.fillHeight: true
                    Layout.rightMargin: 4
                    spacing: 0

                    Repeater {
                        model: root.modernNavSections.length

                        delegate: ModernNavButton {
                            required property int index
                            property var navItem: root.modernNavSections[index] || ({})
                            property string navLabel: navItem.label || ""
                            property string navKey: navItem.key || ""
                            property string navIcon: navItem.icon || ""
                            label: navLabel
                            iconSource: navIcon
                            active: root.activeModernSection === navKey
                            onClicked: root.activateModernSection(navKey)
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.fillHeight: true
                        color: settingsMouseArea.containsMouse ? "#111720" : "#0b0f15"
                        border.color: "#171d27"
                        border.width: 1

                        QGCColoredImage {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: "/qmlimages/Gears.svg"
                            color: settingsMouseArea.containsMouse ? root.gold : root.dim
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }

                        MouseArea {
                            id: settingsMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openFullSettings()
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                spacing: 0
                visible: root.activeModernSection === "fly"

                Rectangle {
                    Layout.preferredWidth: 82
                    Layout.fillHeight: true
                    color: "#07090d"
                    border.color: "#1e242e"
                    border.width: 1

                    ColumnLayout {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 8
                        spacing: 4

                        Repeater {
                            model: root.flyActionModel().length

                            delegate: Rectangle {
                                required property int index
                                property var actionItem: root.flyActionModel()[index] || ({})
                                property string actionText: actionItem.t || ""
                                property string actionShort: actionItem.s || ""
                                property string actionKey: actionItem.a || ""
                                property bool actionEnabled: !!actionItem.enabled
                                property bool actionVisible: actionItem.visible !== false
                                property bool disconnectAction: actionKey === "disconnect"
                                Layout.preferredWidth: 70
                                Layout.preferredHeight: visible ? 52 : 0
                                visible: actionVisible
                                radius: 6
                                opacity: actionEnabled ? 1.0 : 0.78
                                color: disconnectAction ? "#171109" : "#0c1017"
                                border.color: disconnectAction ? root.gold : (actionEnabled ? "#243041" : "#1b2430")
                                border.width: 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: parent.parent.actionShort
                                        color: parent.parent.actionEnabled ? (parent.parent.disconnectAction ? root.gold : root.text) : "#6a7585"
                                        font.pixelSize: 14
                                        font.bold: true
                                        font.family: "Barlow Condensed"
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: parent.parent.actionText
                                        color: parent.parent.actionEnabled ? (parent.parent.disconnectAction ? root.gold : root.dim) : "#586272"
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.family: "Barlow Condensed"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: parent.actionEnabled
                                    onClicked: {
                                        switch (parent.actionKey) {
                                        case "connect": root.openCommLinksSettings(); break
                                        case "disconnect": root.disconnectVehicle(); break
                                        case "arm": root.armVehicle(); break
                                        case "disarm": root.disarmVehicle(); break
                                        case "takeoff": root.takeoffVehicle(); break
                                        case "pause": root.pauseVehicle(); break
                                        case "land": root.landVehicle(); break
                                        case "rtl": root.rtlVehicle(); break
                                        case "center": root.centerOnVehicle(); break
                                        case "fit": root.fitModernMission(); break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: modernMapContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    QtObject {
                        id: modernMapToolInsets

                        property real leftEdgeTopInset: 24
                        property real leftEdgeCenterInset: 24
                        property real leftEdgeBottomInset: 24
                        property real rightEdgeTopInset: 150
                        property real rightEdgeCenterInset: 280
                        property real rightEdgeBottomInset: 280
                        property real topEdgeLeftInset: 48
                        property real topEdgeRightInset: 48
                        property real bottomEdgeLeftInset: 72
                        property real bottomEdgeRightInset: 250
                    }

                    FlyViewMap {
                        id: modernMap
                        x: 0
                        y: 0
                        width: modernMapContainer.width
                        height: modernMapContainer.height
                        mapName: "BriechModernFlyView"
                        planMasterController: root._planMasterController
                        toolInsets: modernMapToolInsets
                        rightPanelWidth: 0
                        pipMode: false

                        onZoomLevelChanged: {
                            QGroundControl.flightMapZoom = modernMap.zoomLevel
                            root.riskZoneViewportRevision++
                            root.airspaceTileRevision++
                            if (root.riskDataSourceUsesMap()) {
                                riskMapRefreshTimer.interval = 4000
                                riskMapRefreshTimer.restart()
                            }
                        }
                        onCenterChanged: {
                            QGroundControl.flightMapPosition = modernMap.center
                            root.riskZoneViewportRevision++
                            root.airspaceTileRevision++
                            if (root.riskDataSourceUsesMap()) {
                                riskMapRefreshTimer.interval = 4000
                                riskMapRefreshTimer.restart()
                            }
                        }
                        onMapReadyChanged: root.initializeModernMapType()
                        onGcsPositionChanged: {
                            if (!root.liveGcsLocationReceived && !root.activeVehicle && modernMap.gcsPosition.isValid && !QGroundControl.flightMapPosition.isValid) {
                                modernMap.center = modernMap.gcsPosition
                                QGroundControl.flightMapPosition = modernMap.gcsPosition
                                root.riskZoneViewportRevision++
                                root.airspaceTileRevision++
                                if (root.riskDataSourceUsesMap()) {
                                    riskMapRefreshTimer.interval = 4000
                                    riskMapRefreshTimer.restart()
                                }
                            }
                        }
                    }

                    ModernWatermarkLayer {
                        anchors.fill: parent
                        visible: root.activeModernSection === "fly" && root.modernWatermarkEnabled
                    }

                    ModernFlightAlertStack {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 20
                        anchors.rightMargin: 214
                        width: 312
                        model: root.modernFlightAlerts()
                        onDismissRequested: function(key, kind) {
                            root.dismissModernFlightAlert(key, kind)
                        }
                    }

                    ModernToastStack {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 44
                        anchors.rightMargin: 12
                        width: 292
                        model: toastModel
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.topMargin: 48
                        anchors.leftMargin: 18
                        width: 420
                        height: 520
                        visible: root.activeModernSection === "fly" && root.activeVehicle && root.modernVehicleMessagesOpen
                        color: "#161b22"
                        border.color: "#4a5564"
                        border.width: 1
                        radius: 4
                        z: QGroundControl.zOrderWidgets + 11

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ModernSettingsAction {
                                    Layout.preferredWidth: 52
                                    label: "ARM"
                                    tone: root.gold
                                    enabled: root.vehicleCanArm()
                                    onClicked: root.armVehicle()
                                }

                                Text {
                                    text: "Vehicle Messages"
                                    color: root.text
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.family: ScreenTools.normalFontFamily
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: "#202734"
                                    border.color: "#5b6574"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "x"
                                        color: root.text
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.modernVehicleMessagesOpen = false
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: "#0f141b"
                                border.color: "#2b3442"
                                border.width: 1
                                radius: 2

                                ScrollView {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    clip: true

                                    TextArea {
                                        id: modernVehicleMessageArea
                                        width: parent.width
                                        readOnly: true
                                        wrapMode: TextEdit.Wrap
                                        textFormat: TextEdit.RichText
                                        color: root.text
                                        selectionColor: root.gold
                                        selectedTextColor: "#0a0e14"
                                        background: null
                                        text: root.activeVehicle ? root.formatVehicleMessageHtml(root.activeVehicle.formattedMessages) : ""

                                        Connections {
                                            target: root.activeVehicle
                                            ignoreUnknownSignals: true

                                            function onNewFormattedMessage(formattedMessage) {
                                                root.recordVehicleWarning(formattedMessage)
                                                modernVehicleMessageArea.insert(0, root.formatVehicleMessageHtml(formattedMessage))
                                            }

                                            function onFormattedMessagesChanged() {
                                                if (root.activeVehicle) {
                                                    root.recordVehicleWarning(root.activeVehicle.formattedMessages)
                                                }
                                                modernVehicleMessageArea.text = root.activeVehicle ? root.formatVehicleMessageHtml(root.activeVehicle.formattedMessages) : ""
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ModernSettingsAction {
                                    Layout.preferredWidth: 82
                                    label: "CLEAR"
                                    tone: root.dim
                                    enabled: !!root.activeVehicle
                                    onClicked: {
                                        if (root.activeVehicle) {
                                            root.activeVehicle.clearMessages()
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: qsTr("%1 messages").arg(root.messageCountText())
                                    color: root.dim
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.topMargin: 20
                        anchors.leftMargin: 18
                        width: 548
                        height: 278
                        visible: root.activeModernSection === "fly" && !root.activeVehicle && root.modernConnectPanelOpen
                        color: "#2a2d31"
                        opacity: 0.96
                        border.color: "#4a4f56"
                        border.width: 1
                        radius: 6
                        z: QGroundControl.zOrderWidgets + 10

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            color: "#2a2d31"
                            radius: 5
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 14

                            ColumnLayout {
                                Layout.preferredWidth: 150
                                Layout.fillHeight: true
                                spacing: 8

                                Text {
                                    text: "Select Link to Connect"
                                    color: "#f8fafc"
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.family: ScreenTools.normalFontFamily
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#23262b"
                                    border.color: "#5c636d"
                                    border.width: 1
                                    radius: 6

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        Text {
                                            visible: !root.hasManualLinkConfigurations()
                                            text: "No Links Configured"
                                            color: "#f8fafc"
                                            font.pixelSize: 12
                                            font.family: ScreenTools.normalFontFamily
                                        }

                                        Repeater {
                                            model: QGroundControl.linkManager.linkConfigurations

                                            delegate: Rectangle {
                                                required property var object
                                                width: parent.width
                                                height: visible ? 34 : 0
                                                visible: object && !object.dynamic && !object.isAutoConnect
                                                radius: 4
                                                color: "#30343a"
                                                border.color: object.link ? root.ok : "#6b7280"
                                                border.width: 1
                                                opacity: object.link ? 0.6 : 1.0

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 10
                                                    text: object.name + (object.link ? " (Connected)" : "")
                                                    color: "#f8fafc"
                                                    font.pixelSize: 11
                                                    font.family: ScreenTools.normalFontFamily
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: !object.link
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: {
                                                        QGroundControl.linkManager.createConnectedLink(object)
                                                        root.modernConnectPanelOpen = false
                                                        root.pushToast(qsTr("Comm Links"), qsTr("Connection requested for %1.").arg(object.name), "info", 2400)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 1
                                Layout.fillHeight: true
                                color: "#50545b"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    spacing: 10

                                    Text {
                                        text: "Communication Links"
                                        color: "#f8fafc"
                                        font.pixelSize: 13
                                        font.family: ScreenTools.normalFontFamily
                                    }

                                    ModernSettingsAction {
                                        Layout.preferredWidth: 104
                                        label: "CONFIGURE"
                                        tone: root.text
                                        onClicked: {
                                            root.modernConnectPanelOpen = false
                                            if (mainWindow && mainWindow.showSettingsTool) {
                                                mainWindow.showSettingsTool(qsTr("Comm Links"))
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    ModernSettingsAction {
                                        Layout.preferredWidth: 32
                                        label: "X"
                                        tone: root.dim
                                        onClicked: root.closeCommLinksPanel()
                                    }
                                }

                                Text {
                                    text: "AutoConnect"
                                    color: "#f8fafc"
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.family: ScreenTools.normalFontFamily
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        id: modernAutoConnectRepeater
                                        model: [
                                            QGroundControl.settingsManager.autoConnectSettings.autoConnectPixhawk,
                                            QGroundControl.settingsManager.autoConnectSettings.autoConnectSiKRadio,
                                            QGroundControl.settingsManager.autoConnectSettings.autoConnectLibrePilot,
                                            QGroundControl.settingsManager.autoConnectSettings.autoConnectUDP,
                                            QGroundControl.settingsManager.autoConnectSettings.autoConnectZeroConf,
                                            QGroundControl.settingsManager.autoConnectSettings.autoConnectRTKGPS
                                        ]

                                        property var names: [ "Pixhawk", "SiK Radio", "LibrePilot", "UDP", "Zero-Conf", "RTK" ]

                                        delegate: Rectangle {
                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: modelData && modelData.visible ? 28 : 0
                                            visible: modelData && modelData.visible
                                            color: "#2e3238"
                                            border.color: "#4c5561"
                                            border.width: 1
                                            radius: 4

                                            Text {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 12
                                                text: modernAutoConnectRepeater.names[index]
                                                color: "#f8fafc"
                                                font.pixelSize: 12
                                                font.family: ScreenTools.normalFontFamily
                                            }

                                            Switch {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.rightMargin: 10
                                                checked: !!modelData.rawValue
                                                onToggled: function() {
                                                    modelData.rawValue = checked
                                                }
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 76
                        anchors.bottomMargin: root.payloadPanelOpen ? 228 : 64
                        width: 336
                        height: 156
                        visible: root.activeModernSection === "fly" && !root.activeVehicle
                        color: "#0a0e14"
                        border.color: "#252c38"
                        border.width: 1
                        radius: 4
                        z: QGroundControl.zOrderWidgets

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "FLY STATION READY"
                                color: root.gold
                                font.pixelSize: 13
                                font.bold: true
                                font.letterSpacing: 1
                                font.family: "Barlow Condensed"
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "No vehicle is connected. The live map, local position, and airspace tools remain active while you prepare the link."
                                color: root.text
                                wrapMode: Text.WordWrap
                                font.pixelSize: 10
                                font.family: ScreenTools.normalFontFamily
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4

                                Text { text: "GCS"; color: root.dim; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                                Text { text: root.gcsLocationText(); color: root.ok; font.pixelSize: 10; font.bold: true; font.family: "monospace" }

                                Text { text: "CENTER"; color: root.dim; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                                Text { text: root.mapCenterText(); color: root.text; font.pixelSize: 10; font.bold: true; font.family: "monospace" }

                                Text { text: "MAP"; color: root.dim; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                                Text { text: root.selectedMapKind.toUpperCase(); color: root.gold; font.pixelSize: 10; font.bold: true; font.family: "monospace" }

                                Text { text: "AIRSPACE"; color: root.dim; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                                Text { text: root.airspaceStatusText(); color: root.airspaceStateColor(); font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: "COMM LINKS"
                                    tone: root.gold
                                    onClicked: root.openCommLinksSettings()
                                }

                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: "CENTER MAP"
                                    tone: root.blue
                                    onClicked: root.centerOnVehicle()
                                }

                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: "SETTINGS"
                                    tone: root.ok
                                    onClicked: root.openFullSettings()
                                }
                            }
                        }
                    }

                    ModernSwarmPanel {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 214
                        anchors.rightMargin: 12
                        width: 264
                        visible: QGroundControl.multiVehicleManager.vehicles.count > 1
                        vehicleModel: QGroundControl.multiVehicleManager.vehicles
                    }

                    ModernSparklinePanel {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 76
                        anchors.bottomMargin: 232
                        width: 320
                        height: 146
                        visible: root.activeModernSection === "fly" && root.activeVehicle && root.speedHistory.length > 1
                        speedSeries: root.speedHistory
                        altitudeSeries: root.altitudeHistory
                        batterySeries: root.batteryHistory
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 76
                        anchors.bottomMargin: 20
                        spacing: 6

                        ModernPayloadPanel {
                            Layout.preferredWidth: 318
                            Layout.preferredHeight: 188
                            visible: root.payloadPanelOpen
                            payloadView: root.payloadView
                            videoVisible: root.hasVideoSignal()
                            videoMode: root.payloadVideoMode
                            zoomLevel: root.payloadZoomLevel
                            onCloseRequested: root.closePayload()
                            function onModeRequested(mode) { root.setPayloadMode(mode) }
                            onZoomRequested: root.cyclePayloadZoom()
                        }

                        RowLayout {
                            Layout.preferredWidth: 318
                            Layout.preferredHeight: 28
                            spacing: 4

                            ModernPayloadButton {
                                Layout.fillWidth: true
                                label: "VIDEO FEED"
                                iconKind: "video"
                                enabled: root.hasVideoSignal()
                                active: root.payloadPanelOpen && root.payloadView === "video"
                                onClicked: root.openPayload("video")
                            }

                            ModernPayloadButton {
                                Layout.fillWidth: true
                                label: "3D VIEW"
                                iconKind: "3d"
                                enabled: root.viewer3DReady()
                                active: root.payloadPanelOpen && root.payloadView === "3d"
                                onClicked: root.openPayload("3d")
                            }
                        }

                    }

                    ModernBatteryArc {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 18
                        anchors.bottomMargin: 48
                        width: 214
                        height: 214
                        visible: root.activeVehicle && !isNaN(root.batteryPercent)
                        percent: root.batteryPercent
                    }

                    ModernMissionScrubber {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        width: Math.min(parent.width * 0.42, 620)
                        visible: root.missionTimelineAvailable()
                        maxIndex: root.missionCoordinates.length - 1
                        currentIndex: root.missionTimelineDisplayedIndex()
                        function onScrubbed(scrubIndex) { root.focusMissionWaypoint(scrubIndex, true) }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 10
                        width: 154
                        height: 26
                        color: "#0b0f15"
                        border.color: root.gold
                        border.width: 1
                        radius: 2

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 10
                                height: 10
                                color: "transparent"
                                border.color: root.gold
                                border.width: 1
                                rotation: 45
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "MISSION TIMELINE"
                                color: root.gold
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                                font.letterSpacing: 1
                            }
                        }

                        visible: root.missionTimelineAvailable()
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: false
                        color: "#020304"
                        opacity: 0.58
                    }

                    Canvas {
                        id: mapCanvas
                        anchors.fill: parent
                        visible: false

                        onPaint: {
                            const c = getContext("2d")
                            const w = width
                            const h = height
                            c.reset()
                            c.fillStyle = "rgba(5,6,8,.24)"
                            c.fillRect(0, 0, w, h)

                            c.strokeStyle = "rgba(255,255,255,0.04)"
                            c.lineWidth = 1
                            for (let x = 0; x < w; x += 82) {
                                c.beginPath()
                                c.moveTo(x, 0)
                                c.lineTo(x, h)
                                c.stroke()
                            }
                            for (let y = 0; y < h; y += 68) {
                                c.beginPath()
                                c.moveTo(0, y)
                                c.lineTo(w, y)
                                c.stroke()
                            }

                            c.strokeStyle = "rgba(255,255,255,0.09)"
                            c.lineWidth = 1
                            for (let i = 0; i < 24; i++) {
                                const y = (i * 53) % h
                                c.beginPath()
                                c.moveTo((i * 37) % w, y)
                                c.bezierCurveTo(w * .25, y + 40, w * .45, y - 26, w, (y + 80) % h)
                                c.stroke()
                            }

                            const pts = [
                                [w*.30, h*.66], [w*.36, h*.60], [w*.41, h*.54], [w*.47, h*.45],
                                [w*.54, h*.39], [w*.62, h*.33], [w*.70, h*.44], [w*.61, h*.56]
                            ]
                            c.strokeStyle = "rgba(59,130,246,.95)"
                            c.lineWidth = 3
                            c.beginPath()
                            pts.forEach((p, i) => i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1]))
                            c.stroke()
                            pts.forEach((p, i) => {
                                c.fillStyle = i === 3 ? root.warn : root.blue
                                c.strokeStyle = "white"
                                c.lineWidth = i === 3 ? 2 : 1
                                c.beginPath()
                                c.arc(p[0], p[1], i === 3 ? 11 : 9, 0, Math.PI * 2)
                                c.fill()
                                c.stroke()
                                c.fillStyle = "white"
                                c.font = "bold 10px \"" + ScreenTools.normalFontFamily + "\""
                                c.textAlign = "center"
                                c.fillText(String(i + 1), p[0], p[1] + 4)
                            })

                            c.fillStyle = root.gold
                            c.beginPath()
                            c.moveTo(w*.54, h*.39 - 18)
                            c.lineTo(w*.54 + 12, h*.39 + 18)
                            c.lineTo(w*.54, h*.39 + 8)
                            c.lineTo(w*.54 - 12, h*.39 + 18)
                            c.closePath()
                            c.fill()
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 44
                        width: alertText.implicitWidth + 32
                        height: 22
                        color: "#211606"
                        border.color: root.warn
                        opacity: 0.95
                        visible: root.activeWindAlert() !== null

                        Text {
                            id: alertText
                            anchors.centerIn: parent
                            text: {
                                const alert = root.activeWindAlert()
                                return alert ? (alert.label || alert.message || "WIND ALERT - MONITOR") : ""
                            }
                            color: root.warn
                            font.pixelSize: 10
                            font.family: ScreenTools.normalFontFamily
                            font.letterSpacing: 1
                        }
                    }

                    Rectangle {
                        id: modernSettingsPanel
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 164
                        anchors.rightMargin: 12
                        width: 318
                        height: 440
                        visible: root.modernSettingsOpen
                        color: "#0a0e14"
                        border.color: root.gold
                        border.width: 1
                        z: QGroundControl.zOrderWidgets

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 3
                            color: root.gold
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 112
                                    Layout.fillHeight: true
                                    color: "transparent"
                                    border.color: "#1e242e"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "< EXIT SETTINGS"
                                        color: root.text
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: "Barlow Condensed"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.modernSettingsOpen = false
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "MODERN SETTINGS"
                                    color: root.text
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.family: "monospace"
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 6
                                columnSpacing: 10

                                Text { text: "GCS LOC"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text { text: root.gcsLocationText(); color: root.liveGcsLocationReceived ? root.ok : root.warn; font.pixelSize: 10; font.bold: true; font.family: "monospace"; elide: Text.ElideRight; Layout.fillWidth: true }

                                Text { text: "MAP"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text { text: root.selectedMapKind.toUpperCase(); color: root.gold; font.pixelSize: 10; font.bold: true; font.family: "monospace" }

                                Text { text: "CENTER"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text { text: root.mapCenterText(); color: root.text; font.pixelSize: 10; font.bold: true; font.family: "monospace"; elide: Text.ElideRight; Layout.fillWidth: true }

                                Text { text: "SOURCE"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text {
                                    text: root.loadCountryAirspace ? ("OPENAIP " + root.airspaceCountryCode) : "OPENAIP VIEW"
                                    color: root.gold
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Text { text: "AIRSPACE"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text {
                                    text: root.airspaceStatusText()
                                    color: root.airspaceStateColor()
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Text { text: "AIR POLY"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text {
                                    text: root.activeAirspaceZones().length + " / " + riskDataManager.status.toUpperCase()
                                    color: riskDataManager.status === "ready" ? root.ok : (riskDataManager.status === "error" ? root.err : root.warn)
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Text { text: "AIRPORTS"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text {
                                    text: root.activeAirportRiskZones().length + " / " + airportDataManager.status.toUpperCase()
                                    color: airportDataManager.status === "ready" ? root.ok : (airportDataManager.status === "error" ? root.err : root.warn)
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Text { text: "AIR TILES"; color: root.dim; font.pixelSize: 10; font.bold: true; font.family: "monospace" }
                                Text {
                                    text: root.airspaceTileOverlayActive() ? "OPENAIP ON" : "OFF"
                                    color: root.airspaceTileOverlayActive() ? root.gold : root.dim
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.airspaceErrorText() !== ""
                                text: root.airspaceErrorText()
                                color: root.err
                                font.pixelSize: 9
                                font.family: "monospace"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: root.border
                            }

                            Text {
                                text: "OPENAIP API KEY"
                                color: root.dim
                                font.pixelSize: 9
                                font.bold: true
                                font.letterSpacing: 1
                                font.family: "monospace"
                            }

                            TextField {
                                id: openAipTokenField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                text: root.openAipToken
                                echoMode: TextInput.Password
                                selectByMouse: true
                                color: root.text
                                placeholderText: "Paste OpenAIP key"
                                placeholderTextColor: "#5d6675"
                                font.pixelSize: 11
                                font.family: "monospace"
                                background: Rectangle {
                                    color: "#06090e"
                                    border.color: openAipTokenField.activeFocus ? root.gold : root.border
                                    border.width: 1
                                    radius: 2
                                }
                                onEditingFinished: root.saveOpenAipToken(text)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                spacing: 6

                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: "SAVE KEY"
                                    tone: root.gold
                                    onClicked: root.saveOpenAipToken(openAipTokenField.text)
                                }

                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: "REFRESH AIR"
                                    tone: root.warn
                                    enabled: root.riskDataSourceTemplate !== "" || root.airportRiskDataSourceTemplate !== ""
                                    onClicked: {
                                        root.refreshRiskDataForMap(true)
                                        root.refreshAirportRiskDataForMap(true)
                                    }
                                }
                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: root.openAipTileOverlayEnabled ? "TILES ON" : "TILES OFF"
                                    tone: root.gold
                                    enabled: root.openAipToken.length > 0
                                    onClicked: {
                                        root.openAipTileOverlayEnabled = !root.openAipTileOverlayEnabled
                                        root.airspaceTileRevision++
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                spacing: 6

                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: "MY LOCATION"
                                    tone: root.ok
                                    enabled: QGroundControl.qgcPositionManger.gcsPosition.isValid
                                    onClicked: root.applyLiveGcsLocation(QGroundControl.qgcPositionManger.gcsPosition)
                                }

                                ModernSettingsAction {
                                    Layout.fillWidth: true
                                    label: "APP SETTINGS"
                                    tone: root.blue
                                    onClicked: root.openFullSettings()
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: "transparent"
                                border.color: root.border
                                opacity: 0.92

                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    text: root.liveGcsLocationReceived ? "Windows location is active for map and airspace requests." : "Enable Windows Location Services, then restart if no location fix appears."
                                    color: root.dim
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 64
                        anchors.topMargin: 84
                        spacing: 4
                        visible: root.riskZoneControls().length > 0 || riskDataManager.status !== "idle" || root.airspaceTileOverlayActive()

                        Rectangle {
                            width: 112
                            height: 24
                            visible: riskDataManager.status !== "idle" || airportDataManager.status !== "idle" || root.airspaceTileOverlayActive()
                            color: "#0c1017"
                            border.color: root.airspaceStateColor()
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.airspaceBadgeText()
                                color: parent.border.color
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                                font.letterSpacing: 1
                            }
                        }

                        Repeater {
                            model: root.riskZoneControls().length

                            delegate: Rectangle {
                                required property int index
                                property var zoneItem: root.riskZoneControls()[index] || ({})
                                property string zoneKey: zoneItem.key || ""
                                property string zoneLabel: zoneItem.label || ""
                                property color zoneTone: zoneItem.tone || root.gold
                                property int zoneCount: Number(zoneItem.count || 0)
                                width: 112
                                height: 28
                                property bool active: root.selectedRiskZone === zoneKey
                                color: active ? "#211606" : "#0c1017"
                                border.color: zoneTone
                                border.width: active ? 2 : 1

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 4
                                    color: parent.zoneTone
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.zoneCount > 1 ? (parent.zoneLabel + " " + parent.zoneCount) : parent.zoneLabel
                                    color: parent.zoneTone
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                    font.letterSpacing: 1
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.selectRiskZone(parent.zoneKey)
                                }
                            }
                        }

                        Rectangle {
                            width: 112
                            height: 28
                            visible: QGroundControl.multiVehicleManager.vehicles.count > 0
                            color: root.selectedRiskZone === "fleet" ? "#1a1609" : "#0c1017"
                            border.color: root.gold
                            border.width: root.selectedRiskZone === "fleet" ? 2 : 1

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 4
                                color: root.gold
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "FLEET"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "monospace"
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.selectRiskZone("fleet")
                            }
                        }
                    }

                    Column {
                        id: mapZoomControls

                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 8
                        anchors.bottomMargin: 42
                        spacing: 2

                        Rectangle {
                            width: 32
                            height: 32
                            color: "#0b0e14"
                            border.color: root.border
                            Text { anchors.centerIn: parent; text: "+"; color: root.text; font.pixelSize: 18 }
                            MouseArea { anchors.fill: parent; onClicked: modernMap.zoomLevel += 1 }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            color: "#0b0e14"
                            border.color: root.border
                            Text { anchors.centerIn: parent; text: "-"; color: root.text; font.pixelSize: 18 }
                            MouseArea { anchors.fill: parent; onClicked: modernMap.zoomLevel -= 1 }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            color: root.modernMapToolsOpen ? "#1a1609" : "#0b0e14"
                            border.color: root.modernMapToolsOpen ? root.gold : root.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "L"; color: root.modernMapToolsOpen ? root.gold : root.text; font.pixelSize: 13; font.bold: true; font.family: "monospace" }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.modernMapToolsOpen = !root.modernMapToolsOpen
                            }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            color: root.modernDiagnosticsOpen ? "#111827" : "#0b0e14"
                            border.color: root.modernDiagnosticsOpen ? root.blue : root.border
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "D"; color: root.modernDiagnosticsOpen ? root.blue : root.text; font.pixelSize: 13; font.bold: true; font.family: "monospace" }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.modernDiagnosticsOpen = !root.modernDiagnosticsOpen
                            }
                        }
                    }

                    ModernMapToolsPanel {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 46
                        anchors.bottomMargin: 42
                        width: 184
                        visible: root.modernMapToolsOpen
                    }

                    ModernDiagnosticsPanel {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 238
                        anchors.bottomMargin: 42
                        width: 236
                        visible: root.modernDiagnosticsOpen
                    }

                    Rectangle {
                        id: mapScaleFrame
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 64
                        anchors.topMargin: 44
                        width: 112
                        height: 34
                        color: "#0b0e14"
                        border.color: root.border

                        MapScale {
                            anchors.centerIn: mapScaleFrame
                            mapControl: modernMap
                        }
                    }

                    Item {
                        id: modernHudCluster
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 18
                        anchors.bottomMargin: 42
                        width: 330
                        height: 304
                        visible: root.activeModernSection === "fly"

                        Timer {
                            interval: 180
                            repeat: true
                            running: modernHudCluster.visible
                            onTriggered: {
                                headingTapeCanvas.requestPaint()
                                hudAttitudeCanvas.requestPaint()
                                hudCompassCanvas.requestPaint()
                            }
                        }

                        Rectangle {
                            id: hudHeadingTape
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 220
                            height: 42
                            color: "#0b0f15"
                            border.color: "#334155"
                            border.width: 1

                            Canvas {
                                id: headingTapeCanvas
                                anchors.fill: parent
                                anchors.margins: 4

                                onPaint: {
                                    const c = getContext("2d")
                                    c.reset()
                                    c.clearRect(0, 0, width, height)
                                    const centerX = width / 2
                                    const heading = root.headingDegreesValue()
                                    const pixelsPerDegree = width / 50
                                    const bottomY = height - 4

                                    c.strokeStyle = "rgba(129,148,179,0.75)"
                                    c.lineWidth = 1

                                    for (let deg = -20; deg <= 20; deg += 5) {
                                        const x = centerX + deg * pixelsPerDegree
                                        const absolute = ((Math.round(heading + deg) % 360) + 360) % 360
                                        const major = deg % 10 === 0
                                        const tickTop = major ? 16 : 22
                                        c.beginPath()
                                        c.moveTo(x, tickTop)
                                        c.lineTo(x, bottomY)
                                        c.stroke()

                                        if (major) {
                                            c.fillStyle = "#dbe6f3"
                                            c.font = "bold 10px monospace"
                                            c.textAlign = "center"
                                            c.fillText(("000" + absolute).slice(-3), x, 11)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                width: 44
                                height: parent.height
                                color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.14)
                                border.color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.78)
                                border.width: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: 5
                                    text: root.normalizedHeadingText()
                                    color: root.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Canvas {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 4
                                    width: 12
                                    height: 8

                                    onPaint: {
                                        const c = getContext("2d")
                                        c.reset()
                                        c.clearRect(0, 0, width, height)
                                        c.fillStyle = root.gold
                                        c.beginPath()
                                        c.moveTo(width / 2, height)
                                        c.lineTo(0, 0)
                                        c.lineTo(width, 0)
                                        c.closePath()
                                        c.fill()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: speedBox
                            anchors.left: parent.left
                            anchors.bottom: hudCircle.bottom
                            anchors.bottomMargin: 74
                            width: 46
                            height: 70
                            color: "#0b0f15"
                            border.color: "#2a3342"
                            border.width: 1

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    text: root.hudSpeedLabel()
                                    color: root.dim
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Text {
                                    text: root.hudSpeedText()
                                    color: root.text
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Text {
                                    text: "m/s"
                                    color: root.dim
                                    font.pixelSize: 8
                                    font.family: "monospace"
                                }
                            }
                        }

                        Item {
                            id: hudCircle
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: 220
                            height: 220
                            Rectangle {
                                id: hudCircleFrame
                                anchors.fill: parent
                                radius: width / 2
                                color: "#0c1118"
                                border.color: "#516377"
                                border.width: 2
                            }

                            Item {
                                id: hudCircleSource
                                anchors.fill: parent
                                visible: false

                                CustomArtificialHorizon {
                                    id: modernHudHorizon
                                    x: -(hudCircle.width * 0.3)
                                    y: -(hudCircle.height * 0.3)
                                    width: hudCircle.width * 1.6
                                    height: hudCircle.height * 1.6
                                    rollAngle: root.hudRollAngle()
                                    pitchAngle: root.hudPitchAngle()
                                    skyColor1: "#1f4d82"
                                    skyColor2: "#3d77b8"
                                    groundColor1: "#82552a"
                                    groundColor2: "#70451d"
                                }

                                Canvas {
                                    id: hudAttitudeCanvas
                                    anchors.fill: parent

                                    onPaint: {
                                        const c = getContext("2d")
                                        c.reset()
                                        c.clearRect(0, 0, width, height)

                                        const cx = width / 2
                                        const cy = height / 2
                                        const roll = -root.hudRollAngle() * Math.PI / 180
                                        const pitchClamp = 35
                                        const pitch = Math.max(-pitchClamp, Math.min(pitchClamp, root.hudPitchAngle()))
                                        const pitchOffset = (pitch / pitchClamp) * (height * 0.18)
                                        const marks = [30, 20, 10, -10, -20, -30]

                                        c.save()
                                        c.translate(cx, cy)
                                        c.rotate(roll)
                                        c.translate(0, pitchOffset)

                                        c.strokeStyle = "#dbe7f5"
                                        c.fillStyle = "#dbe7f5"
                                        c.lineWidth = 2
                                        c.font = "bold 11px monospace"
                                        c.textAlign = "center"

                                        for (let i = 0; i < marks.length; i++) {
                                            const mark = marks[i]
                                            const y = (-mark / pitchClamp) * (height * 0.18)
                                            const lineWidth = Math.abs(mark) === 10 ? width * 0.22 : width * 0.17
                                            c.beginPath()
                                            c.moveTo(-lineWidth / 2, y)
                                            c.lineTo(lineWidth / 2, y)
                                            c.stroke()
                                            c.fillText(String(Math.abs(mark)), -lineWidth / 2 - 18, y + 4)
                                            c.fillText(String(Math.abs(mark)), lineWidth / 2 + 18, y + 4)
                                        }

                                        c.beginPath()
                                        c.moveTo(-width * 0.39, 0)
                                        c.lineTo(width * 0.39, 0)
                                        c.strokeStyle = "#f2f7ff"
                                        c.stroke()
                                        c.restore()

                                        c.strokeStyle = "#f2f7ff"
                                        c.lineWidth = 3
                                        c.beginPath()
                                        c.moveTo(cx - 54, cy)
                                        c.lineTo(cx - 18, cy)
                                        c.moveTo(cx + 18, cy)
                                        c.lineTo(cx + 54, cy)
                                        c.moveTo(cx - 18, cy)
                                        c.lineTo(cx, cy + 12)
                                        c.lineTo(cx + 18, cy)
                                        c.stroke()

                                        c.strokeStyle = root.gold
                                        c.lineWidth = 3
                                        c.beginPath()
                                        c.moveTo(cx, cy - 2)
                                        c.lineTo(cx, cy + 8)
                                        c.stroke()
                                    }
                                }
                            }

                            Rectangle {
                                id: hudCircleMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                                color: "white"
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: hudCircleSource
                                maskSource: hudCircleMask
                            }
                        }

                        Rectangle {
                            id: hudCompass
                            anchors.right: hudCircle.right
                            anchors.bottom: hudCircle.bottom
                            width: 58
                            height: 58
                            radius: width / 2
                            color: "#0b0f15"
                            border.color: "#2a3342"
                            border.width: 1

                            Canvas {
                                id: hudCompassCanvas
                                anchors.fill: parent
                                anchors.margins: 4

                                onPaint: {
                                    const c = getContext("2d")
                                    c.reset()
                                    c.clearRect(0, 0, width, height)
                                    const cx = width / 2
                                    const cy = height / 2
                                    const r = Math.min(width, height) * 0.46
                                    const heading = root.headingDegreesValue()

                                    c.strokeStyle = "rgba(255,255,255,0.24)"
                                    c.lineWidth = 1
                                    c.beginPath()
                                    c.arc(cx, cy, r, 0, Math.PI * 2)
                                    c.stroke()

                                    for (let deg = 0; deg < 360; deg += 30) {
                                        const rel = (deg - heading) * Math.PI / 180
                                        const inner = r * (deg % 90 === 0 ? 0.58 : 0.72)
                                        const outer = r * 0.94
                                        c.beginPath()
                                        c.moveTo(cx + Math.sin(rel) * inner, cy - Math.cos(rel) * inner)
                                        c.lineTo(cx + Math.sin(rel) * outer, cy - Math.cos(rel) * outer)
                                        c.stroke()
                                    }

                                    c.fillStyle = root.gold
                                    c.beginPath()
                                    c.moveTo(cx, cy - r * 0.96)
                                    c.lineTo(cx - 4, cy - r * 0.78)
                                    c.lineTo(cx + 4, cy - r * 0.78)
                                    c.closePath()
                                    c.fill()
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 0

                                Text {
                                    text: root.normalizedHeadingText()
                                    color: root.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                }

                                Text {
                                    text: "HDG"
                                    color: root.gold
                                    font.pixelSize: 7
                                    font.bold: true
                                    font.family: "monospace"
                                }
                            }
                        }
                    }
                }
            }

            ModernWorkspacePage {
                anchors.fill: parent
                visible: root.activeModernSection === "plan"
                contentComponent: planViewComponent
                sectionLabel: "PLAN"
                title: "Mission Planning"
                subtitle: "Modern Briech mission design workspace"
                accentColor: root.gold
                metrics: [
                    { label: "MISSION", value: root.missionTimelineStatusText() },
                    { label: "WAYPOINTS", value: root.missionCoordinates.length },
                    { label: "AIRSPACE", value: root.visibleRiskZones().length + " ZONES" },
                    { label: "UPLOAD", value: root.activeVehicle ? "VEHICLE" : "NO LINK" }
                ]
            }

            ModernWorkspacePage {
                anchors.fill: parent
                visible: root.activeModernSection === "analyze"
                contentComponent: analyzeViewComponent
                sectionLabel: "ANALYZE"
                title: "Flight Intelligence"
                subtitle: "Logs, trends, telemetry review, and post-flight insight"
                accentColor: root.blue
                metrics: [
                    { label: "LOGS", value: "LOCAL" },
                    { label: "TREND", value: root.speedHistory.length > 1 ? "LIVE" : "IDLE" },
                    { label: "EVENTS", value: "0" },
                    { label: "EXPORT", value: "IDLE" }
                ]
            }

            ModernWorkspacePage {
                anchors.fill: parent
                visible: root.activeModernSection === "vehicle"
                contentComponent: vehicleViewComponent
                sectionLabel: "VEHICLE"
                title: "Vehicle Configuration"
                subtitle: "Airframe, sensors, safety, radio, and parameter setup"
                accentColor: root.ok
                metrics: [
                    { label: "LINK", value: root.activeVehicle ? "ONLINE" : "OFFLINE" },
                    { label: "FRAME", value: root.activeVehicle ? "UAS" : "--" },
                    { label: "PARAMS", value: root.activeVehicle ? "READY" : "WAIT" },
                    { label: "SAFETY", value: "CHECK" }
                ]
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: "#05070a"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: root.gold
                opacity: 0.85
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 18

                Text {
                    text: root.activeVehicle ? "ARMED" : "DISARMED"
                    color: root.activeVehicle ? root.gold : root.dim
                    font.bold: true
                    font.pixelSize: 11
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "ALT " + (root.activeVehicle ? root.activeVehicle.altitudeRelative.valueString : "--") + " m"
                    color: root.text
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "GS " + (root.activeVehicle ? root.activeVehicle.groundSpeed.valueString : "--") + " m/s"
                    color: root.text
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "HDG " + root.headingText()
                    color: root.text
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "GPS " + root.gpsStatusText()
                    color: root.text
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "BATT " + root.batteryPercentText()
                    color: root.telemetrySlotValueColor(4)
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "MODE " + root.flightModeText()
                    color: root.ok
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "BRIECH UAS GCS"
                    color: root.gold
                    font.bold: true
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    font.family: ScreenTools.normalFontFamily
                }
            }
        }
    }

    component ModernWaypointMarker: Rectangle {
        id: waypointMarker
        property int number: 1
        property bool highlight: false
        property bool secondaryHighlight: false

        width: waypointMarker.highlight ? 24 : 20
        height: width
        radius: width / 2
        color: waypointMarker.highlight ? root.warn : (waypointMarker.secondaryHighlight ? root.gold : root.blue)
        border.color: "white"
        border.width: waypointMarker.highlight || waypointMarker.secondaryHighlight ? 2 : 1

        Text {
            anchors.centerIn: parent
            text: waypointMarker.number
            color: "white"
            font.pixelSize: waypointMarker.highlight ? 11 : 10
            font.bold: true
            font.family: ScreenTools.normalFontFamily
        }
    }

    component ModernToastStack: Item {
        id: toastStackRoot
        property var model

        implicitHeight: stackColumn.implicitHeight

        Column {
            id: stackColumn
            anchors.fill: parent
            spacing: 8

            Repeater {
                model: toastStackRoot.model
                delegate: Rectangle {
                    id: toastCard
                    required property var modelData
                    width: parent.width
                    height: 58
                    radius: 2
                    color: root.modernGlassStrong
                    border.color: toastCard.modelData.tone === "ok" ? "#22c55e" : toastCard.modelData.tone === "warn" ? "#f59e0b" : root.modernHairline
                    border.width: 1

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        color: toastCard.modelData.tone === "ok" ? "#22c55e" : toastCard.modelData.tone === "warn" ? "#f59e0b" : "#3b82f6"
                    }

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 36
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 2

                        Text {
                            text: toastCard.modelData.title
                            color: "#f8fafc"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }

                        Text {
                            text: toastCard.modelData.message
                            color: "#aab3c1"
                            wrapMode: Text.WordWrap
                            font.pixelSize: 9
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        text: "x"
                        color: "#6a7585"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }
    }

    component ModernFlightAlertStack: Item {
        id: flightAlertStack

        signal dismissRequested(string key, string kind)

        property var model: []

        visible: model && model.length > 0
        implicitHeight: alertColumn.implicitHeight
        z: QGroundControl.zOrderWidgets + 6

        Column {
            id: alertColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            Repeater {
                model: flightAlertStack.model || []

                delegate: Rectangle {
                    id: alertCard

                    required property var modelData

                    width: parent.width
                    height: 64
                    color: Qt.rgba(0.035, 0.045, 0.065, 0.88)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    radius: 2
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: alertCard.modelData.tone || root.warn
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 28
                        anchors.topMargin: 9
                        anchors.bottomMargin: 8
                        spacing: 8

                        Item {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            Layout.alignment: Qt.AlignTop

                            Text {
                                anchors.centerIn: parent
                                text: "!"
                                color: alertCard.modelData.kind === "battery" ? "#9ca3af" : "#ffffff"
                                font.pixelSize: 14
                                font.bold: true
                                font.family: "monospace"
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 13
                                height: 13
                                rotation: 45
                                color: "transparent"
                                border.color: alertCard.modelData.kind === "battery" ? "#9ca3af" : "#ffffff"
                                border.width: 1
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: alertCard.modelData.title || ""
                                color: "#f8fafc"
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "Barlow Condensed"
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: alertCard.modelData.detail || ""
                                color: "#9aa3b2"
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: alertCard.modelData.time || ""
                                color: "#667085"
                                font.pixelSize: 9
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 11
                        anchors.topMargin: 10
                        text: "x"
                        color: closeMouse.containsMouse ? root.text : "#475569"
                        font.pixelSize: 16
                        font.family: "monospace"
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: 32
                        height: 32
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: flightAlertStack.dismissRequested(alertCard.modelData.key || "", alertCard.modelData.kind || "")
                    }
                }
            }
        }
    }

    component ModernMapToolsPanel: Rectangle {
        id: mapToolsPanel

        color: root.modernGlassStrong
        border.color: root.modernGoldHairline
        border.width: 1
        radius: 2
        implicitHeight: mapToolsColumn.implicitHeight + 22
        z: QGroundControl.zOrderWidgets + 5

        ColumnLayout {
            id: mapToolsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "MAP / LAYERS"
                color: root.gold
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1
                font.family: "monospace"
            }

            Repeater {
                model: root.modernMapLayerModel()

                delegate: Rectangle {
                    id: layerRow
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: layerRow.modelData.active ? root.modernGoldFill : root.modernGlassSoft
                    border.color: layerRow.modelData.active ? root.gold : root.modernHairline
                    border.width: 1
                    opacity: layerRow.modelData.available ? 1.0 : 0.38

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        text: layerRow.modelData.active ? "[x]" : "[ ]"
                        color: layerRow.modelData.active ? root.gold : root.dim
                        font.pixelSize: 10
                        font.family: "monospace"
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 30
                        text: layerRow.modelData.label
                        color: layerRow.modelData.active ? root.gold : root.text
                        font.pixelSize: 10
                        font.bold: true
                        font.family: "monospace"
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: layerRow.modelData.available
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.setModernMapKind(layerRow.modelData.key)
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.modernHairline }

            ModernToggleRow {
                Layout.fillWidth: true
                label: "WATERMARK"
                checked: root.modernWatermarkEnabled
                tone: root.gold
                onToggled: function(newChecked) {
                    root.modernWatermarkEnabled = newChecked
                }
            }

            ModernToggleRow {
                Layout.fillWidth: true
                label: "AIR TILES"
                checked: root.openAipTileOverlayEnabled
                enabled: root.openAipToken.length > 0
                tone: root.blue
                onToggled: function(newChecked) {
                    root.openAipTileOverlayEnabled = newChecked
                    root.airspaceTileRevision++
                }
            }

            ModernSettingsAction {
                Layout.fillWidth: true
                label: "MAP SETTINGS"
                tone: root.text
                onClicked: root.openFullSettings()
            }
        }
    }

    component ModernDiagnosticsPanel: Rectangle {
        color: root.modernGlassStrong
        border.color: Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.55)
        border.width: 1
        radius: 2
        implicitHeight: diagnosticsColumn.implicitHeight + 22
        z: QGroundControl.zOrderWidgets + 5

        ColumnLayout {
            id: diagnosticsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "MODERN DIAGNOSTICS"
                color: root.blue
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1
                font.family: "monospace"
            }

            Repeater {
                model: root.modernDiagnosticsModel()

                delegate: RowLayout {
                    id: diagnosticRow
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.preferredWidth: 78
                        text: diagnosticRow.modelData.label
                        color: root.dim
                        font.pixelSize: 9
                        font.bold: true
                        font.family: "monospace"
                    }

                    Text {
                        Layout.fillWidth: true
                        text: diagnosticRow.modelData.value
                        color: diagnosticRow.modelData.tone
                        font.pixelSize: 9
                        font.bold: true
                        font.family: "monospace"
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    component ModernToggleRow: Rectangle {
        id: toggleRow

        signal toggled(bool checked)

        property string label: ""
        property bool checked: false
        property color tone: root.gold

        Layout.preferredHeight: 28
        color: "#080c12"
        border.color: checked ? tone : "#1f2631"
        border.width: 1
        opacity: enabled ? 1.0 : 0.38

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            text: toggleRow.checked ? "■" : "□"
            color: toggleRow.checked ? toggleRow.tone : root.dim
            font.pixelSize: 10
            font.family: "monospace"
        }

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 30
            text: toggleRow.label
            color: toggleRow.checked ? toggleRow.tone : root.text
            font.pixelSize: 10
            font.bold: true
            font.family: "monospace"
        }

        MouseArea {
            anchors.fill: parent
            enabled: toggleRow.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: toggleRow.toggled(!toggleRow.checked)
        }
    }

    component ModernWatermarkLayer: Item {
        id: watermarkLayer

        property url logoSource: "qrc:/Briech/res/logoWatermark.png"
        property var marks: [
            { x: 0.06, y: 0.05, w: 410, rot: 7,  dur: 28000, delay: 0,    drift: 22, opacity: 0.28 },
            { x: 0.64, y: 0.07, w: 370, rot: 8,  dur: 26000, delay: 3000, drift: 20, opacity: 0.24 },
            { x: 0.15, y: 0.25, w: 430, rot: 6,  dur: 31000, delay: 1200, drift: 24, opacity: 0.25 },
            { x: 0.42, y: 0.34, w: 390, rot: 8,  dur: 29000, delay: 4600, drift: 20, opacity: 0.23 },
            { x: 0.72, y: 0.36, w: 400, rot: -6, dur: 27000, delay: 2200, drift: 22, opacity: 0.24 },
            { x: 0.10, y: 0.62, w: 430, rot: 7,  dur: 30000, delay: 5200, drift: 26, opacity: 0.24 },
            { x: 0.52, y: 0.67, w: 450, rot: 8,  dur: 32000, delay: 1600, drift: 24, opacity: 0.23 },
            { x: 0.76, y: 0.76, w: 390, rot: 4,  dur: 25000, delay: 6400, drift: 18, opacity: 0.21 }
        ]

        clip: true

        Repeater {
            model: watermarkLayer.marks

            Item {
                id: watermarkMark

                readonly property var markData: modelData
                property real driftOffset: -markData.drift

                width: Math.min(markData.w, watermarkLayer.width * 0.34)
                height: width * 0.30
                x: watermarkLayer.width * markData.x + driftOffset
                y: watermarkLayer.height * markData.y + (driftOffset * 0.22)
                opacity: markData.opacity
                rotation: markData.rot

                Rectangle {
                    anchors.fill: parent
                    color: "#f5f7fb"
                    opacity: 0.24
                    radius: 2
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                    border.width: 1
                }

                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.76
                    height: parent.height * 0.58
                    source: watermarkLayer.logoSource
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    opacity: 0.78
                }

                SequentialAnimation on driftOffset {
                    running: watermarkLayer.visible
                    loops: Animation.Infinite

                    PauseAnimation { duration: watermarkMark.markData.delay }
                    NumberAnimation {
                        from: -watermarkMark.markData.drift
                        to: watermarkMark.markData.drift
                        duration: watermarkMark.markData.dur
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: watermarkMark.markData.drift
                        to: -watermarkMark.markData.drift
                        duration: watermarkMark.markData.dur
                        easing.type: Easing.InOutSine
                    }
                }

                SequentialAnimation on opacity {
                    running: watermarkLayer.visible
                    loops: Animation.Infinite

                    PauseAnimation { duration: watermarkMark.markData.delay }
                    NumberAnimation {
                        from: watermarkMark.markData.opacity * 0.72
                        to: watermarkMark.markData.opacity
                        duration: Math.max(6000, watermarkMark.markData.dur * 0.35)
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: watermarkMark.markData.opacity
                        to: watermarkMark.markData.opacity * 0.72
                        duration: Math.max(6000, watermarkMark.markData.dur * 0.35)
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    component ModernSparklinePanel: Rectangle {
        property var speedSeries: []
        property var altitudeSeries: []
        property var batterySeries: []

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "LIVE TRENDS"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "SPD / ALT / BATT"
                    color: root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }
            }

            Canvas {
                id: sparkCanvas
                Layout.fillWidth: true
                Layout.fillHeight: true

                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    c.clearRect(0, 0, width, height)

                    function drawSeries(series, color, yMin, yMax, offsetY) {
                        if (!series || series.length < 2) {
                            return
                        }
                        const pad = 6
                        const w = width - pad * 2
                        const h = height - pad * 2
                        c.beginPath()
                        for (let i = 0; i < series.length; i++) {
                            const x = pad + (i / (series.length - 1)) * w
                            const normalized = Math.max(0, Math.min(1, (series[i] - yMin) / (yMax - yMin)))
                            const y = pad + offsetY + h - normalized * (h * 0.32)
                            if (i === 0) c.moveTo(x, y)
                            else c.lineTo(x, y)
                        }
                        c.strokeStyle = color
                        c.lineWidth = 2
                        c.stroke()
                    }

                    c.strokeStyle = "rgba(255,255,255,0.05)"
                    c.lineWidth = 1
                    for (let i = 1; i < 4; i++) {
                        c.beginPath()
                        c.moveTo(0, (height / 4) * i)
                        c.lineTo(width, (height / 4) * i)
                        c.stroke()
                    }

                    drawSeries(speedSeries, "#3b82f6", 0, 30, 2)
                    drawSeries(altitudeSeries, "#22c55e", 0, 200, 14)
                    drawSeries(batterySeries, "#f59e0b", 0, 100, 26)
                }

                Connections {
                    target: root
                    function onSpeedHistoryChanged() { sparkCanvas.requestPaint() }
                    function onAltitudeHistoryChanged() { sparkCanvas.requestPaint() }
                    function onBatteryHistoryChanged() { sparkCanvas.requestPaint() }
                }
            }
        }
    }

    component ModernBatteryArc: Rectangle {
        property real percent: 0
        property real displayPercent: percent

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: width / 2

        Behavior on displayPercent {
            NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
        }

        onPercentChanged: displayPercent = isNaN(percent) ? 0 : Math.max(0, Math.min(100, percent))

        Canvas {
            id: arcCanvas
            anchors.fill: parent

            onPaint: {
                const c = getContext("2d")
                c.reset()
                c.clearRect(0, 0, width, height)
                const cx = width / 2
                const cy = height / 2
                const r = Math.min(width, height) * 0.38
                const start = -Math.PI * 0.75
                const safePercent = isNaN(displayPercent) ? 0 : displayPercent
                const end = start + (Math.PI * 1.5) * (safePercent / 100)

                c.beginPath()
                c.arc(cx, cy, r, start, start + Math.PI * 1.5)
                c.strokeStyle = "rgba(255,255,255,0.06)"
                c.lineWidth = 12
                c.lineCap = "round"
                c.stroke()

                c.beginPath()
                c.arc(cx, cy, r, start, end)
                c.strokeStyle = safePercent > 30 ? (safePercent > 60 ? "#22c55e" : "#f59e0b") : "#ef4444"
                c.lineWidth = 12
                c.lineCap = "round"
                c.stroke()

                c.fillStyle = "#f8fafc"
                c.font = "bold 30px monospace"
                c.textAlign = "center"
                c.fillText(Math.round(safePercent).toString(), cx, cy + 11)
                c.fillStyle = "#6a7585"
                c.font = "10px monospace"
                c.fillText("BATTERY", cx, cy - 24)
            }
        }
    }

    component ModernVideoFeedPanel: Rectangle {
        property bool videoVisible: false
        property string videoMode: "EO"
        property real zoomLevel: 1
        signal modeRequested(string mode)
        signal zoomRequested()

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "LIVE VIDEO FEED"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: videoVisible ? "STREAMING" : "IDLE"
                    color: videoVisible ? "#22c55e" : root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }
            }

            Rectangle {
                id: viewer3DContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#05070a"
                border.color: "#202734"
                border.width: 1
                clip: true

                Loader {
                    anchors.fill: parent
                    active: videoVisible
                    visible: videoVisible
                    source: "qrc:/qml/QGroundControl/FlyView/QGCVideoBackground.qml"
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 8
                    anchors.topMargin: 8
                    width: implicitWidth + 14
                    height: 18
                    color: "#0a0f15"
                    border.color: videoVisible ? "#22c55e" : root.gold
                    border.width: 1
                    radius: 2
                    visible: true

                    property string _statusText: videoVisible ? (videoMode + " | " + zoomLevel + "x") : "NO LINK"
                    implicitWidth: statusLabel.implicitWidth

                    Text {
                        id: statusLabel
                        anchors.centerIn: parent
                        text: parent._statusText
                        color: videoVisible ? "#22c55e" : root.gold
                        font.pixelSize: 8
                        font.bold: true
                        font.family: "monospace"
                        font.letterSpacing: 1
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#05070a"
                    opacity: videoVisible ? 0.08 : 0.82
                    visible: !videoVisible
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: !videoVisible

                    Text {
                        text: "VIDEO FEED"
                        color: root.dim
                        font.pixelSize: 12
                        font.family: "monospace"
                        font.bold: true
                    }

                    Text {
                        text: "No active stream"
                        color: "#8b93a3"
                        font.pixelSize: 10
                    }

                    Row {
                        spacing: 8

                        Rectangle {
                            width: 82
                            height: 24
                            color: "#0b0f15"
                            border.color: root.gold
                            Text {
                                anchors.centerIn: parent
                                text: "START"
                                color: root.gold
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: QGroundControl.videoManager.startVideo()
                            }
                        }

                        Rectangle {
                            width: 82
                            height: 24
                            color: "#0b0f15"
                            border.color: root.border
                            Text {
                                anchors.centerIn: parent
                                text: "STOP"
                                color: root.dim
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: QGroundControl.videoManager.stopVideo()
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: 122
                    height: 20
                    color: "#0a0f15"
                    border.color: "#24303f"
                    border.width: 1
                    radius: 2

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "VIDEO"
                            color: root.dim
                            font.pixelSize: 8
                            font.family: "monospace"
                            font.bold: true
                        }

                        Text {
                            text: videoVisible ? "LIVE" : "STANDBY"
                            color: videoVisible ? "#22c55e" : root.dim
                            font.pixelSize: 8
                            font.family: "monospace"
                            font.bold: true
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: [
                        { label: "EO", key: "EO" },
                        { label: "IR", key: "IR" },
                        { label: "BLEND", key: "BLEND" }
                    ]

                    delegate: Rectangle {
                        Layout.preferredWidth: modelData.key === "BLEND" ? 52 : 30
                        Layout.preferredHeight: 20
                        color: videoMode === modelData.key ? "#1a1407" : "#0b0f15"
                        border.color: videoMode === modelData.key ? root.gold : root.border
                        border.width: 1
                        radius: 2

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: videoMode === modelData.key ? root.gold : root.dim
                            font.pixelSize: 8
                            font.bold: true
                            font.family: "monospace"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: modeRequested(modelData.key)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "ZOOM " + zoomLevel + "x"
                    color: root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    color: "#0b0f15"
                    border.color: root.border
                    border.width: 1
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: "⊕"
                        color: root.gold
                        font.pixelSize: 10
                        font.family: "monospace"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: zoomRequested()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 20
                    color: "#0b0f15"
                    border.color: root.gold
                    border.width: 1
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: "START"
                        color: root.gold
                        font.pixelSize: 8
                        font.family: "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: QGroundControl.videoManager.startVideo()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 20
                    color: "#0b0f15"
                    border.color: root.border
                    border.width: 1
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: "STOP"
                        color: root.dim
                        font.pixelSize: 8
                        font.family: "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: QGroundControl.videoManager.stopVideo()
                    }
                }
            }
        }
    }

    component ModernViewer3DPanel: Rectangle {
        property bool viewer3DEnabled: QGroundControl.settingsManager.viewer3DSettings.enabled.rawValue

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "LIVE 3D VIEW"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: viewer3DEnabled ? "READY" : "DISABLED"
                    color: viewer3DEnabled ? "#22c55e" : root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#05070a"
                border.color: "#202734"
                border.width: 1
                clip: true

                Viewer3D {
                    x: 0
                    y: 0
                    width: viewer3DContainer.width
                    height: viewer3DContainer.height
                    visible: viewer3DEnabled
                    Component.onCompleted: {
                        if (viewer3DEnabled) {
                            open()
                        }
                    }
                    Component.onDestruction: close()
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: !viewer3DEnabled

                    Text {
                        text: "3D VIEW"
                        color: root.dim
                        font.pixelSize: 12
                        font.family: "monospace"
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Viewer3D is disabled in settings"
                        color: "#8b93a3"
                        font.pixelSize: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    component ModernPayloadPanel: Rectangle {
        id: payloadPanel
        property string payloadView: "video"
        property bool videoVisible: false
        property string videoMode: "EO"
        property real zoomLevel: 1
        signal closeRequested()
        signal modeRequested(string mode)
        signal zoomRequested()

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4
        clip: true

        Loader {
            anchors.fill: parent
            active: root.payloadPanelOpen
            sourceComponent: payloadView === "3d" ? modern3DPanelComponent : modernVideoPanelComponent
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.rightMargin: 6
            width: 18
            height: 18
            color: "#0b0f15"
            border.color: root.border
            border.width: 1
            radius: 2
            z: 2

            Text {
                anchors.centerIn: parent
                text: "x"
                color: "#6a7585"
                font.pixelSize: 11
                font.bold: true
                font.family: "monospace"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: closeRequested()
            }
        }

        Component {
            id: modernVideoPanelComponent
            ModernVideoFeedPanel {
                anchors.fill: parent
                videoVisible: payloadPanel.videoVisible
                videoMode: payloadPanel.videoMode
                zoomLevel: payloadPanel.zoomLevel
                onModeRequested: payloadPanel.modeRequested(mode)
                onZoomRequested: payloadPanel.zoomRequested()
            }
        }

        Component {
            id: modern3DPanelComponent
            ModernViewer3DPanel {
                anchors.fill: parent
            }
        }
    }

    component ModernPayloadButton: Rectangle {
        signal clicked()
        property string label: ""
        property string iconKind: "video"
        property bool active: false
        property bool hovered: false

        Layout.preferredHeight: 26
        opacity: enabled ? 1.0 : 0.38
        color: active ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.10) : (hovered ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.06) : Qt.rgba(15 / 255, 18 / 255, 24 / 255, 0.80))
        border.color: active ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.85) : (hovered ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.45) : Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.22))
        border.width: 1
        radius: 2

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5
            spacing: 6

            Item {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                visible: iconKind === "video"

                Rectangle {
                    x: 0
                    y: 2
                    width: 8
                    height: 8
                    color: active ? root.gold : root.dim
                    radius: 1
                }

                Rectangle {
                    x: 8
                    y: 4
                    width: 3
                    height: 4
                    color: active ? root.gold : root.dim
                    radius: 1
                }
            }

            Image {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                visible: iconKind === "3d"
                source: "/qml/QGroundControl/Viewer3D/City3DMapIcon.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: active ? 1.0 : 0.72
            }

                Text {
                    Layout.fillWidth: true
                    text: label
                    color: active ? root.gold : "#c9a84c"
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            hoverEnabled: true
            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: hovered = true
            onExited: hovered = false
            onClicked: clicked()
        }
    }

    component ModernDataPanel: Rectangle {
        id: dataPanel

        property string title: ""
        property var model: []

        Layout.preferredHeight: 104
        color: root.modernGlass
        border.color: root.modernGoldHairline
        border.width: 1
        radius: 2
        layer.enabled: true
        layer.smooth: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: dataPanel.title
                color: root.gold
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1
                font.family: "monospace"
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 8
                rowSpacing: 6

                Repeater {
                    model: dataPanel.model || []

                    delegate: Rectangle {
                        id: dataMetric
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        color: root.modernGlassSoft
                        border.color: root.modernHairline
                        border.width: 1
                        radius: 2

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 3

                            Text {
                                width: parent.width
                                text: dataMetric.modelData.label
                                color: root.dim
                                font.pixelSize: 8
                                font.bold: true
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: dataMetric.modelData.value
                                color: dataMetric.modelData.tone || root.text
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "Barlow Condensed"
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    component ModernSettingsAction: Rectangle {
        id: settingsAction

        signal clicked()
        property string label: ""
        property color tone: root.gold
        property bool hovered: false

        Layout.preferredHeight: 30
        opacity: enabled ? 1.0 : 0.38
        color: hovered && enabled ? Qt.rgba(tone.r, tone.g, tone.b, 0.14) : root.modernGlass
        border.color: hovered && enabled ? tone : Qt.rgba(tone.r, tone.g, tone.b, 0.46)
        border.width: 1
        radius: 2

        Text {
            anchors.centerIn: parent
            text: settingsAction.label
            color: settingsAction.tone
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 1
            font.family: "monospace"
        }

        MouseArea {
            anchors.fill: parent
            enabled: settingsAction.enabled
            hoverEnabled: true
            cursorShape: settingsAction.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: settingsAction.hovered = true
            onExited: settingsAction.hovered = false
            onClicked: settingsAction.clicked()
        }
    }

    component ModernSwarmPanel: Rectangle {
        property var vehicleModel

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "SWARM"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: vehicleModel ? vehicleModel.count : 0
                    color: root.text
                    font.pixelSize: 10
                    font.family: "monospace"
                }
            }

            Repeater {
                model: vehicleModel
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: "#0c1017"
                    border.color: "#1f2631"
                    border.width: 1
                    radius: 3
                    property var vehicleObject: object

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: object === activeVehicle ? "#22c55e" : root.blue
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        text: "BRCH-" + object.id
                        color: root.text
                        font.pixelSize: 9
                        font.family: "monospace"
                        font.bold: true
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 10
                        text: object.flightMode
                        color: root.dim
                        font.pixelSize: 8
                        font.family: "monospace"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 10
                        anchors.bottomMargin: 3
                        text: object.armed ? "ARMED" : "STBY"
                        color: object.armed ? "#22c55e" : root.dim
                        font.pixelSize: 7
                        font.family: "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (vehicleObject && vehicleObject.coordinate && vehicleObject.coordinate.isValid) {
                                modernMap.center = vehicleObject.coordinate
                                modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 16)
                                pushToast(qsTr("Swarm"), qsTr("Focused BRCH-%1 on the map.").arg(vehicleObject.id), "info", 2200)
                            }
                        }
                    }
                }
            }
        }
    }

    component ModernMissionScrubber: Rectangle {
        property int maxIndex: 0
        property int currentIndex: 0
        signal scrubbed(int scrubIndex)
        readonly property int _safeMaxIndex: Math.max(0, maxIndex)
        readonly property int _waypointCount: _safeMaxIndex + 1
        readonly property real _progress: _safeMaxIndex > 0 ? Math.min(currentIndex, _safeMaxIndex) / _safeMaxIndex : 0

        implicitHeight: 74
        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        onCurrentIndexChanged: missionCanvas.requestPaint()
        onMaxIndexChanged: missionCanvas.requestPaint()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "MISSION TIMELINE"
                    color: root.gold
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "monospace"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.missionWaypointProgressText() + " | " + root.missionTimelineSequenceText()
                    color: root.dim
                    font.pixelSize: 9
                    font.family: "monospace"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: root.missionTimelineStatusText()
                    color: root.missionTimelineComplete() ? root.ok : (root.missionTimelineInspectionMode ? root.warn : root.text)
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "monospace"
                }

                Text {
                    text: qsTr("CUR %1").arg(root.missionCurrentWaypointLabel())
                    color: root.text
                    font.pixelSize: 9
                    font.family: "monospace"
                }

                Text {
                    text: qsTr("NEXT %1").arg(root.missionNextWaypointLabel())
                    color: root.gold
                    font.pixelSize: 9
                    font.family: "monospace"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: qsTr("REM %1").arg(root.formatMissionDistance(root.missionRemainingDistanceMeters()))
                    color: root.text
                    font.pixelSize: 9
                    font.family: "monospace"
                }

                Text {
                    text: qsTr("ETA %1").arg(root.formatMissionEta(root.missionEtaSeconds()))
                    color: root.text
                    font.pixelSize: 9
                    font.family: "monospace"
                }

                Text {
                    text: qsTr("HOME %1").arg(root.missionBatteryAtHomeEstimateText())
                    color: root.ok
                    visible: root.missionBatteryAtHomeEstimateText() !== "--"
                    font.pixelSize: 9
                    font.family: "monospace"
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Canvas {
                    id: missionCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const w = width
                        const h = height
                        const pad = 4
                        const railY = h / 2
                        const railLeft = pad
                        const railWidth = w - pad * 2
                        const activeRatio = _safeMaxIndex > 0 ? Math.min(currentIndex, _safeMaxIndex) / _safeMaxIndex : 0
                        const markerX = railLeft + (railWidth * activeRatio)

                        ctx.lineWidth = 1
                        ctx.strokeStyle = "#27303b"
                        ctx.fillStyle = "#0f1319"
                        ctx.fillRect(railLeft, railY - 5, railWidth, 10)
                        ctx.strokeRect(railLeft + 0.5, railY - 4.5, railWidth - 1, 9)

                        ctx.fillStyle = "#151b23"
                        ctx.fillRect(railLeft, railY - 8, railWidth, 16)

                        ctx.fillStyle = "#1a2028"
                        ctx.fillRect(railLeft, railY - 2, railWidth, 4)

                        ctx.fillStyle = root.gold
                        ctx.fillRect(railLeft, railY - 2, railWidth * activeRatio, 4)

                        for (let i = 0; i <= _safeMaxIndex; i++) {
                            const x = railLeft + (railWidth * (_safeMaxIndex === 0 ? 0 : i / _safeMaxIndex))
                            ctx.beginPath()
                            ctx.strokeStyle = i <= currentIndex ? root.gold : "#46505f"
                            ctx.moveTo(x, railY - 7)
                            ctx.lineTo(x, railY + 7)
                            ctx.stroke()

                            ctx.fillStyle = i <= currentIndex ? root.gold : "#54606f"
                            ctx.beginPath()
                            ctx.arc(x, railY, i === currentIndex ? 4 : 2.5, 0, Math.PI * 2)
                            ctx.fill()
                        }

                        ctx.strokeStyle = "rgba(201,168,76,0.88)"
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.moveTo(railLeft, railY)
                        ctx.lineTo(markerX, railY)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.fillStyle = root.gold
                        ctx.moveTo(markerX, railY + 9)
                        ctx.lineTo(markerX - 5, railY + 2)
                        ctx.lineTo(markerX + 5, railY + 2)
                        ctx.closePath()
                        ctx.fill()
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }

                Slider {
                    id: missionSlider
                    anchors.fill: parent
                    from: 0
                    to: Math.max(0, maxIndex)
                    stepSize: 1
                    snapMode: Slider.SnapAlways
                    value: Math.min(currentIndex, Math.max(0, maxIndex))
                    onMoved: scrubbed(Math.round(value))
                    onPressedChanged: if (!pressed) scrubbed(Math.round(value))

                    background: Item { }

                    handle: Rectangle {
                        x: missionSlider.leftPadding + (missionSlider.visualPosition * (missionSlider.availableWidth - width))
                        y: missionSlider.topPadding + (missionSlider.availableHeight - height) / 2
                        width: 18
                        height: 18
                        color: "#151922"
                        border.color: root.gold
                        border.width: 1
                        radius: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            color: root.gold
                            radius: 1
                        }
                    }
                }
            }
        }
    }

    component ModernWorkspacePage: Rectangle {
        property string sectionLabel: ""
        property string title: ""
        property string subtitle: ""
        property color accentColor: root.gold
        property var metrics: []
        property Component contentComponent: null

        color: root.bg

        // If a contentComponent is provided, show it full-bleed and hide the built-in header/metrics.
        Loader {
            id: fullContentLoader
            anchors.fill: parent
            active: parent.visible && contentComponent !== null
            sourceComponent: contentComponent
            visible: contentComponent !== null
            z: 999
        }

        Rectangle {
            anchors.fill: parent
            color: "#05070a"
            visible: contentComponent === null
        }

        Rectangle {
            anchors.fill: parent
            color: accentColor
            opacity: 0.025
            visible: contentComponent === null
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 22
            visible: contentComponent === null

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 4
                    Layout.fillHeight: true
                    color: accentColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: sectionLabel
                        color: accentColor
                        font.pixelSize: 10
                        font.bold: true
                        font.family: ScreenTools.normalFontFamily
                        font.letterSpacing: 2
                    }

                    Text {
                        text: title
                        color: "#f8fafc"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: ScreenTools.normalFontFamily
                    }

                    Text {
                        text: subtitle
                        color: root.dim
                        font.pixelSize: 12
                        font.family: ScreenTools.normalFontFamily
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: metrics

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        color: "#0c1017"
                        border.color: "#222a35"
                        border.width: 1
                        radius: 4

                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            spacing: 7

                            Text {
                                text: modelData.label
                                color: root.dim
                                font.pixelSize: 9
                                font.family: ScreenTools.normalFontFamily
                                font.letterSpacing: 1
                            }

                            Text {
                                text: modelData.value
                                color: accentColor
                                font.pixelSize: 16
                                font.bold: true
                                font.family: ScreenTools.normalFontFamily
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#090d13"
                border.color: "#202734"
                border.width: 1
                radius: 6

                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    sourceComponent: contentComponent
                    visible: contentComponent !== null
                }

                Item {
                    anchors.fill: parent
                    visible: contentComponent === null

                    Column {
                        anchors.centerIn: parent
                        spacing: 12

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 44
                            height: 44
                            radius: 22
                            color: "#101722"
                            border.color: accentColor

                            Text {
                                anchors.centerIn: parent
                                text: sectionLabel.length > 0 ? sectionLabel.charAt(0) : "-"
                                color: accentColor
                                font.pixelSize: 20
                                font.bold: true
                                font.family: ScreenTools.normalFontFamily
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: title + " page slot"
                            color: root.text
                            font.pixelSize: 15
                            font.bold: true
                            font.family: ScreenTools.normalFontFamily
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Ready for the dedicated Modern " + sectionLabel.toLowerCase() + " QML page."
                            color: root.dim
                            font.pixelSize: 11
                            font.family: ScreenTools.normalFontFamily
                        }
                    }
                }
            }
        }
    }

    component ModernNavButton: Rectangle {
        signal clicked()
        property string label: ""
        property string iconSource: ""
        property bool active: false
        property string iconFallback: {
            switch (label) {
            case "FLY": return "F"
            case "PLAN": return "P"
            case "ANALYZE": return "A"
            case "VEHICLE": return "V"
            default: return label.length > 0 ? label.charAt(0) : "?"
            }
        }

        Layout.preferredWidth: 96
        Layout.fillHeight: true
        color: active ? root.modernGoldFill : (mouseArea.containsMouse ? root.modernGlassSoft : root.modernGlassStrong)
        border.color: active ? root.modernGoldHairline : root.modernHairline
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: active ? root.gold : "transparent"
        }

        Row {
            anchors.centerIn: parent
            spacing: 7

            Image {
                id: navIcon
                anchors.verticalCenter: parent.verticalCenter
                width: 13
                height: 13
                source: iconSource
                fillMode: Image.PreserveAspectFit
                opacity: (active || mouseArea.containsMouse) ? 1 : 0.42
                visible: status === Image.Ready
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: iconFallback
                visible: navIcon.status !== Image.Ready
                color: active ? "#ffffff" : (mouseArea.containsMouse ? root.gold : root.dim)
                font.pixelSize: 11
                font.bold: true
                font.family: "Barlow Condensed"
            }

            Text {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: active ? "#ffffff" : (mouseArea.containsMouse ? root.text : root.dim)
                font.pixelSize: 14
                font.family: "Barlow Condensed"
                font.bold: true
                font.letterSpacing: 1
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }   
}
