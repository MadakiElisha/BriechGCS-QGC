pragma ComponentBehavior: Bound

import QtQuick
import QtLocation
import QtPositioning
import QtQml.Models

import QGroundControl
import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// Fleet map layer: while the Fleet page is open, draws on the Modern map
//   - a tag beside each connected vehicle (BRCH id, altitude, heading, data age)
//   - the coordinator's assets (towers)
//   - detected objects, with a circle for their position error
//   - active alerts, highlighted, with their error circle
// Values are live; "--" when unknown. Coordinator items fade when stale.
//
// This item is not drawn itself. The map lives outside the Fleet page, so the
// views are added to the map with addMapItemView() when the page opens and
// removed in Component.onDestruction when the Loader closes the page. That
// keeps "close Fleet" meaning "nothing of Fleet is left on the map".
Item {
    id: root

    /// The map to draw on (the Modern view's FlyViewMap). Null means draw nothing.
    property var map: null

    property var _views: []
    property var _viewMap: null

    function attach() {
        detach()
        if (!map) {
            return
        }
        // Bottom to top: error circles under markers, vehicles on top.
        const components = [objectAreaViewComponent, alertAreaViewComponent, assetViewComponent,
                            objectViewComponent, alertViewComponent, tagViewComponent]
        const views = []
        for (const component of components) {
            const view = component.createObject(map)
            if (view) {
                map.addMapItemView(view)
                views.push(view)
            }
        }
        _views = views
        _viewMap = map
    }

    function detach() {
        for (const view of _views) {
            if (_viewMap) {
                _viewMap.removeMapItemView(view)
            }
            view.destroy()
        }
        _views = []
        _viewMap = null
    }

    onMapChanged: attach()
    Component.onCompleted: attach()
    Component.onDestruction: detach()

    function coordinateOf(pos) {
        return pos && FleetFormat.has(pos.lat) && FleetFormat.has(pos.lon)
            ? QtPositioning.coordinate(pos.lat, pos.lon) : QtPositioning.coordinate()
    }

    // Only alerts still open, acknowledged or approved go on the map.
    SortFilterProxyModel {
        id: activeAlerts
        model: FleetAlertModel
        filters: [
            FunctionFilter {
                function filter(data: AlertData): bool { return data.active }
            }
        ]
    }

    component AlertData: QtObject {
        property bool active
    }

    // A small dark label used by every marker.
    component MarkerLabel: Rectangle {
        id: markerLabel

        property alias text: labelText.text
        property color tone: BriechTheme.textColor

        width: labelText.implicitWidth + 10
        height: 16
        radius: 2
        color: Qt.rgba(4 / 255, 5 / 255, 7 / 255, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1

        Text {
            id: labelText
            anchors.centerIn: parent
            color: markerLabel.tone
            font.pixelSize: 9
            font.bold: true
            font.family: "Share Tech Mono"
        }
    }

    Component {
        id: tagViewComponent

        MapItemView {
            model: QGroundControl.multiVehicleManager.vehicles

            delegate: MapQuickItem {
                id: tag

                required property var object

                coordinate: tag.object.coordinate
                visible: tag.object.coordinate.isValid
                // Negative x anchor: the vehicle sits 22 px left of the tag, so the
                // tag never covers the stock vehicle icon.
                anchorPoint.x: -22
                anchorPoint.y: tagBox.height / 2
                z: QGroundControl.zOrderVehicles + 1

                sourceItem: Rectangle {
                    id: tagBox

                    readonly property bool isActive: tag.object === QGroundControl.multiVehicleManager.activeVehicle
                    // Data age, as on the fleet cards (FleetDataAge, once a second):
                    // amber after 3 s, grey and STALE after 10 s. A stale tag is
                    // dimmed because the position it sits at is no longer current.
                    readonly property int ageLevel: FleetFormat.vehicleAgeLevel(FleetDataAge.levels, tag.object.id)
                    readonly property bool stale: ageLevel === FleetFormat.ageGrey

                    width: tagRow.implicitWidth + 12
                    height: 18
                    radius: 2
                    opacity: stale ? 0.55 : 1
                    color: Qt.rgba(4 / 255, 5 / 255, 7 / 255, 0.85)
                    border.color: isActive ? BriechTheme.goldAccent : Qt.rgba(1, 1, 1, 0.18)
                    border.width: 1

                    Row {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "BRCH-" + tag.object.id
                            color: tagBox.isActive ? BriechTheme.goldAccent : BriechTheme.textColor
                            font.pixelSize: 9
                            font.bold: true
                            font.family: "Share Tech Mono"
                        }

                        Text {
                            text: FleetFormat.factText(tag.object.altitudeRelative, 0, "m")
                            color: BriechTheme.mutedColor
                            font.pixelSize: 9
                            font.family: "Share Tech Mono"
                        }

                        Text {
                            text: FleetFormat.headingText(tag.object)
                            color: BriechTheme.mutedColor
                            font.pixelSize: 9
                            font.family: "Share Tech Mono"
                        }

                        Text {
                            text: FleetFormat.ageText(FleetFormat.vehicleAgeSeconds(FleetDataAge.seconds, tag.object.id))
                                  + (tagBox.stale ? " STALE" : "")
                            color: FleetFormat.ageTone(tagBox.ageLevel, BriechTheme)
                            font.pixelSize: 9
                            font.bold: tagBox.ageLevel === FleetFormat.ageAmber
                            font.family: "Share Tech Mono"
                        }
                    }
                }
            }
        }
    }

    // Towers: a gold square with the asset's name, coloured by health.
    Component {
        id: assetViewComponent

        MapItemView {
            model: FleetAssetModel

            delegate: MapQuickItem {
                id: asset

                required property string asset_id
                required property var name
                required property var pos
                required property var health
                required property bool stale

                coordinate: root.coordinateOf(asset.pos)
                visible: coordinate.isValid
                anchorPoint.x: 7
                anchorPoint.y: 7
                opacity: asset.stale ? 0.45 : 1
                z: QGroundControl.zOrderVehicles - 3

                sourceItem: Item {
                    width: 14 + 6 + assetLabel.width
                    height: 14

                    Rectangle {
                        width: 14
                        height: 14
                        color: Qt.rgba(4 / 255, 5 / 255, 7 / 255, 0.85)
                        border.color: BriechTheme.goldAccent
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            color: FleetFormat.healthTone(asset.health, BriechTheme)
                        }
                    }

                    MarkerLabel {
                        id: assetLabel
                        x: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: (FleetFormat.has(asset.name) ? asset.name : asset.asset_id) + (asset.stale ? " · STALE" : "")
                        tone: asset.stale ? BriechTheme.warnColor : BriechTheme.goldAccent
                    }
                }
            }
        }
    }

    // Detections: a circle for the position error under each marker.
    Component {
        id: objectAreaViewComponent

        MapItemView {
            model: FleetObjectModel

            delegate: MapCircle {
                id: objectArea

                required property var pos
                required property bool stale

                center: root.coordinateOf(objectArea.pos)
                radius: objectArea.pos && FleetFormat.has(objectArea.pos.error_m) ? objectArea.pos.error_m : 0
                visible: center.isValid && radius > 0
                color: Qt.rgba(0.23, 0.51, 0.96, objectArea.stale ? 0.06 : 0.14)
                border.color: Qt.rgba(0.23, 0.51, 0.96, objectArea.stale ? 0.3 : 0.7)
                border.width: 1
                z: QGroundControl.zOrderMapItems
            }
        }
    }

    Component {
        id: objectViewComponent

        MapItemView {
            model: FleetObjectModel

            delegate: MapQuickItem {
                id: detected

                required property var className
                required property var confidence
                required property var pos
                required property bool stale

                coordinate: root.coordinateOf(detected.pos)
                visible: coordinate.isValid
                anchorPoint.x: 5
                anchorPoint.y: 5
                opacity: detected.stale ? 0.45 : 1
                z: QGroundControl.zOrderVehicles - 2

                sourceItem: Item {
                    width: 10 + 5 + objectLabel.width
                    height: 10

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: BriechTheme.blueColor
                        border.color: "white"
                        border.width: 1
                    }

                    MarkerLabel {
                        id: objectLabel
                        x: 15
                        anchors.verticalCenter: parent.verticalCenter
                        text: FleetFormat.wordText(detected.className) + " " + FleetFormat.confidenceText(detected.confidence)
                              + (detected.stale ? " · STALE" : "")
                        tone: detected.stale ? BriechTheme.warnColor : BriechTheme.textColor
                    }
                }
            }
        }
    }

    // Active alerts: a red error circle and a red marker with the severity.
    Component {
        id: alertAreaViewComponent

        MapItemView {
            model: activeAlerts

            delegate: MapCircle {
                id: alertArea

                required property var pos
                required property bool stale

                center: root.coordinateOf(alertArea.pos)
                radius: alertArea.pos && FleetFormat.has(alertArea.pos.error_m) ? alertArea.pos.error_m : 0
                visible: center.isValid && radius > 0
                color: Qt.rgba(0.94, 0.27, 0.27, alertArea.stale ? 0.08 : 0.18)
                border.color: BriechTheme.errColor
                border.width: 2
                z: QGroundControl.zOrderMapItems + 1
            }
        }
    }

    Component {
        id: alertViewComponent

        MapItemView {
            model: activeAlerts

            delegate: MapQuickItem {
                id: alertMarker

                required property var severity
                required property var className
                required property var pos
                required property bool stale

                coordinate: root.coordinateOf(alertMarker.pos)
                visible: coordinate.isValid
                anchorPoint.x: 8
                anchorPoint.y: 8
                opacity: alertMarker.stale ? 0.5 : 1
                z: QGroundControl.zOrderVehicles - 1

                sourceItem: Item {
                    width: 16 + 5 + alertLabel.width
                    height: 16

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: FleetFormat.severityTone(alertMarker.severity, BriechTheme)
                        border.color: "white"
                        border.width: 2

                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    MarkerLabel {
                        id: alertLabel
                        x: 21
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ALERT " + FleetFormat.wordText(alertMarker.severity) + " · "
                              + FleetFormat.wordText(alertMarker.className) + (alertMarker.stale ? " · STALE" : "")
                        tone: FleetFormat.severityTone(alertMarker.severity, BriechTheme)
                    }
                }
            }
        }
    }
}
