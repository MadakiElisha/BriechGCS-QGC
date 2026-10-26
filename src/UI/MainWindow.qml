pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Toolbar

/// @brief Native QML top level window
/// All properties defined here are visible to all QML pages.
ApplicationWindow {
    id:         mainWindow
    visible:    true
    // The special casing for android prevents white bars from showing up on the edges of the screen with newer android versions
    flags:      Qt.Window | (ScreenTools.isAndroid ? Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint : 0)

    property bool   _utmspSendActTrigger
    Component.onCompleted: {
        // Start the sequence of first run prompt(s)
        firstRunPromptManager.nextPrompt()
    }

    /// Saves main window position and size and re-opens it in the same position and size next time
    MainWindowSavedState {
        window: mainWindow
    }

    QtObject {
        id: firstRunPromptManager

        property var currentDialog:     null
        property var rgPromptIds:       QGroundControl.corePlugin.firstRunPromptsToShow()
        property int nextPromptIdIndex: 0

        function clearNextPromptSignal() {
            if (currentDialog) {
                currentDialog.closed.disconnect(nextPrompt)
            }
        }

        function nextPrompt() {
            if (nextPromptIdIndex < rgPromptIds.length) {
                var component = Qt.createComponent(QGroundControl.corePlugin.firstRunPromptResource(rgPromptIds[nextPromptIdIndex]));
                currentDialog = component.createObject(mainWindow)
                currentDialog.closed.connect(nextPrompt)
                currentDialog.open()
                nextPromptIdIndex++
            } else {
                currentDialog = null
                showPreFlightChecklistIfNeeded()
            }
        }
    }

    readonly property real      _topBottomMargins:          ScreenTools.defaultFontPixelHeight * 0.5
    property bool               _briechModernViewInitialized: false
    property string             _pendingSettingsPage: ""

    //-------------------------------------------------------------------------
    //-- Global Scope Variables

    QtObject {
        id: globals

        readonly property var       activeVehicle:                  QGroundControl.multiVehicleManager.activeVehicle
        readonly property real      defaultTextHeight:              ScreenTools.defaultFontPixelHeight
        readonly property real      defaultTextWidth:               ScreenTools.defaultFontPixelWidth
        readonly property var       planMasterControllerFlyView:    flyView.planController
        readonly property var       guidedControllerFlyView:        flyView.guidedController

        // Number of QGCTextField's with validation errors. Used to prevent closing panels with validation errors.
        property int                validationErrorCount:           0

        // Property to manage RemoteID quick access to settings page
        property bool               commingFromRIDIndicator:        false
    }

    /// Default color palette used throughout the UI
    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    //-------------------------------------------------------------------------
    //-- Actions

    signal armVehicleRequest
    signal forceArmVehicleRequest
    signal disarmVehicleRequest
    signal vtolTransitionToFwdFlightRequest
    signal vtolTransitionToMRFlightRequest
    signal showPreFlightChecklistIfNeeded

    //-------------------------------------------------------------------------
    //-- Global Scope Functions

    // This function is used to prevent view switching if there are validation errors
    function allowViewSwitch(previousValidationErrorCount = 0) {
        // Run validation on active focus control to ensure it is valid before switching views
        if (mainWindow.activeFocusControl instanceof FactTextField) {
            mainWindow.activeFocusControl._onEditingFinished()
        }
        return globals.validationErrorCount <= previousValidationErrorCount
    }

    function showPlanView() {
        flyView.visible = false
        planView.visible = true
        briechModernView.visible = false
        toolDrawer.visible = false
    }

    function showFlyView() {
        flyView.visible = true
        planView.visible = false
        briechModernView.visible = false
        toolDrawer.visible = false
    }

    function showBriechModernView() {
        flyView.visible = false
        planView.visible = false
        briechModernView.visible = true
        toolDrawer.visible = false
        if (briechModernView.item && briechModernView.item.activateModernSection) {
            briechModernView.item.activateModernSection("fly")
        }
    }

    function showTool(toolTitle, toolSource, toolIcon) {
        let wasFlyView = flyView.visible
        flyView.visible = false
        planView.visible = false
        briechModernView.visible = false
        toolDrawer.backIcon     = wasFlyView ? "/qmlimages/PaperPlane.svg" : "/qmlimages/Plan.svg"
        toolDrawer.toolTitle    = toolTitle
        toolDrawer.toolSource   = toolSource
        toolDrawer.toolIcon     = toolIcon
        toolDrawer.visible      = true
    }

    function showAnalyzeTool() {
        showTool(qsTr("Analyze Tools"), "qrc:/qml/QGroundControl/AnalyzeView/AnalyzeView.qml", "/qmlimages/Analyze.svg")
    }

    function showVehicleConfig() {
        showTool(qsTr("Vehicle Configuration"), "qrc:/qml/QGroundControl/VehicleSetup/SetupView.qml", "/qmlimages/Gears.svg")
    }

    function showAnalyzeToolPage(pageUrl) {
        showAnalyzeTool()
        toolDrawerLoader.item.showAnalyzePage(pageUrl)
    }

    function showVehicleConfigSummaryPage() {
        showVehicleConfig()
        toolDrawerLoader.item.showSummaryPanel()
    }

    function showVehicleConfigParametersPage() {
        showVehicleConfig()
        toolDrawerLoader.item.showParametersPanel()
    }

    function showVehicleConfigFirmwarePage() {
        showVehicleConfig()
        toolDrawerLoader.item.showFirmwarePanel()
    }

    function showVehicleComponentConfigPage(vehicleComponent) {
        showVehicleConfig()
        toolDrawerLoader.item.showVehicleComponentPanel(vehicleComponent)
    }

    function showKnownVehicleComponentConfigPage(knownVehicleComponent) {
        showVehicleConfig()
        let vehicleComponent = globals.activeVehicle.autopilotPlugin.findKnownVehicleComponent(knownVehicleComponent)
        if (vehicleComponent) {
            toolDrawerLoader.item.showVehicleComponentPanel(vehicleComponent)
        }
    }

    function showSettingsTool(settingsPage = "") {
        _pendingSettingsPage = settingsPage
        showTool(qsTr("Application Settings"), "qrc:/qml/QGroundControl/Controls/AppSettings.qml", "/res/QGCLogoWhite")
        if (_pendingSettingsPage !== "" && toolDrawerLoader.item && toolDrawerLoader.item.showSettingsPage) {
            toolDrawerLoader.item.showSettingsPage(_pendingSettingsPage)
            _pendingSettingsPage = ""
        }
    }

    //-------------------------------------------------------------------------
    //-- Global simple message dialog

    function showMessageDialog(dialogTitle, dialogText, buttons = Dialog.Ok, acceptFunction = null, closeFunction = null) {
        simpleMessageDialogComponent.createObject(mainWindow, { title: dialogTitle, text: dialogText, buttons: buttons, acceptFunction: acceptFunction, closeFunction: closeFunction }).open()
    }

    // This variant is only meant to be called by QGCApplication
    function _showMessageDialog(dialogTitle, dialogText) {
        showMessageDialog(dialogTitle, dialogText)
    }

    Component {
        id: simpleMessageDialogComponent

        QGCSimpleMessageDialog {
        }
    }

    property bool _forceClose: false

    function finishCloseProcess() {
        _forceClose = true
        // For some reason on the Qml side Qt doesn't automatically disconnect a signal when an object is destroyed.
        // So we have to do it ourselves otherwise the signal flows through on app shutdown to an object which no longer exists.
        firstRunPromptManager.clearNextPromptSignal()
        QGroundControl.linkManager.shutdown()
        QGroundControl.videoManager.stopVideo();
        mainWindow.close()
    }

    // Check for things which should prevent the app from closing
    //  Returns true if it is OK to close
    readonly property int _skipUnsavedMissionCheckMask: 0x01
    readonly property int _skipPendingParameterWritesCheckMask: 0x02
    readonly property int _skipActiveConnectionsCheckMask: 0x04
    property int _closeChecksToSkip: 0
    function performCloseChecks() {
        if (!(_closeChecksToSkip & _skipUnsavedMissionCheckMask) && !checkForUnsavedMission()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipPendingParameterWritesCheckMask) && !checkForPendingParameterWrites()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipActiveConnectionsCheckMask) && !checkForActiveConnections()) {
            return false
        }
        finishCloseProcess()
        return true
    }

    property string closeDialogTitle: qsTr("Close %1").arg(QGroundControl.appName)

    function checkForUnsavedMission() {
        if (planView._planMasterController.dirty) {
            showMessageDialog(closeDialogTitle,
                              qsTr("You have a mission edit in progress which has not been saved/sent. If you close you will lose changes. Are you sure you want to close?"),
                              Dialog.Yes | Dialog.No,
                              function() { _closeChecksToSkip |= _skipUnsavedMissionCheckMask; performCloseChecks() })
            return false
        } else {
            return true
        }
    }

    function checkForPendingParameterWrites() {
        for (var index=0; index<QGroundControl.multiVehicleManager.vehicles.count; index++) {
            if (QGroundControl.multiVehicleManager.vehicles.get(index).parameterManager.pendingWrites) {
                mainWindow.showMessageDialog(closeDialogTitle,
                    qsTr("You have pending parameter updates to a vehicle. If you close you will lose changes. Are you sure you want to close?"),
                    Dialog.Yes | Dialog.No,
                    function() { _closeChecksToSkip |= _skipPendingParameterWritesCheckMask; performCloseChecks() })
                return false
            }
        }
        return true
    }

    function checkForActiveConnections() {
        if (QGroundControl.multiVehicleManager.activeVehicle) {
            mainWindow.showMessageDialog(closeDialogTitle,
                qsTr("There are still active connections to vehicles. Are you sure you want to exit?"),
                Dialog.Yes | Dialog.No,
                function() { _closeChecksToSkip |= _skipActiveConnectionsCheckMask; performCloseChecks() })
            return false
        } else {
            return true
        }
    }

    onClosing: (close) => {
        if (!_forceClose) {
            _closeChecksToSkip = 0
            close.accepted = performCloseChecks()
        }
    }

    background: Rectangle {
        anchors.fill:   parent
        color:          QGroundControl.globalPalette.window
    }



    // ── Simulated state  (replace with your MAVLink C++ model) ──────────────
    QtObject {
        id: telemetry

        // Toggle this to preview both states
        property bool   connected:   false   // ← false = disconnected screenshot

        // Connected-state values
        property real   altitude:    127.3
        property real   climbRate:   8.2
        property real   groundSpeed: 16.7
        property int    satellites:  12
        property int    battery:     82
        property string flightMode:  "AUTO"
        property bool   armed:       true
        property string linkStatus:  "Link Status Nominal"
    }

    // ── Design tokens ────────────────────────────────────────────────────────
    QtObject {
        id: theme

        // Backgrounds
        readonly property color bg:          "#1b1b1f"
        readonly property color bgHover:     "#28282d"

        // Text
        readonly property color textBright:  "#dedede"
        readonly property color textMid:     "#9a9a9a"
        readonly property color textDim:     "#5e5e62"

        // Signal colours
        readonly property color green:       "#4db860"
        readonly property color yellow:      "#f5c518"
        readonly property color red:         "#e8453c"
        readonly property color greyDot:     "#4a4a50"

        // Separators
        readonly property color sep:         "#35353a"

        // Typography
        readonly property string font:       "Roboto, 'Noto Sans', sans-serif"
        readonly property int    sz10:       10
        readonly property int    sz11:       11
        readonly property int    sz12:       12
        readonly property int    sz13:       13
        readonly property int    sz14:       14
    }

    Rectangle {
        id: toolbarBar
        width: parent.width
        height: 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        visible: false
        color:        theme.bg

        // Bottom hairline separator
        Rectangle {
            anchors.bottom: parent.bottom
            width:  parent.width
            height: 1
            color:  theme.sep
        }

        RowLayout {
            anchors {
                fill:           parent
                leftMargin:     4
                rightMargin:    0
            }
            spacing: 0

            // ════════════════════════════════════════════════════════════════
            //  LEFT  –  Connection indicator
            // ════════════════════════════════════════════════════════════════
            RowLayout {
                spacing:              6
                Layout.leftMargin:    4
                Layout.alignment:     Qt.AlignVCenter

                // Status dot
                Rectangle {
                    id:     statusDot
                    width:  8
                    height: 8
                    radius: 4
                    color:  telemetry.connected ? theme.green : theme.greyDot

                    SequentialAnimation on opacity {
                        running:  telemetry.connected
                        loops:    Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.00; duration: 900; easing.type: Easing.InOutQuad }
                    }
                    onVisibleChanged: if (!telemetry.connected) opacity = 1
                }

                Text {
                    id:              connectionLabel
                    text:            telemetry.connected
                                     ? ("CONNECTED  " + telemetry.linkStatus)
                                     : "Disconnected  Click to manually connect"
                    color:           "#FFFFFF"
                    font.family:     theme.font
                    font.pixelSize:  theme.sz12
                    font.weight:     Font.Bold
                    renderType:      Text.NativeRendering

                    MouseArea {
                        anchors.fill:  parent
                        enabled:       !telemetry.connected
                        cursorShape:   Qt.PointingHandCursor
                        onClicked: {
                            console.log("Manual connect requested")
                        }
                    }
                }

                Item {
                    width:  18
                    height: 18

                    Rectangle {
                        anchors.centerIn: parent
                        width:   14
                        height:  11
                        radius:  3
                        color:   "transparent"
                        border.color: theme.textDim
                        border.width: 1.5
                    }

                    MouseArea {
                        anchors.fill:  parent
                        cursorShape:   Qt.PointingHandCursor
                        hoverEnabled:  true
                        onEntered:     parent.opacity = 0.7
                        onExited:      parent.opacity = 1.0
                        onClicked:     console.log("Messages panel toggled")
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                visible:          telemetry.connected
                spacing:          0
                Layout.alignment: Qt.AlignVCenter

                component TelCell: RowLayout {
                    property string prefixChar:  ""
                    property color  prefixClr:   theme.textMid
                    property string val:         ""
                    property string unitStr:     ""
                    property bool   showSep:     true

                    spacing: 2
                    Layout.rightMargin: showSep ? 0 : 4

                    Text {
                        text:            prefixChar
                        color:           prefixClr
                        font.family:     theme.font
                        font.pixelSize:  theme.sz11
                        font.weight:     Font.Bold
                        visible:         prefixChar !== ""
                    }
                    Text {
                        text:            val
                        color:           theme.textBright
                        font.family:     theme.font
                        font.pixelSize:  theme.sz13
                        font.weight:     Font.Bold
                    }
                    Text {
                        text:            unitStr
                        color:           theme.textMid
                        font.family:     theme.font
                        font.pixelSize:  theme.sz10
                        visible:         unitStr !== ""
                        Layout.leftMargin: 1
                    }
                    Rectangle {
                        visible:          showSep
                        width:            1
                        height:           18
                        color:            theme.sep
                        Layout.leftMargin:  6
                        Layout.rightMargin: 6
                    }
                }

                TelCell {
                    prefixChar: "↑"
                    val:        telemetry.altitude.toFixed(1)
                    unitStr:    "m"
                }

                TelCell {
                    prefixChar: telemetry.climbRate >= 0 ? "↑" : "↓"
                    prefixClr:  telemetry.climbRate >= 0 ? theme.green : theme.red
                    val:        Math.abs(telemetry.climbRate).toFixed(1)
                    unitStr:    "m/s"
                }

                TelCell {
                    prefixChar: "→"
                    val:        telemetry.groundSpeed.toFixed(1)
                    unitStr:    "m/s"
                }

                TelCell {
                    prefixChar: "+"
                    prefixClr:  theme.textBright
                    val:        telemetry.satellites.toString()
                    unitStr:    ""
                    showSep:    false
                }
                Text {
                    text:           "GPS"
                    color:          theme.textMid
                    font.family:    theme.font
                    font.pixelSize: theme.sz11
                    font.weight:    Font.Bold
                    Layout.rightMargin: 2
                }
                Rectangle {
                    width: 1; height: 18
                    color: theme.sep
                    Layout.leftMargin:  6
                    Layout.rightMargin: 6
                }

                RowLayout {
                    spacing: 2
                    Text {
                        text:           "⚡"
                        color:          telemetry.battery > 25 ? theme.green : theme.red
                        font.pixelSize: theme.sz13
                    }
                    Text {
                        text:           telemetry.battery + "%"
                        color:          telemetry.battery > 25 ? theme.textBright : theme.red
                        font.family:    theme.font
                        font.pixelSize: theme.sz13
                        font.weight:    Font.Bold
                    }
                    Text {
                        text:           "BATT"
                        color:          theme.textMid
                        font.family:    theme.font
                        font.pixelSize: theme.sz10
                        font.weight:    Font.Bold
                    }
                    Rectangle {
                        width: 1; height: 18
                        color: theme.sep
                        Layout.leftMargin:  6
                        Layout.rightMargin: 6
                    }
                }

                Text {
                    text:           telemetry.flightMode
                    color:          theme.textBright
                    font.family:    theme.font
                    font.pixelSize: theme.sz12
                    font.weight:    Font.Bold
                    Layout.rightMargin: 2
                }
                Rectangle {
                    width: 1; height: 18
                    color: theme.sep
                    Layout.leftMargin:  6
                    Layout.rightMargin: 6
                }

                Rectangle {
                    id:             armedPill
                    height:         22
                    width:          armedText.width + 14
                    radius:         3
                    color:          telemetry.armed
                                    ? Qt.rgba(0.91, 0.27, 0.24, 0.15)
                                    : "transparent"
                    border.color:   telemetry.armed ? theme.red   : theme.textDim
                    border.width:   1
                    Layout.rightMargin: 8

                    Text {
                        id:             armedText
                        anchors.centerIn: parent
                        text:           telemetry.armed ? "ARMED" : "DISARMED"
                        color:          telemetry.armed ? theme.red : theme.textMid
                        font.family:    theme.font
                        font.pixelSize: theme.sz12
                        font.weight:    Font.Bold
                    }

                    SequentialAnimation on opacity {
                        running: telemetry.armed
                        loops:   Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 550 }
                        NumberAnimation { to: 1.00; duration: 550 }
                    }
                }
            }

            RowLayout {
                spacing:          0
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                component NavTab: Rectangle {
                    id: tabRoot

                    property string tabLabel:  ""
                    property bool   active:    false
                    signal tabClicked()

                    property alias iconItem: iconSlot.children

                    width:   tabLabel === "ANALYZE" ? 96 : 80
                    height:  48
                    color:   active
                             ? Qt.rgba(0.96, 0.77, 0.09, 0.10)
                             : hov.containsMouse ? theme.bgHover : "transparent"

                    Rectangle {
                        width:  parent.width
                        height: active ? 2 : 0
                        color:  theme.yellow
                        anchors.top: parent.top
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Item {
                            id: iconSlot
                            width:  14
                            height: 14
                        }

                        Text {
                            text:           tabLabel
                            color:          active ? theme.yellow : theme.textDim
                            font.family:    theme.font
                            font.pixelSize: theme.sz11
                            font.weight:    Font.Bold
                        }
                    }

                    HoverHandler { id: hov }
                    TapHandler { onTapped: tabRoot.tabClicked() }
                }

                NavTab {
                    tabLabel: "FLY"
                    active:   parent.activeTab === 0
                    onTabClicked: parent.activeTab = 0

                    iconItem: [
                        Text {
                            anchors.centerIn: parent
                            text:           "✈"
                            color:          parent.parent.parent.active
                                            ? theme.yellow : theme.textDim
                            font.pixelSize: 13
                        }
                    ]
                }

                NavTab {
                    tabLabel: "PLAN"
                    active:   parent.activeTab === 1
                    onTabClicked: parent.activeTab = 1

                    iconItem: [
                        Grid {
                            anchors.centerIn: parent
                            columns: 2
                            spacing: 2
                            property bool act: parent.parent.parent.active
                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int modelData
                                    width:  3; height: 3
                                    color:  parent.act ? theme.yellow : theme.textDim
                                }
                            }
                        }
                    ]
                }

                NavTab {
                    tabLabel: "ANALYZE"
                    active:   parent.activeTab === 2
                    onTabClicked: parent.activeTab = 2

                    iconItem: [
                        Row {
                            anchors.centerIn: parent
                            spacing: 2
                            property bool act: parent.parent.parent.active
                            Repeater {
                                model: [10, 7, 13]
                                Rectangle {
                                    required property int modelData
                                    width:  3
                                    height: modelData
                                    anchors.bottom: parent ? parent.bottom : undefined
                                    color:  parent.act ? theme.yellow : theme.textDim
                                }
                            }
                        }
                    ]
                }

                NavTab {
                    tabLabel: "VEHICLE"
                    active:   parent.activeTab === 3
                    onTabClicked: parent.activeTab = 3
                    width: 88

                    iconItem: [
                        Text {
                            anchors.centerIn: parent
                            text:           "⌨"
                            color:          parent.parent.parent.active
                                            ? theme.yellow : theme.textDim
                            font.pixelSize: 12
                        }
                    ]
                }

                Rectangle {
                    width:  40
                    height: 48
                    color:  gearHov.containsMouse ? theme.bgHover : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text:           "⚙"
                        color:          theme.textDim
                        font.pixelSize: 15
                    }

                    HoverHandler { id: gearHov }
                    TapHandler   { onTapped: console.log("Settings") }
                }
            }
        }
    }

    FlyView {
        id:                     flyView
        anchors.top:            parent.top
        anchors.left:           parent.left
        anchors.right:          parent.right
        anchors.bottom:         parent.bottom
    }

    PlanView {
        id:             planView
        anchors.top:    parent.top
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        visible:        false
    }

    Loader {
        id:             briechModernView
        anchors.fill:   parent
        z:              100
        visible:        false
        active:         visible || mainWindow._briechModernViewInitialized
        source:         "qrc:/Briech/qml/Modern/BriechModernView.qml"

        onVisibleChanged: {
            if (visible) {
                mainWindow._briechModernViewInitialized = true
            }
        }

        onLoaded: {
            if (item && item.activateModernSection) {
                item.activateModernSection("fly")
            }
        }
    }

    footer: LogReplayStatusBar {
        visible: QGroundControl.settingsManager.flyViewSettings.showLogReplayStatusBar.rawValue
    }

    MessageDialog {
        id:                 showTouchAreasNotification
        title:              qsTr("Debug Touch Areas")
        text:               qsTr("Touch Area display toggled")
        buttons:            MessageDialog.Ok
    }

    MessageDialog {
        id:                 advancedModeOnConfirmation
        title:              qsTr("Advanced Mode")
        text:               QGroundControl.corePlugin.showAdvancedUIMessage
        buttons:            MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = true
            }
        }
    }

    MessageDialog {
        id:                 advancedModeOffConfirmation
        title:              qsTr("Advanced Mode")
        text:               qsTr("Turn off Advanced Mode?")
        buttons:            MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = false
            }
        }
    }

    function showToolSelectDialog() {
        if (mainWindow.allowViewSwitch()) {
            mainWindow.showIndicatorDrawer(toolSelectComponent, null)
        }
    }

    Component {
        id: toolSelectComponent

        SelectViewDropdown {
        }
    }

    Rectangle {
        id:             toolDrawer
        anchors.fill:   parent
        visible:        false
        color:          qgcPal.window

        property var backIcon
        property string toolTitle
        property alias toolSource:  toolDrawerLoader.source
        property var toolIcon

        onVisibleChanged: {
            if (!toolDrawer.visible) {
                toolDrawerLoader.source = ""
            }
        }

        // This need to block click event leakage to underlying map.
        DeadMouseArea {
            anchors.fill: parent
        }

        Rectangle {
            id:             toolDrawerToolbar
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            height:         ScreenTools.toolbarHeight
            color:          qgcPal.toolbarBackground

            RowLayout {
                id:                 toolDrawerToolbarLayout
                anchors.leftMargin: ScreenTools.defaultFontPixelWidth
                anchors.left:       parent.left
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                spacing:            ScreenTools.defaultFontPixelWidth

                QGCToolBarButton {
                    id: qgcButton
                    height: parent.height
                    icon.source: "/res/QGCLogoFull.svg"
                    logo: true
                    onClicked: mainWindow.showToolSelectDialog()
                }

                QGCLabel {
                    id:             toolbarDrawerText
                    text:           toolDrawer.toolTitle
                    font.pointSize: ScreenTools.largeFontPointSize
                }
            }
        }

        Loader {
            id:             toolDrawerLoader
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    toolDrawerToolbar.bottom
            anchors.bottom: parent.bottom
            onLoaded: {
                if (mainWindow._pendingSettingsPage !== "" && item && item.showSettingsPage) {
                    item.showSettingsPage(mainWindow._pendingSettingsPage)
                    mainWindow._pendingSettingsPage = ""
                }
            }

            Connections {
                target:                 toolDrawerLoader.item
                ignoreUnknownSignals:   true
                function onPopout() { toolDrawer.visible = false }
            }
        }
    }

    //-------------------------------------------------------------------------
    //-- Critical Vehicle Message Popup

    function showCriticalVehicleMessage(message) {
        closeIndicatorDrawer()
        if (criticalVehicleMessagePopup.visible || QGroundControl.videoManager.fullScreen) {
            // We received additional warning message while an older warning message was still displayed.
            // When the user close the older one drop the message indicator tool so they can see the rest of them.
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = true
        } else {
            criticalVehicleMessagePopup.criticalVehicleMessage      = message
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false
            criticalVehicleMessagePopup.open()
        }
    }

    Popup {
        id:                 criticalVehicleMessagePopup
        y:                  ScreenTools.toolbarHeight + ScreenTools.defaultFontPixelHeight
        x:                  Math.round((mainWindow.width - width) * 0.5)
        width:              mainWindow.width  * 0.55
        height:             criticalVehicleMessageText.contentHeight + ScreenTools.defaultFontPixelHeight * 2
        modal:              false
        focus:              true

        property string criticalVehicleMessage:             ""
        property bool   additionalCriticalMessagesReceived: false

        background: Rectangle {
            anchors.fill:   parent
            color:          qgcPal.alertBackground
            radius:         ScreenTools.defaultFontPixelHeight * 0.5
            border.color:   qgcPal.alertBorder
            border.width:   2

            Rectangle {
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.top:                parent.top
                anchors.topMargin:          -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      vehicleWarningLabel.contentWidth + _margins
                height:                     vehicleWarningLabel.contentHeight + _margins

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 vehicleWarningLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Vehicle Error")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }

            Rectangle {
                id:                         additionalErrorsIndicator
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.bottom:             parent.bottom
                anchors.bottomMargin:       -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      additionalErrorsLabel.contentWidth + _margins
                height:                     additionalErrorsLabel.contentHeight + _margins
                visible:                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 additionalErrorsLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Additional errors received")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }
        }

        QGCLabel {
            id:                 criticalVehicleMessageText
            width:              criticalVehicleMessagePopup.width - ScreenTools.defaultFontPixelHeight
            anchors.centerIn:   parent
            wrapMode:           Text.WordWrap
            color:              qgcPal.alertText
            textFormat:         TextEdit.RichText
            text:               criticalVehicleMessagePopup.criticalVehicleMessage
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                criticalVehicleMessagePopup.close()
                if (criticalVehicleMessagePopup.additionalCriticalMessagesReceived) {
                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false;
                    flyView.dropMainStatusIndicatorTool();
                } else {
                    QGroundControl.multiVehicleManager.activeVehicle.resetErrorLevelMessages();
                }
            }
        }
    }

    //-------------------------------------------------------------------------
    //-- Indicator Drawer

    function showIndicatorDrawer(drawerComponent, indicatorItem) {
        indicatorDrawer.sourceComponent = drawerComponent
        indicatorDrawer.indicatorItem = indicatorItem
        indicatorDrawer.open()
    }

    function closeIndicatorDrawer() {
        indicatorDrawer.close()
    }

    Popup {
        id:             indicatorDrawer
        x:              calcXPosition()
        y:              ScreenTools.toolbarHeight + _margins
        leftInset:      0
        rightInset:     0
        topInset:       0
        bottomInset:    0
        padding:        _margins * 2
        visible:        false
        modal:          true
        focus:          true
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var sourceComponent
        property var indicatorItem

        property bool _expanded:    false
        property real _margins:     ScreenTools.defaultFontPixelHeight / 4

        function calcXPosition() {
            if (indicatorItem) {
                var xCenter = indicatorItem.mapToItem(mainWindow.contentItem, indicatorItem.width / 2, 0).x
                return Math.max(_margins, Math.min(xCenter - (contentItem.implicitWidth / 2), mainWindow.contentItem.width - contentItem.implicitWidth - _margins - (indicatorDrawer.padding * 2) - (ScreenTools.defaultFontPixelHeight / 2)))
            } else {
                return _margins
            }
        }

        onOpened: {
            _expanded                               = false;
            indicatorDrawerLoader.sourceComponent   = indicatorDrawer.sourceComponent
        }
        onClosed: {
            _expanded                               = false
            indicatorItem                           = undefined
            indicatorDrawerLoader.sourceComponent   = undefined
        }

        background: Item {
            Rectangle {
                id:             backgroundRect
                anchors.fill:   parent
                color:          QGroundControl.globalPalette.window
                radius:         indicatorDrawer._margins
                opacity:        0.85
            }

            Rectangle {
                anchors.horizontalCenter:   backgroundRect.right
                anchors.verticalCenter:     backgroundRect.top
                width:                      ScreenTools.largeFontPixelHeight
                height:                     width
                radius:                     width / 2
                color:                      QGroundControl.globalPalette.button
                border.color:               QGroundControl.globalPalette.buttonText
                visible:                    indicatorDrawerLoader.item && indicatorDrawerLoader.item.showExpand && !indicatorDrawer._expanded

                QGCLabel {
                    anchors.centerIn:   parent
                    text:               ">"
                    color:              QGroundControl.globalPalette.buttonText
                }

                QGCMouseArea {
                    fillItem: parent
                    onClicked: indicatorDrawer._expanded = true
                }
            }
        }

        contentItem: QGCFlickable {
            id:             indicatorDrawerLoaderFlickable
            implicitWidth:  Math.min(mainWindow.contentItem.width - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.width)
            implicitHeight: Math.min(mainWindow.contentItem.height - ScreenTools.toolbarHeight - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.height)
            contentWidth:   indicatorDrawerLoader.width
            contentHeight:  indicatorDrawerLoader.height

            Loader {
                id: indicatorDrawerLoader

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "expanded"
                    value:      indicatorDrawer._expanded
                }

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "drawer"
                    value:      indicatorDrawer
                }
            }
        }
    }

    // We have to create the popup windows for the Analyze pages here so that the creation context is rooted
    // to mainWindow. Otherwise if they are rooted to the AnalyzeView itself they will die when the analyze viewSwitch
    // closes.

    function createrWindowedAnalyzePage(title, source) {
        var windowedPage = windowedAnalyzePage.createObject(mainWindow)
        windowedPage.title = title
        windowedPage.source = source
    }

    Component {
        id: windowedAnalyzePage

        Window {
            width:      ScreenTools.defaultFontPixelWidth  * 100
            height:     ScreenTools.defaultFontPixelHeight * 40
            visible:    true

            property alias source: loader.source

            Rectangle {
                color:          QGroundControl.globalPalette.window
                anchors.fill:   parent

                Loader {
                    id:             loader
                    anchors.fill:   parent
                    onLoaded:       item.popped = true
                }
            }

            onClosing: {
                visible = false
                source = ""
            }
        }
    }
}
