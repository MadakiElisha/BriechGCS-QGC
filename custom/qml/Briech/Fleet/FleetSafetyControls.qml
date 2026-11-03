import QtQuick
import QtQuick.Layouts

import QGroundControl
import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// Fleet safety section. Shows how many connected vehicles are armed and how
// many are low on battery, from live QGC state. Fleet-wide commands (hold all,
// return all) go through the coordinator, so none are offered until FleetLink
// exists; per-vehicle commands stay on the Modern view's sidebar.
Rectangle {
    id: root

    readonly property var vehicles: QGroundControl.multiVehicleManager.vehicles
    readonly property int armedCount: FleetFormat.armedCount(vehicles)
    readonly property int lowBatteryCount: FleetFormat.lowBatteryCount(vehicles)

    height: 46
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
        spacing: 4

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

        Text {
            text: "FLEET COMMANDS NEED COORDINATOR"
            color: BriechTheme.mutedColor
            font.pixelSize: 8
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }
    }
}
