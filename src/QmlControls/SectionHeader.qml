import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

CheckBox {
    id:             control
    focusPolicy:    Qt.ClickFocus
    checked:        true
    leftPadding:    0

    property var            color:          qgcPal.text
    property bool           showSpacer:     true
    property ButtonGroup    buttonGroup:    null

    property real _sectionSpacer: ScreenTools.defaultFontPixelHeight * 0.5

    onButtonGroupChanged: {
        if (buttonGroup) {
            buttonGroup.addButton(control)
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: enabled }

    contentItem: ColumnLayout {
        spacing: 0

        Item {
            Layout.preferredHeight: control._sectionSpacer
            width:                  1
            visible:                control.showSpacer
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight:   ScreenTools.defaultFontPixelHeight * 2
            color:            "#1a1e26"
            border.color:     "#252c38"
            border.width:     1

            QGCLabel {
                anchors.left:           parent.left
                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
                anchors.verticalCenter: parent.verticalCenter
                text:       control.text
                color:      "#d8dde6"
                font.bold:  true
                font.family: ScreenTools.normalFontFamily
                font.letterSpacing: 0.5
            }

            QGCColoredImage {
                anchors.right:          parent.right
                anchors.rightMargin:    ScreenTools.defaultFontPixelWidth
                anchors.verticalCenter: parent.verticalCenter
                width:  parent.height * 0.35
                height: width
                source: "/qmlimages/arrow-down.png"
                color:  "#6a7585"
                rotation: control.checked ? 180 : 0
            }
        }
    }

    indicator: Item {}
}
