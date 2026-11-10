import QtQuick

import Custom.Widgets 1.0

// Root of the Briech Fleet page. BriechModernView loads this file through a
// single Loader, and only while FleetSettings.enabled is true and the operator
// has opened it. Everything Fleet shows hangs off this file, so the Modern view
// needs no other fleet hook, and closing the page (Loader inactive) destroys
// every piece below, including the map layer.
//
// Slots, top to bottom:
//   FleetOfflineBanner    shown while the coordinator has been silent for 10 s
//   FleetPanel            vehicle cards (QGC's connected vehicles)
//   FleetAlerts           active coordinator alerts (FleetAlertModel)
//   FleetSafetyControls   fleet safety state, HOLD ALL and RETURN ALL
//   FleetConnectionStatus coordinator link state and DISABLE
//   FleetMapLayers        non-visual: draws vehicle tags, assets, detections and alerts on the Modern map
// Beside the column, when opened with the panel's 3D button:
//   Fleet3DView           the active (or pinned) drone's roll, pitch and heading, in 3D or 2D
//
// The layer must never show placeholder assets, detections or alerts.
Rectangle {
    id: root

    signal closeRequested()
    signal vehicleFocused(var vehicle)
    /// HOLD ALL / RETURN ALL pressed; the Modern view confirms, then FleetDispatch sends.
    signal holdAllRequested()
    signal returnAllRequested()

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

    // The panel sits on the map: without this, a click or scroll on an empty
    // part of the panel reached the map underneath (opening the map's "Go to
    // location" menu, or zooming). Declared first so the panel's own controls,
    // above it, still get their clicks.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: (wheel) => wheel.accepted = true
    }

    Column {
        id: content
        x: 1
        y: 1
        width: parent.width - 2

        FleetOfflineBanner {
            id: offlineBanner
            width: parent.width
        }

        FleetPanel {
            width: parent.width
            maximumHeight: Math.max(120, root.maximumHeight - offlineBanner.height - alerts.height - safety.height - status.height - 2)
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
            onHoldAllRequested: root.holdAllRequested()
            onReturnAllRequested: root.returnAllRequested()
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

    // Attitude view, to the right of the panel. Its 3D scene is created only
    // while it is open (a Loader inside Fleet3DView).
    Loader {
        x: root.width + 8
        y: 0
        active: FleetSettings.attitudeViewOpen
        sourceComponent: Fleet3DView {
            onCloseRequested: FleetSettings.attitudeViewOpen = false
        }
    }
}
