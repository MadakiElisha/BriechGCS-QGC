import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import Custom.Widgets

Item {
    property var parentToolInsets                       // These insets tell you what screen real estate is available for positioning the controls in your overlay
    property var totalToolInsets:   _totalToolInsets    // The insets updated for the custom overlay additions
    property var mapControl

    readonly property string noGPS:         qsTr("NO GPS")
    readonly property real   indicatorValueWidth:   ScreenTools.defaultFontPixelWidth * 7

    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property real   _indicatorDiameter:     ScreenTools.defaultFontPixelWidth * 18
    property real   _indicatorsHeight:      ScreenTools.defaultFontPixelHeight
    property var    _sepColor:              qgcPal.globalTheme === QGCPalette.Light ? Qt.rgba(0,0,0,0.5) : Qt.rgba(1,1,1,0.5)
    property color  _indicatorsColor:       qgcPal.text
    property bool   _isVehicleGps:          _activeVehicle ? _activeVehicle.gps.count.rawValue > 1 && _activeVehicle.gps.hdop.rawValue < 1.4 : false
    property string _altitude:              _activeVehicle ? (isNaN(_activeVehicle.altitudeRelative.value) ? "0.0" : _activeVehicle.altitudeRelative.value.toFixed(1)) + ' ' + _activeVehicle.altitudeRelative.units : "0.0"
    property string _distanceStr:           isNaN(_distance) ? "0" : _distance.toFixed(0) + ' ' + QGroundControl.unitsConversion.appSettingsHorizontalDistanceUnitsString
    property real   _heading:               _activeVehicle   ? _activeVehicle.heading.rawValue : 0
    property real   _distance:              _activeVehicle ? _activeVehicle.distanceToHome.rawValue : 0
    property string _messageTitle:          ""
    property string _messageText:           ""
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property real   _stripTopMargin:        parentToolInsets.topEdgeLeftInset + (_toolsMargin * 0.75)

    function _factNumber(fact, fallback) {
        if (!fact) {
            return fallback
        }
        const value = Number(fact.rawValue)
        return isNaN(value) ? fallback : value
    }

    function _factText(fact, fallback) {
        if (!fact || fact.valueString === undefined || fact.valueString === null || String(fact.valueString).length === 0) {
            return fallback
        }
        return fact.valueString
    }

    function _formatHeading(value) {
        const safeHeading = isNaN(value) ? 0 : ((Math.round(value) % 360) + 360) % 360
        return ("000" + safeHeading).slice(-3)
    }

    function _headingNumberValue() {
        return _formatHeading(_heading)
    }

    function _vehicleBatteryPercent() {
        if (!_activeVehicle) {
            return "--"
        }
        if (_activeVehicle.batteries && _activeVehicle.batteries.count > 0) {
            var lowest = NaN
            for (var i = 0; i < _activeVehicle.batteries.count; i++) {
                var battery = _activeVehicle.batteries.get(i)
                var percent = battery && battery.percentRemaining ? Number(battery.percentRemaining.rawValue) : NaN
                if (!isNaN(percent) && (isNaN(lowest) || percent < lowest)) {
                    lowest = percent
                }
            }
            if (!isNaN(lowest)) {
                return Math.round(lowest) + "%"
            }
        }
        if (_activeVehicle.battery && _activeVehicle.battery.percentRemaining) {
            var singlePercent = Number(_activeVehicle.battery.percentRemaining.rawValue)
            return isNaN(singlePercent) ? "--" : Math.round(singlePercent) + "%"
        }
        return "--"
    }

    function _missionIndexText() {
        if (!_activeVehicle || !_activeVehicle.missionManager) {
            return "--"
        }
        var index = _activeVehicle.missionItemIndex ? _factNumber(_activeVehicle.missionItemIndex, NaN) : NaN
        if (isNaN(index)) {
            index = _activeVehicle.missionManager.currentIndex
        }
        return index >= 0 ? String(index + 1) : "--"
    }

    function _distanceToNextWpText() {
        if (!_activeVehicle || !_activeVehicle.distanceToNextWP) {
            return "--"
        }
        const value = _factNumber(_activeVehicle.distanceToNextWP, NaN)
        return isNaN(value) ? "--" : _activeVehicle.distanceToNextWP.valueString
    }

    function _speedText() {
        if (!_activeVehicle) {
            return "--"
        }
        const airspeed = _factNumber(_activeVehicle.airSpeed, NaN)
        if (!isNaN(airspeed) && airspeed > 0.1) {
            return _factText(_activeVehicle.airSpeed, "--")
        }
        return _factText(_activeVehicle.groundSpeed, "--")
    }

    function _speedKey() {
        if (!_activeVehicle) {
            return "SPD"
        }
        const airspeed = _factNumber(_activeVehicle.airSpeed, NaN)
        return !isNaN(airspeed) && airspeed > 0.1 ? "ASPD" : "GSPD"
    }

    function secondsToHHMMSS(timeS) {
        var sec_num = parseInt(timeS, 10);
        var hours   = Math.floor(sec_num / 3600);
        var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
        var seconds = sec_num - (hours * 3600) - (minutes * 60);
        if (hours   < 10) {hours   = "0"+hours;}
        if (minutes < 10) {minutes = "0"+minutes;}
        if (seconds < 10) {seconds = "0"+seconds;}
        return hours+':'+minutes+':'+seconds;
    }

    QGCToolInsets {
        id:                     _totalToolInsets
        leftEdgeTopInset:       parentToolInsets.leftEdgeTopInset
        leftEdgeCenterInset:    exampleRectangle.leftEdgeCenterInset
        leftEdgeBottomInset:    parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset:      parentToolInsets.rightEdgeTopInset
        rightEdgeCenterInset:   parentToolInsets.rightEdgeCenterInset
        rightEdgeBottomInset:   parent.width - compassBackground.x
        topEdgeLeftInset:       parentToolInsets.topEdgeLeftInset
        topEdgeCenterInset:     telemetryStrip.y + telemetryStrip.height
        topEdgeRightInset:      parentToolInsets.topEdgeRightInset
        bottomEdgeLeftInset:    parentToolInsets.bottomEdgeLeftInset
        bottomEdgeCenterInset:  parentToolInsets.bottomEdgeCenterInset
        bottomEdgeRightInset:   parent.height - attitudeIndicator.y
    }

    // This is an example of how you can use parent tool insets to position an element on the custom fly view layer
    // - we use parent topEdgeLeftInset to position the widget below the toolstrip
    // - we use parent bottomEdgeLeftInset to dodge the virtual joystick if enabled
    // - we use the parent leftEdgeTopInset to size our element to the same width as the ToolStripAction
    // - we export the width of this element as the leftEdgeCenterInset so that the map will recenter if the vehicle flys behind this element
    Rectangle {
        id: exampleRectangle
        visible: false // to see this example, set this to true. To view insets, enable the insets viewer FlyView.qml
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: parentToolInsets.topEdgeLeftInset + _toolsMargin
        anchors.bottomMargin: parentToolInsets.bottomEdgeLeftInset + _toolsMargin
        anchors.leftMargin: _toolsMargin
        width: parentToolInsets.leftEdgeTopInset - _toolsMargin
        color: 'red'

        property real leftEdgeCenterInset: visible ? x + width : 0
    }

    Rectangle {
        id: headingTapePanel
        anchors.bottom: parent.bottom
        anchors.bottomMargin: _toolsMargin
        anchors.horizontalCenter: parent.horizontalCenter
        width: ScreenTools.defaultFontPixelWidth * 34
        height: ScreenTools.defaultFontPixelHeight * 2.0
        color: "#0b1017"
        border.color: "#2a3342"
        border.width: 1
        clip: true

        Canvas {
            id: flyHeadingTape
            anchors.fill: parent
            anchors.margins: 4

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                const centerX = width / 2
                const heading = _heading
                const pixelsPerDegree = width / 60
                const bottomY = height - 4

                ctx.strokeStyle = "rgba(170,182,201,0.72)"
                ctx.lineWidth = 1

                for (let deg = -30; deg <= 30; deg += 5) {
                    const x = centerX + deg * pixelsPerDegree
                    const absolute = ((Math.round(heading + deg) % 360) + 360) % 360
                    const major = deg % 10 === 0
                    const tickTop = major ? 16 : 22
                    ctx.beginPath()
                    ctx.moveTo(x, tickTop)
                    ctx.lineTo(x, bottomY)
                    ctx.stroke()

                    if (major) {
                        ctx.fillStyle = "#d8dee8"
                        ctx.font = "bold 11px monospace"
                        ctx.textAlign = "center"
                        ctx.fillText(("000" + absolute).slice(-3), x, 11)
                    }
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: parent.width * 0.16
            height: parent.height
            color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.12)
            border.color: Qt.rgba(201 / 255, 168 / 255, 76 / 255, 0.78)
            border.width: 1

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 5
                text: _headingNumberValue()
                color: "#f7f9fc"
                font.family: "monospace"
                font.pixelSize: 11
                font.bold: true
            }

            Canvas {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                width: 12
                height: 8

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = "#c9a84c"
                    ctx.beginPath()
                    ctx.moveTo(width / 2, height)
                    ctx.lineTo(0, 0)
                    ctx.lineTo(width, 0)
                    ctx.closePath()
                    ctx.fill()
                }
            }
        }
    }

    Rectangle {
        id: telemetryStrip
        anchors.top:                parent.top
        anchors.horizontalCenter:    parent.horizontalCenter
        anchors.topMargin:          _stripTopMargin
        width:                      Math.min(parent.width * 0.78, ScreenTools.defaultFontPixelWidth * 66)
        height:                     ScreenTools.defaultFontPixelHeight * 2.8
        color:                      Qt.rgba(0.04, 0.05, 0.07, 0.92)
        border.color:               Qt.rgba(0.79, 0.66, 0.30, 0.42)
        border.width:               1
        radius:                     3
        clip:                       true

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.10
        }

        Row {
            anchors.fill: parent
            anchors.margins: ScreenTools.defaultFontPixelWidth * 0.7
            spacing: ScreenTools.defaultFontPixelWidth * 0.55

            Repeater {
                model: [
                    { k: "WP", v: _missionIndexText(), u: "" },
                    { k: "ALT", v: _activeVehicle ? _factText(_activeVehicle.altitudeRelative, "--") : "--", u: "m" },
                    { k: _speedKey(), v: _speedText(), u: "m/s" },
                    { k: "GSPD", v: _activeVehicle ? _factText(_activeVehicle.groundSpeed, "--") : "--", u: "m/s" },
                    { k: "HDG", v: _activeVehicle ? _formatHeading(_factNumber(_activeVehicle.heading, NaN)) : "---", u: "deg" },
                    { k: "DIST HOME", v: _activeVehicle ? _factText(_activeVehicle.distanceToHome, "--") : "--", u: "m" },
                    { k: "NEXT WP", v: _distanceToNextWpText(), u: _activeVehicle && _distanceToNextWpText() !== "--" ? "m" : "" },
                    { k: "TIME", v: _activeVehicle && _activeVehicle.flightTime ? _activeVehicle.flightTime.valueString : "--:--:--", u: "" },
                    { k: "BATT", v: _vehicleBatteryPercent(), u: "" },
                    { k: "MODE", v: _activeVehicle ? _activeVehicle.flightMode : "STBY", u: "" }
                ]

                Rectangle {
                    width: telemetryStrip.width / 10 - ScreenTools.defaultFontPixelWidth * 0.14
                    height: parent.height
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                            text: modelData.k
                            color: BriechTheme.goldAccent
                            font.pixelSize: 8
                            font.bold: true
                            font.family: "monospace"
                        }

                        Row {
                            spacing: 2
                            anchors.horizontalCenter: parent.horizontalCenter

                            Text {
                                text: modelData.v
                                color: BriechTheme.textColor
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "monospace"
                            }

                            Text {
                                visible: modelData.u !== ""
                                text: modelData.u
                                color: BriechTheme.mutedColor
                                font.pixelSize: 7
                                font.family: "monospace"
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id:                     compassBackground
        anchors.bottom:         attitudeIndicator.bottom
        anchors.right:          attitudeIndicator.left
        anchors.rightMargin:    -attitudeIndicator.width * 0.08
        width:                  attitudeIndicator.width * 0.38
        height:                 attitudeIndicator.height * 0.34
        radius:                 2
        color:                  "#0b1017"
        border.color:           "#2a3342"
        border.width:           1

        Rectangle {
            id:                     compassBezel
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:     _toolsMargin
            anchors.left:           parent.left
            width:                  height
            height:                 parent.height - (northLabelBackground.height / 2) - (headingLabelBackground.height / 2)
            radius:                 height / 2
            border.color:           "#7a8799"
            border.width:           1
            color:                  Qt.rgba(0,0,0,0)
        }

        Rectangle {
            id:                         northLabelBackground
            anchors.top:                compassBezel.top
            anchors.topMargin:          -height / 2
            anchors.horizontalCenter:   compassBezel.horizontalCenter
            width:                      northLabel.contentWidth * 1.5
            height:                     northLabel.contentHeight * 1.5
            radius:                     ScreenTools.defaultFontPixelWidth  * 0.25
            color:                      "#111823"

            QGCLabel {
                id:                 northLabel
                anchors.centerIn:   parent
                text:               "N"
                color:              "#d9e1ea"
                font.pointSize:     ScreenTools.smallFontPointSize
            }
        }

        Image {
            id:                 headingNeedle
            anchors.centerIn:   compassBezel
            height:             compassBezel.height * 0.75
            width:              height
            source:             "/custom/img/compass_needle.svg"
            fillMode:           Image.PreserveAspectFit
            sourceSize.height:  height
            transform: [
                Rotation {
                    origin.x:   headingNeedle.width  / 2
                    origin.y:   headingNeedle.height / 2
                    angle:      _heading
                }]
        }

        Rectangle {
            id:                         headingLabelBackground
            anchors.top:                compassBezel.bottom
            anchors.topMargin:          -height / 2
            anchors.horizontalCenter:   compassBezel.horizontalCenter
            width:                      headingLabel.contentWidth * 1.5
            height:                     headingLabel.contentHeight * 1.5
            radius:                     ScreenTools.defaultFontPixelWidth  * 0.25
            color:                      "#111823"

            QGCLabel {
                id:                 headingLabel
                anchors.centerIn:   parent
                text:               _headingNumberValue()
                color:              "#d9e1ea"
                font.pointSize:     ScreenTools.smallFontPointSize
            }
        }
    }

    Rectangle {
        id:                     attitudeIndicator
        anchors.bottomMargin:   _toolsMargin + parentToolInsets.bottomEdgeRightInset
        anchors.rightMargin:    _toolsMargin
        anchors.bottom:         parent.bottom
        anchors.right:          parent.right
        height:                 ScreenTools.defaultFontPixelHeight * 8.4
        width:                  height
        radius:                 height * 0.5
        color:                  "#0c1118"
        border.color:           "#2a3342"
        border.width:           1

        BriechAttitudeIndicator {
            size:               parent.height * 0.95
            vehicle:            _activeVehicle
            showHeading:        true
            anchors.centerIn:   parent
        }
    }
}
