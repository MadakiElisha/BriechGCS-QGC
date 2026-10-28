pragma ComponentBehavior: Bound

import QtQuick

// Map type picker pinned to the top-right of the Fly map: SATELLITE, STREET,
// TERRAIN and HYBRID, each with a small drawn thumbnail; the selected type is
// gold. Uses the view's existing map-type logic (setModernMapKind).
Column {
    id: root

    /// The BriechModernView root; supplies the map-type helpers and colour tokens.
    required property var view

    readonly property var kinds: [
        { key: "satellite", label: "SATELLITE" },
        { key: "street", label: "STREET" },
        { key: "terrain", label: "TERRAIN" },
        { key: "hybrid", label: "HYBRID" }
    ]

    width: 134
    spacing: 2

    Repeater {
        model: root.kinds

        delegate: Rectangle {
            id: row

            required property var modelData

            readonly property bool selected: root.view.selectedMapKind === modelData.key
            readonly property bool available: root.view.findModernMapType(modelData.key) !== null

            width: root.width
            height: 34
            radius: 2
            color: selected ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.10) : (rowArea.containsMouse ? "#121720" : root.view.modernGlassStrong)
            border.color: selected ? root.view.gold : root.view.modernHairline
            border.width: 1
            opacity: available ? 1 : 0.45

            Canvas {
                id: thumbnail
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 18

                onPaint: {
                    const ctx = getContext("2d")
                    const kind = row.modelData.key
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = kind === "street" ? "#1b2433" : (kind === "terrain" ? "#26301f" : "#1e3a24")
                    ctx.fillRect(0, 0, width, height)
                    ctx.lineWidth = 1
                    if (kind === "satellite" || kind === "hybrid") {
                        ctx.fillStyle = "#2f5a33"
                        ctx.fillRect(3, 3, 8, 6)
                        ctx.fillRect(15, 9, 8, 6)
                    }
                    if (kind === "street" || kind === "hybrid") {
                        ctx.strokeStyle = kind === "street" ? "#6b84a8" : "#c9d3e0"
                        ctx.beginPath()
                        ctx.moveTo(0, height / 2); ctx.lineTo(width, height / 2)
                        ctx.moveTo(width / 2, 0); ctx.lineTo(width / 2, height)
                        ctx.stroke()
                    }
                    if (kind === "terrain") {
                        ctx.strokeStyle = "#7f9a5a"
                        ctx.beginPath()
                        ctx.moveTo(0, 13); ctx.lineTo(7, 7); ctx.lineTo(12, 10); ctx.lineTo(19, 4); ctx.lineTo(width, 9)
                        ctx.stroke()
                    }
                    ctx.strokeStyle = "#3a4250"
                    ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
                }
            }

            Text {
                anchors.left: thumbnail.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label
                color: row.selected ? root.view.gold : root.view.text
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
                font.family: "Share Tech Mono"
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: row.available
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.view.setModernMapKind(row.modelData.key)
            }
        }
    }
}
