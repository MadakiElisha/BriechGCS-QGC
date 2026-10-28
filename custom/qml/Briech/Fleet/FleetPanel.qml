pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import Custom.Widgets 1.0

// Fleet list: one card per vehicle QGC is connected to. Clicking a card makes
// that vehicle the active one, which is the vehicle every command acts on.
// Until FleetLink exists this lists QGC vehicles only, with live values.
Rectangle {
    id: root

    signal closeRequested()
    signal vehicleFocused(var vehicle)

    /// Tallest the panel may grow before the card list scrolls.
    property real maximumHeight: 600

    readonly property var vehicles: QGroundControl.multiVehicleManager.vehicles
    readonly property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle

    width: 252
    height: Math.min(maximumHeight, header.height + cardList.contentHeight + statusRow.height + 2)
    radius: 2
    color: "#080a0e"
    border.color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.25)
    border.width: 1

    function batteryPercent(vehicle) {
        if (!vehicle || !vehicle.batteries || vehicle.batteries.count === 0) {
            return NaN
        }
        // Report the lowest pack, as the Modern view header does.
        let lowest = NaN
        for (let i = 0; i < vehicle.batteries.count; i++) {
            const battery = vehicle.batteries.get(i)
            const percent = battery && battery.percentRemaining ? Number(battery.percentRemaining.rawValue) : NaN
            if (!isNaN(percent) && (isNaN(lowest) || percent < lowest)) {
                lowest = percent
            }
        }
        return lowest
    }

    function batteryTone(percent) {
        if (isNaN(percent)) {
            return BriechTheme.mutedColor
        }
        return percent > 30 ? BriechTheme.okColor : (percent > 20 ? BriechTheme.warnColor : BriechTheme.errColor)
    }

    function linkPercent(vehicle) {
        const loss = vehicle ? Number(vehicle.mavlinkLossPercent) : NaN
        return isNaN(loss) ? NaN : Math.round(Math.max(0, Math.min(100, 100 - loss)))
    }

    function factText(fact, decimals, suffix) {
        if (!fact) {
            return "--"
        }
        const value = Number(fact.rawValue)
        return isNaN(value) ? "--" : value.toFixed(decimals) + suffix
    }

    Column {
        anchors.fill: parent
        anchors.margins: 1

        // Header: "FLEET — N VEHICLES" and close.
        Item {
            id: header
            width: parent.width
            height: 34

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "FLEET — " + root.vehicles.count + (root.vehicles.count === 1 ? " VEHICLE" : " VEHICLES")
                color: BriechTheme.goldAccent
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.5
                font.family: "Share Tech Mono"
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: closeArea.containsMouse ? BriechTheme.textColor : BriechTheme.mutedColor
                font.pixelSize: 12

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.075)
            }
        }

        ListView {
            id: cardList
            width: parent.width
            height: root.height - header.height - statusRow.height - 2
            clip: true
            model: root.vehicles
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: cardList.contentHeight > cardList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

            delegate: FleetVehicleCard {
                width: cardList.width
            }
        }

        // Honest status line: what is and is not wired up yet.
        Rectangle {
            id: statusRow
            width: parent.width
            height: 26
            color: "#05070a"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "COORDINATOR: NOT CONNECTED · 3D: " + (FleetSettings.quick3DAvailable ? "OK" : "2D")
                color: BriechTheme.mutedColor
                font.pixelSize: 8
                font.letterSpacing: 1
                font.family: "Share Tech Mono"
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
                    // Turning Fleet off deactivates the Loader that owns this panel.
                    onClicked: FleetSettings.enabled = false
                }
            }
        }
    }

    // One vehicle: identity, status pill, battery ring, live values, battery bar.
    component FleetVehicleCard: Rectangle {
        id: card

        required property var object

        readonly property bool isActive: object === root.activeVehicle
        readonly property real battery: root.batteryPercent(object)
        readonly property color batteryTone: root.batteryTone(battery)
        readonly property real link: root.linkPercent(object)
        readonly property bool batteryLow: !isNaN(battery) && battery < 20

        height: 112
        color: isActive ? "#11141b" : (cardArea.containsMouse ? "#0d1016" : "transparent")

        // Active vehicle marker.
        Rectangle {
            width: 3
            height: parent.height
            color: card.isActive ? BriechTheme.goldAccent : "transparent"
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            anchors.topMargin: 9
            spacing: 6

            RowLayout {
                width: parent.width
                spacing: 6

                Text {
                    text: "BRCH-" + card.object.id
                    color: BriechTheme.textColor
                    font.pixelSize: 15
                    font.bold: true
                    font.family: "Barlow Condensed"
                }

                Text {
                    Layout.fillWidth: true
                    text: String(card.object.vehicleTypeString).toUpperCase()
                    color: BriechTheme.mutedColor
                    elide: Text.ElideRight
                    font.pixelSize: 9
                    font.letterSpacing: 1
                    font.family: "Share Tech Mono"
                }

                // Status pill: battery low outranks armed / standby.
                Rectangle {
                    readonly property color tone: card.batteryLow ? BriechTheme.errColor : (card.object.armed ? BriechTheme.okColor : BriechTheme.blueColor)
                    Layout.preferredWidth: pillText.implicitWidth + 12
                    Layout.preferredHeight: 16
                    radius: 2
                    color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
                    border.color: tone
                    border.width: 1

                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: card.batteryLow ? "BATT LOW" : (card.object.armed ? "ARMED" : "STANDBY")
                        color: parent.tone
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1
                        font.family: "Share Tech Mono"
                    }
                }

                // Battery ring.
                Canvas {
                    id: ring
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30

                    property real percent: card.battery
                    property color tone: card.batteryTone
                    onPercentChanged: requestPaint()
                    onToneChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const r = width / 2 - 2
                        ctx.lineWidth = 3
                        ctx.strokeStyle = "#1f2631"
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
                        ctx.stroke()
                        if (!isNaN(percent)) {
                            ctx.strokeStyle = tone
                            ctx.beginPath()
                            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0, Math.min(100, percent)) / 100)
                            ctx.stroke()
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: isNaN(card.battery) ? "--" : Math.round(card.battery) + "%"
                        color: card.batteryTone
                        font.pixelSize: 7
                        font.bold: true
                        font.family: "Share Tech Mono"
                    }
                }
            }

            GridLayout {
                width: parent.width
                columns: 3
                rowSpacing: 3
                columnSpacing: 6

                CardValue { label: "ALT"; value: root.factText(card.object.altitudeRelative, 1, "m") }
                CardValue { label: "ASPD"; value: root.factText(card.object.airSpeed, 1, "") }
                CardValue {
                    label: "BATT"
                    value: isNaN(card.battery) ? "--" : Math.round(card.battery) + "%"
                    tone: card.batteryTone
                }
                CardValue {
                    label: "HDG"
                    value: {
                        const heading = card.object.heading ? Number(card.object.heading.rawValue) : NaN
                        return isNaN(heading) ? "--" : ("000" + ((Math.round(heading) % 360 + 360) % 360)).slice(-3) + "°"
                    }
                }
                CardValue { label: "MODE"; value: String(card.object.flightMode).toUpperCase(); tone: BriechTheme.okColor }
                CardValue {
                    label: "LINK"
                    value: isNaN(card.link) ? "--" : card.link + "%"
                    tone: isNaN(card.link) ? BriechTheme.mutedColor : (card.link >= 90 ? BriechTheme.okColor : (card.link >= 70 ? BriechTheme.warnColor : BriechTheme.errColor))
                }
            }
        }

        // Battery bar along the bottom of the card.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            anchors.bottomMargin: 6
            height: 2
            color: "#1f2631"

            Rectangle {
                width: isNaN(card.battery) ? 0 : parent.width * Math.max(0, Math.min(100, card.battery)) / 100
                height: parent.height
                color: card.batteryTone
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.05)
        }

        MouseArea {
            id: cardArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                // Commands always act on the active vehicle, so selecting a
                // card must make that vehicle active.
                if (card.object !== root.activeVehicle) {
                    QGroundControl.multiVehicleManager.activeVehicle = card.object
                }
                root.vehicleFocused(card.object)
            }
        }
    }

    component CardValue: Column {
        property string label
        property string value: "--"
        property color tone: BriechTheme.textColor

        Layout.fillWidth: true
        spacing: 0

        Text {
            text: parent.label
            color: BriechTheme.mutedColor
            font.pixelSize: 8
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }

        Text {
            text: parent.value
            color: parent.tone
            font.pixelSize: 12
            font.bold: true
            font.family: "Share Tech Mono"
        }
    }
}
