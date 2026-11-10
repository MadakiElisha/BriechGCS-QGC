import QtQuick

import QGroundControl
import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// Attitude view (handoff, section 8): the selected drone's roll, pitch and
// heading, read from QGC's own Vehicle data. It rides the flight path, so it
// needs no coordinator.
//
//   - 3D: FlightGhostScene.qml, loaded only while this view is open, and only
//     when the build has Qt Quick 3D (FleetSettings.quick3DAvailable) and the
//     operator chose 3D (FleetSettings.prefer3D).
//   - 2D: QGC-style attitude indicator (BriechAttitudeIndicator), used when
//     Quick3D is missing, when the scene fails to load, or by choice.
//
// The view follows the active vehicle. PIN keeps it on the vehicle shown at
// that moment, whichever vehicle is active later. There is no pop-out window:
// the project keeps to one top-level window (the handoff lists the pop-out as
// the first thing to cut).
Rectangle {
    id: root

    signal closeRequested()

    readonly property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool pinned: false
    property var pinnedVehicle: null
    // A pinned vehicle that disconnects becomes null, and the view goes back
    // to following the active vehicle.
    readonly property var vehicle: pinned && pinnedVehicle ? pinnedVehicle : activeVehicle

    property bool sceneFailed: false
    readonly property bool show3D: FleetSettings.quick3DAvailable && FleetSettings.prefer3D && !sceneFailed

    readonly property int ageLevel: vehicle ? FleetFormat.vehicleAgeLevel(FleetDataAge.levels, vehicle.id) : FleetFormat.ageUnknown
    readonly property bool stale: ageLevel === FleetFormat.ageGrey

    function angleText(fact) {
        const value = fact ? Number(fact.rawValue) : NaN
        return isNaN(value) ? "--" : value.toFixed(0) + "°"
    }

    function headingText(fact) {
        const value = fact ? Number(fact.rawValue) : NaN
        return isNaN(value) ? "---" : ("000" + ((Math.round(value) % 360 + 360) % 360)).slice(-3)
    }

    width: 300
    height: 280
    radius: 2
    color: "#080a0e"
    border.color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.25)
    border.width: 1

    // Keep clicks and scrolls on the panel from reaching the map underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: (wheel) => wheel.accepted = true
    }

    // Title bar: name, 3D/2D, PIN, close.
    Item {
        id: titleBar
        x: 1
        y: 1
        width: parent.width - 2
        height: 30

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "ATTITUDE · " + (root.vehicle ? "BRCH-" + root.vehicle.id : "--")
            color: BriechTheme.goldAccent
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.2
            font.family: "Share Tech Mono"
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            TitleButton {
                visible: FleetSettings.quick3DAvailable
                label: FleetSettings.prefer3D ? "3D" : "2D"
                lit: FleetSettings.prefer3D && !root.sceneFailed
                onClicked: {
                    root.sceneFailed = false
                    FleetSettings.prefer3D = !FleetSettings.prefer3D
                }
            }

            TitleButton {
                label: "PIN"
                lit: root.pinned
                enabled: root.pinned || !!root.vehicle
                onClicked: {
                    root.pinnedVehicle = root.pinned ? null : root.vehicle
                    root.pinned = !root.pinned
                }
            }

            TitleButton {
                label: "✕"
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

    // View: 3D scene or 2D indicator.
    Item {
        id: viewArea
        x: 1
        anchors.top: titleBar.bottom
        anchors.bottom: footer.top
        width: parent.width - 2
        clip: true
        opacity: root.stale ? 0.55 : 1

        Loader {
            id: sceneLoader
            anchors.fill: parent
            active: root.show3D && root.visible && !!root.vehicle
            // Loaded by URL, not as a component, so a build without Qt Quick 3D
            // never parses the file.
            source: "qrc:/Briech/qml/Fleet/FlightGhostScene.qml"
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.warn("Fleet 3D view could not load; showing the 2D indicator")
                    root.sceneFailed = true
                }
            }
        }

        Binding {
            target: sceneLoader.item
            property: "vehicle"
            value: root.vehicle
            when: sceneLoader.status === Loader.Ready
        }

        Loader {
            anchors.centerIn: parent
            active: !root.show3D && root.visible && !!root.vehicle
            sourceComponent: BriechAttitudeIndicator {
                vehicle: root.vehicle
                size: Math.min(viewArea.width, viewArea.height) - 12
                showHeading: true
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !root.vehicle
            text: "NO VEHICLE"
            color: BriechTheme.mutedColor
            font.pixelSize: 11
            font.bold: true
            font.family: "Share Tech Mono"
        }
    }

    // Footer: the numbers the view shows, and how old they are.
    Row {
        id: footer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        anchors.left: parent.left
        anchors.leftMargin: 10
        spacing: 12

        Repeater {
            model: [
                { k: "ROLL", v: root.vehicle ? root.angleText(root.vehicle.roll) : "--" },
                { k: "PITCH", v: root.vehicle ? root.angleText(root.vehicle.pitch) : "--" },
                { k: "HDG", v: root.vehicle ? root.headingText(root.vehicle.heading) : "---" }
            ]

            delegate: Row {
                required property var modelData
                spacing: 4

                Text {
                    text: parent.modelData.k
                    color: BriechTheme.mutedColor
                    font.pixelSize: 9
                    font.family: "Share Tech Mono"
                }

                Text {
                    text: parent.modelData.v
                    color: BriechTheme.textColor
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "Share Tech Mono"
                }
            }
        }

        Text {
            text: root.vehicle
                  ? FleetFormat.ageText(FleetFormat.vehicleAgeSeconds(FleetDataAge.seconds, root.vehicle.id))
                    + (root.stale ? " STALE" : "")
                  : "--"
            color: FleetFormat.ageTone(root.ageLevel, BriechTheme)
            font.pixelSize: 10
            font.bold: root.ageLevel === FleetFormat.ageAmber
            font.family: "Share Tech Mono"
        }
    }

    component TitleButton: Rectangle {
        id: button

        signal clicked()
        property string label
        property bool lit: false

        width: Math.max(24, buttonText.implicitWidth + 12)
        height: 18
        radius: 2
        color: lit ? Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.18) : "transparent"
        border.color: lit ? BriechTheme.goldAccent : Qt.rgba(1, 1, 1, 0.18)
        border.width: 1
        opacity: enabled ? 1 : 0.4

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.label
            color: button.lit ? BriechTheme.goldAccent : (buttonArea.containsMouse ? BriechTheme.textColor : BriechTheme.mutedColor)
            font.pixelSize: 9
            font.bold: true
            font.family: "Share Tech Mono"
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
