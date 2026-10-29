pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import QGroundControl
import QGroundControl.FlightMap
import QGroundControl.Controls
import QGroundControl.UTMSP
import Custom.Widgets 1.0



Item {
    id: root
    anchors.fill: parent

    signal exitRequested()
    signal simulationHomeSuggested(string home)

    // Theme defaults (overridden when embedded in BriechModernView)
    property color gold: "#C9A84C"
    property color border: "#252c38"
    property color text: "#d8dde6"
    property color dim: "#6a7585"
    property color ok: "#22c55e"
    property color warn: "#f59e0b"
    property color err: "#ef4444"

    // Controllers
    // The mission controller is owned by BriechModernView. Keeping it there
    // is important: this Plan view is created/destroyed as the user changes
    // sections, but the mission must remain available across that navigation.
    property var planMasterController
    property var _planMasterController: planMasterController
    property var _missionController: planMasterController.missionController
    property var _geoFenceController: planMasterController.geoFenceController
    property var _rallyPointController: planMasterController.rallyPointController

    readonly property int _layerMission: 1
    readonly property int _layerFence: 2
    readonly property int _layerRally: 3
    property int _editingLayer: _layerMission
    property bool simulationPanelOpen: false
    // Create Plan / Storage panel, toggled by the FILE sidebar action.
    property bool filePanelOpen: true
    property string simulationHome: "8.893321,7.264172,400.0,0.0"
    property string simulationSpeedup: "1"
    property bool fitPending: false
    property bool waitingForPX4Upload: false
    property double px4UploadWaitStartedAt: 0
    required property var simulationController

    BriechDialog {
        id: briechDialog
    }

    function showBriechMessage(title, message, tone) {
        briechDialog.showInfo(title, message, tone || root.gold)
    }

    function confirmBriechAction(title, message, action, confirmLabel, tone) {
        briechDialog.showConfirmation(title, message, action,
                                      confirmLabel || qsTr("CONFIRM"), tone || root.gold)
    }

    function hasPX4SITLVehicle() {
        if (!simulationController.running) {
            return false
        }
        const vehicle = QGroundControl.multiVehicleManager.activeVehicle
        return !!vehicle
            && vehicle.px4Firmware
            && Number(vehicle.id) === Number(simulationController.systemId)
            && !!vehicle.vehicleLinkManager
            && !vehicle.vehicleLinkManager.communicationLost
    }

    function px4SimulationModelForPlan() {
        const vehicle = root._planMasterController ? root._planMasterController.controllerVehicle : null
        if (vehicle && vehicle.vtol) {
            return "sihsim_standard_vtol"
        }
        if (vehicle && vehicle.fixedWing) {
            return "sihsim_airplane"
        }
        return "sihsim_quadx"
    }

    function px4SimulationProfileText() {
        const model = px4SimulationModelForPlan()
        if (model === "sihsim_standard_vtol") {
            return qsTr("PX4 SIH · STANDARD VTOL")
        }
        if (model === "sihsim_airplane") {
            return qsTr("PX4 SIH · FIXED WING")
        }
        return qsTr("PX4 SIH · QUADROTOR X")
    }

    function connectSimulationLink() {
        const udpPort = 14550
        const configurations = QGroundControl.linkManager.linkConfigurations
        for (let index = 0; index < configurations.count; index++) {
            const configuration = configurations.get(index)
            if (configuration
                    && configuration.linkType === LinkConfiguration.TypeUdp
                    && Number(configuration.localPort) === udpPort) {
                if (configuration.link) {
                    return
                }
                QGroundControl.linkManager.createConnectedLink(configuration)
                return
            }
        }

        const configuration = QGroundControl.linkManager.createConfiguration(LinkConfiguration.TypeUdp, "Briech PX4 SITL UDP")
        configuration.localPort = udpPort
        configuration.dynamic = true
        QGroundControl.linkManager.endCreateConfiguration(configuration)
        QGroundControl.linkManager.createConnectedLink(configuration)
    }

    MapFitFunctions {
        id: mapFitFunctions
        map: editorMap
        planMasterController: root._planMasterController
        usePlannedHomePosition: true
    }

    function fitPlanToMap() {
        if (!editorMap.mapReady || editorMap.width <= 1 || editorMap.height <= 1) {
            fitPending = true
            return
        }

        fitPending = false
        if (planMasterController.containsItems) {
            mapFitFunctions.fitMapViewportToMissionItems()
        } else if (editorMap.mapReady) {
            editorMap.center = root.sharedMapCenter()
        }
    }

    // Re-entering Plan creates the visual editor again. Fit the restored
    // mission immediately so imported/uploaded waypoints are visible without
    // requiring the operator to press FIT PLAN.
    Component.onCompleted: Qt.callLater(root.fitPlanToMap)

    function sharedMapCenter() {
        return QGroundControl.flightMapPosition.isValid ? QGroundControl.flightMapPosition : QtPositioning.coordinate(8.893321, 7.264172)
    }

    function mapTypeKeywords(kind) {
        switch (String(kind || "").toLowerCase()) {
        case "street":
            return ["street", "map"]
        case "satellite":
            return ["satellite", "sat"]
        case "terrain":
            return ["terrain", "topo", "topographic"]
        case "hybrid":
            return ["hybrid"]
        default:
            return [String(kind || "").toLowerCase()]
        }
    }

    function currentSharedMapKind() {
        const settings = QGroundControl.settingsManager.flightMapSettings
        const mapType = String(settings.mapType.rawValue || settings.mapType.value || "").toLowerCase()
        const kinds = ["hybrid", "satellite", "terrain", "street"]
        for (let i = 0; i < kinds.length; i++) {
            const keywords = mapTypeKeywords(kinds[i])
            for (let keywordIndex = 0; keywordIndex < keywords.length; keywordIndex++) {
                if (mapType.indexOf(keywords[keywordIndex]) !== -1) {
                    return kinds[i]
                }
            }
        }
        return "hybrid"
    }

    function findEditorMapType(kind) {
        if (!editorMap || !editorMap.mapReady) {
            return null
        }
        const keywords = mapTypeKeywords(kind)
        for (let i = 0; i < editorMap.supportedMapTypes.length; i++) {
            const candidate = editorMap.supportedMapTypes[i]
            const candidateName = String(candidate.name || "").toLowerCase()
            for (let keywordIndex = 0; keywordIndex < keywords.length; keywordIndex++) {
                if (candidateName.indexOf(keywords[keywordIndex]) !== -1) {
                    return candidate
                }
            }
        }
        return null
    }

    function syncEditorMapTypeFromSharedState() {
        if (!editorMap || !editorMap.mapReady) {
            return
        }
        const candidate = findEditorMapType(currentSharedMapKind())
        if (candidate && (!editorMap.activeMapType || editorMap.activeMapType.name !== candidate.name)) {
            editorMap.activeMapType = candidate
        }
    }

    function syncEditorMapFromSharedState() {
        if (!editorMap || !editorMap.mapReady) {
            return
        }
        const center = sharedMapCenter()
        if (!coordinatesClose(editorMap.center, center)) {
            editorMap.center = center
        }
        if (Math.abs(editorMap.zoomLevel - QGroundControl.flightMapZoom) > 0.01) {
            editorMap.zoomLevel = QGroundControl.flightMapZoom
        }
        syncEditorMapTypeFromSharedState()
    }

    function coordinatesClose(a, b) {
        return a && b && a.isValid && b.isValid
            && Math.abs(a.latitude - b.latitude) < 0.000001
            && Math.abs(a.longitude - b.longitude) < 0.000001
    }

    function formatMissionTime(seconds) {
        const totalSeconds = Math.max(0, Math.floor(Number(seconds) || 0))
        const hours = Math.floor(totalSeconds / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const remainingSeconds = totalSeconds % 60
        return [hours, minutes, remainingSeconds].map(function(value) {
            return value < 10 ? "0" + value : String(value)
        }).join(":")
    }

    function missionDistanceText() {
        const distance = Number(_missionController.missionPlannedDistance)
        if (isNaN(distance)) {
            return "--"
        }
        return QGroundControl.unitsConversion.metersToAppSettingsHorizontalDistanceUnits(distance).toFixed(0)
            + " " + QGroundControl.unitsConversion.appSettingsHorizontalDistanceUnitsString
    }

    function missionAltitudeDifferenceText() {
        const item = _missionController.currentPlanViewItem
        if (!item || isNaN(Number(item.altDifference))) {
            return "--"
        }
        return QGroundControl.unitsConversion.metersToAppSettingsVerticalDistanceUnits(Number(item.altDifference)).toFixed(1)
            + " " + QGroundControl.unitsConversion.appSettingsVerticalDistanceUnitsString
    }

    function planStatusText() {
        if (planMasterController.syncInProgress) {
            return "SYNCING"
        }
        if (planMasterController.dirty) {
            return "UNSAVED"
        }
        return planMasterController.containsItems ? "READY" : "EMPTY"
    }

    function planStatusColor() {
        if (planMasterController.syncInProgress) {
            return "#60a5fa"
        }
        if (planMasterController.dirty) {
            return root.gold
        }
        return planMasterController.containsItems ? "#4ade80" : root.dim
    }

    function insertSimpleItemAfterCurrent(coordinate) {
        const nextIndex = _missionController.currentPlanViewVIIndex + 1
        _missionController.insertSimpleMissionItem(coordinate, nextIndex, true)
    }

    function editorMapCenter() {
        const coordinate = editorMap.center
        coordinate.latitude = coordinate.latitude.toFixed(7)
        coordinate.longitude = coordinate.longitude.toFixed(7)
        coordinate.altitude = coordinate.altitude.toFixed(2)
        return coordinate
    }

    // Sidebar shortcut, following the stock Plan view tool strip: insert a
    // waypoint after the current item at the map center.
    function insertWaypointAtMapCenter() {
        setEditingLayer(_layerMission)
        insertSimpleItemAfterCurrent(editorMapCenter())
    }

    // Editing layers. The right panel's MISSION / FENCE / RALLY tabs and the
    // sidebar both switch layers, so keep the two in step.
    readonly property bool fenceSupported: _geoFenceController.supported
    readonly property bool rallySupported: _rallyPointController.supported

    function setEditingLayer(layer) {
        _editingLayer = layer
        rightPanel.expanded = true
    }

    function toggleEditingLayer(layer) {
        setEditingLayer(_editingLayer === layer ? _layerMission : layer)
    }

    on_EditingLayerChanged: rightPanel._editingTool = _editingLayer - _layerMission

    function editingLayerHint() {
        if (_editingLayer === _layerFence) {
            return fenceSupported
                ? qsTr("FENCE  ·  Add a polygon or circle fence from the right panel, then drag its vertices on the map.")
                : qsTr("FENCE  ·  This vehicle does not support geofences.")
        }
        if (_editingLayer === _layerRally) {
            return rallySupported
                ? qsTr("RALLY  ·  Click the map to add a rally point. Drag points to move them.")
                : qsTr("RALLY  ·  This vehicle does not support rally points.")
        }
        return ""
    }

    function handleMapClick(mouse) {
        editorMap.focus = true
        if (!mainWindow.allowViewSwitch()) {
            return
        }

        const coordinate = editorMap.toCoordinate(Qt.point(mouse.x, mouse.y), false)
        coordinate.latitude = coordinate.latitude.toFixed(7)
        coordinate.longitude = coordinate.longitude.toFixed(7)
        coordinate.altitude = coordinate.altitude.toFixed(2)

        if (_editingLayer === _layerMission) {
            insertSimpleItemAfterCurrent(coordinate)
        } else if (_editingLayer === _layerRally) {
            if (rallySupported) {
                _rallyPointController.addPoint(coordinate)
            } else {
                showBriechMessage(qsTr("Rally Points"), qsTr("The connected vehicle does not support rally points."), root.warn)
            }
        }
    }

    // Plan templates replace the current plan, as in the stock Plan view.
    function createPlanFromTemplate(planCreator) {
        const create = function() {
            setEditingLayer(_layerMission)
            if (planCreator.blankPlan) {
                planCreator.createPlan(editorMapCenter())
                planMasterController.manualCreation = true
            } else {
                planCreator.createPlan(editorMapCenter())
                Qt.callLater(root.fitPlanToMap)
            }
        }
        if (planMasterController.containsItems) {
            confirmBriechAction(qsTr("Create Plan"),
                qsTr("Replace the current plan with a new %1 plan? Unsaved changes will be lost.").arg(planCreatorLabel(planCreator)),
                create, qsTr("REPLACE PLAN"), root.warn)
        } else {
            create()
        }
    }

    function planCreatorLabel(planCreator) {
        return planCreator.blankPlan ? qsTr("Blank") : planCreator.name
    }

    function importKmlWaypointsFromFile(filename) {
        if (planMasterController.containsItems) {
            confirmBriechAction(qsTr("Import KML Waypoints"),
                qsTr("Replace the current mission with the KML waypoints? Existing mission items will be removed, but vehicle data is not changed until you upload."),
                function() { planMasterController.importKmlWaypoints(filename, false) }, qsTr("REPLACE PLAN"), root.warn)
        } else {
            planMasterController.importKmlWaypoints(filename, false)
        }
    }

    function suggestSimulationHomeFromMission() {
        if (!_missionController.visualItems || _missionController.visualItems.count < 2) {
            return
        }
        let firstMissionItem = null
        for (let index = 0; index < _missionController.visualItems.count; index++) {
            const item = _missionController.visualItems.get(index)
            if (item && item.specifiesCoordinate && !item.homePosition && !item.isStandaloneCoordinate
                    && item.coordinate && item.coordinate.isValid) {
                firstMissionItem = item
                break
            }
        }
        if (!firstMissionItem) {
            return
        }
        const coordinate = firstMissionItem.coordinate
        const home = coordinate.latitude.toFixed(7) + "," + coordinate.longitude.toFixed(7) + "," +
            Math.max(0, Number(coordinate.altitude) || 0).toFixed(2) + ",270.0"
        simulationHome = home
        simulationHomeField.text = home
        simulationHomeSuggested(home)
    }

    function startSimulationAtMissionHome() {
        // Resolve the route origin immediately before launch. An import event
        // can be missed while this view is recreated, but the persistent
        // mission controller remains authoritative.
        suggestSimulationHomeFromMission()
        simulationController.startPX4SITL(simulationHomeField.text, Number(simulationSpeedField.text), px4SimulationModelForPlan())
    }

    function startPX4AndQueueMissionUpload() {
        if (waitingForPX4Upload) {
            return
        }
        waitingForPX4Upload = true
        px4UploadWaitStartedAt = Date.now()
        px4UploadConnectTimer.start()

        if (!simulationController.running && !simulationController.busy) {
            suggestSimulationHomeFromMission()
            simulationController.startPX4SITL(simulationHomeField.text, Number(simulationSpeedField.text), px4SimulationModelForPlan())
        } else if (simulationController.running) {
            connectSimulationLink()
        }
        pushToast(qsTr("PX4 SITL"), qsTr("Starting PX4 and waiting for the vehicle before uploading this plan."), "info", 4000)
    }

    function finishPX4UploadWait(message, tone) {
        px4UploadConnectTimer.stop()
        waitingForPX4Upload = false
        px4UploadWaitStartedAt = 0
        if (message && message.length > 0) {
            showBriechMessage(qsTr("PX4 SITL"), message, tone || root.warn)
        }
    }

    function advancePX4UploadWait() {
        if (!waitingForPX4Upload) {
            px4UploadConnectTimer.stop()
            return
        }
        if (!simulationController.running && !simulationController.busy && simulationController.lastError.length > 0) {
            finishPX4UploadWait(simulationController.lastError, root.err)
            return
        }
        if (Date.now() - px4UploadWaitStartedAt >= 60000) {
            finishPX4UploadWait(qsTr("PX4 did not connect within 60 seconds. Check that the local PX4 SIH image is running and sending MAVLink to UDP port 14550."), root.warn)
            return
        }
        if (!simulationController.running) {
            return
        }

        const vehicle = QGroundControl.multiVehicleManager.getVehicleById(simulationController.systemId)
        if (!vehicle || !vehicle.px4Firmware) {
            connectSimulationLink()
            return
        }
        if (QGroundControl.multiVehicleManager.activeVehicle !== vehicle) {
            QGroundControl.multiVehicleManager.activeVehicle = vehicle
            return
        }
        if (!vehicle.vehicleLinkManager || vehicle.vehicleLinkManager.communicationLost) {
            connectSimulationLink()
            return
        }

        const precheck = _missionController.sendToVehiclePreCheck()
        if (precheck === MissionController.SendToVehiclePreCheckStateOk) {
            px4UploadConnectTimer.stop()
            waitingForPX4Upload = false
            px4UploadWaitStartedAt = 0
            planMasterController.sendToVehicle()
            pushToast(qsTr("PX4 SITL"), qsTr("PX4 connected. Uploading the plan."), "info", 3000)
        } else if (precheck !== MissionController.SendToVehiclePreCheckStateNoActiveVehicle) {
            finishPX4UploadWait(qsTr("PX4 connected, but QGC cannot upload this plan in the current vehicle state."), root.warn)
        }
    }

    Timer {
        id: px4UploadConnectTimer
        interval: 250
        repeat: true
        running: root.waitingForPX4Upload
        onTriggered: root.advancePX4UploadWait()
    }

    function sendMissionToVehicle() {
        switch (_missionController.sendToVehiclePreCheck()) {
        case MissionController.SendToVehiclePreCheckStateOk:
            planMasterController.sendToVehicle()
            break
        case MissionController.SendToVehiclePreCheckStateNoActiveVehicle:
            startPX4AndQueueMissionUpload()
            break
        case MissionController.SendToVehiclePreCheckStateActiveMission:
            showBriechMessage(qsTr("Upload Blocked"), qsTr("Pause the active mission before uploading a new plan."), root.warn)
            break
        case MissionController.SendToVehiclePreCheckStateFirwmareVehicleMismatch:
            confirmBriechAction(qsTr("Vehicle Mismatch"), qsTr("The plan vehicle type differs from the connected vehicle."),
                function() { planMasterController.sendToVehicle() }, qsTr("UPLOAD ANYWAY"), root.warn)
            break
        }
    }

    function uploadMission() {
        if (waitingForPX4Upload) {
            return
        }
        if (planMasterController.readyForSaveState() === VisualMissionItem.NotReadyForSaveData) {
            showBriechMessage(qsTr("Unable to Upload"), qsTr("Complete all mission items before uploading."), root.warn)
            return
        }
        if ((simulationController.running || simulationController.busy)
                && !root.hasPX4SITLVehicle()) {
            startPX4AndQueueMissionUpload()
            return
        }
        sendMissionToVehicle()
    }

    Connections {
        target: QGroundControl
        ignoreUnknownSignals: true
        function onFlightMapPositionChanged() { root.syncEditorMapFromSharedState() }
        function onFlightMapZoomChanged() { root.syncEditorMapFromSharedState() }
    }

    Connections {
        target: QGroundControl.settingsManager.flightMapSettings.mapType
        ignoreUnknownSignals: true
        function onRawValueChanged() { root.syncEditorMapTypeFromSharedState() }
    }

    // Top header (Exit + metrics)
    Rectangle {
        id: topHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: ScreenTools.toolbarHeight
        color: "#0b0d10"
        border.color: Qt.rgba(1,1,1,0.02)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2
            layoutDirection: Qt.LeftToRight

            Rectangle {
                id: exitBtn
                width: 120
                Layout.fillHeight: true
                color: "transparent"
                Text { anchors.centerIn: parent; text: "<  EXIT PLAN"; color: exitHover.containsMouse ? root.gold : root.text; font.pixelSize: 12; font.family: ScreenTools.normalFontFamily; font.bold: true }
                MouseArea { id: exitHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.exitRequested() }
            }

            Item { width: 16 }

            RowLayout {
                spacing: 18
                Repeater {
                    model: [ {label: "ALT DIFF", value: root.missionAltitudeDifferenceText()}, {label: "TOTAL MISSION", value: root.missionDistanceText()}, {label: "TIME", value: root.formatMissionTime(_missionController.missionTime)} ]
                    delegate: Column {
                        spacing: 2
                        Text { text: modelData.label; color: "#9aa3ad"; font.pixelSize: 10; font.family: ScreenTools.normalFontFamily }
                        Text { text: modelData.value; color: root.text; font.pixelSize: 12; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 124
                Layout.preferredHeight: 28
                color: Qt.rgba(1, 1, 1, 0.025)
                border.color: planStatusColor()
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 7

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: planStatusColor()
                    }

                    Text {
                        text: planStatusText()
                        color: planStatusColor()
                        font.pixelSize: 10
                        font.bold: true
                        font.family: "monospace"
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 108
                Layout.preferredHeight: 28
                color: fitPlanMouse.containsMouse ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.14) : Qt.rgba(1, 1, 1, 0.025)
                border.color: fitPlanMouse.containsMouse ? root.gold : root.border
                border.width: 1
                opacity: planMasterController.containsItems ? 1 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "FIT PLAN"
                    color: fitPlanMouse.containsMouse ? root.gold : root.text
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                }

                MouseArea {
                    id: fitPlanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: planMasterController.containsItems
                    onClicked: root.fitPlanToMap()
                }
            }

            Rectangle {
                Layout.preferredWidth: 92
                Layout.preferredHeight: 28
                color: simulationPanelOpen ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.16) : Qt.rgba(1, 1, 1, 0.025)
                border.color: simulationPanelOpen ? root.gold : root.border
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "SIMULATION"
                    color: simulationPanelOpen ? root.gold : root.text
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: simulationPanelOpen = !simulationPanelOpen
                }
            }
        }
    }

    Rectangle {
        id: simulationPanel
        visible: simulationPanelOpen
        z: 50
        anchors.top: topHeader.bottom
        anchors.bottom: bottomBar.top
        anchors.right: parent.right
        width: 390
        color: "#080c12"
        border.color: Qt.rgba(root.gold.r, root.gold.g, root.gold.b, 0.72)
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 3
            color: root.gold
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "DEMO FLIGHT"
                        color: root.gold
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 1
                        font.family: "monospace"
                    }

                    Text {
                        text: "PX4 SIH · real MAVLink"
                        color: root.dim
                        font.pixelSize: 10
                        font.family: "monospace"
                    }
                }

                Text {
                    text: simulationController.status
                    color: simulationController.running ? root.ok : (simulationController.busy ? root.gold : (simulationController.lastError.length > 0 ? root.err : root.dim))
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "monospace"
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: "#111925"
                    border.color: root.border

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: root.text
                        font.pixelSize: 16
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: simulationPanelOpen = false
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.border }

            Text { text: "PX4 VEHICLE · AUTO SELECT"; color: "#91a0b3"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1; font.family: "monospace" }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                color: "#111925"
                border.color: "#344154"
                border.width: 1

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: root.px4SimulationProfileText()
                    color: simulationController.running ? "#8190a2" : root.text
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 11
                    font.family: "monospace"
                    elide: Text.ElideRight
                }
            }

            Text { text: "HOME · LAT,LON,ALT,HEADING"; color: "#91a0b3"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1; font.family: "monospace" }
            TextField {
                id: simulationHomeField
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                text: root.simulationHome
                selectByMouse: true
                color: root.text
                placeholderText: "8.893321,7.264172,400.0,0.0"
                placeholderTextColor: "#66758a"
                font.pixelSize: 11
                font.family: "monospace"
                background: Rectangle {
                    color: "#111925"
                    border.color: simulationHomeField.activeFocus ? root.gold : "#344154"
                    border.width: 1
                    radius: 2
                }
            }

            Text { text: "SIMULATION SPEED"; color: "#91a0b3"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1; font.family: "monospace" }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: simulationSpeedField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    text: root.simulationSpeedup
                    validator: DoubleValidator { bottom: 0.1; top: 20.0 }
                    color: root.text
                    selectByMouse: true
                    font.pixelSize: 11
                    font.family: "monospace"
                    background: Rectangle {
                        color: "#111925"
                        border.color: simulationSpeedField.activeFocus ? root.gold : "#344154"
                        border.width: 1
                        radius: 2
                    }
                }
                Text { text: "×"; color: root.dim; font.pixelSize: 12 }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ModernSettingsAction {
                    Layout.fillWidth: true
                    label: simulationController.running ? "PX4 SITL RUNNING" : (simulationController.busy ? "STARTING PX4..." : "START PX4 SITL")
                    tone: root.ok
                    enabled: !simulationController.running && !simulationController.busy
                    onClicked: root.startSimulationAtMissionHome()
                }

                ModernSettingsAction {
                    Layout.fillWidth: true
                    label: simulationController.running ? "STOP PX4 SITL" : "STOP"
                    tone: root.err
                    enabled: simulationController.running && !simulationController.busy
                    onClicked: simulationController.stopSimulation()
                }
            }

                ModernSettingsAction {
                    Layout.fillWidth: true
                    label: root.hasPX4SITLVehicle() ? "PX4 SITL CONNECTED" : "CONNECT PX4 SITL"
                    tone: root.blue
                    enabled: simulationController.running && !root.hasPX4SITLVehicle()
                    onClicked: root.connectSimulationLink()
                }

            Text {
                Layout.fillWidth: true
                visible: simulationController.lastError.length > 0
                text: simulationController.lastError
                color: root.err
                font.pixelSize: 9
                font.family: "monospace"
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }

    // Left panel
    Rectangle {
        id: leftPanel
        width: root.filePanelOpen ? 300 : 0
        visible: root.filePanelOpen
        anchors.top: topHeader.bottom
        anchors.left: parent.left
            anchors.bottom: bottomBar.top
        color: "#0f1113"
        border.color: "#22252a"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ── CREATE PLAN ──────────────────────────────────────
            Text {
                text: "CREATE PLAN"
                color: root.gold
                font.pixelSize: 14
                font.bold: true
                font.family: "Barlow Condensed"
                font.letterSpacing: 1
            }

            GridLayout {
                columns: 2
                columnSpacing: 6
                rowSpacing: 6
                Layout.fillWidth: true

                // Blank, Survey, Corridor Scan and Structure Scan (not offered
                // for fixed-wing) come from the PlanMasterController.
                Repeater {
                    model: planMasterController.planCreators
                    delegate: Rectangle {
                        id: planCreatorCard
                        required property var object
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        radius: 4
                        color: cardHover.containsMouse ? "#14171c" : "#0b0d10"
                        border.color: cardHover.containsMouse ? root.gold : "#22252a"
                        clip: true

                        Image {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: cardLabel.top
                            anchors.margins: 6
                            fillMode: Image.PreserveAspectFit
                            source: planCreatorCard.object.imageResource
                            sourceSize.width: width
                            mipmap: true
                            opacity: 0.9
                        }

                        Text {
                            id: cardLabel
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 8
                            horizontalAlignment: Text.AlignHCenter
                            text: root.planCreatorLabel(planCreatorCard.object).toUpperCase()
                            color: cardHover.containsMouse ? root.gold : root.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: ScreenTools.normalFontFamily
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: cardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.createPlanFromTemplate(planCreatorCard.object)
                        }
                    }
                }
            }

            // ── STORAGE ──────────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: "#22252a" }

            Text {
                text: "STORAGE"
                color: root.gold
                font.pixelSize: 11
                font.bold: true
                font.family: ScreenTools.normalFontFamily
                font.letterSpacing: 1
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    color: "transparent"
                    border.color: "#3b82f6"
                    radius: 3
                    Text { anchors.centerIn: parent; text: "OPEN..."; color: "#3b82f6"; font.pixelSize: 10; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    MouseArea { anchors.fill: parent; onClicked: {
                        if (planMasterController.dirty) {
                            confirmBriechAction(qsTr("Open Plan"),
                                qsTr("You have unsaved/unsent changes. Loading a new Plan will lose these changes. Are you sure?"),
                                function() {
                                    planMasterController.loadFromSelectedFile()
                                }, qsTr("OPEN PLAN"), root.warn)
                        } else {
                            planMasterController.loadFromSelectedFile()
                        }
                    }}
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    color: "#1a1e26"
                    border.color: "#353c4a"
                    radius: 3
                    Text { anchors.centerIn: parent; text: "SAVE"; color: root.text; font.pixelSize: 10; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    MouseArea { anchors.fill: parent; onClicked: {
                        if (planMasterController.currentPlanFile !== "") {
                            planMasterController.saveToCurrent()
                        } else {
                            planMasterController.saveToSelectedFile()
                        }
                    }}
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    color: "#1a1e26"
                    border.color: "#353c4a"
                    radius: 3
                    Text { anchors.centerIn: parent; text: "SAVE AS..."; color: root.text; font.pixelSize: 10; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    MouseArea { anchors.fill: parent; onClicked: planMasterController.saveToSelectedFile() }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 34
                color: "#1a1e26"
                border.color: "#353c4a"
                radius: 3
                Text {
                    anchors.centerIn: parent
                    text: "SAVE MISSION WAYPOINTS AS KML..."
                    color: root.text
                    font.pixelSize: 10
                    font.bold: true
                    font.family: ScreenTools.normalFontFamily
                }
                MouseArea { anchors.fill: parent; onClicked: {
                    if (_missionController.visualItems.count > 1) {
                        planMasterController.saveKmlToSelectedFile()
                    }
                }}
            }

            // ── VEHICLE ──────────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: "#22252a" }

            Rectangle {
                Layout.fillWidth: true
                height: 36
                color: kmlImportMouse.containsMouse ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.16) : Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.07)
                border.color: kmlImportMouse.containsMouse ? root.gold : Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.45)
                border.width: 1
                radius: 2

                Text {
                    anchors.centerIn: parent
                    text: "IMPORT KML WAYPOINTS..."
                    color: kmlImportMouse.containsMouse ? root.gold : root.text
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                }

                MouseArea {
                    id: kmlImportMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: kmlImportDialog.openForLoad()
                }
            }

            Text {
                text: "VEHICLE"
                color: root.gold
                font.pixelSize: 11
                font.bold: true
                font.family: ScreenTools.normalFontFamily
                font.letterSpacing: 1
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    color: "transparent"
                    border.color: "#3b82f6"
                    radius: 3
                    Text { anchors.centerIn: parent; text: root.waitingForPX4Upload ? "WAITING FOR PX4..." : "UPLOAD"; color: "#3b82f6"; font.pixelSize: 10; font.bold: true; font.family: ScreenTools.normalFontFamily; elide: Text.ElideRight }
                    MouseArea { anchors.fill: parent; enabled: !root.waitingForPX4Upload; onClicked: root.uploadMission() }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    color: "#1a1e26"
                    border.color: "#353c4a"
                    radius: 3
                    Text { anchors.centerIn: parent; text: "DOWNLOAD"; color: root.text; font.pixelSize: 10; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    MouseArea { anchors.fill: parent; onClicked: {
                        if (planMasterController.dirty) {
                            confirmBriechAction(qsTr("Download"),
                                qsTr("You have unsaved/unsent changes. Downloading from the Vehicle will lose these changes. Are you sure?"),
                                function() {
                                    planMasterController.loadFromVehicle()
                                }, qsTr("DOWNLOAD"), root.warn)
                        } else {
                            planMasterController.loadFromVehicle()
                        }
                    }}
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    color: "transparent"
                    border.color: "#ef4444"
                    radius: 3
                    Text { anchors.centerIn: parent; text: "CLEAR"; color: "#ef4444"; font.pixelSize: 10; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    MouseArea { anchors.fill: parent; onClicked: {
                        confirmBriechAction(qsTr("Clear Plan"),
                            qsTr("Are you sure you want to remove all the items from the plan editor?"),
                            function() { planMasterController.removeAll() }, qsTr("CLEAR PLAN"), root.err)
                    }}
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    QGCFileDialog {
        id: kmlImportDialog
        folder: QGroundControl.settingsManager.appSettings.missionSavePath
        title: qsTr("Import KML Waypoints")
        nameFilters: ShapeFileHelper.fileDialogKMLFilters

        onAcceptedForLoad: (file) => {
            root.importKmlWaypointsFromFile(file)
            close()
        }
    }

    Connections {
        target: root._planEditorController
        ignoreUnknownSignals: true

        function onKmlWaypointsImported(count) {
            root.suggestSimulationHomeFromMission()
            Qt.callLater(root.fitPlanToMap)
            showBriechMessage(qsTr("KML Import Complete"),
                qsTr("Imported %1 waypoint(s) into the mission plan.").arg(count), root.ok)
        }

        function onKmlWaypointImportFailed(errorMessage) {
            showBriechMessage(qsTr("KML Import Failed"), errorMessage, root.err)
        }
    }

    // Map area between left and right panels
    FlightMap {
        id: editorMap
        anchors.top: topHeader.bottom
        anchors.left: leftPanel.right
        anchors.right: rightPanel.expanded ? rightPanel.left : parent.right
        anchors.bottom: bottomBar.top
        mapName: "MissionEditor"
        allowGCSLocationCenter: true
        allowVehicleLocationCenter: true
        planView: true

        property real _nonInteractiveOpacity: 0.5
        // Area new fence shapes and complex item polygons are placed in; the
        // stock fence and polygon editors require it on their map.
        property real _viewportMargin: ScreenTools.defaultFontPixelWidth * 4
        property rect centerViewport: Qt.rect(_viewportMargin, _viewportMargin,
                                              Math.max(1, width - _viewportMargin * 2),
                                              Math.max(1, height - _viewportMargin * 2))

        zoomLevel: QGroundControl.flightMapZoom
        center: root.sharedMapCenter()

        onZoomLevelChanged: QGroundControl.flightMapZoom = editorMap.zoomLevel
        onCenterChanged: QGroundControl.flightMapPosition = editorMap.center
        onMapReadyChanged: {
            root.syncEditorMapFromSharedState()
            if (root.fitPending || root._missionController.containsItems) {
                Qt.callLater(root.fitPlanToMap)
            }
        }
        onMapClicked: (mouse) => root.handleMapClick(mouse)

        // Mission visuals
        Repeater {
            model: root._missionController.visualItems
            delegate: MissionItemMapVisual {
                map: editorMap
                opacity: root._editingLayer == root._layerMission ? 1 : 0.5
                interactive: root._editingLayer == root._layerMission
                vehicle: root._planMasterController.controllerVehicle
                onClicked: { root._missionController.setCurrentPlanViewSeqNum(sequenceNumber, false) }
            }
        }

        MissionLineView {
            showSpecialVisual: root._missionController.isROIBeginCurrentItem
            model: root._missionController.simpleFlightPathSegments
            opacity: root._editingLayer == root._layerMission ? 1 : editorMap._nonInteractiveOpacity
        }

        MapItemView {
            model: root._editingLayer == root._layerMission ? root._missionController.directionArrows : undefined

            delegate: MapLineArrow {
                fromCoord: object ? object.coordinate1 : undefined
                toCoord: object ? object.coordinate2 : undefined
                arrowPosition: 3
                z: QGroundControl.zOrderWaypointLines + 1
            }
        }

        MapQuickItem {
            id: splitSegmentItem
            anchorPoint.x: sourceItem.width / 2
            anchorPoint.y: sourceItem.height / 2
            z: QGroundControl.zOrderWaypointLines + 1
            visible: root._editingLayer == root._layerMission

            sourceItem: SplitIndicator {
                onClicked: root._missionController.insertSimpleMissionItem(splitSegmentItem.coordinate,
                                                                            root._missionController.currentPlanViewVIIndex,
                                                                            true)
            }

            function updateSplitCoordinate() {
                if (root._missionController.splitSegment) {
                    const segment = root._missionController.splitSegment
                    const distance = segment.coordinate1.distanceTo(segment.coordinate2)
                    const azimuth = segment.coordinate1.azimuthTo(segment.coordinate2)
                    splitSegmentItem.coordinate = segment.coordinate1.atDistanceAndAzimuth(distance / 2, azimuth)
                } else {
                    splitSegmentItem.coordinate = QtPositioning.coordinate()
                }
            }

            Connections {
                target: root._missionController
                function onSplitSegmentChanged() { splitSegmentItem.updateSplitCoordinate() }
            }

            Connections {
                target: root._missionController.splitSegment
                ignoreUnknownSignals: true
                function onCoordinate1Changed() { splitSegmentItem.updateSplitCoordinate() }
                function onCoordinate2Changed() { splitSegmentItem.updateSplitCoordinate() }
            }
        }

        // Vehicles
        MapItemView {
            model: QGroundControl.multiVehicleManager.vehicles
            delegate: VehicleMapItem {
                vehicle: object
                coordinate: object.coordinate
                map: editorMap
                size: ScreenTools.defaultFontPixelHeight * 3
                z: QGroundControl.zOrderMapItems - 1
            }
        }

        GeoFenceMapVisuals {
            map: editorMap
            myGeoFenceController: root._geoFenceController
            interactive: root._editingLayer == root._layerFence
            homePosition: root._missionController.plannedHomePosition
            planView: true
            opacity: root._editingLayer == root._layerFence ? 1 : editorMap._nonInteractiveOpacity
        }

        RallyPointMapVisuals {
            map: editorMap
            myRallyPointController: root._rallyPointController
            interactive: root._editingLayer == root._layerRally
            planView: true
            opacity: root._editingLayer == root._layerRally ? 1 : editorMap._nonInteractiveOpacity
        }
    }

    Connections {
        target: root._missionController
        ignoreUnknownSignals: true

        function onContainsItemsChanged() {
            if (root._missionController.containsItems) {
                Qt.callLater(root.fitPlanToMap)
            }
        }

        function onNewItemsFromVehicle() {
            Qt.callLater(root.fitPlanToMap)
        }
    }

    Connections {
        target: root._missionController.visualItems
        ignoreUnknownSignals: true

        function onCountChanged() {
            if (root._missionController.containsItems) {
                Qt.callLater(root.fitPlanToMap)
            }
        }
    }

    // Editing layer hint, shown while editing the fence or rally layer
    Rectangle {
        anchors.top: topHeader.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: editorMap.horizontalCenter
        width: Math.min(editorMap.width - 24, layerHintText.implicitWidth + 24)
        height: 28
        radius: 2
        visible: root._editingLayer !== root._layerMission
        color: "#0b0d10"
        border.color: root.gold
        border.width: 1

        Text {
            id: layerHintText
            anchors.centerIn: parent
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            text: root.editingLayerHint()
            color: root.text
            font.pixelSize: 10
            font.bold: true
            font.family: "monospace"
            elide: Text.ElideRight
        }
    }

    // Right panel (reuses existing PlanViewRightPanel)
    PlanViewRightPanel {
        id: rightPanel
        anchors.top: topHeader.bottom
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        width: Math.min(root.width * 0.3, ScreenTools.defaultFontPixelWidth * 30)
        planMasterController: root._planMasterController
        editorMap: editorMap
        on_EditingToolChanged: root._editingLayer = rightPanel._editingTool + root._layerMission
    }

    // Bottom summary bar
    Rectangle {
        id: bottomBar
        height: 86
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: "#050509"
        border.color: "#1b1f23"

        TerrainProfile {
            id: modernTerrainProfile
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            height: 40
            visibleWidth: width
            missionController: root._missionController
            opacity: 0.85
        }

        Text {
            anchors.left: parent.left
            anchors.top: modernTerrainProfile.bottom
            anchors.leftMargin: 12
            anchors.topMargin: 4
            text: "ELEVATION PROFILE"
            color: root.gold
            font.pixelSize: 8
            font.bold: true
            font.family: "monospace"
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            anchors.topMargin: 58
            spacing: 18

            Text { text: "ALT DIFF: " + root.missionAltitudeDifferenceText(); color: root.dim; font.pixelSize: 12 }
            Text { text: "TOTAL MISSION: " + root.missionDistanceText(); color: root.dim; font.pixelSize: 12 }
            Text { text: "TIME: " + root.formatMissionTime(_missionController.missionTime); color: root.dim; font.pixelSize: 12 }
        }
    }

    // Small overlay indicators (IAS + attitude) near right panel
    Rectangle {
        id: iasIndicator
        width: 56
        height: 56
        radius: 6
        color: "#0b0d10"
        border.color: root.border
        x: (rightPanel.expanded ? (root.width - rightPanel.width) : root.width) - width - 12
        y: bottomBar.y - height - 24

        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Column { anchors.centerIn: parent; spacing: 2; Text { text: "IAS"; color: root.dim; font.pixelSize: 10 } Text { text: QGroundControl.multiVehicleManager.activeVehicle ? ("BRCH-" + QGroundControl.multiVehicleManager.activeVehicle.id) : "--"; color: root.gold; font.bold: true } }
    }

    component ModernSettingsAction: Rectangle {
        id: settingsAction
        signal clicked()
        property string label: ""
        property color tone: root.gold
        property bool hovered: false

        Layout.preferredHeight: 30
        opacity: 1.0
        color: hovered && enabled ? Qt.rgba(tone.r, tone.g, tone.b, 0.16) : "#111925"
        border.color: enabled ? (hovered ? tone : Qt.rgba(tone.r, tone.g, tone.b, 0.58)) : "#344154"
        border.width: 1
        radius: 2

        Text {
            anchors.centerIn: parent
            text: settingsAction.label
            color: settingsAction.enabled ? settingsAction.tone : "#7f8da0"
            font.pixelSize: 10
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

}
