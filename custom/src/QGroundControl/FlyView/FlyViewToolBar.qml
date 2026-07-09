import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import Custom.Widgets 1.0

Item {
    id: control
    width: parent.width
    height: ScreenTools.toolbarHeight

    required property var guidedValueSlider
    required property bool utmspSliderTrigger

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var _guidedController: globals.guidedControllerFlyView
    property real _leftRightMargin: ScreenTools.defaultFontPixelWidth * 0.75
    property color _barColor: "#090b10"
    property color _barEdge: BriechTheme.goldAccent

    function dropMainStatusIndicatorTool() {
        mainStatusIndicator.dropMainStatusIndicator()
    }

    QGCPalette { id: qgcPal }

    Rectangle {
        anchors.fill: parent
        color: _barColor
        border.color: _barEdge
        border.width: 0
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: _barEdge
        opacity: 0.75
    }

    QGCFlickable {
        anchors.fill: parent
        contentWidth: toolBarLayout.width
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: toolBarLayout
            height: parent.height
            spacing: 0

            Item {
                id: leftPanel
                width: leftPanelLayout.implicitWidth
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0.06, 0.07, 0.10, 0.95)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: _barEdge
                }

                RowLayout {
                    id: leftPanelLayout
                    height: parent.height
                    spacing: ScreenTools.defaultFontPixelWidth * 1.4

                    RowLayout {
                        id: brandLayout
                        height: parent.height
                        spacing: ScreenTools.defaultFontPixelWidth * 0.7

                        QGCToolBarButton {
                            id: qgcButton
                            Layout.fillHeight: true
                            icon.source: "/res/QGCLogoFull.svg"
                            logo: true
                            onClicked: mainWindow.showToolSelectDialog()
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.alignment: Qt.AlignVCenter

                            QGCLabel {
                                text: "BRIECH UAS"
                                color: BriechTheme.textColor
                                font.family: BriechTheme.fontCondensed
                                font.pixelSize: 15
                                font.bold: true
                                font.letterSpacing: 1
                            }

                            QGCLabel {
                                text: qsTr("Ground Control Station")
                                color: BriechTheme.goldAccent
                                font.family: BriechTheme.fontCondensed
                                font.pixelSize: 9
                                font.letterSpacing: 2
                            }
                        }
                    }

                    MainStatusIndicator {
                        id: mainStatusIndicator
                        Layout.fillHeight: true
                    }

                    QGCButton {
                        id: disconnectButton
                        text: qsTr("Disconnect")
                        visible: _activeVehicle && _activeVehicle.vehicleLinkManager.communicationLost
                        onClicked: _activeVehicle.closeVehicle()
                    }

                    FlightModeIndicator {
                        Layout.fillHeight: true
                        visible: _activeVehicle
                    }
                }
            }

            Item {
                id: centerPanel
                width: Math.max(guidedActionConfirm.visible ? guidedActionConfirm.width : 0, control.width - (leftPanel.width + rightPanel.width))
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                }

                GuidedActionConfirm {
                    id: guidedActionConfirm
                    height: parent.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    guidedController: control._guidedController
                    guidedValueSlider: control.guidedValueSlider
                    utmspSliderTrigger: control.utmspSliderTrigger
                    messageDisplay: guidedActionMessageDisplay
                }
            }

            Item {
                id: rightPanel
                width: flyViewIndicators.width
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                }

                FlyViewToolBarIndicators {
                    id: flyViewIndicators
                    height: parent.height
                }
            }
        }
    }

    Rectangle {
        id: guidedActionMessageDisplay
        anchors.top: control.bottom
        anchors.topMargin: ScreenTools.defaultFontPixelHeight * 0.5
        x: control.mapFromItem(guidedActionConfirm.parent, guidedActionConfirm.x, 0).x + (guidedActionConfirm.width - guidedActionMessageDisplay.width) / 2
        width: messageLabel.contentWidth + (ScreenTools.defaultFontPixelWidth * 1)
        height: messageLabel.contentHeight + (ScreenTools.defaultFontPixelHeight * 0.8)
        color: qgcPal.windowTransparent
        radius: ScreenTools.defaultBorderRadius
        visible: guidedActionConfirm.visible

        QGCLabel {
            id: messageLabel
            x: ScreenTools.defaultFontPixelWidth * 0.5
            y: ScreenTools.defaultFontPixelHeight * 0.4
            width: ScreenTools.defaultFontPixelWidth * 30
            wrapMode: Text.WordWrap
            text: guidedActionConfirm.message
        }
    }

    ParameterDownloadProgress {
        anchors.fill: parent
    }
}
