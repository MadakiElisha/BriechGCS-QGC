import QtQuick
import QtQuick.Layouts

import QGroundControl
import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// Fleet safety section. Shows how many connected vehicles are armed and how
// many are low on battery, from live QGC state, and offers HOLD ALL and
// RETURN ALL for the vehicles that are flying. The buttons only ask: the
// Modern view confirms with the operator (listing the vehicles) before
// FleetDispatch sends anything. They work with or without the coordinator.
Rectangle {
    id: root

    signal holdAllRequested()
    signal returnAllRequested()

    readonly property var vehicles: QGroundControl.multiVehicleManager.vehicles
    readonly property int armedCount: FleetFormat.armedCount(vehicles)
    readonly property int flyingCount: FleetFormat.flyingCount(vehicles)
    readonly property int lowBatteryCount: FleetFormat.lowBatteryCount(vehicles)

    height: 64
    color: "transparent"

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(1, 1, 1, 0.075)
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        RowLayout {
            width: parent.width
            spacing: 10

            Text {
                text: "SAFETY"
                color: BriechTheme.goldAccent
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.5
                font.family: "Share Tech Mono"
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "ARMED " + root.armedCount + "/" + root.vehicles.count
                color: root.armedCount > 0 ? BriechTheme.okColor : BriechTheme.mutedColor
                font.pixelSize: 9
                font.letterSpacing: 1
                font.family: "Share Tech Mono"
            }

            Text {
                text: "BATT LOW " + root.lowBatteryCount
                color: root.lowBatteryCount > 0 ? BriechTheme.errColor : BriechTheme.mutedColor
                font.pixelSize: 9
                font.letterSpacing: 1
                font.family: "Share Tech Mono"
            }
        }

        // Only vehicles in the air are commanded; with none flying both stay disabled.
        RowLayout {
            width: parent.width
            spacing: 6

            CommandButton {
                Layout.fillWidth: true
                text: "HOLD ALL"
                tone: BriechTheme.goldAccent
                enabled: root.flyingCount > 0
                onClicked: root.holdAllRequested()
            }

            CommandButton {
                Layout.fillWidth: true
                text: "RETURN ALL"
                tone: BriechTheme.warnColor
                enabled: root.flyingCount > 0
                onClicked: root.returnAllRequested()
            }
        }
    }

    component CommandButton: Rectangle {
        id: button

        signal clicked()

        property string text
        property color tone

        implicitHeight: 22
        opacity: enabled ? 1 : 0.35
        radius: 2
        color: buttonArea.containsMouse && enabled ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        border.color: button.tone
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: button.text
            color: button.tone
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 1.5
            font.family: "Share Tech Mono"
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: button.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
