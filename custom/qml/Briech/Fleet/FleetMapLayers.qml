pragma ComponentBehavior: Bound

import QtQuick
import QtLocation

import QGroundControl
import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// Fleet map layer: while the Fleet page is open, puts a tag beside each
// connected vehicle with its BRCH id, altitude and heading (live values,
// "--" when unknown).
//
// This item is not drawn itself. The map lives outside the Fleet page, so the
// tags are added to the map with addMapItemView() when the page opens and
// removed in Component.onDestruction when the Loader closes the page. That
// keeps "close Fleet" meaning "nothing of Fleet is left on the map".
Item {
    id: root

    /// The map to draw on (the Modern view's FlyViewMap). Null means draw nothing.
    property var map: null

    property var _view: null
    property var _viewMap: null

    function attach() {
        detach()
        if (!map) {
            return
        }
        _view = tagViewComponent.createObject(map)
        if (_view) {
            map.addMapItemView(_view)
            _viewMap = map
        }
    }

    function detach() {
        if (_view) {
            if (_viewMap) {
                _viewMap.removeMapItemView(_view)
            }
            _view.destroy()
        }
        _view = null
        _viewMap = null
    }

    onMapChanged: attach()
    Component.onCompleted: attach()
    Component.onDestruction: detach()

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

                    width: tagRow.implicitWidth + 12
                    height: 18
                    radius: 2
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
                    }
                }
            }
        }
    }
}
