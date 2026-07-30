import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.UTMSP

Item {
    required property var editorMap
    required property var planMasterController

    id: root

    // These must match the indices of _editingToolComponents
    readonly property int _editingToolMission:  0
    readonly property int _editingToolFence:    1
    readonly property int _editingToolRally:    2

    property int _editingTool:              _editingToolMission
    property var _missionController:        planMasterController.missionController
    property var _geoFenceController:       planMasterController.geoFenceController
    property var _rallyPointController:     planMasterController.rallyPointController
    property var _visualItems:              _missionController.visualItems
    property var _editingToolComponents:    [ missionToolComponent, fenceToolComponent, rallyToolComponent ]
    property real _toolsMargin:             ScreenTools.defaultFontPixelWidth * 0.75

    function selectNextNotReady() {
        var foundCurrent = false
        for (var i=0; i<_missionController.visualItems.count; i++) {
            var vmi = _missionController.visualItems.get(i)
            if (vmi.readyForSaveState === VisualMissionItem.NotReadyForSaveData) {
                _missionController.setCurrentPlanViewSeqNum(vmi.sequenceNumber, true)
                break
            }
        }
    }

    QGCPalette { id: qgcPal }

    Rectangle {
        id:             rightPanelBackground
        anchors.fill:   parent
        color:          "#0f1113"
        opacity:        1.0
    }


    // Open/Close panel
    Item {
        id:                     panelOpenCloseButton
        anchors.right:          parent.left
        anchors.verticalCenter: parent.verticalCenter
        width:                  toggleButtonRect.width - toggleButtonRect.radius
        height:                 toggleButtonRect.height
        clip:                   true

        property bool _expanded: root.anchors.right == root.parent.right

        Rectangle {
            id:             toggleButtonRect
            width:          ScreenTools.defaultFontPixelWidth * 2.25
            height:         width * 3
            radius:         ScreenTools.defaultBorderRadius
            color:          "#0f1113"
            border.color:   "#252c38"
            border.width:   1

            QGCLabel {
                id:                 toggleButtonLabel
                anchors.centerIn:   parent
                text:               panelOpenCloseButton._expanded ? ">" : "<"
                color:              "#C9A84C"
                font.bold:          true
            }

        }

        QGCMouseArea {
            anchors.fill: parent

            onClicked: {
                if (panelOpenCloseButton._expanded) {
                    // Close panel
                    root.anchors.right = undefined
                    root.anchors.left = root.parent.right
                } else {
                    // Open panel
                    root.anchors.left = undefined
                    root.anchors.right = root.parent.right
                }
            }
        }
    }

    //-------------------------------------------------------
    // Right Panel Controls
    Item {
        anchors.fill: rightPanelBackground

        DeadMouseArea {
            anchors.fill:   parent
        }

        ColumnLayout {
            anchors.fill:        parent
            anchors.topMargin:   ScreenTools.defaultFontPixelHeight * 0.4
            spacing:             ScreenTools.defaultFontPixelHeight * 0.6

            Row {
                Layout.fillWidth:  true
                Layout.leftMargin: 0
                height: ScreenTools.defaultFontPixelHeight * 2.4
                spacing: 0

                Repeater {
                    model: [qsTr("MISSION"), qsTr("FENCE"), qsTr("RALLY")]

                    delegate: Rectangle {
                        property bool _active: root._editingTool === index
                        width: parent.width / 3
                        height: parent.height
                        color: _active ? "#211c10" : "transparent"

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left:   parent.left
                            anchors.right:  parent.right
                            height: 2
                            color: _active ? "#C9A84C" : "#252c38"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: _active ? "#C9A84C" : "#6a7585"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: ScreenTools.normalFontFamily
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root._editingTool = index
                                if (index === 0) _editingLayer = _layerMission
                                else if (index === 1) _editingLayer = _layerFence
                                else _editingLayer = _layerRally
                            }
                        }
                    }
                }
            }

            Loader {
                id:                  editingToolLoader
                Layout.fillWidth:    true
                Layout.fillHeight:   true
                Layout.leftMargin:   ScreenTools.defaultFontPixelWidth * 0.75
                Layout.rightMargin:  ScreenTools.defaultFontPixelWidth * 0.75
                Layout.bottomMargin: ScreenTools.defaultFontPixelHeight * 0.4
                sourceComponent:     root._editingToolComponents[root._editingTool]
            }
        }

        Component {
            id: missionToolComponent

            ColumnLayout {
                spacing: ScreenTools.defaultFontPixelHeight / 2

                QGCListView {
                    id:                 missionItemEditorListView
                    Layout.fillWidth:   true
                    Layout.fillHeight:  true
                    spacing:            ScreenTools.defaultFontPixelHeight * 0.4
                    topMargin:          ScreenTools.defaultFontPixelHeight * 0.25
                    bottomMargin:       ScreenTools.defaultFontPixelHeight * 0.25
                    orientation:        ListView.Vertical
                    model:              _missionController.visualItems
                    cacheBuffer:        Math.max(height * 2, 0)
                    clip:               true
                    currentIndex:       _missionController.currentPlanViewSeqNum
                    highlightMoveDuration: 250

                    delegate: MissionItemEditor {
                        map:                  editorMap
                        masterController:     planMasterController
                        missionItem:          object
                        width:                missionItemEditorListView.width
                        readOnly:             false
                        activeHighlightColor: "#211c10"

                        onClicked: _missionController.setCurrentPlanViewSeqNum(object.sequenceNumber, false)

                        onRemove: {
                            var removeVIIndex = index
                            _missionController.removeVisualItem(removeVIIndex)
                            if (removeVIIndex >= _missionController.visualItems.count) {
                                removeVIIndex--
                            }
                        }

                        onSelectNextNotReadyItem: selectNextNotReady()
                    }
                }
            }
        }

        Component {
            id: fenceToolComponent

            Column {
                spacing: ScreenTools.defaultFontPixelHeight / 2

                GeoFenceEditor {
                    width:                  parent.width
                    myGeoFenceController:   root._geoFenceController
                    flightMap:              root.editorMap
                }
            }
        }


        Component {
            id: rallyToolComponent

            Column {
                spacing: ScreenTools.defaultFontPixelHeight / 2

                RallyPointEditorHeader {
                    width:              parent.width
                    controller:         root._rallyPointController
                }

                RallyPointItemEditor {
                    width:              parent.width
                    visible:            root._rallyPointController.points.count
                    rallyPoint:         root._rallyPointController.currentRallyPoint
                    controller:         root._rallyPointController
                }
            }
        }

        Component {
            id: utmspToolComponent

            Column {
                spacing: ScreenTools.defaultFontPixelHeight / 2

                UTMSPAdapterEditor{
                    width:                  parent.width
                    currentMissionItems:     root._visualItems
                    myGeoFenceController:    root._geoFenceController
                    flightMap:               root.editorMap
                    triggerSubmitButton:     _triggerSubmit
                    resetRegisterFlightPlan: _resetRegisterFlightPlan

                    onRemoveFlightPlanTriggered: {
                        root.planMasterController.removeAllFromVehicle()
                        root._missionController.setCurrentPlanViewSeqNum(0, true)
                        _resetRegisterFlightPlan = true
                    }

                    onResetGeofencePolygonTriggered: {
                        resetUTMSPGeoFenceTimer.start()
                    }

                    Timer {
                        id:             resetUTMSPGeoFenceTimer
                        interval:       2500
                        running:        false
                        repeat:         false
                        onTriggered:    _resetGeofencePolygon = true
                    }
                }
            }
        }
    }
}
