import QtQuick

import Custom.Widgets 1.0

// Fleet alerts section. Alerts come from the coordinator through FleetLink,
// which does not exist yet, so this states that there is no source instead of
// showing an empty "all clear" that nobody actually checked.
Rectangle {
    id: root

    /// Alert list model. Stays null until FleetLink and the alert model exist;
    /// rows are rendered once the model's roles are agreed.
    property var model: null

    readonly property bool hasSource: model !== null && model !== undefined

    height: 30
    color: "transparent"

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(1, 1, 1, 0.075)
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "ALERTS"
        color: BriechTheme.goldAccent
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 1.5
        font.family: "Share Tech Mono"
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasSource ? (root.model.count > 0 ? root.model.count + " ACTIVE" : "NONE") : "NO SOURCE"
        color: root.hasSource && root.model.count > 0 ? BriechTheme.warnColor : BriechTheme.mutedColor
        font.pixelSize: 9
        font.letterSpacing: 1
        font.family: "Share Tech Mono"
    }
}
