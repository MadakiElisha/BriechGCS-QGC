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



Item {
    id: root
    anchors.fill: parent

    signal exitRequested()

    // Theme defaults (overridden when embedded in BriechModernView)
    property color gold: "#C9A84C"
    property color border: "#252c38"
    property color text: "#d8dde6"
    property color dim: "#6a7585"

    // Controllers
    property var _planMasterController: planMasterController
    property var _missionController: planMasterController.missionController
    property var _geoFenceController: planMasterController.geoFenceController
    property var _rallyPointController: planMasterController.rallyPointController

    readonly property int _layerMission: 1
    readonly property int _layerFence: 2
    readonly property int _layerRally: 3
    property int _editingLayer: _layerMission

    PlanMasterController {
        id: planMasterController
        flyView: false

        Component.onCompleted: {
            planMasterController.start()
            root._missionController.setCurrentPlanViewSeqNum(0, true)
        }
    }

    function sharedMapCenter() {
        return QGroundControl.flightMapPosition.isValid ? QGroundControl.flightMapPosition : QtPositioning.coordinate(9.0765, 7.3986)
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
        } else if (_editingLayer === _layerRally && _rallyPointController.supported) {
            _rallyPointController.addPoint(coordinate)
        }
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
        }
    }

    // Left panel
    Rectangle {
        id: leftPanel
        width: 300
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

                Repeater {
                    model: planMasterController.planCreators
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 110
                        radius: 4
                        color: "#0b0d10"
                        border.color: cardHover.containsMouse ? root.gold : "#22252a"
                        clip: true

                        Image {
                            id: thumb
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: cardLabel.top
                            anchors.margins: 4
                            fillMode: Image.PreserveAspectFit
                            source: (modelData && modelData.thumbnail) ? modelData.thumbnail : ""
                            opacity: 0.9
                        }

                        Text {
                            id: cardLabel
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 8
                            text: (modelData && modelData.name) ? modelData.name : "Template"
                            color: cardHover.containsMouse ? root.gold : root.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: ScreenTools.normalFontFamily
                        }

                        MouseArea {
                            id: cardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { if (modelData && modelData.createPlan) modelData.createPlan(editorMap.center) }
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
                            mainWindow.showMessageDialog(qsTr("Open Plan"),
                                qsTr("You have unsaved/unsent changes. Loading a new Plan will lose these changes. Are you sure?"),
                                Dialog.Yes | Dialog.Cancel,
                                function() { planMasterController.loadFromSelectedFile() })
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
                    Text { anchors.centerIn: parent; text: "UPLOAD"; color: "#3b82f6"; font.pixelSize: 10; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    MouseArea { anchors.fill: parent; onClicked: planMasterController.upload() }
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
                            mainWindow.showMessageDialog(qsTr("Download"),
                                qsTr("You have unsaved/unsent changes. Downloading from the Vehicle will lose these changes. Are you sure?"),
                                Dialog.Yes | Dialog.Cancel,
                                function() { planMasterController.loadFromVehicle() })
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
                        mainWindow.showMessageDialog(qsTr("Clear"),
                            qsTr("Are you sure you want to remove all the items from the plan editor?"),
                            Dialog.Yes | Dialog.Cancel,
                            function() { planMasterController.removeAll() })
                    }}
                }
            }

            Item { Layout.fillHeight: true }
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

        zoomLevel: QGroundControl.flightMapZoom
        center: root.sharedMapCenter()

        onZoomLevelChanged: QGroundControl.flightMapZoom = editorMap.zoomLevel
        onCenterChanged: QGroundControl.flightMapPosition = editorMap.center
        onMapReadyChanged: root.syncEditorMapFromSharedState()
        onMapClicked: (mouse) => root.handleMapClick(mouse)

        // Mission visuals
        Repeater {
            model: root._missionController.visualItems
            delegate: MissionItemMapVisual {
                map: editorMap
                opacity: root._editingLayer == root._layerMission ? 1 : 0.5
                interactive: root._editingLayer == root._layerMission
                vehicle: planMasterController.controllerVehicle
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

    // Right panel (reuses existing PlanViewRightPanel)
    PlanViewRightPanel {
        id: rightPanel
        anchors.top: topHeader.bottom
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        width: Math.min(root.width * 0.3, ScreenTools.defaultFontPixelWidth * 30)
        planMasterController: planMasterController
        editorMap: editorMap
    }

    // Bottom summary bar
    Rectangle {
        id: bottomBar
        height: 48
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: "#050509"
        border.color: "#1b1f23"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
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

}
