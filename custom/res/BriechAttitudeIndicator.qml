pragma ComponentBehavior: Bound

import QtQuick

import QGroundControl
import QGroundControl.Controls
import Custom.Widgets 1.0

Item {
    id: root

    property var vehicle: null
    property real size: 320
    property bool showHeading: true

    readonly property real _rollAngle: vehicle ? vehicle.roll.rawValue : 0
    readonly property real _pitchAngle: vehicle ? vehicle.pitch.rawValue : 0
    readonly property string _iasText: vehicle ? vehicle.airSpeed.valueString : "0.0"
    readonly property string _altText: vehicle ? vehicle.altitudeRelative.valueString : "0.0"
    readonly property string _vsiText: vehicle ? vehicle.climbRate.valueString : "0.0"
    readonly property string _headingText: vehicle ? vehicle.heading.rawValue.toFixed(0) : "OFF"

    function batteryPercent() {
        if (!vehicle) {
            return 0
        }
        if (vehicle.battery && vehicle.battery.percentRemaining) {
            const pct = Number(vehicle.battery.percentRemaining.rawValue)
            return isNaN(pct) ? 0 : Math.max(0, Math.min(100, pct))
        }
        return 0
    }

    width: size
    height: size

    Item {
        id: instrument
        anchors.fill: parent

        CustomArtificialHorizon {
            anchors.fill: parent
            rollAngle: root._rollAngle
            pitchAngle: root._pitchAngle
            skyColor1: "#0a2e50"
            skyColor2: "#2f85d4"
            groundColor1: "#897459"
            groundColor2: "#4b3820"
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.35)
            border.width: 1
            radius: width / 2
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: width * 0.04
            width: parent.width * 0.24
            height: parent.height * 0.50
            color: Qt.rgba(0.04, 0.05, 0.07, 0.78)
            border.color: Qt.rgba(201/255, 168/255, 76/255, 0.35)
            border.width: 1
            radius: 2

            Column {
                anchors.centerIn: parent
                spacing: 0

                Text {
                    text: "IAS"
                    color: BriechTheme.goldAccent
                    font.family: "monospace"
                    font.pixelSize: 8
                    font.bold: true
                }

                        Text {
                            text: root._iasText
                    color: BriechTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: parent.width * 0.18
                    font.bold: true
                }

                Text {
                    text: "m/s"
                    color: BriechTheme.mutedColor
                    font.family: "monospace"
                    font.pixelSize: 7
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: width * 0.04
            width: parent.width * 0.24
            height: parent.height * 0.50
            color: Qt.rgba(0.04, 0.05, 0.07, 0.78)
            border.color: Qt.rgba(201/255, 168/255, 76/255, 0.35)
            border.width: 1
            radius: 2

            Column {
                anchors.centerIn: parent
                spacing: 0

                Text {
                    text: "ALT"
                    color: BriechTheme.goldAccent
                    font.family: "monospace"
                    font.pixelSize: 8
                    font.bold: true
                }

                        Text {
                            text: root._altText
                    color: BriechTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: parent.width * 0.18
                    font.bold: true
                }

                Text {
                    text: "m"
                    color: BriechTheme.mutedColor
                    font.family: "monospace"
                    font.pixelSize: 7
                }

                Rectangle {
                    width: parent.width * 0.72
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 3
                }

                Text {
                    text: "VSI " + root._vsiText
                    color: BriechTheme.blueColor
                    font.family: "monospace"
                    font.pixelSize: 8
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 4
                }
            }
        }

        Canvas {
            id: batteryArc
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: width * 0.07
            anchors.bottomMargin: height * 0.07
            width: parent.width * 0.22
            height: width

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                const pct = root.batteryPercent() / 100.0
                const cx = width / 2
                const cy = height / 2
                const r = Math.min(width, height) * 0.40
                const start = -Math.PI * 0.75
                const end = start + Math.PI * 1.5 * pct

                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + Math.PI * 1.5)
                ctx.strokeStyle = "rgba(255,255,255,0.14)"
                ctx.lineWidth = 3
                ctx.stroke()

                ctx.beginPath()
                ctx.arc(cx, cy, r, start, end)
                ctx.strokeStyle = pct > 0.4 ? "#22c55e" : (pct > 0.2 ? "#f59e0b" : "#ef4444")
                ctx.lineWidth = 3
                ctx.stroke()
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: height * 0.06
            width: parent.width * 0.34
            height: parent.height * 0.08
            color: Qt.rgba(0.05, 0.06, 0.08, 0.82)
            border.color: Qt.rgba(201/255, 168/255, 76/255, 0.35)
            border.width: 1
            radius: 2
            visible: root.showHeading

            Text {
                anchors.centerIn: parent
                text: root._headingText
                color: BriechTheme.textColor
                font.family: "monospace"
                font.pixelSize: parent.height * 0.48
                font.bold: true
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.12
            height: 2
            color: BriechTheme.textColor
        }

        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: parent.height * 0.06
            color: BriechTheme.goldAccent
            anchors.topMargin: -2
        }
    }
}
