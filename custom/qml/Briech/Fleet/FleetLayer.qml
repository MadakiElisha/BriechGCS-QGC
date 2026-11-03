import QtQuick

import Custom.Widgets 1.0

// Root of the Briech Fleet page. BriechModernView loads this file through a
// single Loader, and only while FleetSettings.enabled is true and the operator
// has opened it. Everything Fleet shows hangs off this file, so the Modern view
// needs no other fleet hook, and closing the page (Loader inactive) destroys
// every piece below, including the map layer.
//
// Slots, top to bottom:
//   FleetPanel            vehicle cards (QGC vehicles until FleetLink exists)
//   FleetAlerts           fleet alerts (no source until FleetLink exists)
//   FleetSafetyControls   fleet safety state; fleet-wide commands need the coordinator
//   FleetConnectionStatus coordinator link state and DISABLE
//   FleetMapLayers        non-visual: draws Fleet items on the Modern map
//
// The layer must never show placeholder assets, detections or alerts.
Rectangle {
    id: root

    signal closeRequested()
    signal vehicleFocused(var vehicle)

    /// Tallest the page may grow; set by the Modern view from the space left
    /// on the map. The vehicle list absorbs any shortfall and scrolls.
    property real maximumHeight: 600

    /// The Modern view's map. Set by the Modern view; FleetMapLayers draws on it.
    property var map: null

    width: 252
    height: content.implicitHeight + 2
    radius: 2
    color: "#080a0e"
    border.color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.25)
    border.width: 1

    Column {
        id: content
        x: 1
        y: 1
        width: parent.width - 2

        FleetPanel {
            width: parent.width
            maximumHeight: Math.max(120, root.maximumHeight - alerts.height - safety.height - status.height - 2)
            onCloseRequested: root.closeRequested()
            onVehicleFocused: (vehicle) => root.vehicleFocused(vehicle)
        }

        FleetAlerts {
            id: alerts
            width: parent.width
        }

        FleetSafetyControls {
            id: safety
            width: parent.width
        }

        FleetConnectionStatus {
            id: status
            width: parent.width
            // Turning Fleet off deactivates the Loader that owns this page.
            onDisableRequested: FleetSettings.enabled = false
        }
    }

    FleetMapLayers {
        map: root.map
    }
}
