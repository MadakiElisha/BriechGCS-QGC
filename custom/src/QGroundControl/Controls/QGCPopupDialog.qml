import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls

// Briech override of QGC's src/QmlControls/QGCPopupDialog.qml (loaded instead of
// it by CustomOverrideInterceptor). Behaviour is the stock file's, unchanged:
// same properties, signals, buttons, Esc handling, validation and close rules.
// Only the look differs, and only while the Briech Modern view is showing
// (mainWindow._briechFramelessWindow): a navy panel with a gold bar, an upper-
// case title and a BRIECH UAS tag, like BriechDialog. With the Modern view
// hidden (Legacy UI) every colour and size is the stock one. Buttons inside the
// dialog follow through the briechDialogContent marker (see QGCButton.qml).
// On an upstream QGC update, diff the stock file and carry its changes over.
//
// Provides the standard dialog mechanism for QGC. Works 99% like Qml Dialog.
//
// Example usage:
//      Component {
//          id: dialogComponent
//
//          QGCPopupDialog {
//              ...
//          }
//      }
//
//      onFoo: dialogComponent.createObject(mainWindow).open()
//
// Notes:
//  * QGCPopupDialog should be created from a component to limit the memory usage of the dialog
//      to only when it is displayed.
//  * Parent for createObject should always be mainWindow.
// Differences from standard Qml Dialog:
//  * The QGCPopupDialog object will automatically be destroyed when it closed. You can override this
//      behaviour by setting destroyOnClose to false if it was not created dynamically.
//  * Dialog will automatically close after accepted/rejected signal processing. You can prevent this by setting
//      preventClose = true prior to returning from your signal handlers.
Popup {
    id:                 root
    width:  mainWindow.width
    height: mainWindow.height
    parent:             Overlay.overlay
    modal:              true
    focus:              true
    margins:            0

    property string title
    property var    buttons:                Dialog.Ok
    property alias  acceptButtonEnabled:    acceptButton.enabled
    property alias  rejectButtonEnabled:    rejectButton.enabled
    property var    dialogProperties
    property bool   destroyOnClose:         true
    property bool   preventClose:           false

    property real maxContentAvailableWidth:    mainWindow.width - _contentMargin * 6
    property real maxContentAvailableHeight:   mainWindow.height - titleRowLayout.height - _contentMargin * 7

    readonly property real headerMinWidth: titleLabel.implicitWidth + rejectButton.width + acceptButton.width + titleRowLayout.spacing * 2

    signal accepted
    signal rejected

    property var    _qgcPal:            QGroundControl.globalPalette
    /// Briech look: only while the Modern view is showing (never in the Legacy UI).
    readonly property bool _briech:     typeof mainWindow !== "undefined" && mainWindow._briechFramelessWindow === true
    readonly property color _briechGold: "#c9a84c"
    property real   _frameSize:         ScreenTools.defaultFontPixelWidth
    property real   _contentMargin:     ScreenTools.defaultFontPixelHeight / 2
    property bool   _acceptAllowed:     acceptButton.visible
    property bool   _rejectAllowed:     rejectButton.visible
    property int    _previousValidationErrorCount: 0

    background: QGCMouseArea {
        width:  mainWindow.width
        height: mainWindow.height

        onClicked: {
            if (closePolicy & Popup.CloseOnPressOutside) {
                _reject()
            }
        }
    }

    Component.onCompleted: {
        // The last child item will be the true dialog content.
        // Re-Parent it to the right place in the ui hierarchy.
        contentChildren[contentChildren.length - 1].parent = dialogContentParent
    }

    onAboutToShow: {
        _previousValidationErrorCount = globals.validationErrorCount
        setupDialogButtons(buttons)
        if (_briech) {
            acceptButton.text = acceptButton.text.toUpperCase()
            rejectButton.text = rejectButton.text.toUpperCase()
        }
    }

    onClosed: {
        globals.validationErrorCount = _previousValidationErrorCount
        Qt.inputMethod.hide()
        if (destroyOnClose) {
            root.destroy()
        }
    }

    function _accept() {
        if (_acceptAllowed && mainWindow.allowViewSwitch(_previousValidationErrorCount)) {
            accepted()
            if (preventClose) {
                preventClose = false
            } else {
                close()
            }
        }
    }

    function _reject() {
        // Dialogs with cancel button are allowed to close with validation errors
        if (_rejectAllowed && ((buttons & Dialog.Cancel) || mainWindow.allowViewSwitch(_previousValidationErrorCount))) {
            rejected()
            if (preventClose) {
                preventClose = false
            } else {
                close()
            }
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: parent.enabled }

    function setupDialogButtons(buttons) {
        acceptButton.visible = false
        rejectButton.visible = false
        // Accept role buttons
        if (buttons & Dialog.Ok) {
            acceptButton.text = qsTr("Ok")
            acceptButton.visible = true
        } else if (buttons & Dialog.Open) {
            acceptButton.text = qsTr("Open")
            acceptButton.visible = true
        } else if (buttons & Dialog.Save) {
            acceptButton.text = qsTr("Save")
            acceptButton.visible = true
        } else if (buttons & Dialog.Apply) {
            acceptButton.text = qsTr("Apply")
            acceptButton.visible = true
        } else if (buttons & Dialog.Open) {
            acceptButton.text = qsTr("Open")
            acceptButton.visible = true
        } else if (buttons & Dialog.SaveAll) {
            acceptButton.text = qsTr("Save All")
            acceptButton.visible = true
        } else if (buttons & Dialog.Yes) {
            acceptButton.text = qsTr("Yes")
            acceptButton.visible = true
        } else if (buttons & Dialog.YesToAll) {
            acceptButton.text = qsTr("Yes to All")
            acceptButton.visible = true
        } else if (buttons & Dialog.Retry) {
            acceptButton.text = qsTr("Retry")
            acceptButton.visible = true
        } else if (buttons & Dialog.Reset) {
            acceptButton.text = qsTr("Reset")
            acceptButton.visible = true
        } else if (buttons & Dialog.RestoreToDefaults) {
            acceptButton.text = qsTr("Restore to Defaults")
            acceptButton.visible = true
        } else if (buttons & Dialog.Ignore) {
            acceptButton.text = qsTr("Ignore")
            acceptButton.visible = true
        }

        // Reject role buttons
        if (buttons & Dialog.Cancel) {
            rejectButton.text = qsTr("Cancel")
            rejectButton.visible = true
        } else if (buttons & Dialog.Close) {
            rejectButton.text = qsTr("Close")
            rejectButton.visible = true
        } else if (buttons & Dialog.No) {
            rejectButton.text = qsTr("No")
            rejectButton.visible = true
        } else if (buttons & Dialog.NoToAll) {
            rejectButton.text = qsTr("No to All")
            rejectButton.visible = true
        } else if (buttons & Dialog.Abort) {
            rejectButton.text = qsTr("Abort")
            rejectButton.visible = true
        }

        closePolicy = Popup.NoAutoClose
        if (buttons & Dialog.Cancel) {
            closePolicy |= Popup.CloseOnEscape
        }
    }

    function disableAcceptButton() {
        acceptButton.enabled = false
    }

    Rectangle {
        x:              mainLayout.x - _contentMargin
        y:              mainLayout.y - _contentMargin
        width:          mainLayout.width + _contentMargin * 2
        height:         mainLayout.height + _contentMargin * 2
        color:          _briech ? "#080d14" : _qgcPal.windowShade
        radius:         _briech ? 3 : root.padding / 2
        border.width:   1
        border.color:   _briech ? _briechGold : _qgcPal.windowShadeLight

        // Briech: gold bar along the top edge.
        Rectangle {
            visible:        root._briech
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            height:         3
            color:          root._briechGold
        }
    }

    ColumnLayout {
        id:                 mainLayout
        anchors.centerIn:   parent

        /// Read by QGCButton.qml: buttons anywhere in the dialog (its own OK /
        /// CANCEL and the content's) take the Briech look.
        readonly property bool briechDialogContent: root._briech

        x:                  _contentMargin
        y:                  _contentMargin
        spacing:            _contentMargin

        RowLayout {
            id:                     titleRowLayout
            Layout.fillWidth:       true
            spacing:                _contentMargin

            // Briech: gold dot before the title.
            Rectangle {
                visible:                    root._briech
                Layout.preferredWidth:      8
                Layout.preferredHeight:     8
                Layout.alignment:           Qt.AlignVCenter
                radius:                     4
                color:                      root._briechGold
            }

            QGCLabel {
                id:                 titleLabel
                Layout.fillWidth:   true
                text:               root._briech ? root.title.toUpperCase() : root.title
                font.pointSize:     ScreenTools.mediumFontPointSize
                font.bold:          root._briech
                font.family:        root._briech ? "monospace" : ScreenTools.normalFontFamily
                color:              root._briech ? "#f2e3b0" : _qgcPal.text
                verticalAlignment:	Text.AlignVCenter
            }

            // Briech: the brand tag, as on BriechDialog.
            QGCLabel {
                visible:            root._briech
                text:               "BRIECH UAS"
                color:              "#77869a"
                font.family:        "monospace"
                font.bold:          true
                font.pixelSize:     9
                verticalAlignment:  Text.AlignVCenter
            }

            QGCButton {
                id:                     rejectButton
                onClicked:              _reject()
                Layout.minimumWidth:    height * 1.5
            }

            QGCButton {
                id:                     acceptButton
                primary:                true
                onClicked:              _accept()
                Layout.minimumWidth:    height * 1.5
            }
        }

        Rectangle {
            Layout.fillWidth:       true
            Layout.preferredWidth:  Math.min(maxAvailableWidth, totalContentWidth)
            Layout.preferredHeight: Math.min(maxAvailableHeight, totalContentHeight)
            color:                  _briech ? "#0b111a" : _qgcPal.window
            border.width:           _briech ? 1 : 0
            border.color:           "#1c2633"

            property real totalContentWidth:    dialogContentParent.childrenRect.width + _contentMargin * 2
            property real totalContentHeight:   dialogContentParent.childrenRect.height + _contentMargin * 2
            property real maxAvailableWidth:    mainWindow.width - _contentMargin * 4
            property real maxAvailableHeight:   mainWindow.height - titleRowLayout.height - _contentMargin * 5

            QGCFlickable {
                anchors.margins:    _contentMargin
                anchors.fill:       parent
                contentWidth:       dialogContentParent.childrenRect.width
                contentHeight:      dialogContentParent.childrenRect.height

                Item {
                    id:     dialogContentParent
                    focus:  true


                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape && _rejectAllowed) {
                            _reject()
                            event.accepted = true
                        }
                    }
                }
            }
        }
    }
}
