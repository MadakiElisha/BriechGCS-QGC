import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtLocation
import QtPositioning
import QGroundControl
import QGroundControl.FlightMap
import QGroundControl.Controls
import QGroundControl.UTMSP



Item {
    id: root
    anchors.fill: parent

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
            _missionController.setCurrentPlanViewSeqNum(0, true)
        }
    }

    Component.onCompleted: {
        console.log("PlanViewModern: Component completed; size=" + root.width + "x" + root.height)
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
                MouseArea { id: exitHover; anchors.fill: parent; hoverEnabled: true; onClicked: planMasterController.removeAll() }
            }

            Item { width: 16 }

            RowLayout {
                spacing: 18
                Repeater {
                    model: [ {label: "ALT DIFF", value: "0.0 m"}, {label: "TOTAL MISSION", value: "0 m"}, {label: "TIME", value: "00:00:00"} ]
                    delegate: Column {
                        spacing: 2
                        Text { text: modelData.label; color: "#9aa3ad"; font.pixelSize: 10; font.family: ScreenTools.normalFontFamily }
                        Text { text: modelData.value; color: root.text; font.pixelSize: 12; font.bold: true; font.family: ScreenTools.normalFontFamily }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // Left panel
    Rectangle {
        id: leftPanel
        width: 300
        anchors.top: topHeader.bottom
        anchors.left: parent.left
        anchors.bottom: parent.bottom
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
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        mapName: "BriechModernPlanView"
        allowGCSLocationCenter: true
        allowVehicleLocationCenter: true
        planView: true

        zoomLevel: QGroundControl.flightMapZoom
        center: QGroundControl.flightMapPosition

        onZoomLevelChanged: QGroundControl.flightMapZoom = editorMap.zoomLevel
        onCenterChanged: QGroundControl.flightMapPosition = editorMap.center

        // Mission visuals
        Repeater {
            model: _missionController.visualItems
            delegate: MissionItemMapVisual {
                map: editorMap
                opacity: _editingLayer == _layerMission ? 1 : 0.5
                interactive: _editingLayer == _layerMission
                vehicle: planMasterController.controllerVehicle
                onClicked: { _missionController.setCurrentPlanViewSeqNum(sequenceNumber, false) }
            }
        }

        MissionLineView {
            model: _missionController.simpleFlightPathSegments
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
    }

    /* Debug overlay to confirm component instantiation */
    Rectangle {
        id: debugOverlay
        anchors.left: leftPanel.right
        anchors.top: topHeader.bottom
        width: 160
        height: 28
        color: "#00000088"
        visible: true

        Text { anchors.centerIn: parent; text: "PlanView loaded"; color: root.gold; font.pixelSize: 12 }
    }

    // Right panel (reuses existing PlanViewRightPanel)
    PlanViewRightPanel {
        id: rightPanel
        anchors.top: topHeader.bottom
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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

            Text { text: "ALT DIFF: 0.0 m"; color: root.dim; font.pixelSize: 12 }
            Text { text: "TOTAL MISSION: 0 m"; color: root.dim; font.pixelSize: 12 }
            Text { text: "TIME: 00:00:00"; color: root.dim; font.pixelSize: 12 }
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
