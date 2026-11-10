import QtQuick
import QtQuick3D
import QtPositioning

// The 3D scene of the attitude view (handoff, section 8): one drone, shown
// with the roll, pitch and heading QGC reads from the vehicle, at its
// position relative to home, with a trail of where it has been.
//
// Loaded by Fleet3DView only when this build has Qt Quick 3D
// (FleetSettings.quick3DAvailable), the operator chose 3D and the view is
// open. If it fails to load, Fleet3DView shows the 2D indicator instead.
//
// Conventions are the stock Viewer3D drone model's (src/Viewer3D/.../
// DroneModelDjiF450.qml), so this view and QGC's attitude indicator agree:
//   - world frame: x east, y north, z up, one unit = one metre;
//   - heading: rotation about z of (90 - heading);
//   - roll and pitch: Quaternion.fromEulerAngles(roll, -pitch, 0) in the
//     body frame (x forward, y left, z up).
// The camera follows behind the drone and turns with its heading only, so
// roll and pitch look as they do on an attitude indicator.
//
// Cost: the model is built from Quick3D's built-in primitives (well under
// 2,000 triangles; the stock DJI F450 meshes are over 100,000), one light, no
// shadows. Attitude values are bound to QGC's facts, which only notify when a
// value changes; position is sampled 4 times a second into plain numbers.
// A hovering drone therefore changes nothing in the scene and costs almost
// nothing to show.
Item {
    id: root

    /// The QGC Vehicle to show, or null.
    property var vehicle: null

    // ---- Attitude, in degrees, from QGC's facts (0 when unknown; Fleet3DView
    // shows "--" for unknown values beside the scene).
    function factNumber(fact) {
        const value = fact ? Number(fact.rawValue) : NaN
        return isNaN(value) ? 0 : value
    }
    readonly property real rollDeg: vehicle ? factNumber(vehicle.roll) : 0
    readonly property real pitchDeg: vehicle ? factNumber(vehicle.pitch) : 0
    readonly property real headingDeg: vehicle ? factNumber(vehicle.heading) : 0

    // Heading, unwrapped: from 359 to 1 degree it goes to 361, not back to 1,
    // so the animation turns the short way round.
    property real yawTarget: 0
    property real yawShown: yawTarget
    Behavior on yawShown {
        enabled: root.animate
        NumberAnimation { duration: 90 }
    }
    onHeadingDegChanged: {
        const current = ((yawTarget % 360) + 360) % 360
        yawTarget += ((headingDeg - current + 540) % 360) - 180
    }

    // ---- Position relative to home, metres. Sampled by the timer below:
    // reading vehicle.coordinate in a binding would create a coordinate
    // wrapper on every position report (see custom/README.md).
    property real east: 0
    property real north: 0
    property real up: 0
    property bool positionValid: false
    property var _origin: null      // used when the vehicle has no home yet
    property int _ticks: 0
    // Off for one sample after the vehicle changes, so it jumps instead of
    // flying across the scene.
    property bool animate: false

    Behavior on east { enabled: root.animate; NumberAnimation { duration: 250 } }
    Behavior on north { enabled: root.animate; NumberAnimation { duration: 250 } }
    Behavior on up { enabled: root.animate; NumberAnimation { duration: 250 } }

    readonly property int trailLength: 120

    function reset() {
        animate = false
        _origin = null
        _ticks = 0
        trail.clear()
        yawTarget = headingDeg
        sample()
    }

    function sample() {
        const c = vehicle ? vehicle.coordinate : null
        if (!c || !c.isValid) {
            positionValid = false
            return
        }
        let home = vehicle.homePosition
        if (!home || !home.isValid) {
            if (!_origin) {
                _origin = QtPositioning.coordinate(c.latitude, c.longitude)
            }
            home = _origin
        }
        const distance = home.distanceTo(c)
        const azimuth = home.azimuthTo(c) * Math.PI / 180
        east = distance * Math.sin(azimuth)
        north = distance * Math.cos(azimuth)
        const alt = Number(vehicle.altitudeRelative ? vehicle.altitudeRelative.rawValue : NaN)
        up = isNaN(alt) ? 0 : alt
        positionValid = true

        // Trail: one point every half second, only when the drone has moved
        // at least half a metre, so a hovering drone adds nothing.
        _ticks++
        if (_ticks % 2 === 0) {
            const last = trail.count > 0 ? trail.get(trail.count - 1) : null
            const moved = !last || Math.hypot(east - last.ex, north - last.ny, up - last.uz) >= 0.5
            if (moved) {
                trail.append({ ex: east, ny: north, uz: up })
                if (trail.count > trailLength) {
                    trail.remove(0, trail.count - trailLength)
                }
            }
        }
        animate = true
    }

    onVehicleChanged: reset()
    Component.onCompleted: reset()

    Timer {
        interval: 250
        repeat: true
        running: !!root.vehicle
        onTriggered: root.sample()
    }

    ListModel { id: trail }

    View3D {
        anchors.fill: parent
        camera: chaseCamera

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "#1d3b5c"
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        DirectionalLight {
            eulerRotation: Qt.vector3d(-55, -30, 0)
            brightness: 1.0
            ambientColor: Qt.rgba(0.45, 0.45, 0.5, 1)
            castsShadow: false
        }

        // Z-up world (ENU) inside Quick3D's Y-up space.
        Node {
            eulerRotation.x: -90

            // Ground at home altitude, 4 km square, with a 20 m grid so
            // movement and height are visible.
            Model {
                source: "#Rectangle"
                scale: Qt.vector3d(40, 40, 1)
                materials: DefaultMaterial { diffuseColor: "#33402a" }
            }

            Repeater3D {
                model: 41
                delegate: Model {
                    required property int index
                    source: "#Cube"
                    position: Qt.vector3d((index - 20) * 20, 0, 0.05)
                    scale: Qt.vector3d(0.0015, 8, 0.0005)
                    materials: gridMaterial
                }
            }

            Repeater3D {
                model: 41
                delegate: Model {
                    required property int index
                    source: "#Cube"
                    position: Qt.vector3d(0, (index - 20) * 20, 0.05)
                    scale: Qt.vector3d(8, 0.0015, 0.0005)
                    materials: gridMaterial
                }
            }

            // Home: a short white post.
            Model {
                source: "#Cylinder"
                position: Qt.vector3d(0, 0, 0.75)
                eulerRotation.x: 90
                scale: Qt.vector3d(0.004, 0.015, 0.004)
                materials: DefaultMaterial { diffuseColor: "#e8edf3" }
            }

            // Trail: up to 120 positions, one every half second.
            Repeater3D {
                model: trail
                delegate: Model {
                    required property real ex
                    required property real ny
                    required property real uz
                    source: "#Sphere"
                    position: Qt.vector3d(ex, ny, uz)
                    scale: Qt.vector3d(0.003, 0.003, 0.003)
                    materials: trailMaterial
                }
            }

            // The drone: heading on this node, roll and pitch on the next.
            Node {
                visible: root.positionValid
                position: Qt.vector3d(root.east, root.north, root.up)
                eulerRotation: Qt.vector3d(0, 0, 90 - root.yawShown)

                Node {
                    rotation: Quaternion.fromEulerAngles(Qt.vector3d(root.rollDeg, -root.pitchDeg, 0))
                    Behavior on rotation {
                        enabled: root.animate
                        QuaternionAnimation { duration: 90 }
                    }

                    // Body, 0.6 x 0.6 x 0.2 m.
                    Model {
                        source: "#Cube"
                        scale: Qt.vector3d(0.006, 0.006, 0.002)
                        materials: DefaultMaterial { diffuseColor: "#2a2f38" }
                    }

                    // Nose: a gold cone pointing forward (+x).
                    Model {
                        source: "#Cone"
                        position: Qt.vector3d(0.42, 0, 0)
                        eulerRotation.z: -90
                        scale: Qt.vector3d(0.0016, 0.003, 0.0016)
                        materials: DefaultMaterial { diffuseColor: "#c9a84c" }
                    }

                    // Four arms at 45, 135, 225 and 315 degrees, each with a
                    // rotor disc. The two front rotors are red.
                    Repeater3D {
                        model: 4
                        delegate: Node {
                            id: arm
                            required property int index
                            readonly property bool front: index === 0 || index === 3
                            eulerRotation.z: 45 + index * 90

                            Model {
                                source: "#Cube"
                                position: Qt.vector3d(0.45, 0, 0)
                                scale: Qt.vector3d(0.009, 0.0008, 0.0008)
                                materials: DefaultMaterial { diffuseColor: "#3a404a" }
                            }

                            Model {
                                source: "#Cylinder"
                                position: Qt.vector3d(0.9, 0, 0.08)
                                eulerRotation.x: 90
                                scale: Qt.vector3d(0.0055, 0.0004, 0.0055)
                                materials: DefaultMaterial {
                                    diffuseColor: arm.front ? "#e0453a" : "#d8dee8"
                                    opacity: 0.85
                                }
                            }
                        }
                    }
                }
            }

            // Chase camera: follows the drone's position and heading (not its
            // roll or pitch), 4.5 m behind and 1.1 m above, looking 12 degrees down.
            Node {
                position: Qt.vector3d(root.east, root.north, root.up)
                eulerRotation: Qt.vector3d(0, 0, 90 - root.yawShown)

                Node {
                    position: Qt.vector3d(-4.5, 0, 1.1)
                    eulerRotation.z: -90

                    PerspectiveCamera {
                        id: chaseCamera
                        eulerRotation.x: 78
                        fieldOfView: 55
                        clipNear: 0.1
                        clipFar: 6000
                    }
                }
            }
        }

        DefaultMaterial {
            id: gridMaterial
            diffuseColor: "#56663f"
            lighting: DefaultMaterial.NoLighting
        }

        DefaultMaterial {
            id: trailMaterial
            diffuseColor: "#c9a84c"
            lighting: DefaultMaterial.NoLighting
        }
    }
}
