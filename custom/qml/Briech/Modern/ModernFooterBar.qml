pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import QGroundControl

// Status bar along the bottom of the Modern view: armed state and live flight
// values on the left, build version and ground-station position on the right.
Rectangle {
    id: control

    /// The BriechModernView root; supplies the vehicle, helpers and colour tokens.
    required property var view

    readonly property var vehicle: view.activeVehicle
    readonly property var gcsPosition: QGroundControl.qgcPositionManger.gcsPosition

    implicitHeight: 28
    color: "#05070a"

    function fixed(fact, decimals) {
        if (!vehicle || !fact) {
            return "--"
        }
        const value = Number(fact.rawValue)
        return isNaN(value) ? "--" : value.toFixed(decimals)
    }

    function climbText() {
        const text = fixed(vehicle ? vehicle.climbRate : null, 1)
        return text === "--" || text.charAt(0) === "-" ? text : "+" + text
    }

    function armedText() {
        if (!vehicle) {
            return "NO VEHICLE"
        }
        return vehicle.armed ? "ARMED" : "DISARMED"
    }

    function locationText() {
        if (!gcsPosition || !gcsPosition.isValid) {
            return ""
        }
        return "GCS " + gcsPosition.latitude.toFixed(4) + ", " + gcsPosition.longitude.toFixed(4)
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: control.view.gold
        opacity: 0.85
    }

    RowLayout {
        anchors.fill: parent
        anchors.rightMargin: 12
        spacing: 0

        FooterCell {
            value: control.armedText()
            valueTone: control.vehicle && control.vehicle.armed ? control.view.gold : control.view.dim
            bold: true
        }
        FooterCell { icon: "↑"; value: control.fixed(control.vehicle ? control.vehicle.altitudeRelative : null, 1); unit: "m" }
        FooterCell { icon: "⇡"; value: control.climbText(); unit: "m/s" }
        FooterCell { label: "AirSpd"; value: control.fixed(control.vehicle ? control.vehicle.airSpeed : null, 1); unit: "m/s" }
        FooterCell { icon: "→"; value: control.fixed(control.vehicle ? control.vehicle.groundSpeed : null, 1); unit: "m/s" }
        FooterCell { label: "Thr"; value: control.fixed(control.vehicle ? control.vehicle.throttlePct : null, 0); unit: "%" }
        FooterCell { icon: "◷"; value: control.view.flightTimeText() }

        Item { Layout.fillWidth: true }

        Text {
            text: "BRIECH UAS"
            color: control.view.gold
            font.bold: true
            font.pixelSize: 11
            font.letterSpacing: 1.5
            font.family: "Barlow Condensed"
        }

        Text {
            Layout.leftMargin: 8
            text: "GCS " + QGroundControl.qgcVersion
                  + (control.locationText() !== "" ? "  ·  " + control.locationText() : "")
            color: control.view.dim
            font.pixelSize: 10
            font.family: "Share Tech Mono"
        }
    }

    // One footer cell: optional icon or label, a value and a unit, with a divider.
    component FooterCell: Item {
        id: cell

        property string icon: ""
        property string label: ""
        property string value: "--"
        property color valueTone: control.view.text
        property string unit: ""
        property bool bold: false

        Layout.fillHeight: true
        Layout.preferredWidth: cellRow.implicitWidth + 24

        RowLayout {
            id: cellRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                visible: cell.icon !== "" || cell.label !== ""
                text: cell.icon !== "" ? cell.icon : cell.label
                color: control.view.dim
                font.pixelSize: 10
                font.family: "Share Tech Mono"
            }

            Text {
                text: cell.value
                color: cell.valueTone
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: cell.bold ? 1 : 0
                font.family: cell.bold ? "Barlow Condensed" : "Share Tech Mono"
            }

            Text {
                visible: cell.unit !== ""
                text: cell.unit
                color: control.view.dim
                font.pixelSize: 9
                font.family: "Share Tech Mono"
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height - 10
            color: control.view.modernHairline
        }
    }
}
