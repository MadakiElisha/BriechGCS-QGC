import QtQuick

// Stand-in for QGC's QGroundControl.Viewer3D module, built only when the 3D
// viewer is off (QGC_VIEWER3D=OFF, required when Qt Quick 3D is missing).
//
// QGC then does not build its own Viewer3D module, but stock FlyView.qml,
// FlyViewToolStripActionList.qml and our Modern view import it without a
// condition. A missing import fails the whole file, so the main window would
// not load at all. This module supplies the same type with the same small API
// (isOpen, open, close) and is never open: there is no 3D viewer in this build.
// The Fleet attitude view shows its 2D indicator instead (BRIECH_FLEET_3D off).
// Wired up in custom/CMakeLists.txt.
Item {
    property bool isOpen: false

    function open() {
        console.info("Viewer3D: not in this build (built without Qt Quick 3D)")
    }

    function close() {
        isOpen = false
    }

    visible: false
    enabled: false
}
