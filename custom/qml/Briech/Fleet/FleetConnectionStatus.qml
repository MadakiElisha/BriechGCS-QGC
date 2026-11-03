import QtQuick

import Custom.Widgets 1.0

// Bottom row of the Fleet page: whether the coordinator link (FleetLink) is
// up, whether the 3D view is available, and DISABLE.
Rectangle {
    id: root

    signal disableRequested()

    /// True once FleetLink reports a live coordinator connection. FleetLink
    /// does not exist yet, so nothing sets this and the row reads NOT CONNECTED.
    property bool connected: false

    height: 26
    color: "#05070a"

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(1, 1, 1, 0.075)
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: root.connected ? BriechTheme.okColor : BriechTheme.mutedColor
        }

        Text {
            text: "COORDINATOR: " + (root.connected ? "CONNECTED" : "NOT CONNECTED")
                  + " · 3D: " + (FleetSettings.quick3DAvailable ? "OK" : "2D")
            color: root.connected ? BriechTheme.okColor : BriechTheme.mutedColor
            font.pixelSize: 8
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: "DISABLE"
        color: disableArea.containsMouse ? BriechTheme.errColor : BriechTheme.mutedColor
        font.pixelSize: 8
        font.bold: true
        font.letterSpacing: 1
        font.family: "Share Tech Mono"

        MouseArea {
            id: disableArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.disableRequested()
        }
    }
}
