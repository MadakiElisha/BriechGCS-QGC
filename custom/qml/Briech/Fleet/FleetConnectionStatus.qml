import QtQuick

import Custom.Widgets 1.0

// Bottom row of the Fleet page: whether the coordinator link (FleetLink) is
// up, whether the 3D view is available, and DISABLE.
Rectangle {
    id: root

    signal disableRequested()

    /// True while FleetLink has a live coordinator connection.
    property bool connected: FleetLink.state === FleetLink.Connected

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
            // CONNECTED, CONNECTING, RETRYING IN 4 S, UNAUTHORIZED or DISABLED
            text: "COORDINATOR: " + FleetLink.stateText
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
