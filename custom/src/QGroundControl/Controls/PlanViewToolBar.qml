import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import Custom.Widgets 1.0

Rectangle {
    id: root
    width: parent.width
    height: ScreenTools.toolbarHeight
    color: "#090b10"

    property var planMasterController
    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property real _controllerProgressPct: planMasterController.missionController.progressPct

    QGCPalette { id: qgcPal }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: BriechTheme.goldAccent
        opacity: 0.75
    }

    Rectangle {
        id: leftBrandBand
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: brandRow.width + (ScreenTools.defaultFontPixelWidth * 3)
        color: Qt.rgba(0.06, 0.07, 0.10, 0.95)

        RowLayout {
            id: brandRow
            anchors.left: parent.left
            anchors.leftMargin: ScreenTools.defaultFontPixelWidth
            anchors.verticalCenter: parent.verticalCenter
            spacing: ScreenTools.defaultFontPixelWidth * 0.7

            QGCToolBarButton {
                height: parent.height
                icon.source: "/res/QGCLogoFull.svg"
                logo: true
                onClicked: mainWindow.showToolSelectDialog()
            }

            ColumnLayout {
                spacing: 0

                QGCLabel {
                    text: "BRIECH UAS"
                    color: BriechTheme.textColor
                    font.family: BriechTheme.fontCondensed
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1
                }

                QGCLabel {
                    text: qsTr("Mission Planning")
                    color: BriechTheme.goldAccent
                    font.family: BriechTheme.fontCondensed
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }
        }
    }

    QGCFlickable {
        id: toolsFlickable
        anchors.left: leftBrandBand.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        contentWidth: toolIndicators.width
        flickableDirection: Flickable.HorizontalFlick

        PlanToolBarIndicators {
            id: toolIndicators
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            planMasterController: root.planMasterController
        }
    }

    Rectangle {
        id: progressBar
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: 4
        width: _controllerProgressPct * parent.width
        color: BriechTheme.okColor
        visible: false

        onVisibleChanged: {
            if (visible) {
                largeProgressBar._userHide = false
            }
        }
    }

    Rectangle {
        id: largeProgressBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height
        color: qgcPal.window
        visible: _showLargeProgress

        property bool _userHide: false
        property bool _showLargeProgress: progressBar.visible && !_userHide && qgcPal.globalTheme === palette.Light

        Connections {
            target: QGroundControl.multiVehicleManager
            function onActiveVehicleChanged(activeVehicle) { largeProgressBar._userHide = false }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: _controllerProgressPct * parent.width
            color: BriechTheme.okColor
        }

        QGCLabel {
            anchors.centerIn: parent
            text: qsTr("Syncing Mission")
            font.pointSize: ScreenTools.largeFontPointSize
            visible: _controllerProgressPct !== 1
        }

        QGCLabel {
            anchors.centerIn: parent
            text: qsTr("Done")
            font.pointSize: ScreenTools.largeFontPointSize
            visible: _controllerProgressPct === 1
        }

        MouseArea {
            anchors.fill: parent
            onClicked: largeProgressBar._userHide = true
        }
    }

    Connections {
        target: planMasterController.missionController

        function onProgressPctChanged(progressPct) {
            if (progressPct === 1) {
                if (root.visible) {
                    resetProgressTimer.start()
                } else {
                    progressBar.visible = false
                }
            } else if (progressPct > 0) {
                progressBar.visible = true
            }
        }
    }

    Timer {
        id: resetProgressTimer
        interval: 3000
        onTriggered: progressBar.visible = false
    }
}
