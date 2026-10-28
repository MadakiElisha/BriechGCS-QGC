import QtQuick

// Root of the Briech Fleet layer. BriechModernView loads this file through a
// single Loader, and only while FleetSettings.enabled is true. Fleet pieces
// (the fleet panel now; alerts and markers later) are pulled in from here so
// the Modern view never needs another fleet hook.
//
// Until FleetLink (the coordinator connection) exists, the layer shows only
// real QGC state. It must never show placeholder assets or detections.
Column {
    id: root

    signal closeRequested()
    signal vehicleFocused(var vehicle)

    /// Tallest the layer may grow; set by the Modern view from the space left
    /// on the map.
    property real maximumHeight: 600

    spacing: 6

    FleetPanel {
        maximumHeight: root.maximumHeight
        onCloseRequested: root.closeRequested()
        onVehicleFocused: (vehicle) => root.vehicleFocused(vehicle)
    }
}
