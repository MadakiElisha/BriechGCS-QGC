import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// Briech override of QGC's src/QmlControls/QGCButton.qml (loaded instead of it
// by CustomOverrideInterceptor). Identical everywhere except inside a dialog
// drawn with the Briech look (QGCPopupDialog.qml sets briechDialogContent on
// its layout while the Modern view is showing): there it takes the Briech
// button style, gold for the primary button. Never in the Legacy UI. On an
// upstream QGC update, diff the stock file and carry its changes over.
//
/// Standard push button control:
///     If there is both an icon and text the icon will be to the left of the text
///     If icon only, icon will be centered
Button {
    property bool primary: false
    property bool showBorder: qgcPal.globalTheme === QGCPalette.Light
    property real backRadius: ScreenTools.defaultBorderRadius
    property real heightFactor: 0.5
    property string iconSource: ""
    property real fontWeight: Font.Normal // default for qml Text
    property real pointSize: ScreenTools.defaultFontPointSize

    property alias wrapMode: text.wrapMode
    property alias horizontalAlignment: text.horizontalAlignment
    property alias backgroundColor: backRect.color
    property alias textColor: text.color

    id: control
    hoverEnabled: !ScreenTools.isMobile
    topPadding: _verticalPadding
    bottomPadding: _verticalPadding
    leftPadding: _horizontalPadding
    rightPadding: _horizontalPadding
    focusPolicy: Qt.ClickFocus
    font.family: ScreenTools.normalFontFamily
    text: ""

    property bool _showHighlight: enabled && (pressed | checked)
    property int _horizontalPadding: ScreenTools.defaultFontPixelWidth * 2
    property int _verticalPadding: Math.round(ScreenTools.defaultFontPixelHeight * heightFactor) - (iconSource === "" ? 0 : (_iconHeight - ScreenTools.defaultFontPixelHeight)  / 2)
    property real _iconHeight: text.height * 1.5

    QGCPalette { id: qgcPal; colorGroupEnabled: control.enabled }

    /// True inside a Briech-styled dialog (an ancestor sets briechDialogContent).
    property bool _briech: false

    function _findBriechDialog() {
        for (let item = control.parent; item; item = item.parent) {
            if (item.briechDialogContent !== undefined) {
                _briech = item.briechDialogContent === true
                return
            }
        }
        _briech = false
    }

    // After the dialog has moved its content into place.
    Component.onCompleted: Qt.callLater(_findBriechDialog)
    onParentChanged: Qt.callLater(_findBriechDialog)

    background: Rectangle {
        id: backRect
        radius: backRadius
        implicitWidth: ScreenTools.implicitButtonWidth
        implicitHeight: ScreenTools.implicitButtonHeight
        border.width: control._briech ? 1 : (showBorder ? 1 : 0)
        border.color: control._briech ? (primary ? "#c9a84c" : "#3b485b") : qgcPal.buttonBorder
        color: control._briech ? (primary ? "#c9a84c" : "#111925") : (primary ? qgcPal.primaryButton : qgcPal.button)

        Rectangle {
            anchors.fill: parent
            color: control._briech ? "#c9a84c" : qgcPal.buttonHighlight
            opacity: _showHighlight ? (control._briech ? 0.35 : 1) : control.enabled && control.hovered ? .2 : 0
            radius: parent.radius
        }
    }

    contentItem: RowLayout {
        spacing: ScreenTools.defaultFontPixelWidth

        QGCColoredImage {
            id: icon
            Layout.alignment: Qt.AlignHCenter
            source: control.iconSource
            height: _iconHeight
            width: height
            color: text.color
            fillMode: Image.PreserveAspectFit
            sourceSize.height: height
            visible: control.iconSource !== ""
        }

        QGCLabel {
            id: text
            Layout.alignment: Qt.AlignHCenter
            text: control.text
            font.pointSize: control.pointSize
            font.family: control.font.family
            font.weight: fontWeight
            color: control._briech ? (primary ? "#05070a" : "#d8dde6")
                                   : (_showHighlight ? qgcPal.buttonHighlightText : (primary ? qgcPal.primaryButtonText : qgcPal.buttonText))
            visible: control.text !== ""
        }
    }
}
