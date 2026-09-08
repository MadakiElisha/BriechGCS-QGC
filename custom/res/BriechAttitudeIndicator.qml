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
    property real pitchClampDegrees: 35
    property color frameColor: Qt.rgba(0.10, 0.14, 0.20, 0.96)
    property color bezelColor: Qt.rgba(0.80, 0.84, 0.90, 0.18)

    function factNumber(fact, fallback) {
        if (!fact) {
            return fallback
        }
        const value = Number(fact.rawValue)
        return isNaN(value) ? fallback : value
    }

    function factText(fact, fallback) {
        if (!fact || fact.valueString === undefined || fact.valueString === null || String(fact.valueString).length === 0) {
            return fallback
        }
        return fact.valueString
    }

    function normalizedHeadingText() {
        if (!vehicle || !vehicle.heading) {
            return "OFF"
        }
        const rawHeading = factNumber(vehicle.heading, NaN)
        if (isNaN(rawHeading)) {
            return "OFF"
        }
        const normalized = ((Math.round(rawHeading) % 360) + 360) % 360
        return ("000" + normalized).slice(-3)
    }

    function iasDisplayText() {
        if (!vehicle) {
            return "--"
        }
        const airspeed = factNumber(vehicle.airSpeed, NaN)
        if (!isNaN(airspeed) && airspeed > 0.1) {
            return factText(vehicle.airSpeed, "--")
        }
        return factText(vehicle.groundSpeed, "--")
    }

    function altitudeDisplayText() {
        return vehicle ? factText(vehicle.altitudeRelative, "--") : "--"
    }

    function vsiDisplayText() {
        return vehicle ? factText(vehicle.climbRate, "--") : "--"
    }

    function speedLabelText() {
        if (!vehicle) {
            return "SPD"
        }
        const airspeed = factNumber(vehicle.airSpeed, NaN)
        return !isNaN(airspeed) && airspeed > 0.1 ? "IAS" : "GS"
    }

    readonly property real _rollAngle: vehicle ? factNumber(vehicle.roll, 0) : 0
    readonly property real _pitchAngle: vehicle ? factNumber(vehicle.pitch, 0) : 0
    readonly property string _iasText: iasDisplayText()
    readonly property string _altText: altitudeDisplayText()
    readonly property string _vsiText: vsiDisplayText()
    readonly property string _headingText: normalizedHeadingText()
    readonly property real _clampedPitch: Math.max(-pitchClampDegrees, Math.min(pitchClampDegrees, _pitchAngle))
    readonly property real _pitchOffset: (_clampedPitch / pitchClampDegrees) * (size * 0.18)

    function batteryPercent() {
        if (!vehicle) {
            return 0
        }
        if (vehicle.batteries && vehicle.batteries.count > 0) {
            let lowest = NaN
            for (let i = 0; i < vehicle.batteries.count; i++) {
                const battery = vehicle.batteries.get(i)
                const percent = battery && battery.percentRemaining ? Number(battery.percentRemaining.rawValue) : NaN
                if (!isNaN(percent) && (isNaN(lowest) || percent < lowest)) {
                    lowest = percent
                }
            }
            if (!isNaN(lowest)) {
                return Math.max(0, Math.min(100, lowest))
            }
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

        Rectangle {
            id: attitudeMask
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: root.frameColor
            border.color: root.bezelColor
            border.width: 1
            clip: true

            CustomArtificialHorizon {
                anchors.fill: attitudeMask
                rollAngle: root._rollAngle
                pitchAngle: root._pitchAngle
                skyColor1: "#1f4d82"
                skyColor2: "#3d77b8"
                groundColor1: "#82552a"
                groundColor2: "#70451d"
            }

            Repeater {
                model: [30, 20, 10, -10, -20, -30]

                delegate: Item {
                    required property int modelData
                    width: attitudeMask.width
                    height: attitudeMask.height
                    anchors.centerIn: parent
                    rotation: -root._rollAngle

                    readonly property real yOffset: (-modelData / root.pitchClampDegrees) * (attitudeMask.height * 0.18) + root._pitchOffset
                    readonly property real lineWidth: Math.abs(modelData) === 10 ? attitudeMask.width * 0.22 : attitudeMask.width * 0.17

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height * 0.5 + parent.yOffset
                        width: parent.lineWidth
                        height: 2
                        color: "#dbe7f5"
                    }

                    Text {
                        anchors.right: parent.horizontalCenter
                        anchors.rightMargin: parent.lineWidth * 0.55
                        y: parent.height * 0.5 + parent.yOffset - 8
                        text: Math.abs(parent.modelData)
                        color: "#dbe7f5"
                        font.family: "monospace"
                        font.pixelSize: 10
                        font.bold: true
                    }

                    Text {
                        anchors.left: parent.horizontalCenter
                        anchors.leftMargin: parent.lineWidth * 0.55
                        y: parent.height * 0.5 + parent.yOffset - 8
                        text: Math.abs(parent.modelData)
                        color: "#dbe7f5"
                        font.family: "monospace"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                y: root._pitchOffset
                width: parent.width * 0.78
                height: 2
                color: "#f2f7ff"
                rotation: -root._rollAngle
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: width * -0.06
            width: parent.width * 0.21
            height: parent.height * 0.26
            color: Qt.rgba(0.05, 0.07, 0.10, 0.94)
            border.color: Qt.rgba(201/255, 168/255, 76/255, 0.42)
            border.width: 1
            radius: 2

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    text: root.speedLabelText()
                    color: BriechTheme.goldAccent
                    font.family: "monospace"
                    font.pixelSize: 10
                    font.bold: true
                }

                Text {
                    text: root._iasText
                    color: BriechTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: parent.width * 0.24
                    font.bold: true
                }

                Text {
                    text: "m/s"
                    color: BriechTheme.mutedColor
                    font.family: "monospace"
                    font.pixelSize: 8
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.16
            height: 4
            color: "#f2f7ff"
        }

        Rectangle {
            anchors.centerIn: parent
            width: 3
            height: parent.height * 0.07
            color: BriechTheme.goldAccent
            anchors.verticalCenterOffset: 3
        }

        Item {
            anchors.centerIn: parent
            width: parent.width * 0.24
            height: parent.height * 0.08

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.36
                height: 3
                color: "#f2f7ff"
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.36
                height: 3
                color: "#f2f7ff"
            }

            Canvas {
                anchors.centerIn: parent
                width: parent.width * 0.30
                height: parent.height

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#f2f7ff"
                    ctx.lineWidth = 3
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.lineTo(width / 2, height - 2)
                    ctx.lineTo(width, 0)
                    ctx.stroke()
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.rightMargin: width * -0.02
            anchors.bottomMargin: height * -0.01
            width: parent.width * 0.23
            height: width
            radius: width / 2
            color: Qt.rgba(0.05, 0.07, 0.10, 0.94)
            border.color: Qt.rgba(201/255, 168/255, 76/255, 0.42)
            border.width: 1
            visible: root.showHeading
            clip: true

            Canvas {
                anchors.fill: parent
                anchors.margins: 6

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    const cx = width / 2
                    const cy = height / 2
                    const r = Math.min(width, height) * 0.44
                    const heading = root.factNumber(root.vehicle ? root.vehicle.heading : null, 0)

                    ctx.strokeStyle = "rgba(255,255,255,0.24)"
                    ctx.lineWidth = 1.2
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.stroke()

                    for (let deg = 0; deg < 360; deg += 30) {
                        const rel = (deg - heading) * Math.PI / 180
                        const inner = r * (deg % 90 === 0 ? 0.58 : 0.70)
                        const outer = r * 0.94
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.sin(rel) * inner, cy - Math.cos(rel) * inner)
                        ctx.lineTo(cx + Math.sin(rel) * outer, cy - Math.cos(rel) * outer)
                        ctx.stroke()
                    }

                    ctx.fillStyle = "#f2f7ff"
                    ctx.beginPath()
                    ctx.moveTo(cx, cy - r * 0.96)
                    ctx.lineTo(cx - 4, cy - r * 0.78)
                    ctx.lineTo(cx + 4, cy - r * 0.78)
                    ctx.closePath()
                    ctx.fill()
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 1

                Text {
                    text: root._headingText
                    color: BriechTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: parent.width * 0.18
                    font.bold: true
                }

                Text {
                    text: "HDG"
                    color: BriechTheme.goldAccent
                    font.family: "monospace"
                    font.pixelSize: 8
                    font.bold: true
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: height * 0.02
            width: parent.width * 0.70
            height: parent.height * 0.14
            color: Qt.rgba(0.05, 0.07, 0.10, 0.94)
            border.color: Qt.rgba(0.42, 0.50, 0.63, 0.42)
            border.width: 1
            radius: 0
            visible: root.showHeading

            Canvas {
                id: headingTape
                anchors.fill: parent
                anchors.margins: 4

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    const centerX = width / 2
                    const topPad = 6
                    const bottomY = height - 6
                    const heading = root.factNumber(root.vehicle ? root.vehicle.heading : null, 0)
                    const majorStep = 10
                    const pixelsPerDegree = width / 60

                    ctx.strokeStyle = "rgba(132,148,174,0.75)"
                    ctx.lineWidth = 1

                    for (let deg = -30; deg <= 30; deg += 5) {
                        const x = centerX + deg * pixelsPerDegree
                        const absolute = ((Math.round(heading + deg) % 360) + 360) % 360
                        const major = deg % majorStep === 0
                        const tickTop = major ? topPad + 6 : topPad + 12

                        ctx.beginPath()
                        ctx.moveTo(x, tickTop)
                        ctx.lineTo(x, bottomY)
                        ctx.stroke()

                        if (major) {
                            ctx.fillStyle = "#d8dee8"
                            ctx.font = "bold 11px monospace"
                            ctx.textAlign = "center"
                            ctx.fillText(("000" + absolute).slice(-3), x, 12)
                        }
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                width: parent.width * 0.14
                height: parent.height
                color: Qt.rgba(201/255, 168/255, 76/255, 0.12)
                border.color: Qt.rgba(201/255, 168/255, 76/255, 0.68)
                border.width: 1

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    text: root._headingText
                    color: BriechTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: 11
                    font.bold: true
                }

                Canvas {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    width: 12
                    height: 8

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = BriechTheme.goldAccent
                        ctx.beginPath()
                        ctx.moveTo(width / 2, height)
                        ctx.lineTo(0, 0)
                        ctx.lineTo(width, 0)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: width * -0.06
            width: parent.width * 0.21
            height: parent.height * 0.26
            color: Qt.rgba(0.05, 0.07, 0.10, 0.94)
            border.color: Qt.rgba(201/255, 168/255, 76/255, 0.42)
            border.width: 1
            radius: 2

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    text: "ALT"
                    color: BriechTheme.goldAccent
                    font.family: "monospace"
                    font.pixelSize: 10
                    font.bold: true
                }

                Text {
                    text: root._altText
                    color: BriechTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: parent.width * 0.24
                    font.bold: true
                }

                Text {
                    text: "m"
                    color: BriechTheme.mutedColor
                    font.family: "monospace"
                    font.pixelSize: 8
                }

                Text {
                    text: "VSI " + root._vsiText
                    color: "#6eb8ff"
                    font.family: "monospace"
                    font.pixelSize: 8
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
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
                ctx.strokeStyle = "rgba(255,255,255,0.18)"
                ctx.lineWidth = 4
                ctx.stroke()

                ctx.beginPath()
                ctx.arc(cx, cy, r, start, end)
                ctx.strokeStyle = pct > 0.4 ? "#22c55e" : (pct > 0.2 ? "#f59e0b" : "#ef4444")
                ctx.lineWidth = 4
                ctx.stroke()
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Qt.rgba(0.82, 0.88, 0.95, 0.20)
            border.width: 1
            radius: width / 2
        }
    }
}
