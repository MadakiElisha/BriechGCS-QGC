import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root

    property string dialogTitle: ""
    property string dialogMessage: ""
    property string accent: "#c9a84c"
    property string acceptText: "ACKNOWLEDGE"
    property string cancelText: "CANCEL"
    property bool confirmation: false
    property var acceptCallback: null

    modal: true
    focus: true
    // A confirmation must be dismissed deliberately. Escape remains a safe
    // cancel path, while click-outside cannot accidentally discard a warning
    // or obscure which action is pending.
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    width: Math.min(520, Math.max(320, Overlay.overlay ? Overlay.overlay.width - 64 : 520))
    padding: 0

    function showInfo(title, message, tone) {
        dialogTitle = title || "BRIECH UAS"
        dialogMessage = message || ""
        accent = tone || "#c9a84c"
        acceptText = "ACKNOWLEDGE"
        confirmation = false
        acceptCallback = null
        open()
    }

    function showConfirmation(title, message, callback, confirmLabel, tone) {
        dialogTitle = title || "CONFIRM ACTION"
        dialogMessage = message || ""
        accent = tone || "#c9a84c"
        acceptText = confirmLabel || "CONFIRM"
        confirmation = true
        acceptCallback = callback
        open()
    }

    function accept() {
        const callback = acceptCallback
        close()
        if (callback) {
            callback()
        }
    }

    onOpened: {
        // Never make a destructive confirmation the default keyboard action.
        // Informational prompts can focus their sole acknowledgement button.
        if (confirmation) {
            cancelButton.forceActiveFocus()
        } else {
            acceptButton.forceActiveFocus()
        }
    }

    background: Rectangle {
        color: "#080d14"
        border.color: root.accent
        border.width: 1
        radius: 3

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 3
            color: root.accent
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: "#0d1622"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: root.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: root.dialogTitle.toUpperCase()
                    color: "#f2e3b0"
                    font.family: "monospace"
                    font.bold: true
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Text {
                    text: "BRIECH UAS"
                    color: "#77869a"
                    font.family: "monospace"
                    font.pixelSize: 9
                    font.bold: true
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.margins: 18
            text: root.dialogMessage
            color: "#d8dde6"
            font.family: "Segoe UI"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            lineHeight: 1.25
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#273446"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 14
            spacing: 10

            Item { Layout.fillWidth: true }

            Button {
                id: cancelButton
                visible: root.confirmation
                text: root.cancelText
                implicitWidth: 108
                implicitHeight: 34
                onClicked: root.close()

                contentItem: Text {
                    text: parent.text
                    color: "#a8b3c2"
                    font.family: "monospace"
                    font.bold: true
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: "#111925"
                    border.color: "#3b485b"
                    border.width: 1
                    radius: 2
                }
            }

            Button {
                id: acceptButton
                text: root.acceptText
                implicitWidth: root.confirmation ? 128 : 132
                implicitHeight: 34
                onClicked: root.confirmation ? root.accept() : root.close()

                contentItem: Text {
                    text: parent.text
                    color: "#05070a"
                    font.family: "monospace"
                    font.bold: true
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: root.accent
                    radius: 2
                }
            }
        }
    }
}
