import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap
import QGroundControl.Viewer3D
import Custom.Widgets 1.0

Item {
    id: root
    anchors.fill: parent
    clip: true

    property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property color gold: BriechTheme.goldAccent
    property color bg: BriechTheme.bgPrimary
    property color panel: BriechTheme.panelBg
    property color panel2: BriechTheme.panelBg2
    property color border: BriechTheme.borderColor
    property color dim: BriechTheme.mutedColor
    property color text: BriechTheme.textColor
    property color ok: BriechTheme.okColor
    property color warn: BriechTheme.warnColor
    property color err: BriechTheme.errColor
    property color blue: BriechTheme.blueColor
    property string activeModernSection: "fly"
    property string selectedMapKind: "satellite"
    property string selectedRiskZone: ""
    property bool _mapTypeInitialized: false
    property int missionScrubIndex: 0
    property bool payloadPanelOpen: false
    property string payloadView: "video"
    property string payloadVideoMode: "EO"
    property int payloadZoomIndex: 0
    property real payloadZoomLevel: 1
    property real batteryPercent: 82
    property real riskPulse: 0
    property var defaultCenter: QtPositioning.coordinate(9.0765, 7.3986)
    property var overlayCenter: activeVehicle && activeVehicle.coordinate.isValid ? activeVehicle.coordinate : (QGroundControl.flightMapPosition.isValid ? QGroundControl.flightMapPosition : defaultCenter)
    property var speedHistory: [12, 13, 12.4, 13.2, 14.1, 15.0, 16.2, 16.8, 17.3, 17.1, 17.7, 18.2, 18.0]
    property var altitudeHistory: [110, 112, 113, 114, 115, 118, 121, 123, 124, 124, 123, 124, 124]
    property var batteryHistory: [82, 82, 82, 81, 81, 81, 80, 80, 80, 80, 79, 79, 78]

    property var missionCoordinates: []

    ListModel {
        id: toastModel
    }

    function telemetryValue(fact, fallback) {
        return fact ? fact.valueString : fallback
    }

    function numericFactValue(fact, fallback) {
        if (!fact) {
            return fallback
        }
        const value = Number(fact.rawValue)
        return isNaN(value) ? fallback : value
    }

    function currentBatteryPercent() {
        if (activeVehicle && activeVehicle.batteries && activeVehicle.batteries.count > 0) {
            let lowest = NaN
            for (let i = 0; i < activeVehicle.batteries.count; i++) {
                const battery = activeVehicle.batteries.get(i)
                const percent = battery && battery.percentRemaining ? Number(battery.percentRemaining.rawValue) : NaN
                if (!isNaN(percent) && (isNaN(lowest) || percent < lowest)) {
                    lowest = percent
                }
            }
            if (!isNaN(lowest)) {
                return lowest
            }
        }
        return 82
    }

    function appendSample(series, sample, maxCount) {
        const next = series.slice()
        next.push(sample)
        while (next.length > maxCount) {
            next.shift()
        }
        return next
    }

    function refreshTelemetrySamples() {
        const speed = activeVehicle ? numericFactValue(activeVehicle.groundSpeed, 0) : 0
        const altitude = activeVehicle ? numericFactValue(activeVehicle.altitudeRelative, 0) : 0
        const battery = currentBatteryPercent()

        speedHistory = appendSample(speedHistory, speed, 40)
        altitudeHistory = appendSample(altitudeHistory, altitude, 40)
        batteryHistory = appendSample(batteryHistory, battery, 40)
        batteryPercent = battery
    }

    function pushToast(title, message, tone, durationMs) {
        toastModel.append({
            title: title,
            message: message,
            tone: tone || "info",
            expiresAt: Date.now() + (durationMs || 3500)
        })
        toastSweepTimer.start()
    }

    function updateMissionWaypoint(index, coordinate) {
        const next = missionCoordinates.slice()
        next[index] = coordinate
        missionCoordinates = next
        missionScrubIndex = index
        pushToast(qsTr("Waypoint %1").arg(index + 1), qsTr("Waypoint repositioned."), "info", 2400)
    }

    function focusMissionWaypoint(index, announce) {
        if (missionCoordinates.length === 0) {
            return
        }
        const safeIndex = Math.max(0, Math.min(index, missionCoordinates.length - 1))
        missionScrubIndex = safeIndex
        const coordinate = missionCoordinateAt(safeIndex)
        if (modernMap.mapReady && coordinate.isValid) {
            modernMap.center = coordinate
            modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 15)
        }
        if (announce !== false) {
            pushToast(qsTr("Mission"), qsTr("Waypoint %1 focused on the map.").arg(safeIndex + 1), "info", 2200)
        }
    }

    function openPayload(view) {
        payloadView = view
        payloadPanelOpen = true
        if (view === "3d") {
            pushToast(qsTr("Payload"), qsTr("3D view opened."), "info", 2200)
        } else {
            pushToast(qsTr("Payload"), qsTr("Video feed opened."), "info", 2200)
        }
    }

    function closePayload() {
        payloadPanelOpen = false
    }

    function setPayloadMode(mode) {
        payloadVideoMode = mode
    }

    function cyclePayloadZoom() {
        const zoomLevels = [1, 2, 4, 8]
        payloadZoomIndex = (payloadZoomIndex + 1) % zoomLevels.length
        payloadZoomLevel = zoomLevels[payloadZoomIndex]
    }

    function missionCoordinateAt(index) {
        if (index < 0) {
            return missionCoordinates[0]
        }
        if (index >= missionCoordinates.length) {
            return missionCoordinates[missionCoordinates.length - 1]
        }
        return missionCoordinates[index]
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
            pushToast(qsTr("Map"), qsTr("%1 map active").arg(kind.charAt(0).toUpperCase() + kind.slice(1)), "info", 2200)
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
        pushToast(qsTr("Modern GCS"), qsTr("Map and telemetry layers are ready."), "ok", 3200)
    }

    function fitModernMission() {
        if (modernMap.mapReady && missionCoordinates.length > 1) {
            modernMap.setVisibleRegion(QtPositioning.rectangle(offsetCoordinate(0.18, -0.31), offsetCoordinate(-0.20, 0.21)))
            pushToast(qsTr("Mission"), qsTr("View fitted to the current mission envelope."), "info", 2400)
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

    function riskZoneSpec(kind) {
        switch (kind) {
        case "nfz":
            return {
                center: offsetCoordinate(0.096, -0.037),
                zoom: 13,
                region: QtPositioning.rectangle(offsetCoordinate(0.145, -0.12), offsetCoordinate(0.055, 0.03)),
                toast: qsTr("NFZ focused. Keep clear.")
            }
        case "restricted":
            return {
                center: offsetCoordinate(-0.070, 0.020),
                zoom: 13,
                region: QtPositioning.rectangle(offsetCoordinate(-0.020, -0.040), offsetCoordinate(-0.120, 0.085)),
                toast: qsTr("Restricted airspace focused.")
            }
        case "advisory":
            return {
                center: offsetCoordinate(-0.014, 0.182),
                zoom: 12,
                region: QtPositioning.rectangle(offsetCoordinate(0.060, 0.115), offsetCoordinate(-0.080, 0.245)),
                toast: qsTr("Advisory zone focused.")
            }
        case "radar":
            return {
                center: offsetCoordinate(-0.086, -0.140),
                zoom: 13,
                region: QtPositioning.rectangle(offsetCoordinate(-0.020, -0.075), offsetCoordinate(-0.150, -0.206)),
                toast: qsTr("Radar coverage focused.")
            }
        case "fleet":
            return {
                center: activeVehicle && activeVehicle.coordinate.isValid ? activeVehicle.coordinate : offsetCoordinate(0.095, 0.083),
                zoom: 14,
                region: activeVehicle && activeVehicle.coordinate.isValid
                    ? QtPositioning.rectangle(offsetCoordinate(0.030, 0.030), offsetCoordinate(-0.030, -0.030))
                    : QtPositioning.rectangle(offsetCoordinate(0.150, 0.150), offsetCoordinate(0.025, 0.020)),
                toast: qsTr("Fleet focus active.")
            }
        default:
            return null
        }
    }

    function riskZoneOpacity(kind) {
        if (!selectedRiskZone || selectedRiskZone === kind) {
            return 1.0
        }
        return 0.28
    }

    function riskZonePulseOpacity(kind) {
        const pulse = 0.88 + 0.12 * ((Math.sin(riskPulse) + 1) / 2)
        return riskZoneOpacity(kind) * pulse
    }

    function riskZoneBorderWidth(kind) {
        return selectedRiskZone === kind ? 3 : 2
    }

    function selectRiskZone(kind) {
        const spec = riskZoneSpec(kind)
        if (!spec) {
            return
        }
        selectedRiskZone = kind
        if (kind === "fleet") {
            centerOnVehicle()
        } else {
            if (modernMap.mapReady && spec.region) {
                modernMap.setVisibleRegion(spec.region)
            } else {
                modernMap.center = spec.center
                modernMap.zoomLevel = Math.max(modernMap.zoomLevel, spec.zoom)
            }
        }
        pushToast(qsTr("Risk Zone"), spec.toast, "warn", 2600)
    }

    Timer {
        interval: 60
        running: true
        repeat: true
        onTriggered: root.riskPulse += 0.18
    }

    function activateModernSection(section) {
        activeModernSection = section
        if (section !== "fly") {
            payloadPanelOpen = false
        }
        if (section !== "fly") {
            pushToast(qsTr("Modern %1").arg(section.toUpperCase()), qsTr("Workspace opened."), "info", 2200)
        }
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
            pushToast(qsTr("Vehicle"), qsTr("Connection closed."), "warn", 2200)
        } else {
            QGroundControl.startPX4MockLink(true)
            pushToast(qsTr("Vehicle"), qsTr("Mock vehicle link started."), "ok", 2800)
        }
    }

    Timer {
        id: telemetryTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.refreshTelemetrySamples()
    }

    Timer {
        id: toastSweepTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: {
            for (let i = toastModel.count - 1; i >= 0; i--) {
                if (toastModel.get(i).expiresAt <= Date.now()) {
                    toastModel.remove(i)
                }
            }
            if (toastModel.count === 0) {
                stop()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.bg
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.topMargin: 10
        width: modernBadge.implicitWidth + 24
        height: 24
        color: "#0b0f15"
        border.color: root.gold
        border.width: 1
        radius: 3
        z: 999

       
    }

    Component.onCompleted: {
        refreshTelemetrySamples()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
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
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    source: "qrc:/Briech/res/logoBlack.png"
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    text: "BRIECH UAS"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 20
                    font.letterSpacing: 2
                    font.family: "Barlow Condensed"
                }

                Text {
                    text: "Ground Control Station"
                    color: root.gold
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    font.family: "Barlow Condensed"
                    font.bold: true
                }

                Item { Layout.fillWidth: true }
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
                            font.pixelSize: 16
                            font.bold: true
                            font.family: "Barlow Condensed"
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
                                font.pixelSize: 14
                                font.family: "Barlow Condensed"
                                font.bold: true
                            }

                            Text {
                                id: value
                                text: modelData.v
                                color: modelData.k === "BATT" || modelData.k === "MODE" ? root.ok : root.text
                                font.pixelSize: 14
                                font.bold: true
                                font.family: "Barlow Condensed"
                            }

                            Text {
                                id: unit
                                text: modelData.u
                                color: root.dim
                                font.pixelSize: 16
                                font.family: ScreenTools.normalFontFamily
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

                        onZoomLevelChanged: QGroundControl.flightMapZoom = modernMap.zoomLevel
                        onCenterChanged: QGroundControl.flightMapPosition = modernMap.center
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
                            border.width: root.riskZoneBorderWidth("geofence")
                            opacity: root.riskZonePulseOpacity("geofence")
                            z: QGroundControl.zOrderMapItems
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.014, -0.095)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 1
                            opacity: root.riskZonePulseOpacity("geofence")
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
                            border.width: root.riskZoneBorderWidth("nfz")
                            opacity: root.riskZonePulseOpacity("nfz")
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(0.096, -0.037)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            opacity: root.riskZonePulseOpacity("nfz")
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
                            border.width: root.riskZoneBorderWidth("restricted")
                            opacity: root.riskZonePulseOpacity("restricted")
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.070, 0.020)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            opacity: root.riskZonePulseOpacity("restricted")
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
                            border.width: root.riskZoneBorderWidth("radar")
                            opacity: root.riskZonePulseOpacity("radar")
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.086, -0.140)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            opacity: root.riskZonePulseOpacity("radar")
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
                            border.width: root.riskZoneBorderWidth("advisory")
                            opacity: root.riskZonePulseOpacity("advisory")
                            z: QGroundControl.zOrderMapItems + 1
                        }

                        MapQuickItem {
                            coordinate: root.offsetCoordinate(-0.014, 0.182)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 2
                            opacity: root.riskZonePulseOpacity("advisory")
                            sourceItem: ModernZoneLabel { text: "ADVISORY - HIGH TRAFFIC"; borderColor: root.blue; textColor: "#93c5fd" }
                        }

                        MapPolyline {
                            path: root.missionCoordinates
                            line.width: 3
                            line.color: root.blue
                            z: QGroundControl.zOrderWaypointLines
                            visible: root.missionCoordinates.length > 0
                        }

                        MapItemView {
                            model: root.missionCoordinates
                            visible: root.missionCoordinates.length > 0
                            delegate: MapQuickItem {
                                id: waypointItem
                                property var dragCoordinate: modelData
                                coordinate: dragOverlay.itemCoordinate
                                anchorPoint.x: sourceItem.width / 2
                                anchorPoint.y: sourceItem.height / 2
                                z: QGroundControl.zOrderWaypointLines + 1
                                sourceItem: ModernWaypointMarker {
                                    number: index + 1
                                    highlight: index === root.missionScrubIndex
                                }

                                MissionItemIndicatorDrag {
                                    id: dragOverlay
                                    mapControl: modernMap
                                    itemIndicator: waypointItem
                                    itemCoordinate: waypointItem.dragCoordinate
                                    onDragStop: root.updateMissionWaypoint(index, itemCoordinate)
                                }
                            }
                        }

                        MapQuickItem {
                            coordinate: root.activeVehicle && root.activeVehicle.homePosition.isValid ? root.activeVehicle.homePosition : root.defaultCenter
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height / 2
                            z: QGroundControl.zOrderMapItems + 4
                            visible: root.activeVehicle && root.activeVehicle.homePosition.isValid
                            sourceItem: Item {
                                width: 22
                                height: 28

                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    width: 20
                                    height: 20
                                    source: "qrc:/qmlimages/MapHome.svg"
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    text: "HOME"
                                    color: root.gold
                                    font.pixelSize: 7
                                    font.family: "monospace"
                                    font.bold: true
                                }
                            }
                        }

                        MapQuickItem {
                            coordinate: activeVehicle && activeVehicle.coordinate.isValid ? activeVehicle.coordinate : root.offsetCoordinate(0.095, 0.083)
                            anchorPoint.x: sourceItem.width / 2
                            anchorPoint.y: sourceItem.height + 8
                            z: QGroundControl.zOrderVehicles + 1
                            opacity: root.riskZonePulseOpacity("fleet")
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

                    ModernToastStack {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 44
                        anchors.rightMargin: 12
                        width: 292
                        model: toastModel
                    }

                    ModernSwarmPanel {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 214
                        anchors.rightMargin: 12
                        width: 264
                        vehicleModel: QGroundControl.multiVehicleManager.vehicles
                    }

                    ModernSparklinePanel {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 76
                        anchors.bottomMargin: 232
                        width: 320
                        height: 146
                        visible: root.activeModernSection === "fly"
                        speedSeries: root.speedHistory
                        altitudeSeries: root.altitudeHistory
                        batterySeries: root.batteryHistory
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 76
                        anchors.bottomMargin: 20
                        spacing: 6

                        ModernPayloadPanel {
                            Layout.preferredWidth: 318
                            Layout.preferredHeight: 188
                            visible: root.payloadPanelOpen
                            payloadView: root.payloadView
                            videoVisible: QGroundControl.videoManager.hasVideo || QGroundControl.videoManager.isStreamSource || QGroundControl.videoManager.isUvc || QGroundControl.videoManager.decoding
                            videoMode: root.payloadVideoMode
                            zoomLevel: root.payloadZoomLevel
                            onCloseRequested: root.closePayload()
                            function onModeRequested(mode) { root.setPayloadMode(mode) }
                            onZoomRequested: root.cyclePayloadZoom()
                        }

                        RowLayout {
                            Layout.preferredWidth: 318
                            Layout.preferredHeight: 28
                            spacing: 4

                            ModernPayloadButton {
                                Layout.fillWidth: true
                                label: "VIDEO FEED"
                                iconKind: "video"
                                active: root.payloadPanelOpen && root.payloadView === "video"
                                onClicked: root.openPayload("video")
                            }

                            ModernPayloadButton {
                                Layout.fillWidth: true
                                label: "3D VIEW"
                                iconKind: "3d"
                                active: root.payloadPanelOpen && root.payloadView === "3d"
                                onClicked: root.openPayload("3d")
                            }
                        }

                    }

                    ModernBatteryArc {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 18
                        anchors.bottomMargin: 48
                        width: 214
                        height: 214
                        percent: root.batteryPercent
                    }

                    ModernMissionScrubber {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        width: Math.min(parent.width * 0.42, 620)
                        visible: root.missionCoordinates.length > 0
                        maxIndex: root.missionCoordinates.length - 1
                        currentIndex: root.missionScrubIndex
                        function onScrubbed(scrubIndex) { root.focusMissionWaypoint(scrubIndex, true) }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 10
                        width: 154
                        height: 26
                        color: "#0b0f15"
                        border.color: root.gold
                        border.width: 1
                        radius: 2

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 10
                                height: 10
                                color: "transparent"
                                border.color: root.gold
                                border.width: 1
                                rotation: 45
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "MISSION TIMELINE"
                                color: root.gold
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                                font.letterSpacing: 1
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
                                c.font = "10px \"" + ScreenTools.normalFontFamily + "\""
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
                                c.font = "bold 10px \"" + ScreenTools.normalFontFamily + "\""
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
                            font.family: ScreenTools.normalFontFamily
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
                                    font.family: ScreenTools.normalFontFamily
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
                        anchors.top: parent.top
                        anchors.leftMargin: 64
                        anchors.topMargin: 84
                        spacing: 4

                        Repeater {
                            model: [
                                { label: "NFZ", key: "nfz", tone: root.err },
                                { label: "RESTRICTED", key: "restricted", tone: root.warn },
                                { label: "ADVISORY", key: "advisory", tone: root.blue },
                                { label: "RADAR", key: "radar", tone: "#a855f7" }
                            ]

                            delegate: Rectangle {
                                width: 112
                                height: 28
                                property bool active: root.selectedRiskZone === modelData.key
                                color: active ? "#211606" : "#0c1017"
                                border.color: modelData.tone
                                border.width: active ? 2 : 1

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 4
                                    color: modelData.tone
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: modelData.tone
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                    font.letterSpacing: 1
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.selectRiskZone(modelData.key)
                                }
                            }
                        }

                        Rectangle {
                            width: 112
                            height: 28
                            color: root.selectedRiskZone === "fleet" ? "#1a1609" : "#0c1017"
                            border.color: root.gold
                            border.width: root.selectedRiskZone === "fleet" ? 2 : 1

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 4
                                color: root.gold
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "FLEET"
                                color: root.gold
                                font.pixelSize: 10
                                font.bold: true
                                font.family: "monospace"
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.selectRiskZone("fleet")
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
                                        font.family: ScreenTools.normalFontFamily
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
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "ALT " + (activeVehicle ? activeVehicle.altitudeRelative.valueString : "0.0") + " m"
                    color: root.text
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Text {
                    text: "GS " + (activeVehicle ? activeVehicle.groundSpeed.valueString : "0.0") + " m/s"
                    color: root.text
                    font.pixelSize: 10
                    font.family: ScreenTools.normalFontFamily
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "BRIECH UAS GCS"
                    color: root.gold
                    font.bold: true
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    font.family: ScreenTools.normalFontFamily
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
            font.family: ScreenTools.normalFontFamily
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
            font.family: ScreenTools.normalFontFamily
        }
    }

    component ModernToastStack: Item {
        property var model

        implicitHeight: stackColumn.implicitHeight

        Column {
            id: stackColumn
            anchors.fill: parent
            spacing: 8

            Repeater {
                model: parent.model
                delegate: Rectangle {
                    width: parent.width
                    height: 58
                    radius: 4
                    color: "#11151c"
                    border.color: modelData.tone === "ok" ? "#22c55e" : modelData.tone === "warn" ? "#f59e0b" : "#2a3340"
                    border.width: 1

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        color: modelData.tone === "ok" ? "#22c55e" : modelData.tone === "warn" ? "#f59e0b" : "#3b82f6"
                    }

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 36
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 2

                        Text {
                            text: modelData.title
                            color: "#f8fafc"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }

                        Text {
                            text: modelData.message
                            color: "#aab3c1"
                            wrapMode: Text.WordWrap
                            font.pixelSize: 9
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        text: "x"
                        color: "#6a7585"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }
    }

    component ModernSparklinePanel: Rectangle {
        property var speedSeries: []
        property var altitudeSeries: []
        property var batterySeries: []

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "LIVE TRENDS"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "SPD / ALT / BATT"
                    color: root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }
            }

            Canvas {
                id: sparkCanvas
                Layout.fillWidth: true
                Layout.fillHeight: true

                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    c.clearRect(0, 0, width, height)

                    function drawSeries(series, color, yMin, yMax, offsetY) {
                        if (!series || series.length < 2) {
                            return
                        }
                        const pad = 6
                        const w = width - pad * 2
                        const h = height - pad * 2
                        c.beginPath()
                        for (let i = 0; i < series.length; i++) {
                            const x = pad + (i / (series.length - 1)) * w
                            const normalized = Math.max(0, Math.min(1, (series[i] - yMin) / (yMax - yMin)))
                            const y = pad + offsetY + h - normalized * (h * 0.32)
                            if (i === 0) c.moveTo(x, y)
                            else c.lineTo(x, y)
                        }
                        c.strokeStyle = color
                        c.lineWidth = 2
                        c.stroke()
                    }

                    c.strokeStyle = "rgba(255,255,255,0.05)"
                    c.lineWidth = 1
                    for (let i = 1; i < 4; i++) {
                        c.beginPath()
                        c.moveTo(0, (height / 4) * i)
                        c.lineTo(width, (height / 4) * i)
                        c.stroke()
                    }

                    drawSeries(speedSeries, "#3b82f6", 0, 30, 2)
                    drawSeries(altitudeSeries, "#22c55e", 0, 200, 14)
                    drawSeries(batterySeries, "#f59e0b", 0, 100, 26)
                }

                Connections {
                    target: root
                    function onSpeedHistoryChanged() { sparkCanvas.requestPaint() }
                    function onAltitudeHistoryChanged() { sparkCanvas.requestPaint() }
                    function onBatteryHistoryChanged() { sparkCanvas.requestPaint() }
                }
            }
        }
    }

    component ModernBatteryArc: Rectangle {
        property real percent: 0
        property real displayPercent: percent

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: width / 2

        Behavior on displayPercent {
            NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
        }

        onPercentChanged: displayPercent = Math.max(0, Math.min(100, percent))

        Canvas {
            id: arcCanvas
            anchors.fill: parent

            onPaint: {
                const c = getContext("2d")
                c.reset()
                c.clearRect(0, 0, width, height)
                const cx = width / 2
                const cy = height / 2
                const r = Math.min(width, height) * 0.38
                const start = -Math.PI * 0.75
                const end = start + (Math.PI * 1.5) * (displayPercent / 100)

                c.beginPath()
                c.arc(cx, cy, r, start, start + Math.PI * 1.5)
                c.strokeStyle = "rgba(255,255,255,0.06)"
                c.lineWidth = 12
                c.lineCap = "round"
                c.stroke()

                c.beginPath()
                c.arc(cx, cy, r, start, end)
                c.strokeStyle = displayPercent > 30 ? (displayPercent > 60 ? "#22c55e" : "#f59e0b") : "#ef4444"
                c.lineWidth = 12
                c.lineCap = "round"
                c.stroke()

                c.fillStyle = "#f8fafc"
                c.font = "bold 30px monospace"
                c.textAlign = "center"
                c.fillText(Math.round(displayPercent).toString(), cx, cy + 11)
                c.fillStyle = "#6a7585"
                c.font = "10px monospace"
                c.fillText("BATTERY", cx, cy - 24)
            }
        }
    }

    component ModernVideoFeedPanel: Rectangle {
        property bool videoVisible: false
        property string videoMode: "EO"
        property real zoomLevel: 1
        signal modeRequested(string mode)
        signal zoomRequested()

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "LIVE VIDEO FEED"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: videoVisible ? "STREAMING" : "IDLE"
                    color: videoVisible ? "#22c55e" : root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#05070a"
                border.color: "#202734"
                border.width: 1
                clip: true

                Loader {
                    anchors.fill: parent
                    active: videoVisible
                    visible: videoVisible
                    source: "qrc:/qml/QGroundControl/FlyView/QGCVideoBackground.qml"
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 8
                    anchors.topMargin: 8
                    width: implicitWidth + 14
                    height: 18
                    color: "#0a0f15"
                    border.color: videoVisible ? "#22c55e" : root.gold
                    border.width: 1
                    radius: 2
                    visible: true

                    property string _statusText: videoVisible ? (videoMode + " | " + zoomLevel + "x") : "NO LINK"
                    implicitWidth: statusLabel.implicitWidth

                    Text {
                        id: statusLabel
                        anchors.centerIn: parent
                        text: parent._statusText
                        color: videoVisible ? "#22c55e" : root.gold
                        font.pixelSize: 8
                        font.bold: true
                        font.family: "monospace"
                        font.letterSpacing: 1
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#05070a"
                    opacity: videoVisible ? 0.08 : 0.82
                    visible: !videoVisible
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: !videoVisible

                    Text {
                        text: "VIDEO FEED"
                        color: root.dim
                        font.pixelSize: 12
                        font.family: "monospace"
                        font.bold: true
                    }

                    Text {
                        text: "No active stream"
                        color: "#8b93a3"
                        font.pixelSize: 10
                    }

                    Row {
                        spacing: 8

                        Rectangle {
                            width: 82
                            height: 24
                            color: "#0b0f15"
                            border.color: root.gold
                            Text {
                                anchors.centerIn: parent
                                text: "START"
                                color: root.gold
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: QGroundControl.videoManager.startVideo()
                            }
                        }

                        Rectangle {
                            width: 82
                            height: 24
                            color: "#0b0f15"
                            border.color: root.border
                            Text {
                                anchors.centerIn: parent
                                text: "STOP"
                                color: root.dim
                                font.pixelSize: 9
                                font.bold: true
                                font.family: "monospace"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: QGroundControl.videoManager.stopVideo()
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: 122
                    height: 20
                    color: "#0a0f15"
                    border.color: "#24303f"
                    border.width: 1
                    radius: 2

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "VIDEO"
                            color: root.dim
                            font.pixelSize: 8
                            font.family: "monospace"
                            font.bold: true
                        }

                        Text {
                            text: videoVisible ? "LIVE" : "STANDBY"
                            color: videoVisible ? "#22c55e" : root.dim
                            font.pixelSize: 8
                            font.family: "monospace"
                            font.bold: true
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: [
                        { label: "EO", key: "EO" },
                        { label: "IR", key: "IR" },
                        { label: "BLEND", key: "BLEND" }
                    ]

                    delegate: Rectangle {
                        Layout.preferredWidth: modelData.key === "BLEND" ? 52 : 30
                        Layout.preferredHeight: 20
                        color: videoMode === modelData.key ? "#1a1407" : "#0b0f15"
                        border.color: videoMode === modelData.key ? root.gold : root.border
                        border.width: 1
                        radius: 2

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: videoMode === modelData.key ? root.gold : root.dim
                            font.pixelSize: 8
                            font.bold: true
                            font.family: "monospace"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: modeRequested(modelData.key)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "ZOOM " + zoomLevel + "x"
                    color: root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    color: "#0b0f15"
                    border.color: root.border
                    border.width: 1
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: "⊕"
                        color: root.gold
                        font.pixelSize: 10
                        font.family: "monospace"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: zoomRequested()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 20
                    color: "#0b0f15"
                    border.color: root.gold
                    border.width: 1
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: "START"
                        color: root.gold
                        font.pixelSize: 8
                        font.family: "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: QGroundControl.videoManager.startVideo()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 20
                    color: "#0b0f15"
                    border.color: root.border
                    border.width: 1
                    radius: 2

                    Text {
                        anchors.centerIn: parent
                        text: "STOP"
                        color: root.dim
                        font.pixelSize: 8
                        font.family: "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: QGroundControl.videoManager.stopVideo()
                    }
                }
            }
        }
    }

    component ModernViewer3DPanel: Rectangle {
        property bool viewer3DEnabled: QGroundControl.settingsManager.viewer3DSettings.enabled.rawValue

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "LIVE 3D VIEW"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: viewer3DEnabled ? "READY" : "DISABLED"
                    color: viewer3DEnabled ? "#22c55e" : root.dim
                    font.pixelSize: 8
                    font.family: "monospace"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#05070a"
                border.color: "#202734"
                border.width: 1
                clip: true

                Viewer3D {
                    anchors.fill: parent
                    visible: viewer3DEnabled
                    Component.onCompleted: {
                        if (viewer3DEnabled) {
                            open()
                        }
                    }
                    Component.onDestruction: close()
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: !viewer3DEnabled

                    Text {
                        text: "3D VIEW"
                        color: root.dim
                        font.pixelSize: 12
                        font.family: "monospace"
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Viewer3D is disabled in settings"
                        color: "#8b93a3"
                        font.pixelSize: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    component ModernPayloadPanel: Rectangle {
        id: payloadPanel
        property string payloadView: "video"
        property bool videoVisible: false
        property string videoMode: "EO"
        property real zoomLevel: 1
        signal closeRequested()
        signal modeRequested(string mode)
        signal zoomRequested()

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4
        clip: true

        Loader {
            anchors.fill: parent
            active: root.payloadPanelOpen
            sourceComponent: payloadView === "3d" ? modern3DPanelComponent : modernVideoPanelComponent
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.rightMargin: 6
            width: 18
            height: 18
            color: "#0b0f15"
            border.color: root.border
            border.width: 1
            radius: 2
            z: 2

            Text {
                anchors.centerIn: parent
                text: "x"
                color: "#6a7585"
                font.pixelSize: 11
                font.bold: true
                font.family: "monospace"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: closeRequested()
            }
        }

        Component {
            id: modernVideoPanelComponent
            ModernVideoFeedPanel {
                anchors.fill: parent
                videoVisible: payloadPanel.videoVisible
                videoMode: payloadPanel.videoMode
                zoomLevel: payloadPanel.zoomLevel
                onModeRequested: payloadPanel.modeRequested(mode)
                onZoomRequested: payloadPanel.zoomRequested()
            }
        }

        Component {
            id: modern3DPanelComponent
            ModernViewer3DPanel {
                anchors.fill: parent
            }
        }
    }

    component ModernPayloadButton: Rectangle {
        signal clicked()
        property string label: ""
        property string iconKind: "video"
        property bool active: false
        property bool hovered: false

        Layout.preferredHeight: 26
        color: active ? "rgba(201,168,76,0.10)" : (hovered ? "rgba(201,168,76,0.06)" : "rgba(15,18,24,0.80)")
        border.color: active ? "rgba(201,168,76,0.85)" : (hovered ? "rgba(201,168,76,0.45)" : "rgba(201,168,76,0.22)")
        border.width: 1
        radius: 2

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5
            spacing: 6

            Item {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                visible: iconKind === "video"

                Rectangle {
                    x: 0
                    y: 2
                    width: 8
                    height: 8
                    color: active ? root.gold : root.dim
                    radius: 1
                }

                Rectangle {
                    x: 8
                    y: 4
                    width: 3
                    height: 4
                    color: active ? root.gold : root.dim
                    radius: 1
                }
            }

            Image {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                visible: iconKind === "3d"
                source: "/qml/QGroundControl/Viewer3D/City3DMapIcon.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: active ? 1.0 : 0.72
            }

                Text {
                    Layout.fillWidth: true
                    text: label
                    color: active ? root.gold : "#c9a84c"
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: hovered = true
            onExited: hovered = false
            onClicked: clicked()
        }
    }

    component ModernSwarmPanel: Rectangle {
        property var vehicleModel

        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "SWARM"
                    color: root.gold
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "monospace"
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: vehicleModel ? vehicleModel.count : 0
                    color: root.text
                    font.pixelSize: 10
                    font.family: "monospace"
                }
            }

            Repeater {
                model: vehicleModel
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: "#0c1017"
                    border.color: "#1f2631"
                    border.width: 1
                    radius: 3
                    property var vehicleObject: object

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: object === activeVehicle ? "#22c55e" : root.blue
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        text: "BRCH-" + object.id
                        color: root.text
                        font.pixelSize: 9
                        font.family: "monospace"
                        font.bold: true
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 10
                        text: object.flightMode
                        color: root.dim
                        font.pixelSize: 8
                        font.family: "monospace"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 10
                        anchors.bottomMargin: 3
                        text: object.armed ? "ARMED" : "STBY"
                        color: object.armed ? "#22c55e" : root.dim
                        font.pixelSize: 7
                        font.family: "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (vehicleObject && vehicleObject.coordinate && vehicleObject.coordinate.isValid) {
                                modernMap.center = vehicleObject.coordinate
                                modernMap.zoomLevel = Math.max(modernMap.zoomLevel, 16)
                                pushToast(qsTr("Swarm"), qsTr("Focused BRCH-%1 on the map.").arg(vehicleObject.id), "info", 2200)
                            }
                        }
                    }
                }
            }
        }
    }

    component ModernMissionScrubber: Rectangle {
        property int maxIndex: 0
        property int currentIndex: 0
        signal scrubbed(int scrubIndex)
        readonly property int _safeMaxIndex: Math.max(0, maxIndex)
        readonly property int _waypointCount: _safeMaxIndex + 1
        readonly property real _progress: _safeMaxIndex > 0 ? Math.min(currentIndex, _safeMaxIndex) / _safeMaxIndex : 0

        implicitHeight: 74
        color: "#090d13"
        border.color: "#202734"
        border.width: 1
        radius: 4

        onCurrentIndexChanged: missionCanvas.requestPaint()
        onMaxIndexChanged: missionCanvas.requestPaint()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "MISSION TIMELINE"
                    color: root.gold
                    font.pixelSize: 9
                    font.bold: true
                    font.family: "monospace"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "WP " + (Math.min(currentIndex, _safeMaxIndex) + 1) + " / " + _waypointCount
                    color: root.dim
                    font.pixelSize: 9
                    font.family: "monospace"
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Canvas {
                    id: missionCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const w = width
                        const h = height
                        const pad = 4
                        const railY = h / 2
                        const railLeft = pad
                        const railWidth = w - pad * 2
                        const activeRatio = _safeMaxIndex > 0 ? Math.min(currentIndex, _safeMaxIndex) / _safeMaxIndex : 0
                        const markerX = railLeft + (railWidth * activeRatio)

                        ctx.lineWidth = 1
                        ctx.strokeStyle = "#27303b"
                        ctx.fillStyle = "#0f1319"
                        ctx.fillRect(railLeft, railY - 5, railWidth, 10)
                        ctx.strokeRect(railLeft + 0.5, railY - 4.5, railWidth - 1, 9)

                        ctx.fillStyle = "#151b23"
                        ctx.fillRect(railLeft, railY - 8, railWidth, 16)

                        ctx.fillStyle = "#1a2028"
                        ctx.fillRect(railLeft, railY - 2, railWidth, 4)

                        ctx.fillStyle = root.gold
                        ctx.fillRect(railLeft, railY - 2, railWidth * activeRatio, 4)

                        for (let i = 0; i <= _safeMaxIndex; i++) {
                            const x = railLeft + (railWidth * (_safeMaxIndex === 0 ? 0 : i / _safeMaxIndex))
                            ctx.beginPath()
                            ctx.strokeStyle = i <= currentIndex ? root.gold : "#46505f"
                            ctx.moveTo(x, railY - 7)
                            ctx.lineTo(x, railY + 7)
                            ctx.stroke()

                            ctx.fillStyle = i <= currentIndex ? root.gold : "#54606f"
                            ctx.beginPath()
                            ctx.arc(x, railY, i === currentIndex ? 4 : 2.5, 0, Math.PI * 2)
                            ctx.fill()
                        }

                        ctx.strokeStyle = "rgba(201,168,76,0.88)"
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.moveTo(railLeft, railY)
                        ctx.lineTo(markerX, railY)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.fillStyle = root.gold
                        ctx.moveTo(markerX, railY + 9)
                        ctx.lineTo(markerX - 5, railY + 2)
                        ctx.lineTo(markerX + 5, railY + 2)
                        ctx.closePath()
                        ctx.fill()
                    }

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }

                Slider {
                    id: missionSlider
                    anchors.fill: parent
                    from: 0
                    to: Math.max(0, maxIndex)
                    stepSize: 1
                    snapMode: Slider.SnapAlways
                    value: Math.min(currentIndex, Math.max(0, maxIndex))
                    onMoved: scrubbed(Math.round(value))
                    onPressedChanged: if (!pressed) scrubbed(Math.round(value))

                    background: Item { }

                    handle: Rectangle {
                        x: missionSlider.leftPadding + (missionSlider.visualPosition * (missionSlider.availableWidth - width))
                        y: missionSlider.topPadding + (missionSlider.availableHeight - height) / 2
                        width: 18
                        height: 18
                        color: "#151922"
                        border.color: root.gold
                        border.width: 1
                        radius: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            color: root.gold
                            radius: 1
                        }
                    }
                }
            }
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
                        font.family: ScreenTools.normalFontFamily
                        font.letterSpacing: 2
                    }

                    Text {
                        text: title
                        color: "#f8fafc"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: ScreenTools.normalFontFamily
                    }

                    Text {
                        text: subtitle
                        color: root.dim
                        font.pixelSize: 12
                        font.family: ScreenTools.normalFontFamily
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
                                font.family: ScreenTools.normalFontFamily
                                font.letterSpacing: 1
                            }

                            Text {
                                text: modelData.value
                                color: accentColor
                                font.pixelSize: 16
                                font.bold: true
                                font.family: ScreenTools.normalFontFamily
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
                                font.family: ScreenTools.normalFontFamily
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: title + " page slot"
                            color: root.text
                            font.pixelSize: 15
                            font.bold: true
                            font.family: ScreenTools.normalFontFamily
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Ready for the dedicated Modern " + sectionLabel.toLowerCase() + " QML page."
                            color: root.dim
                            font.pixelSize: 11
                            font.family: ScreenTools.normalFontFamily
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
                opacity: (active || mouseArea.containsMouse) ? 1 : 0.42
            }

            Text {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: (active || mouseArea.containsMouse) ? "#ffffff" : root.dim
                font.pixelSize: 16
                font.family: "Barlow Condensed"
                font.bold: true
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
