import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Window {
    id: root
    width: 1200
    height: 700
    visible: true
    title: qsTr("Briech Ground Control Software")
    color: "#0f0f0f"

    // --- CONNECTION STATE ---
    // Change this to 'false' to see the state from Screenshot 2026-05-05 at 10.50.32.png
    property bool isConnected: true

    FontLoader {
        id: logoFont
        source: "qrc:/fonts/Geo-Regular"
        onStatusChanged: {
            if (status === FontLoader.Ready) {
                console.log("Logo font loaded:", name)
            } else if (status === FontLoader.Error) {
                console.warn("Logo font failed to load:", source)
            }
        }
    }

    // --- MAIN HEADER (Branding) ---
    Rectangle {
        id: header
        width: parent.width; height: 60
        color: "#000000"; z: 10

        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20

            Row {
                spacing: 12; Layout.alignment: Qt.AlignVCenter
                Rectangle {
                    width: 30; height: 30; color: "transparent"; radius: 4
                    border.color: "#FFBF00"; border.width: 1
                    Text { text: "B"; anchors.centerIn: parent; font.bold: true; color: "#FFBF00"; font.pixelSize: 18 }
                }
                Text {
                    id: mainTitle
                    text: "BRIECH UAS"
                    color: "white"; font.pixelSize: 24; font.weight: Font.ExtraBold
                    font.family: logoFont.status === FontLoader.Ready ? logoFont.name : (geoFontFamily || "Arial")
                }
            }
            Item { Layout.fillWidth: true }
            Text { text: "16:51:11"; color: "#888888"; font.pixelSize: 12 }
        }
        Rectangle { width: parent.width; height: 1; color: "#222222"; anchors.bottom: parent.bottom }
    }

    // --- DYNAMIC VIEW TOOLBAR (Telemetry + Navigation) ---
    Rectangle {
        id: viewToolbar
        width: parent.width; height: 50
        color: "#151515"
        anchors.top: header.bottom; z: 9

        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20
            spacing: 20

            // LEFT SIDE: Connection Status & Telemetry
            Row {
                spacing: 15; Layout.alignment: Qt.AlignVCenter

                // Status Indicator Dot
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: root.isConnected ? "#4CAF50" : "#555555"
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        running: root.isConnected; loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.4; duration: 800 }
                        NumberAnimation { from: 0.4; to: 1.0; duration: 800 }
                    }
                }

                // Connection Text
                Text {
                    text: root.isConnected ? "BRCH-01 — Damisa VTOL — AUTO MISSION" : "Disconnected — Click to manually connect"
                    color: "white"; font.pixelSize: 14; font.weight: Font.Medium
                }

                // Message Icon
                Text { text: "🗨"; color: "#888888"; font.pixelSize: 16 }

                // Separator before Telemetry
                Rectangle { width: 1; height: 20; color: "#333333"; visible: root.isConnected }

                // Telemetry Data Group (Matches Screenshot 2026-05-05 at 10.51.07.png)
                Row {
                    spacing: 20; visible: root.isConnected

                    // Simple helper for telemetry labels
                    function telemetry(icon, val, unit, color) {
                        return { i: icon, v: val, u: unit, c: color || "white" }
                    }

                    property var stats: [
                        telemetry("↑", "124.3", "m"),
                        telemetry("↕", "+1.1", "m/s", "#4CAF50"),
                        telemetry("→", "17.8", "m/s"),
                        telemetry("✦", "12", "GPS", "#4CAF50"),
                        telemetry("⚡", "82%", "BATT", "#4CAF50")
                    ]

                    Repeater {
                        model: parent.stats
                        Row {
                            spacing: 5
                            Text { text: modelData.i; color: "#888888"; font.pixelSize: 12 }
                            Text { text: modelData.v; color: modelData.c; font.pixelSize: 14; font.bold: true }
                            Text { text: modelData.u; color: "#888888"; font.pixelSize: 10; anchors.baseline: parent.baseline }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true } // Pushes Nav to the right

            // RIGHT SIDE: View Navigation (FLY, PLAN, etc.)
            Row {
                spacing: 30; Layout.alignment: Qt.AlignVCenter
                Repeater {
                    model: ["FLY", "PLAN", "ANALYZE", "VEHICLE"]
                    Text {
                        id: navText
                        text: modelData
                        color: (mouseArea.containsMouse || (modelData === "PLAN")) ? "#FFBF00" : "#888888"
                        font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 1

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData === "FLY") mainStack.replace("Home.qml")
                                else if (modelData === "PLAN") mainStack.replace("Plan.qml")
                            }
                        }

                        Rectangle {
                            anchors.top: parent.bottom; anchors.topMargin: 4
                            width: parent.width; height: 2; color: "#FFBF00"
                            visible: mouseArea.containsMouse || (modelData === "PLAN")
                        }
                    }
                }
            }
        }
    }

    StackView {
        id: mainStack
        anchors.top: viewToolbar.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        initialItem: Rectangle { color: "#111111"; Text { text: "PLAN VIEW"; color: "white"; anchors.centerIn: parent } }
    }
}
