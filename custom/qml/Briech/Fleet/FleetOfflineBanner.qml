import QtQuick

import Custom.Widgets 1.0

// Shown while Fleet is on and the coordinator has been silent for 10 s
// (FleetLink.coordinatorSilent). Assets, detections and alerts on screen are
// then not current; flying, HOLD ALL and RETURN ALL do not need the
// coordinator and keep working. Takes no space while hidden.
Rectangle {
    id: root

    readonly property bool shown: FleetSettings.enabled && FleetLink.coordinatorSilent

    visible: shown
    height: shown ? column.implicitHeight + 14 : 0
    color: Qt.rgba(BriechTheme.errColor.r, BriechTheme.errColor.g, BriechTheme.errColor.b, 0.14)
    border.color: BriechTheme.errColor
    border.width: 1

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 2

        Text {
            width: parent.width
            // e.g. "COORDINATOR OFFLINE · RETRYING IN 4 S"
            text: "COORDINATOR OFFLINE · " + FleetLink.stateText
            color: BriechTheme.errColor
            elide: Text.ElideRight
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }

        Text {
            width: parent.width
            text: "Towers, detections and alerts are not current. Flying, HOLD ALL and RETURN ALL still work."
            color: BriechTheme.textColor
            wrapMode: Text.WordWrap
            font.pixelSize: 9
            font.family: "Share Tech Mono"
        }
    }
}
