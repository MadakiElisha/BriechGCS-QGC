import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap

Item {
    id: root

    property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property color gold: "#C9A84C"
    property color bg: "#080a0e"
    property color panel: "#0f1218"
    property color panel2: "#141820"
    property color border: "#252c38"
    property color dim: "#6a7585"
    property color text: "#d8dde6"
    property color ok: "#22c55e"
    property color warn: "#f59e0b"
    property color err: "#ef4444"
    property color blue: "#3b82f6"
    property string activeModernSection: "fly"
    property string selectedMapKind: "satellite"
    property bool _mapTypeInitialized: false
    property var defaultCenter: QtPositioning.coordinate(9.0765, 7.3986)
    property var overlayCenter: activeVehicle && activeVehicle.coordinate.isValid ? activeVehicle.coordinate : (QGroundControl.flightMapPosition.isValid ? QGroundControl.flightMapPosition : defaultCenter)

    property var missionCoordinates: [
        offsetCoordinate(-0.155, -0.255),
        offsetCoordinate(-0.112, -0.205),
        offsetCoordinate(-0.071, -0.151),
        offsetCoordinate(-0.028, -0.092),
        offsetCoordinate(0.019, -0.031),
        offsetCoordinate(0.058, 0.025),
        offsetCoordinate(0.095, 0.083),
        offsetCoordinate(0.046, 0.135),
        offsetCoordinate(-0.032, 0.083)
    ]

    function telemetryValue(fact, fallback) {
        return fact ? fact.valueString : fallback
    }

    Component {
        id: planViewComponent
        Loader { anchors.fill: parent; source: "qrc:/Briech/qml/Modern/PlanViewModern.qml" }
    }

    function offsetCoordinate(latitudeOffset, longitudeOffset) {
        return QtPositioning.coordinate(overlayCenter.latitude + latitudeOffset, overlayCenter.longitude + longitudeOffset)
    }

    function mapTypeKeywords(kind) {
        switch (kind) {
        case "satellite":
            return ["satellite"]
        case "street":
            return ["street", "road", "map"]
        case "terrain":
            return ["terrain", "topo", "topographic"]
        case "hybrid":
            return ["hybrid"]
        default:
            return [kind]
        }
    }

    function findMapType(kind) {
        if (!modernMap.mapReady) {
            return null
        }
        const keywords = mapTypeKeywords(kind)
        for (let i = 0; i < modernMap.supportedMapTypes.length; i++) {
            const candidate = modernMap.supportedMapTypes[i]
            const candidateName = candidate.name.toLowerCase()
            for (let keywordIndex = 0; keywordIndex < keywords.length; keywordIndex++) {
                if (candidateName.indexOf(keywords[keywordIndex]) !== -1) {
                    return candidate
                }
            }
        }
        return null
    }

    function setMapType(kind) {
        const candidate = findMapType(kind)
        if (candidate) {
            modernMap.activeMapType = candidate
            selectedMapKind = kind
        }
    }

    function updateSelectedMapKindFromActiveType() {
        if (!modernMap.activeMapType || !modernMap.activeMapType.name) {
            return
        }
        const activeName = modernMap.activeMapType.name.toLowerCase()
        const kinds = ["hybrid", "satellite", "terrain", "street"]
        for (let i = 0; i < kinds.length; i++) {
            const keywords = mapTypeKeywords(kinds[i])
            for (let keywordIndex = 0; keywordIndex < keywords.length; keywordIndex++) {
                if (activeName.indexOf(keywords[keywordIndex]) !== -1) {
                    selectedMapKind = kinds[i]
                    return
                }
            }
        }
    }

    function initializeModernMapType() {
        if (!modernMap.mapReady || _mapTypeInitialized) {
            return
        }
        _mapTypeInitialized = true
        if (!modernMap.center.isValid) {
            modernMap.center = defaultCenter
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 11)
        }
        if (findMapType("satellite")) {
            setMapType("satellite")
        } else {
            updateSelectedMapKindFromActiveType()
        }
    }

    function fitModernMission() {
        if (modernMap.mapReady && missionCoordinates.length > 1) {
            modernMap.setVisibleRegion(QtPositioning.rectangle(offsetCoordinate(0.18, -0.31), offsetCoordinate(-0.20, 0.21)))
        }
    }

    function cycleMapType() {
        const types = ["satellite", "street", "terrain", "hybrid"]
        const currentIndex = Math.max(0, types.indexOf(selectedMapKind))
        for (let step = 1; step <= types.length; step++) {
            const nextKind = types[(currentIndex + step) % types.length]
            if (findMapType(nextKind)) {
                setMapType(nextKind)
                return
            }
        }
    }

    function activateModernSection(section) {
        activeModernSection = section
    }

    function centerOnVehicle() {
        if (activeVehicle && activeVehicle.coordinate.isValid) {
            modernMap.center = activeVehicle.coordinate
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 16)
        } else if (modernMap.gcsPosition.isValid) {
            modernMap.center = modernMap.gcsPosition
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 14)
        }
    }

    function confirmVehicleAction(title, message, action) {
        if (!activeVehicle) {
            mainWindow.showMessageDialog(qsTr("No Vehicle"), qsTr("Connect to a vehicle before using this action."))
            return
        }
        mainWindow.showMessageDialog(title, message, Dialog.Yes | Dialog.No, action)
    }

    function armVehicle() {
        confirmVehicleAction(qsTr("Arm Vehicle"), qsTr("Arm the active vehicle?"), function() { activeVehicle.armed = true })
    }

    function disarmVehicle() {
        confirmVehicleAction(qsTr("Disarm Vehicle"), qsTr("Disarm the active vehicle?"), function() { activeVehicle.armed = false })
    }

    function takeoffVehicle() {
        confirmVehicleAction(qsTr("Takeoff"), qsTr("Command guided takeoff?"), function() {
            activeVehicle.guidedModeTakeoff(Math.max(15, activeVehicle.minimumTakeoffAltitudeMeters()))
        })
    }

    function landVehicle() {
        confirmVehicleAction(qsTr("Land"), qsTr("Command land now?"), function() { activeVehicle.guidedModeLand() })
    }

    function rtlVehicle() {
        confirmVehicleAction(qsTr("Return To Launch"), qsTr("Command return to launch?"), function() { activeVehicle.guidedModeRTL(false) })
    }

    function pauseVehicle() {
        confirmVehicleAction(qsTr("Pause"), qsTr("Pause at current position?"), function() { activeVehicle.pauseVehicle() })
    }

    function connectMockVehicle() {
        if (activeVehicle) {
            activeVehicle.closeVehicle()
        } else {
            QGroundControl.startPX4MockLink(true)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: "#05070a"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.gold
                opacity: 0.85
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Image {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    source: "/Briech/res/QGCLogoFull.svg"
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    text: "BRIECH UAS"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    font.family: "Geo-Regular"
                }

                Text {
                    text: "Ground Control Station"
                    color: root.gold
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    font.family: "Geo-Regular"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: activeVehicle ? ("BRCH-" + activeVehicle.id) : "STANDBY"
                    color: root.dim
                    font.pixelSize: 10
                    font.family: "Geo-Regular"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: root.panel

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 282
                    Layout.fillHeight: true
                    color: "transparent"
                    border.color: "#1e242e"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 4
                            color: activeVehicle ? root.ok : "#333842"
                        }

                        Text {
                            Layout.fillWidth: true
                            text: activeVehicle ? "BRCH-01 - ACTIVE LINK" : "DISCONNECTED - MANUAL CONNECT"
                            color: root.text
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            font.bold: true
                            font.family: "Geo-Regular"
                        }
                    }
                }

                Repeater {
                    model: [
                        { k: "ALT", v: activeVehicle ? activeVehicle.altitudeRelative.valueString : "0.0", u: "m" },
                        { k: "GS", v: activeVehicle ? activeVehicle.groundSpeed.valueString : "0.0", u: "m/s" },
                        { k: "HDG", v: activeVehicle ? activeVehicle.heading.valueString : "---", u: "deg" },
                        { k: "GPS", v: activeVehicle ? "3D" : "--", u: "" },
                        { k: "BATT", v: activeVehicle ? "LIVE" : "--", u: "" },
                        { k: "MODE", v: activeVehicle ? activeVehicle.flightMode : "STBY", u: "" }
                    ]

                    delegate: Rectangle {
                        Layout.preferredWidth: Math.max(82, label.implicitWidth + value.implicitWidth + unit.implicitWidth + 26)
                        Layout.fillHeight: true
                        color: "transparent"
                        border.color: "#1e242e"
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                id: label
                                text: modelData.k
                                color: root.dim
                                font.pixelSize: 9
                                font.family: "Geo-Regular"
                            }

                            Text {
                                id: value
                                text: modelData.v
                                color: modelData.k === "BATT" || modelData.k === "MODE" ? root.ok : root.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Geo-Regular"
                            }

                            Text {
                                id: unit
                                text: modelData.u
                                color: root.dim
                                font.pixelSize: 9
                                font.family: "Geo-Regular"
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    Layout.fillHeight: true
                    Layout.rightMargin: 4
                    spacing: 0

                    Repeater {
                        model: [
                            { label: "FLY", key: "fly", icon: "/qmlimages/PaperPlane.svg" },
                            { label: "PLAN", key: "plan", icon: "/qmlimages/Plan.svg" },
                            { label: "ANALYZE", key: "analyze", icon: "/qmlimages/Analyze.svg" },
                            { label: "VEHICLE", key: "vehicle", icon: "/qmlimages/Gears.svg" }
                        ]

                        delegate: ModernNavButton {
                            label: modelData.label
                            iconSource: modelData.icon
                            active: root.activeModernSection === modelData.key
                            onClicked: root.activateModernSection(modelData.key)
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                spacing: 0
                visible: root.activeModernSection === "fly"

                Rectangle {
                    Layout.preferredWidth: 54
                    Layout.fillHeight: true
                    color: "#07090d"
                    border.color: "#1e242e"
                    border.width: 1

                    ColumnLayout {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 8
                        spacing: 4

                        Repeater {
                            model: [
                                { t: activeVehicle ? "DISC" : "MOCK", s: activeVehicle ? "X" : "C", a: "connect" },
                                { t: activeVehicle && activeVehicle.armed ? "DISARM" : "ARM", s: activeVehicle && activeVehicle.armed ? "D" : "A", a: activeVehicle && activeVehicle.armed ? "disarm" : "arm" },
                                { t: "TAKE", s: "T", a: "takeoff" },
                                { t: "PAUSE", s: "P", a: "pause" },
                                { t: "LAND", s: "L", a: "land" },
                                { t: "RTL", s: "R", a: "rtl" },
                                { t: "CENTER", s: "C", a: "center" },
                                { t: "FIT", s: "F", a: "fit" }
                            ]

                            delegate: Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 48
                                radius: 6
                                color: index === 0 ? "#211c10" : "transparent"
                                border.color: index === 0 ? root.gold : "transparent"

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.s
                                        color: index === 0 ? root.gold : root.dim
                                        font.pixelSize: 15
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.t
                                        color: index === 0 ? root.gold : root.dim
                                        font.pixelSize: 8
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        switch (modelData.a) {
                                        case "connect": root.connectMockVehicle(); break
                                        case "arm": root.armVehicle(); break
                                        case "disarm": root.disarmVehicle(); break
                                        case "takeoff": root.takeoffVehicle(); break
                                        case "pause": root.pauseVehicle(); break
                                        case "land": root.landVehicle(); break
                                        case "rtl": root.rtlVehicle(); break
                                        case "center": root.centerOnVehicle(); break
                                        case "fit": root.fitModernMission(); break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    FlightMap {
                        id: modernMap
                        anchors.fill: parent
                        mapName: "BriechModernView"
                        allowGCSLocationCenter: true
                        allowVehicleLocationCenter: true
                        planView: false
                        zoomLevel: QGroundControl.flightMapZoom
                        center: QGroundControl.flightMapPosition

                        onZoomLevelChanged: QGroundControl.flightMapZoom = zoomLevel
                        onCenterChanged: QGroundControl.flightMapPosition = center
                        onMapReadyChanged: root.initializeModernMapType()
                        onActiveMapTypeChanged: root.updateSelectedMapKindFromActiveType()

                        MapPolygon {
                            path: [
                                root.offsetCoordinate(0.18, -0.31),
                                root.offsetCoordinate(0.19, 0.22),
                                root.offsetCoordinate(-0.19, 0.23),
                                root.offsetCoordinate(-0.20, -0.31)
                            ]
                            color: "#16c9a84c"
                            border.color: "#77c9a84c"
                            border.width: 2
                            z: QGroundControl.zOrderMapItems
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.014, -0.095)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 1
                            sourceItem: ModernZoneLabel { text: "GEOFENCE"; borderColor: root.gold; textColor: root.gold }
                        }

                        MapPolygon {
                            path: [
                                root.offsetCoordinate(0.125, -0.09),
                                root.offsetCoordinate(0.125, 0.015),
                                root.offsetCoordinate(0.066, 0.015),
                                root.offsetCoordinate(0.066, -0.09)
                            ]
                            color: "#33ef4444"
                            border.color: root.err
                            border.width: 2
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(0.096, -0.037)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            sourceItem: ModernZoneLabel { text: "NFZ - MILITARY"; borderColor: root.err; textColor: root.err }
                        }

                        MapPolygon {
                            path: [
                                root.offsetCoordinate(-0.035, -0.045),
                                root.offsetCoordinate(-0.036, 0.086),
                                root.offsetCoordinate(-0.105, 0.087),
                                root.offsetCoordinate(-0.104, -0.047)
                            ]
                            color: "#2bf59e0b"
                            border.color: root.warn
                            border.width: 2
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.070, 0.020)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            sourceItem: ModernZoneLabel { text: "RESTRICTED"; borderColor: root.warn; textColor: root.warn }
                        }

                        MapPolygon {
                            path: [
                                root.offsetCoordinate(-0.022, -0.075),
                                root.offsetCoordinate(-0.021, -0.206),
                                root.offsetCoordinate(-0.150, -0.206),
                                root.offsetCoordinate(-0.150, -0.074)
                            ]
                            color: "#24a855f7"
                            border.color: "#a855f7"
                            border.width: 2
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.086, -0.140)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            sourceItem: ModernZoneLabel { text: "RADAR COVERAGE"; borderColor: "#a855f7"; textColor: "#c084fc" }
                        }

                        MapPolygon {
                            path: [
                                root.offsetCoordinate(0.045, 0.125),
                                root.offsetCoordinate(0.047, 0.237),
                                root.offsetCoordinate(-0.075, 0.240),
                                root.offsetCoordinate(-0.077, 0.126)
                            ]
                            color: "#203b82f6"
                            border.color: root.blue
                            border.width: 2
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.014, 0.182)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            sourceItem: ModernZoneLabel { text: "ADVISORY - HIGH TRAFFIC"; borderColor: root.blue; textColor: "#93c5fd" }
                        }

                        MapPolyline {
                            path: root.missionCoordinates
                            line.width: 3
                            line.color: root.blue
                            z: QGroundControl.zOrderWaypointLines
                        }

                        MapItemView {
                            model: root.missionCoordinates
                            delegate: MapQuickItem {
                                coordinate: modelData
                                anchorPoint.x: sourceItem.width / 2
                                anchorPoint.y: sourceItem.height / 2
                                z: QGroundControl.zOrderWaypointLines + 1
                                sourceItem: ModernWaypointMarker {
                                    number: index + 1
                                    highlight: index === 3
                                }
                            }
                        }

                        MapQuickItem {
                            coordinate: activeVehicle && activeVehicle.coordinate.isValid ? activeVehicle.coordinate : root.offsetCoordinate(0.095, 0.083)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height + 8
                            z: QGroundControl.zOrderVehicles + 1
                            sourceItem: ModernZoneLabel {
                                text: activeVehicle ? ("BRCH-" + activeVehicle.id + " - " + activeVehicle.flightMode) : "BRCH-01 - DAMISA"
                                borderColor: root.gold
                                textColor: root.gold
                            }
                        }

                        MapPolyline {
                            id: trajectoryPolyline
                            line.width: 3
                            line.color: root.blue
                            z: QGroundControl.zOrderTrajectoryLines

                            Connections {
                                target: QGroundControl.multiVehicleManager
                                function onActiveVehicleChanged() {
                                    trajectoryPolyline.path = activeVehicle ? activeVehicle.trajectoryPoints.list() : []
                                }
                            }

                            Connections {
                                target: activeVehicle ? activeVehicle.trajectoryPoints : null
                                function onPointAdded(coordinate) { trajectoryPolyline.addCoordinate(coordinate) }
                                function onUpdateLastPoint(coordinate) { trajectoryPolyline.replaceCoordinate(trajectoryPolyline.pathLength() - 1, coordinate) }
                                function onPointsCleared() { trajectoryPolyline.path = [] }
                            }
                        }

                        MapItemView {
                            model: QGroundControl.multiVehicleManager.vehicles
                            delegate: VehicleMapItem {
                                vehicle: object
                                coordinate: object.coordinate
                                map: modernMap
                                size: ScreenTools.defaultFontPixelHeight * 3
                                z: QGroundControl.zOrderVehicles
                            }
                        }

                        MapItemView {
                            model: QGroundControl.adsbVehicleManager.adsbVehicles
                            delegate: VehicleMapItem {
                                coordinate: object.coordinate
                                altitude: object.altitude
                                callsign: object.callsign
                                heading: object.heading
                                alert: object.alert
                                map: modernMap
                                size: ScreenTools.defaultFontPixelHeight * 2.5
                                z: QGroundControl.zOrderVehicles
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: false
                        color: "#020304"
                        opacity: 0.58
                    }

                    Canvas {
                        id: mapCanvas
                        anchors.fill: parent
                        visible: false

                        onPaint: {
                            const c = getContext("2d")
                            const w = width
                            const h = height
                            c.reset()
                            c.fillStyle = "rgba(5,6,8,.24)"
                            c.fillRect(0, 0, w, h)

                            c.strokeStyle = "rgba(255,255,255,0.04)"
                            c.lineWidth = 1
                            for (let x = 0; x < w; x += 82) {
                                c.beginPath()
                                c.moveTo(x, 0)
                                c.lineTo(x, h)
                                c.stroke()
                            }
                            for (let y = 0; y < h; y += 68) {
                                c.beginPath()
                                c.moveTo(0, y)
                                c.lineTo(w, y)
                                c.stroke()
                            }

                            c.strokeStyle = "rgba(255,255,255,0.09)"
                            c.lineWidth = 1
                            for (let i = 0; i < 24; i++) {
                                const y = (i * 53) % h
                                c.beginPath()
                                c.moveTo((i * 37) % w, y)
                                c.bezierCurveTo(w * .25, y + 40, w * .45, y - 26, w, (y + 80) % h)
                                c.stroke()
                            }

                            function zone(x, y, zw, zh, stroke, fill, label) {
                                c.setLineDash([7, 4])
                                c.strokeStyle = stroke
                                c.fillStyle = fill
                                c.lineWidth = 2
                                c.fillRect(x, y, zw, zh)
                                c.strokeRect(x, y, zw, zh)
                                c.setLineDash([])
                                c.fillStyle = "rgba(8,10,14,0.82)"
                                c.strokeStyle = stroke
                                c.lineWidth = 1
                                const tw = c.measureText(label).width + 18
                                c.fillRect(x + zw * .43, y + zh * .45, tw, 20)
                                c.strokeRect(x + zw * .43, y + zh * .45, tw, 20)
                                c.fillStyle = stroke
                                c.font = "10px \"Geo-Regular\""
                                c.fillText(label, x + zw * .43 + 9, y + zh * .45 + 13)
                            }

                            zone(w * .17, h * .17, w * .58, h * .61, "rgba(201,168,76,.48)", "rgba(201,168,76,.03)", "GEOFENCE")
                            zone(w * .34, h * .25, w * .13, h * .12, "rgba(239,68,68,.9)", "rgba(239,68,68,.16)", "NFZ")
                            zone(w * .53, h * .42, w * .16, h * .18, "rgba(245,158,11,.9)", "rgba(245,158,11,.13)", "RESTRICTED")
                            zone(w * .39, h * .48, w * .19, h * .22, "rgba(168,85,247,.85)", "rgba(168,85,247,.10)", "RADAR")
                            zone(w * .71, h * .30, w * .14, h * .18, "rgba(59,130,246,.85)", "rgba(59,130,246,.09)", "ADVISORY")

                            const pts = [
                                [w*.30, h*.66], [w*.36, h*.60], [w*.41, h*.54], [w*.47, h*.45],
                                [w*.54, h*.39], [w*.62, h*.33], [w*.70, h*.44], [w*.61, h*.56]
                            ]
                            c.strokeStyle = "rgba(59,130,246,.95)"
                            c.lineWidth = 3
                            c.beginPath()
                            pts.forEach((p, i) => i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1]))
                            c.stroke()
                            pts.forEach((p, i) => {
                                c.fillStyle = i === 3 ? root.warn : root.blue
                                c.strokeStyle = "white"
                                c.lineWidth = i === 3 ? 2 : 1
                                c.beginPath()
                                c.arc(p[0], p[1], i === 3 ? 11 : 9, 0, Math.PI * 2)
                                c.fill()
                                c.stroke()
                                c.fillStyle = "white"
                                c.font = "bold 10px \"Geo-Regular\""
                                c.textAlign = "center"
                                c.fillText(String(i + 1), p[0], p[1] + 4)
                            })

                            c.fillStyle = root.gold
                            c.beginPath()
                            c.moveTo(w*.54, h*.39 - 18)
                            c.lineTo(w*.54 + 12, h*.39 + 18)
                            c.lineTo(w*.54, h*.39 + 8)
                            c.lineTo(w*.54 - 12, h*.39 + 18)
                            c.closePath()
                            c.fill()
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 44
                        width: alertText.implicitWidth + 32
                        height: 22
                        color: "#211606"
                        border.color: root.warn
                        opacity: 0.95

                        Text {
                            id: alertText
                            anchors.centerIn: parent
                            text: "WIND SHEAR DETECTED - MONITOR"
                            color: root.warn
                            font.pixelSize: 10
                            font.family: "Geo-Regular"
                            font.letterSpacing: 1
                        }
                    }

                    Column {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 4

                        Repeater {
                            model: [
                                { label: "SATELLITE", key: "satellite" },
                                { label: "STREET", key: "street" },
                                { label: "TERRAIN", key: "terrain" },
                                { label: "HYBRID", key: "hybrid" }
                            ]
                            delegate: Rectangle {
                                width: 112
                                height: 28
                                property bool active: root.selectedMapKind === modelData.key
                                property bool available: root.findMapType(modelData.key) !== null
                                color: active ? "#211c10" : "#0c1017"
                                border.color: active ? root.gold : root.border
                                opacity: available ? 1 : 0.48

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.active ? root.gold : root.dim
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1
                                    font.family: "Geo-Regular"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: parent.available
                                    onClicked: root.setMapType(modelData.key)
                                }
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 8
                        anchors.bottomMargin: 42
                        spacing: 2

                        Rectangle {
                            width: 32
                            height: 32
                            color: "#0b0e14"
                            border.color: root.border
                            Text { anchors.centerIn: parent; text: "+"; color: root.text; font.pixelSize: 18 }
                            MouseArea { anchors.fill: parent; onClicked: modernMap.zoomLevel += 1 }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            color: "#0b0e14"
                            border.color: root.border
                            Text { anchors.centerIn: parent; text: "-"; color: root.text; font.pixelSize: 18 }
                            MouseArea { anchors.fill: parent; onClicked: modernMap.zoomLevel -= 1 }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 64
                        anchors.topMargin: 44
                        width: 112
                        height: 34
                        color: "#0b0e14"
                        border.color: root.border

                        MapScale {
                            anchors.centerIn: parent
                            mapControl: modernMap
                        }
                    }

                    ColumnLayout {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 18
                        anchors.bottomMargin: 42
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 220
                            Layout.preferredHeight: 42
                            color: "#0b0e14"
                            border.color: root.border

                            Row {
                                anchors.centerIn: parent
                                spacing: 18
                                Repeater {
                                    model: ["050", "060", "070", "080", "090"]
                                    delegate: Text {
                                        text: modelData
                                        color: index === 2 ? root.gold : root.text
                                        font.pixelSize: 10
                                        font.family: "Geo-Regular"
                                    }
                                }
                            }
                        }

                        Canvas {
                            Layout.preferredWidth: 220
                            Layout.preferredHeight: 220

                            onPaint: {
                                const c = getContext("2d")
                                c.reset()
                                const cx = width / 2
                                const cy = height / 2
                                const r = 104
                                c.beginPath()
                                c.arc(cx, cy, r, 0, Math.PI * 2)
                                c.clip()
                                c.fillStyle = "#225b8f"
                                c.fillRect(0, 0, width, cy)
                                c.fillStyle = "#5e3f1f"
                                c.fillRect(0, cy, width, height)
                                c.strokeStyle = "white"
                                c.lineWidth = 2
                                c.beginPath()
                                c.moveTo(0, cy)
                                c.lineTo(width, cy - 4)
                                c.stroke()
                                c.strokeStyle = "rgba(255,255,255,.72)"
                                c.lineWidth = 2
                                c.beginPath()
                                c.moveTo(cx - 54, cy)
                                c.lineTo(cx - 18, cy)
                                c.moveTo(cx + 18, cy)
                                c.lineTo(cx + 54, cy)
                                c.moveTo(cx - 18, cy)
                                c.lineTo(cx, cy + 12)
                                c.lineTo(cx + 18, cy)
                                c.stroke()
                                c.beginPath()
                                c.arc(cx, cy, r, 0, Math.PI * 2)
                                c.strokeStyle = root.border
                                c.lineWidth = 3
                                c.stroke()
                            }
                        }
                    }
                }
            }

            ModernWorkspacePage {
                anchors.fill: parent
                visible: root.activeModernSection === "plan"
                contentComponent: planViewComponent
                sectionLabel: "PLAN"
                title: "Mission Planning"
                subtitle: "Modern Briech mission design workspace"
                accentColor: root.gold
                metrics: [
                    { label: "MISSION", value: "DRAFT" },
                    { label: "WAYPOINTS", value: root.missionCoordinates.length },
                    { label: "AIRSPACE", value: "4 ZONES" },
                    { label: "UPLOAD", value: "READY" }
                ]
            }

            ModernWorkspacePage {
                anchors.fill: parent
                visible: root.activeModernSection === "analyze"
                sectionLabel: "ANALYZE"
                title: "Flight Intelligence"
                subtitle: "Logs, trends, telemetry review, and post-flight insight"
                accentColor: root.blue
                metrics: [
                    { label: "LOGS", value: "LOCAL" },
                    { label: "TREND", value: "LIVE" },
                    { label: "EVENTS", value: "0" },
                    { label: "EXPORT", value: "IDLE" }
                ]
            }

            ModernWorkspacePage {
                anchors.fill: parent
                visible: root.activeModernSection === "vehicle"
                sectionLabel: "VEHICLE"
                title: "Vehicle Configuration"
                subtitle: "Airframe, sensors, safety, radio, and parameter setup"
                accentColor: root.ok
                metrics: [
                    { label: "LINK", value: activeVehicle ? "ONLINE" : "OFFLINE" },
                    { label: "FRAME", value: activeVehicle ? "UAS" : "--" },
                    { label: "PARAMS", value: activeVehicle ? "READY" : "WAIT" },
                    { label: "SAFETY", value: "CHECK" }
                ]
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: "#05070a"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: root.gold
                opacity: 0.85
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 18

                Text {
                    text: activeVehicle ? "ARMED" : "DISARMED"
                    color: activeVehicle ? root.gold : root.dim
                    font.bold: true
                    font.pixelSize: 11
                    font.family: "Geo-Regular"
                }

                Text {
                    text: "ALT " + (activeVehicle ? activeVehicle.altitudeRelative.valueString : "0.0") + " m"
                    color: root.text
                    font.pixelSize: 10
                    font.family: "Geo-Regular"
                }

                Text {
                    text: "GS " + (activeVehicle ? activeVehicle.groundSpeed.valueString : "0.0") + " m/s"
                    color: root.text
                    font.pixelSize: 10
                    font.family: "Geo-Regular"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "BRIECH UAS GCS"
                    color: root.gold
                    font.bold: true
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    font.family: "Geo-Regular"
                }
            }
        }
    }

    component ModernZoneLabel: Rectangle {
        property alias text: label.text
        property color borderColor: root.gold
        property color textColor: root.gold

        width: Math.max(68, label.implicitWidth + 18)
        height: 22
        radius: 4
        color: "#cc080a0e"
        border.color: borderColor
        border.width: 1

        Text {
            id: label
            anchors.centerIn: parent
            color: textColor
            font.pixelSize: 9
            font.bold: true
            font.family: "Geo-Regular"
            font.letterSpacing: 1
        }
    }

    component ModernWaypointMarker: Rectangle {
        property int number: 1
        property bool highlight: false

        width: highlight ? 24 : 20
        height: width
        radius: width / 2
        color: highlight ? root.warn : root.blue
        border.color: "white"
        border.width: highlight ? 2 : 1

        Text {
            anchors.centerIn: parent
            text: number
            color: "white"
            font.pixelSize: highlight ? 11 : 10
            font.bold: true
            font.family: "Geo-Regular"
        }
    }

    component ModernWorkspacePage: Rectangle {
        property string sectionLabel: ""
        property string title: ""
        property string subtitle: ""
        property color accentColor: root.gold
        property var metrics: []
        property Component contentComponent: null

        color: root.bg

        // If a contentComponent is provided, show it full-bleed and hide the built-in header/metrics.
        Loader {
            id: fullContentLoader
            anchors.fill: parent
            sourceComponent: contentComponent
            visible: contentComponent !== null
            z: 999
        }

        Rectangle {
            anchors.fill: parent
            color: "#05070a"
            visible: contentComponent === null
        }

        Rectangle {
            anchors.fill: parent
            color: accentColor
            opacity: 0.025
            visible: contentComponent === null
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 22
            visible: contentComponent === null

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 4
                    Layout.fillHeight: true
                    color: accentColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: sectionLabel
                        color: accentColor
                        font.pixelSize: 10
                        font.bold: true
                        font.family: "Geo-Regular"
                        font.letterSpacing: 2
                    }

                    Text {
                        text: title
                        color: "#f8fafc"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: "Geo-Regular"
                    }

                    Text {
                        text: subtitle
                        color: root.dim
                        font.pixelSize: 12
                        font.family: "Geo-Regular"
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: metrics

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        color: "#0c1017"
                        border.color: "#222a35"
                        border.width: 1
                        radius: 4

                        Column {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            spacing: 7

                            Text {
                                text: modelData.label
                                color: root.dim
                                font.pixelSize: 9
                                font.family: "Geo-Regular"
                                font.letterSpacing: 1
                            }

                            Text {
                                text: modelData.value
                                color: accentColor
                                font.pixelSize: 16
                                font.bold: true
                                font.family: "Geo-Regular"
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#090d13"
                border.color: "#202734"
                border.width: 1
                radius: 6

                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    sourceComponent: contentComponent
                    visible: contentComponent !== null
                }

                Item {
                    anchors.fill: parent
                    visible: contentComponent === null

                    Column {
                        anchors.centerIn: parent
                        spacing: 12

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 44
                            height: 44
                            radius: 22
                            color: "#101722"
                            border.color: accentColor

                            Text {
                                anchors.centerIn: parent
                                text: sectionLabel.length > 0 ? sectionLabel.charAt(0) : "-"
                                color: accentColor
                                font.pixelSize: 20
                                font.bold: true
                                font.family: "Geo-Regular"
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: title + " page slot"
                            color: root.text
                            font.pixelSize: 15
                            font.bold: true
                            font.family: "Geo-Regular"
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Ready for the dedicated Modern " + sectionLabel.toLowerCase() + " QML page."
                            color: root.dim
                            font.pixelSize: 11
                            font.family: "Geo-Regular"
                        }
                    }
                }
            }
        }
    }

    component ModernNavButton: Rectangle {
        signal clicked()
        property string label: ""
        property string iconSource: ""
        property bool active: false

        Layout.preferredWidth: Math.max(82, labelText.implicitWidth + 40)
        Layout.fillHeight: true
        color: active ? "#151922" : (mouseArea.containsMouse ? "#111720" : "#0b0f15")
        border.color: active ? "#303641" : "#171d27"
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: active ? root.gold : "transparent"
        }

        Row {
            anchors.centerIn: parent
            spacing: 7

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 13
                height: 13
                source: iconSource
                fillMode: Image.PreserveAspectFit
                opacity: active ? 1 : 0.42
            }

            Text {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: active ? "#ffffff" : root.dim
                font.pixelSize: 11
                font.bold: true
                font.family: "Geo-Regular"
                font.letterSpacing: 1
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }
}
