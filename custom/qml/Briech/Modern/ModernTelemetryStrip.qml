pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import QGroundControl

// Thin telemetry strip under the Modern view header (Fly section): mission
// progress and flight values on the left, battery and mode on the right.
// Every value comes from the active vehicle or the view's mission helpers;
// anything QGC does not provide is shown as "--".
Rectangle {
    id: control

    /// The BriechModernView root; supplies the vehicle, helpers and colour tokens.
    required property var view

    readonly property var vehicle: view.activeVehicle

    implicitHeight: 36
    color: view.modernGlass
    border.color: view.modernHairline
    border.width: 1

    function factNumber(fact) {
        if (!vehicle || !fact) {
            return NaN
        }
        return Number(fact.rawValue)
    }

    function fixed(fact, decimals, unit) {
        const value = factNumber(fact)
        return isNaN(value) ? "--" : value.toFixed(decimals) + " " + unit
    }

    function waypointText() {
        if (!view.missionTimelineAvailable()) {
            return "-- / --"
        }
        const total = view.missionCoordinates.length
        const current = view.missionTimelineComplete() ? total : Math.min(view.missionTimelineLiveIndex() + 1, total)
        return current + " / " + total
    }

    function distanceToWaypointText() {
        if (!vehicle || !vehicle.coordinate.isValid || !view.missionTimelineAvailable() || view.missionTimelineComplete()) {
            return "--"
        }
        const target = view.missionCoordinateAt(view.missionTimelineLiveIndex())
        return target && target.isValid ? view.formatMissionDistance(vehicle.coordinate.distanceTo(target)) : "--"
    }

    function headingText() {
        const heading = factNumber(vehicle ? vehicle.heading : null)
        return isNaN(heading) ? "--" : ("000" + ((Math.round(heading) % 360 + 360) % 360)).slice(-3) + "°"
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        StripCell { label: "WP"; value: control.waypointText(); valueTone: control.view.ok }
        StripCell { label: "ALTITUDE"; value: control.fixed(control.vehicle ? control.vehicle.altitudeRelative : null, 1, "m") }
        StripCell { label: "AIRSPEED"; value: control.fixed(control.vehicle ? control.vehicle.airSpeed : null, 1, "m/s") }
        StripCell { label: "GROUNDSPD"; value: control.fixed(control.vehicle ? control.vehicle.groundSpeed : null, 1, "m/s") }
        StripCell { label: "HEADING"; value: control.headingText() }
        StripCell {
            label: "DIST HOME"
            value: control.view.formatMissionDistance(control.factNumber(control.vehicle ? control.vehicle.distanceToHome : null))
        }
        StripCell { label: "DIST WP"; value: control.distanceToWaypointText() }
        StripCell { label: "TIME"; value: control.view.flightTimeText() }

        Item { Layout.fillWidth: true }

        StripCell {
            label: "BATTERY"
            value: control.view.batteryPercentText()
            valueTone: {
                const percent = control.view.currentBatteryPercent()
                return isNaN(percent) ? control.view.dim : (percent > 30 ? control.view.ok : (percent > 20 ? control.view.warn : control.view.err))
            }
        }
        StripCell {
            label: "MODE"
            value: control.view.flightModeText().toUpperCase() + (clickable ? " ▾" : "")
            valueTone: control.view.ok
            clickable: control.view.flightModeOptions().length > 0
            onClicked: stripModeMenu.opened ? stripModeMenu.close() : stripModeMenu.open()

            ModernFlightModeMenu {
                id: stripModeMenu
                view: control.view
                y: parent.height + 2
                // Keep the menu on screen: this cell sits at the right edge.
                x: parent.width - width
            }
        }
    }

    // One strip cell: small uppercase label above a mono value.
    component StripCell: Rectangle {
        id: cell

        signal clicked()

        property string label
        property string value: "--"
        property color valueTone: control.view.text
        property bool clickable: false

        Layout.fillHeight: true
        Layout.preferredWidth: Math.max(76, Math.max(labelText.implicitWidth, valueText.implicitWidth) + 22)
        color: clickable && cellMouse.containsMouse ? control.view.modernGlassSoft : "transparent"
        border.color: control.view.modernHairline
        border.width: 1

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                id: labelText
                text: cell.label
                color: control.view.dim
                font.pixelSize: 9
                font.family: "Share Tech Mono"
                font.letterSpacing: 1
            }

            Text {
                id: valueText
                text: cell.value
                color: cell.valueTone
                font.pixelSize: 13
                font.bold: true
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
}
