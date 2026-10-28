pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// Flight-mode picker opened from the Modern view header and telemetry strip.
// Lists only the modes the active vehicle reports, grouped AUTO and
// MANUAL / ASSISTED (see BriechModernView.flightModeOptions()).
Popup {
    id: menu

    /// The BriechModernView root; supplies the vehicle, helpers and colour tokens.
    required property var view

    readonly property var vehicle: view.activeVehicle

    width: Math.max(parent ? parent.width : 0, 170)
    padding: 4
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    background: Rectangle {
        color: menu.view.modernGlassStrong
        border.color: menu.view.modernGoldHairline
        border.width: 1
        radius: 2
    }

    contentItem: Column {
        spacing: 1

        Repeater {
            model: menu.opened ? menu.view.flightModeOptions() : []

            delegate: Rectangle {
                id: modeOption
                required property var modelData
                readonly property bool isHeader: !!modelData.header
                readonly property bool current: !isHeader && !!menu.vehicle && menu.vehicle.flightMode === modelData.mode
                width: menu.availableWidth
                height: isHeader ? 20 : 26
                radius: 2
                color: modeOption.current ? menu.view.modernGoldFill : (optionMouse.containsMouse && !modeOption.isHeader ? menu.view.modernGlassSoft : "transparent")

                // Group heading (AUTO, MANUAL / ASSISTED): a label, not a mode.
                Text {
                    visible: modeOption.isHeader
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: modeOption.modelData.label
                    color: menu.view.gold
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 1.5
                    font.family: "Share Tech Mono"
                }

                Text {
                    visible: !modeOption.isHeader
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: (modeOption.current ? "▸ " : "") + modeOption.modelData.label
                    color: modeOption.current ? menu.view.gold : menu.view.text
                    font.pixelSize: 12
                    font.bold: modeOption.current
                    font.family: "Barlow Condensed"
                }

                MouseArea {
                    id: optionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !modeOption.isHeader
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        menu.view.selectFlightMode(modeOption.modelData.mode)
                        menu.close()
                    }
                }
            }
        }
    }
}
