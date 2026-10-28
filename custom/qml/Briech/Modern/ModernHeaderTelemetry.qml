pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl

// Live readouts in the Modern view header: altitude, climb, ground speed, GPS,
// battery, flight mode (with the mode picker), armed state and a Trends popup.
// Every value comes from the active vehicle through the owning view's helpers.
RowLayout {
    id: control

    /// The BriechModernView root; supplies the vehicle, helpers and colour tokens.
    required property var view

    readonly property var vehicle: view.activeVehicle

    spacing: 0
    visible: !!vehicle

    function climbText() {
        if (!vehicle || !vehicle.climbRate) {
            return "--"
        }
        const climb = Number(vehicle.climbRate.rawValue)
        if (isNaN(climb)) {
            return "--"
        }
        return (climb >= 0 ? "+" : "") + climb.toFixed(1)
    }

    function gpsFixLevel() {
        if (!vehicle || !vehicle.gps || !vehicle.gps.lock) {
            return 0
        }
        const lock = Number(vehicle.gps.lock.rawValue)
        return isNaN(lock) ? 0 : lock
    }

    function gpsFixText() {
        const lock = gpsFixLevel()
        return lock >= 3 ? "3D" : (lock === 2 ? "2D" : "NO FIX")
    }

    function gpsCountText() {
        return vehicle && vehicle.gps && vehicle.gps.count ? vehicle.gps.count.valueString : "--"
    }

    function batteryTone() {
        const percent = view.currentBatteryPercent()
        if (isNaN(percent)) {
            return view.dim
        }
        return percent > 30 ? view.ok : (percent > 20 ? view.warn : view.err)
    }

    function armedText() {
        if (!vehicle) {
            return "--"
        }
        return vehicle.armed ? "ARMED" : String(view.vehicleReadyText()).toUpperCase()
    }

    function armedTone() {
        if (!vehicle) {
            return view.dim
        }
        if (vehicle.armed) {
            return view.gold
        }
        return view.vehicleCanArm() ? view.ok : view.warn
    }

    HeaderCell {
        icon: "↑"
        value: control.view.altitudeText()
        unit: "m"
    }

    HeaderCell {
        icon: "⇡"
        value: control.climbText()
        unit: "m/s"
    }

    HeaderCell {
        icon: "→"
        value: control.view.groundSpeedText()
        unit: "m/s"
    }

    HeaderCell {
        icon: "✦"
        iconTone: control.gpsFixLevel() >= 3 ? control.view.ok : (control.gpsFixLevel() === 2 ? control.view.warn : control.view.err)
        value: control.gpsCountText()
        unit: control.gpsFixText()
    }

    HeaderCell {
        icon: "ϟ"
        iconTone: control.batteryTone()
        value: control.view.batteryPercentText()
        valueTone: control.batteryTone()
        unit: "BATT"
    }

    HeaderCell {
        id: modeCell
        value: control.view.flightModeText()
        valueTone: control.view.ok
        unit: control.view.flightModeOptions().length > 0 ? "▾" : ""
        unitTone: control.view.gold
        clickable: control.view.flightModeOptions().length > 0
        onClicked: flightModePopup.opened ? flightModePopup.close() : flightModePopup.open()

        ModernFlightModeMenu {
            id: flightModePopup
            view: control.view
            y: parent.height + 2
        }
    }

    HeaderCell {
        value: control.armedText()
        valueTone: control.armedTone()
    }

    HeaderCell {
        id: trendsCell
        icon: "⌁"
        iconTone: trendsPopup.opened ? control.view.gold : control.view.dim
        value: "Trends"
        valueTone: trendsPopup.opened ? control.view.gold : control.view.text
        clickable: true
        onClicked: trendsPopup.opened ? trendsPopup.close() : trendsPopup.open()

        Popup {
            id: trendsPopup
            y: parent.height + 2
            width: 260
            padding: 10
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

            background: Rectangle {
                color: control.view.modernGlassStrong
                border.color: control.view.modernGoldHairline
                border.width: 1
                radius: 2
            }

            contentItem: Column {
                spacing: 8

                Text {
                    text: "LAST 40 S"
                    color: control.view.dim
                    font.pixelSize: 9
                    font.family: "Share Tech Mono"
                    font.letterSpacing: 1
                }

                TrendRow { label: "ALT"; unit: "m"; samples: control.view.altitudeHistory; tone: control.view.blue }
                TrendRow { label: "GS"; unit: "m/s"; samples: control.view.speedHistory; tone: control.view.gold }
                TrendRow { label: "BATT"; unit: "%"; samples: control.view.batteryHistory; tone: control.view.ok }
            }
        }
    }

    // One bordered header cell: optional icon, value, unit/label.
    component HeaderCell: Rectangle {
        id: cell

        signal clicked()

        property string icon: ""
        property color iconTone: control.view.dim
        property string value: "--"
        property color valueTone: control.view.text
        property string unit: ""
        property color unitTone: control.view.dim
        property bool clickable: false

        Layout.preferredWidth: Math.max(64, cellRow.implicitWidth + 22)
        Layout.fillHeight: true
        color: clickable && cellMouse.containsMouse ? control.view.modernGlassSoft : "transparent"
        border.color: control.view.modernHairline
        border.width: 1

        RowLayout {
            id: cellRow
            anchors.centerIn: parent
            spacing: 5

            Text {
                visible: cell.icon !== ""
                text: cell.icon
                color: cell.iconTone
                font.pixelSize: 12
                font.bold: true
            }

            Text {
                text: cell.value
                color: cell.valueTone
                font.pixelSize: 13
                font.bold: true
                font.family: "Share Tech Mono"
            }

            Text {
                visible: cell.unit !== ""
                text: cell.unit
                color: cell.unitTone
                font.pixelSize: 10
                font.family: "Share Tech Mono"
            }
        }

        MouseArea {
            id: cellMouse
            anchors.fill: parent
            enabled: cell.clickable
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: cell.clicked()
        }
    }

    // A labelled sparkline drawn from one of the view's sample histories.
    component TrendRow: RowLayout {
        id: trend

        property string label
        property string unit
        property var samples: []
        property color tone: control.view.gold

        implicitWidth: 240
        spacing: 8

        onSamplesChanged: sparkline.requestPaint()

        Text {
            Layout.preferredWidth: 34
            text: trend.label
            color: control.view.dim
            font.pixelSize: 10
            font.family: "Share Tech Mono"
        }

        Canvas {
            id: sparkline
            Layout.fillWidth: true
            Layout.preferredHeight: 26

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const values = trend.samples || []
                if (values.length < 2) {
                    return
                }
                let min = values[0]
                let max = values[0]
                for (let i = 1; i < values.length; i++) {
                    min = Math.min(min, values[i])
                    max = Math.max(max, values[i])
                }
                const span = max - min > 0.001 ? max - min : 1
                ctx.strokeStyle = trend.tone
                ctx.lineWidth = 1.5
                ctx.beginPath()
                for (let j = 0; j < values.length; j++) {
                    const x = j / (values.length - 1) * width
                    const y = height - 2 - (values[j] - min) / span * (height - 4)
                    if (j === 0) {
                        ctx.moveTo(x, y)
                    } else {
                        ctx.lineTo(x, y)
                    }
                }
                ctx.stroke()
            }
        }

        Text {
            Layout.preferredWidth: 58
            horizontalAlignment: Text.AlignRight
            text: trend.samples && trend.samples.length > 0
                  ? Number(trend.samples[trend.samples.length - 1]).toFixed(1) + " " + trend.unit
                  : "--"
            color: control.view.text
            font.pixelSize: 10
            font.family: "Share Tech Mono"
        }
    }
}
