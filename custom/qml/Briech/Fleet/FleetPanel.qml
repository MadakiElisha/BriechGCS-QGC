pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// Fleet list: one card per vehicle QGC is connected to. Clicking a card makes
// that vehicle the active one, which is the vehicle every command acts on.
// Until FleetLink exists this lists QGC vehicles only, with live values.
// FleetLayer draws the frame around this and the other Fleet sections.
Item {
    id: root

    signal closeRequested()
    signal vehicleFocused(var vehicle)

    /// Tallest the panel may grow before the card list scrolls.
    property real maximumHeight: 600

    readonly property var vehicles: QGroundControl.multiVehicleManager.vehicles
    readonly property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    // Link percentages, sampled once a second (see FleetFormat.linkPercent).
    property var linkPercents: ({})

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.linkPercents = FleetFormat.sampleLinkPercents(root.vehicles)
    }

    width: 250
    height: Math.min(maximumHeight, header.height + cardList.contentHeight)

    Column {
        anchors.fill: parent

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

            // Opens or closes the attitude view (Fleet3DView) beside the panel.
            Rectangle {
                anchors.right: closeText.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: attitudeText.implicitWidth + 12
                height: 18
                radius: 2
                color: FleetSettings.attitudeViewOpen ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.18) : "transparent"
                border.color: FleetSettings.attitudeViewOpen ? BriechTheme.goldAccent : Qt.rgba(1, 1, 1, 0.18)
                border.width: 1

                Text {
                    id: attitudeText
                    anchors.centerIn: parent
                    text: "3D"
                    color: FleetSettings.attitudeViewOpen ? BriechTheme.goldAccent
                         : (attitudeArea.containsMouse ? BriechTheme.textColor : BriechTheme.mutedColor)
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "Share Tech Mono"
                }

                MouseArea {
                    id: attitudeArea
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: FleetSettings.attitudeViewOpen = !FleetSettings.attitudeViewOpen
                }
            }

            Text {
                id: closeText
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
            height: root.height - header.height
            clip: true
            model: root.vehicles
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: cardList.contentHeight > cardList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

            delegate: FleetVehicleCard {
                width: cardList.width
            }
        }
    }

    // One vehicle: identity, status pill, battery ring, live values, battery bar.
    component FleetVehicleCard: Rectangle {
        id: card

        required property var object

        readonly property bool isActive: object === root.activeVehicle
        readonly property real battery: FleetFormat.batteryPercent(object)
        readonly property color batteryTone: FleetFormat.batteryTone(battery, BriechTheme)
        readonly property real link: FleetFormat.sampledLink(root.linkPercents, card.object.id)
        readonly property bool batteryLow: !isNaN(battery) && battery < FleetFormat.lowBatteryPercent
        // Data age, from FleetDataAge once a second: amber after 3 s, grey and
        // stale after 10 s. A stale card is dimmed: its values are not current.
        readonly property int ageLevel: FleetFormat.vehicleAgeLevel(FleetDataAge.levels, object.id)
        readonly property var ageSeconds: FleetFormat.vehicleAgeSeconds(FleetDataAge.seconds, object.id)
        readonly property bool stale: ageLevel === FleetFormat.ageGrey

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
                opacity: card.stale ? 0.55 : 1

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

                // How long ago this drone was last heard.
                Text {
                    text: FleetFormat.ageText(card.ageSeconds)
                    color: FleetFormat.ageTone(card.ageLevel, BriechTheme)
                    font.pixelSize: 9
                    font.bold: card.ageLevel === FleetFormat.ageAmber
                    font.family: "Share Tech Mono"
                }

                // Status pill: stale outranks battery low, which outranks armed / standby.
                Rectangle {
                    readonly property color tone: card.stale ? BriechTheme.mutedColor
                                                : card.batteryLow ? BriechTheme.errColor
                                                : (card.object.armed ? BriechTheme.okColor : BriechTheme.blueColor)
                    Layout.preferredWidth: pillText.implicitWidth + 12
                    Layout.preferredHeight: 16
                    radius: 2
                    color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
                    border.color: tone
                    border.width: 1

                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: card.stale ? "STALE" : card.batteryLow ? "BATT LOW" : (card.object.armed ? "ARMED" : "STANDBY")
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
                        text: FleetFormat.batteryText(card.battery)
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
                opacity: card.stale ? 0.55 : 1
                rowSpacing: 3
                columnSpacing: 6

                CardValue { label: "ALT"; value: FleetFormat.factText(card.object.altitudeRelative, 1, "m") }
                CardValue { label: "ASPD"; value: FleetFormat.factText(card.object.airSpeed, 1, "") }
                CardValue {
                    label: "BATT"
                    value: FleetFormat.batteryText(card.battery)
                    tone: card.batteryTone
                }
                CardValue { label: "HDG"; value: FleetFormat.headingText(card.object) }
                CardValue { label: "MODE"; value: String(card.object.flightMode).toUpperCase(); tone: BriechTheme.okColor }
                CardValue {
                    label: "LINK"
                    value: isNaN(card.link) ? "--" : card.link + "%"
                    tone: FleetFormat.linkTone(card.link, BriechTheme)
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
