pragma ComponentBehavior: Bound

import QtQuick

import Custom.Widgets 1.0

// Stack of operator notifications (BriechModernView.pushToast). Each card: a
// tone bar, an icon, an upper-case title, a mono detail line, the time it was
// raised and a close button. Clicking anywhere on a card dismisses it.
Item {
    id: root

    /// ListModel with roles: title, message, tone ("ok", "warn", "crit", "info"), time.
    property var model

    implicitHeight: stackColumn.implicitHeight

    function toneColor(tone) {
        switch (tone) {
        case "ok": return BriechTheme.okColor
        case "warn": return BriechTheme.warnColor
        case "crit": return BriechTheme.errColor
        default: return BriechTheme.blueColor
        }
    }

    function toneIcon(tone) {
        switch (tone) {
        case "ok": return "✓"
        case "warn": return "⚠"
        case "crit": return "✕"
        default: return "i"
        }
    }

    Column {
        id: stackColumn
        width: parent.width
        spacing: 8

        Repeater {
            model: root.model

            delegate: Rectangle {
                id: card

                required property int index
                required property string title
                required property string message
                required property string tone
                required property string time

                readonly property color accent: root.toneColor(tone)

                width: stackColumn.width
                height: content.implicitHeight + 22
                radius: 2
                color: "#0d1016"
                border.color: Qt.rgba(1, 1, 1, 0.07)
                border.width: 1

                // Tone bar.
                Rectangle {
                    width: 3
                    height: parent.height
                    color: card.accent
                }

                Text {
                    id: icon
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 16
                    anchors.topMargin: 11
                    text: root.toneIcon(card.tone)
                    color: card.tone === "ok" ? BriechTheme.textColor : card.accent
                    font.pixelSize: 15
                    font.bold: true
                }

                Column {
                    id: content
                    anchors.left: icon.right
                    anchors.right: closeButton.left
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    anchors.topMargin: 11
                    spacing: 4

                    Text {
                        width: parent.width
                        text: String(card.title).toUpperCase()
                        color: "#f1f3f5"
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 0.5
                        font.family: "Barlow Condensed"
                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: card.message
                        color: "#aab3c1"
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        font.family: "Share Tech Mono"
                    }

                    Text {
                        visible: text.length > 0
                        text: card.time
                        color: BriechTheme.mutedColor
                        font.pixelSize: 9
                        font.family: "Share Tech Mono"
                    }
                }

                Text {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 12
                    anchors.topMargin: 9
                    text: "✕"
                    color: closeArea.containsMouse ? BriechTheme.textColor : BriechTheme.mutedColor
                    font.pixelSize: 13
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.model.remove(card.index)
                }
            }
        }
    }
}
