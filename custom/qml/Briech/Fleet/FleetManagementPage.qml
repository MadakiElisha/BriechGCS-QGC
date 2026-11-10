pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models

import QGroundControl
import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// FLEET tab of the Modern view: the full fleet management page.
//
// The Modern view loads this only while the FLEET tab is selected, so it costs
// nothing otherwise. It never creates a map (the FLY map is reused through
// "Show on map") and never sends flight commands itself: APPROVE and REJECT
// only ask the Modern view, which confirms with the operator before
// FleetDispatch sends anything.
//
// The roster lists QGC's connected vehicles (`model`). Below it, the
// coordinator's towers, detections and alerts come from FleetAssetModel,
// FleetObjectModel and FleetAlertModel. While the coordinator is not connected
// those sections say so, and any rows left over read STALE; they never show an
// empty "all clear" nobody checked.
Rectangle {
    id: root

    signal enableRequested()
    signal showOnMapRequested(var vehicle)
    signal openVehicleSetupRequested(var vehicle)
    /// APPROVE / REJECT on an alert with a proposal; the Modern view confirms first.
    signal approveAlertRequested(string alertId)
    signal rejectAlertRequested(string alertId)

    /// Roster source. Each row needs an "object" role holding the vehicle.
    property var model: QGroundControl.multiVehicleManager.vehicles

    /// The vehicle shown in the detail panel. Selecting a row does not change
    /// the active vehicle; only "Make active vehicle" does.
    property var selectedVehicle: null

    /// Roster order: "id" (ascending) or "battery" (lowest first).
    property string sortKey: "id"

    readonly property var vehicles: QGroundControl.multiVehicleManager.vehicles
    // Link percentages, sampled once a second (see FleetFormat.linkPercent).
    property var linkPercents: ({})

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.linkPercents = FleetFormat.sampleLinkPercents(root.vehicles)
    }
    readonly property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.075)
    readonly property color panelColor: "#080a0e"

    color: "#05070a"

    /// Keeps the selection valid: drop it when its vehicle disconnects, and
    /// default to the active vehicle (or the first one) when nothing is selected.
    function refreshSelection() {
        let stillConnected = false
        for (let i = 0; i < vehicles.count; i++) {
            if (vehicles.get(i) === selectedVehicle) {
                stillConnected = true
                break
            }
        }
        if (!stillConnected) {
            selectedVehicle = activeVehicle ? activeVehicle : (vehicles.count > 0 ? vehicles.get(0) : null)
        }
    }

    Component.onCompleted: refreshSelection()

    Connections {
        target: root.vehicles
        function onCountChanged() { root.refreshSelection() }
    }

    // Fleet switched off: explain and offer ENABLE; nothing else is created.
    Column {
        anchors.centerIn: parent
        width: Math.min(420, parent.width - 40)
        spacing: 14
        visible: !FleetSettings.enabled

        Text {
            width: parent.width
            text: "FLEET IS OFF"
            color: BriechTheme.goldAccent
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 24
            font.bold: true
            font.letterSpacing: 2
            font.family: "Barlow Condensed"
        }

        Text {
            width: parent.width
            text: "Turn Fleet on to manage every connected vehicle from one page. It stays on until you disable it."
            color: BriechTheme.mutedColor
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 12
            font.family: "Share Tech Mono"
        }

        ActionButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "ENABLE FLEET"
            primary: true
            onClicked: root.enableRequested()
        }
    }

    Loader {
        anchors.fill: parent
        active: FleetSettings.enabled
        sourceComponent: pageContent
    }

    Component {
        id: pageContent

        ColumnLayout {
            spacing: 12

            // Coordinator silent for 10 s: say so above everything else.
            FleetOfflineBanner {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: visible ? 12 : 0
                Layout.preferredHeight: height
            }

            // Title.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 16
                spacing: 2

                Text {
                    text: "FLEET MANAGEMENT"
                    color: BriechTheme.textColor
                    font.pixelSize: 24
                    font.bold: true
                    font.letterSpacing: 1.5
                    font.family: "Barlow Condensed"
                }

                Text {
                    text: "Vehicles connected to this ground station · coordinator: " + FleetLink.stateText.toLowerCase()
                    color: BriechTheme.mutedColor
                    font.pixelSize: 11
                    font.family: "Share Tech Mono"
                }
            }

            // Summary bar.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 8

                readonly property int armed: FleetFormat.armedCount(root.vehicles)
                readonly property int airborne: FleetFormat.flyingCount(root.vehicles)
                readonly property int lowBattery: FleetFormat.lowBatteryCount(root.vehicles)
                readonly property real worstLink: FleetFormat.worstLinkPercent(root.linkPercents)

                SummaryTile { label: "VEHICLES"; value: root.vehicles.count }
                SummaryTile {
                    label: "ARMED"
                    value: parent.armed
                    tone: parent.armed > 0 ? BriechTheme.okColor : BriechTheme.textColor
                }
                SummaryTile {
                    label: "AIRBORNE"
                    value: parent.airborne
                    tone: parent.airborne > 0 ? BriechTheme.blueColor : BriechTheme.textColor
                }
                SummaryTile {
                    label: "BATT LOW"
                    value: parent.lowBattery
                    tone: parent.lowBattery > 0 ? BriechTheme.errColor : BriechTheme.textColor
                }
                SummaryTile {
                    label: "WORST LINK"
                    value: isNaN(parent.worstLink) ? "--" : parent.worstLink + "%"
                    tone: FleetFormat.linkTone(parent.worstLink, BriechTheme)
                }
                SummaryTile {
                    label: "ACTIVE ALERTS"
                    // "--" until the coordinator has been heard: no source is not "0 alerts".
                    readonly property bool known: FleetLink.state === FleetLink.Connected || FleetAlertModel.count > 0
                    value: known ? FleetAlertModel.activeCount : "--"
                    tone: known && FleetAlertModel.activeCount > 0 ? BriechTheme.errColor : BriechTheme.textColor
                }
                SummaryTile {
                    label: "COORDINATOR"
                    // CONNECTED, CONNECTING, RETRYING IN 4 S, UNAUTHORIZED or DISABLED
                    value: FleetLink.stateText
                    tone: FleetLink.state === FleetLink.Connected ? BriechTheme.okColor
                        : FleetLink.state === FleetLink.Unauthorized ? BriechTheme.errColor
                        : BriechTheme.mutedColor
                }
            }

            // Roster and detail, or the empty state.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.vehicles.count === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "NO VEHICLES CONNECTED"
                        color: BriechTheme.textColor
                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1.5
                        font.family: "Barlow Condensed"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Connect a vehicle, or start the PX4 SITL simulator from the FLY tab."
                        color: BriechTheme.mutedColor
                        font.pixelSize: 11
                        font.family: "Share Tech Mono"
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 12
                    visible: root.vehicles.count > 0

                    FleetRoster {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    VehicleDetail {
                        Layout.preferredWidth: 340
                        Layout.fillHeight: true
                        vehicle: root.selectedVehicle
                    }
                }
            }

            // Coordinator data. The schemas have no tasking message, so the
            // third section is the coordinator's fixed assets (towers).
            RowLayout {
                Layout.fillWidth: true
                // A nested layout fills by default; the roster above takes the spare height.
                Layout.fillHeight: false
                Layout.preferredHeight: 160
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 8

                CoordinatorList {
                    title: "ASSETS"
                    model: FleetAssetModel
                    emptyText: "NO ASSETS REPORTED"
                    rowDelegate: AssetRow {}
                }
                CoordinatorList {
                    title: "DETECTIONS"
                    model: FleetObjectModel
                    emptyText: "NO DETECTIONS"
                    rowDelegate: ObjectRow {}
                }
                CoordinatorList {
                    title: "ALERTS"
                    model: FleetAlertModel
                    // Alerts still waiting for a decision (or carrying one out)
                    // first, so the one that needs APPROVE is never below a
                    // list of expired ones. Same order as the model otherwise.
                    listModel: SortFilterProxyModel {
                        model: FleetAlertModel
                        sorters: [
                            FunctionSorter {
                                function sort(lhsData: AlertOrderRow, rhsData: AlertOrderRow): int {
                                    return root.alertRank(lhsData.status) - root.alertRank(rhsData.status)
                                }
                            }
                        ]
                    }
                    emptyText: "NO ALERTS"
                    rowDelegate: AlertRow {}
                }
            }

            AuditRow {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
            }

            LinkMessages {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 16
            }
        }
    }

    // One figure in the summary bar.
    component SummaryTile: Rectangle {
        id: tile

        property string label
        property var value: "--"
        property color tone: BriechTheme.textColor

        Layout.fillWidth: true
        Layout.preferredHeight: 54
        color: root.panelColor
        border.color: root.hairline
        border.width: 1

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                text: tile.label
                color: BriechTheme.mutedColor
                font.pixelSize: 9
                font.letterSpacing: 1.5
                font.family: "Share Tech Mono"
            }

            Text {
                text: tile.value
                color: tile.tone
                font.pixelSize: 18
                font.bold: true
                font.family: "Share Tech Mono"
            }
        }
    }

    // One coordinator section: a title, the link state or row count, and a
    // compact list. Rows kept from before a disconnect stay, marked STALE.
    component CoordinatorList: Rectangle {
        id: coordinatorSection

        property string title
        property var model
        /// What the list shows; the same rows as model, possibly sorted.
        property var listModel: model
        property string emptyText
        property Component rowDelegate

        readonly property bool connected: FleetLink.state === FleetLink.Connected
        readonly property string awaitingText: "AWAITING COORDINATOR - " + FleetLink.stateText

        Layout.fillWidth: true
        Layout.fillHeight: true
        color: root.panelColor
        border.color: root.hairline
        border.width: 1

        RowLayout {
            id: sectionHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: 30

            Text {
                text: coordinatorSection.title
                color: BriechTheme.goldAccent
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
                font.family: "Share Tech Mono"
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.maximumWidth: coordinatorSection.width * 0.7
                text: coordinatorSection.connected ? String(coordinatorSection.model.count) : coordinatorSection.awaitingText
                color: coordinatorSection.connected ? BriechTheme.textColor : BriechTheme.warnColor
                elide: Text.ElideRight
                font.pixelSize: 10
                font.family: "Share Tech Mono"
            }
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 12
            visible: coordinatorSection.model.count === 0
            text: coordinatorSection.connected ? coordinatorSection.emptyText : coordinatorSection.awaitingText
            color: BriechTheme.mutedColor
            font.pixelSize: 10
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }

        ListView {
            id: sectionList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: sectionHeader.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 1
            clip: true
            model: coordinatorSection.listModel
            delegate: coordinatorSection.rowDelegate
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: sectionList.contentHeight > sectionList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        }
    }

    // Base for a coordinator row: fixed height, hairline below, faded when stale.
    component CoordinatorRow: Rectangle {
        required property int ageSeconds
        required property bool stale

        width: ListView.view ? ListView.view.width : 0
        height: 24
        color: "transparent"
        opacity: stale ? 0.55 : 1

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.05)
        }
    }

    // Age, or the age and STALE once the row is stale.
    component AgeCell: RowCell {
        property int ageSeconds
        property bool stale

        cellWidth: 74
        horizontalAlignment: Text.AlignRight
        text: FleetFormat.ageText(ageSeconds) + (stale ? " STALE" : "")
        color: stale ? BriechTheme.warnColor : BriechTheme.mutedColor
        font.pixelSize: 10
    }

    component AssetRow: CoordinatorRow {
        id: assetRow

        required property string asset_id
        required property var name
        required property var kind
        required property var health
        required property var link
        required property var battery_pct
        required property var mains_power

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            RowCell {
                Layout.fillWidth: true
                text: FleetFormat.has(assetRow.name) ? assetRow.name : assetRow.asset_id
                font.pixelSize: 10
            }
            RowCell { cellWidth: 44; text: FleetFormat.wordText(assetRow.kind); color: BriechTheme.mutedColor; font.pixelSize: 10 }
            RowCell {
                cellWidth: 64
                text: FleetFormat.wordText(assetRow.health)
                color: FleetFormat.healthTone(assetRow.health, BriechTheme)
                font.pixelSize: 10
            }
            RowCell {
                cellWidth: 56
                text: FleetFormat.wordText(assetRow.link)
                color: FleetFormat.assetLinkTone(assetRow.link, BriechTheme)
                font.pixelSize: 10
            }
            RowCell {
                cellWidth: 52
                // A battery reading if there is one, else whether it is on mains.
                text: FleetFormat.has(assetRow.battery_pct) ? assetRow.battery_pct + "%"
                      : (assetRow.mains_power === true ? "MAINS" : "--")
                color: BriechTheme.mutedColor
                font.pixelSize: 10
            }
            AgeCell { ageSeconds: assetRow.ageSeconds; stale: assetRow.stale }
        }
    }

    component ObjectRow: CoordinatorRow {
        id: objectRow

        required property string object_id
        required property var className
        required property var confidence
        required property var pos
        required property var seen_by

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            RowCell { Layout.fillWidth: true; text: FleetFormat.wordText(objectRow.className); font.pixelSize: 10 }
            RowCell { cellWidth: 36; text: FleetFormat.confidenceText(objectRow.confidence); font.pixelSize: 10 }
            RowCell { cellWidth: 44; text: FleetFormat.errorText(objectRow.pos); color: BriechTheme.mutedColor; font.pixelSize: 10 }
            RowCell {
                cellWidth: 64
                text: objectRow.seen_by ? objectRow.seen_by.join(",") : "--"
                color: BriechTheme.mutedColor
                font.pixelSize: 10
            }
            AgeCell { ageSeconds: objectRow.ageSeconds; stale: objectRow.stale }
        }
    }

    component AlertRow: CoordinatorRow {
        id: alertRow

        required property string alert_id
        required property var severity
        required property var className
        required property var confidence
        required property var reason
        required property var status
        required property bool active
        required property var proposal

        /// The coordinator proposed a vehicle and nobody has decided yet.
        readonly property bool decidable: !!proposal && (status === "open" || status === "acknowledged")

        // Closed alerts stay listed, dimmed.
        opacity: stale || !active ? 0.55 : 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            RowCell {
                cellWidth: 48
                text: FleetFormat.wordText(alertRow.severity)
                color: FleetFormat.severityTone(alertRow.severity, BriechTheme)
                font.pixelSize: 10
                font.bold: true
            }
            RowCell { cellWidth: 56; text: FleetFormat.wordText(alertRow.className); font.pixelSize: 10 }
            RowCell { cellWidth: 36; text: FleetFormat.confidenceText(alertRow.confidence); font.pixelSize: 10 }
            RowCell {
                Layout.fillWidth: true
                text: FleetFormat.has(alertRow.reason) ? alertRow.reason : "--"
                color: BriechTheme.mutedColor
                font.pixelSize: 10
            }
            RowCell { cellWidth: 84; text: FleetFormat.wordText(alertRow.status); font.pixelSize: 10 }
            AgeCell { ageSeconds: alertRow.ageSeconds; stale: alertRow.stale }
            // Only ask: the Modern view shows the proposal and confirms before anything is sent.
            SmallButton {
                visible: alertRow.decidable
                text: "APPROVE"
                tone: BriechTheme.okColor
                onClicked: root.approveAlertRequested(alertRow.alert_id)
            }
            SmallButton {
                visible: alertRow.decidable
                text: "REJECT"
                tone: BriechTheme.mutedColor
                onClicked: root.rejectAlertRequested(alertRow.alert_id)
            }
        }
    }

    component SmallButton: Rectangle {
        id: smallButton

        signal clicked()

        property string text
        property color tone

        Layout.preferredWidth: smallText.implicitWidth + 12
        Layout.preferredHeight: 18
        radius: 2
        color: smallArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        border.color: tone
        border.width: 1

        Text {
            id: smallText
            anchors.centerIn: parent
            text: smallButton.text
            color: smallButton.tone
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }

        MouseArea {
            id: smallArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: smallButton.clicked()
        }
    }

    // The local hash-chained log of operator actions (FleetAudit): how many
    // entries, and whether the chain still verifies. VERIFY re-reads the file.
    component AuditRow: Rectangle {
        id: auditRow

        // Not checked until the operator asks; never shown as OK before that.
        property var result: null

        Layout.preferredHeight: 28
        color: root.panelColor
        border.color: root.hairline
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 10

            Text {
                text: "LOCAL AUDIT"
                color: BriechTheme.goldAccent
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
                font.family: "Share Tech Mono"
            }

            Text {
                text: FleetAudit.count + (FleetAudit.count === 1 ? " ENTRY" : " ENTRIES")
                      + (FleetAudit.lastError.length > 0 ? " · WRITE FAILED: " + FleetAudit.lastError : "")
                color: FleetAudit.lastError.length > 0 ? BriechTheme.errColor : BriechTheme.mutedColor
                elide: Text.ElideRight
                Layout.fillWidth: true
                font.pixelSize: 10
                font.family: "Share Tech Mono"
            }

            Text {
                text: !auditRow.result ? "--"
                      : auditRow.result.ok ? "CHAIN OK"
                      : "BROKEN AT #" + auditRow.result.firstBroken
                color: !auditRow.result ? BriechTheme.mutedColor
                       : auditRow.result.ok ? BriechTheme.okColor : BriechTheme.errColor
                font.pixelSize: 10
                font.bold: !!auditRow.result
                font.family: "Share Tech Mono"
            }

            SmallButton {
                text: "VERIFY"
                tone: BriechTheme.goldAccent
                onClicked: auditRow.result = FleetAudit.verify()
            }
        }

        // A new entry makes an earlier result out of date.
        Connections {
            target: FleetAudit
            function onChanged() { auditRow.result = null }
        }
    }

    // Debug list of what FleetLink received, collapsed by default.
    component LinkMessages: Rectangle {
        id: messages

        property bool expanded: false

        Layout.preferredHeight: expanded ? 28 + 132 : 28
        color: root.panelColor
        border.color: root.hairline
        border.width: 1

        RowLayout {
            id: messagesHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: 28

            Text {
                text: "LINK MESSAGES"
                color: BriechTheme.goldAccent
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.5
                font.family: "Share Tech Mono"
            }

            Text {
                text: "LAST " + FleetLink.recentMessages.length + " · DROPPED " + FleetLink.droppedCount
                color: FleetLink.droppedCount > 0 ? BriechTheme.warnColor : BriechTheme.mutedColor
                font.pixelSize: 10
                font.family: "Share Tech Mono"
            }

            Item { Layout.fillWidth: true }

            Text {
                text: messages.expanded ? "HIDE ▴" : "SHOW ▾"
                color: BriechTheme.mutedColor
                font.pixelSize: 10
                font.family: "Share Tech Mono"
            }
        }

        MouseArea {
            anchors.fill: messagesHeader
            cursorShape: Qt.PointingHandCursor
            onClicked: messages.expanded = !messages.expanded
        }

        ListView {
            id: messageList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: messagesHeader.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 6
            visible: messages.expanded
            clip: true
            model: messages.expanded ? FleetLink.recentMessages : []
            boundsBehavior: Flickable.StopAtBounds

            delegate: Text {
                required property string modelData

                width: messageList.width
                text: modelData
                color: BriechTheme.mutedColor
                elide: Text.ElideRight
                font.pixelSize: 10
                font.family: "Share Tech Mono"
            }
        }
    }

    // Flat button in the Briech style.
    component ActionButton: Rectangle {
        id: button

        signal clicked()

        property string text
        property bool primary: false

        implicitWidth: buttonText.implicitWidth + 28
        implicitHeight: 30
        radius: 2
        opacity: enabled ? 1 : 0.4
        color: primary ? (buttonArea.containsMouse ? "#2a2310" : "#1a1609")
                       : (buttonArea.containsMouse ? "#121720" : "#0c1017")
        border.color: primary ? BriechTheme.goldAccent : Qt.rgba(1, 1, 1, 0.18)
        border.width: 1

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.text
            color: button.primary ? BriechTheme.goldAccent : BriechTheme.textColor
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: button.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // Roster: header with sort controls, then one row per vehicle.
    component FleetRoster: Rectangle {
        id: roster

        color: root.panelColor
        border.color: root.hairline
        border.width: 1

        // Sorting happens in a proxy so rows are never rebuilt by hand. QGC's
        // vehicle list does not announce value changes, so the battery order is
        // refreshed every few seconds; a model that emits dataChanged (Part B)
        // re-sorts on its own.
        SortFilterProxyModel {
            id: rosterModel
            model: root.model
            sorters: [
                FunctionSorter {
                    enabled: root.sortKey === "id"
                    function sort(lhsData: RosterRow, rhsData: RosterRow): int {
                        return lhsData.object.id - rhsData.object.id
                    }
                },
                FunctionSorter {
                    enabled: root.sortKey === "battery"
                    function sort(lhsData: RosterRow, rhsData: RosterRow): int {
                        const lhs = FleetFormat.batteryPercent(lhsData.object)
                        const rhs = FleetFormat.batteryPercent(rhsData.object)
                        // Unknown battery sorts last; ties fall back to id.
                        if (isNaN(lhs) !== isNaN(rhs)) {
                            return isNaN(lhs) ? 1 : -1
                        }
                        if (isNaN(lhs) || lhs === rhs) {
                            return lhsData.object.id - rhsData.object.id
                        }
                        return lhs < rhs ? -1 : 1
                    }
                }
            ]
        }

        Connections {
            target: root
            function onSortKeyChanged() { rosterModel.invalidateSorter() }
        }

        Timer {
            interval: 5000
            repeat: true
            running: root.sortKey === "battery"
            onTriggered: rosterModel.invalidateSorter()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // Column headings. ID and BATT sort the roster.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                color: "#05070a"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 8

                    HeaderCell { label: "ID"; cellWidth: 70; sortKey: "id" }
                    HeaderCell { label: "TYPE"; Layout.fillWidth: true }
                    HeaderCell { label: "FIRMWARE"; cellWidth: 96 }
                    HeaderCell { label: "MODE"; cellWidth: 84 }
                    HeaderCell { label: "STATE"; cellWidth: 64 }
                    HeaderCell { label: "BATT"; cellWidth: 52; sortKey: "battery" }
                    HeaderCell { label: "GPS"; cellWidth: 92 }
                    HeaderCell { label: "LINK"; cellWidth: 44 }
                    HeaderCell { label: "COMMS"; cellWidth: 52 }
                    HeaderCell { label: "AGE"; cellWidth: 40 }
                    HeaderCell { label: "LAST FLEET CMD"; cellWidth: 140 }
                }
            }

            ListView {
                id: rosterList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: rosterModel
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: rosterList.contentHeight > rosterList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

                delegate: RosterRowDelegate {
                    width: rosterList.width
                }
            }
        }
    }

    // Role data the sorters read from each proxy row.
    component RosterRow: QtObject {
        property var object
    }

    component AlertOrderRow: QtObject {
        property string status
    }

    /// Sort rank: waiting for a decision (as FleetAlertModel counts active: no
    /// status, open, acknowledged) first, then approved, then closed.
    function alertRank(status) {
        if (!status || status === "open" || status === "acknowledged") {
            return 0
        }
        return status === "approved" ? 1 : 2
    }

    component HeaderCell: Text {
        id: headerCell

        property string label
        /// Fixed column width; columns with Layout.fillWidth leave it unset.
        property real cellWidth: implicitWidth
        /// Roster sort key this heading selects; empty for non-sortable columns.
        property string sortKey: ""
        readonly property bool sorted: sortKey.length > 0 && root.sortKey === sortKey

        Layout.preferredWidth: cellWidth
        text: label + (sortKey.length > 0 ? " ▾" : "")
        color: sorted ? BriechTheme.goldAccent : BriechTheme.mutedColor
        elide: Text.ElideRight
        font.pixelSize: 9
        font.bold: sorted
        font.letterSpacing: 1.5
        font.family: "Share Tech Mono"

        MouseArea {
            anchors.fill: parent
            enabled: headerCell.sortKey.length > 0
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.sortKey = headerCell.sortKey
        }
    }

    component RosterRowDelegate: Rectangle {
        id: row

        required property var object

        readonly property bool selected: object === root.selectedVehicle
        readonly property bool isActive: object === root.activeVehicle
        readonly property real battery: FleetFormat.batteryPercent(object)
        readonly property real link: FleetFormat.sampledLink(root.linkPercents, object.id)
        readonly property bool commsLost: !!object.vehicleLinkManager && object.vehicleLinkManager.communicationLost
        // Data age (FleetDataAge, once a second): amber after 3 s, grey and stale after 10 s.
        readonly property int ageLevel: FleetFormat.vehicleAgeLevel(FleetDataAge.levels, object.id)
        readonly property bool stale: ageLevel === FleetFormat.ageGrey

        height: 40
        color: selected ? "#11141b" : (rowArea.containsMouse ? "#0d1016" : "transparent")

        Rectangle {
            width: 3
            height: parent.height
            color: row.selected ? BriechTheme.goldAccent : "transparent"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            spacing: 8
            opacity: row.stale ? 0.55 : 1

            RowCell {
                cellWidth: 70
                text: "BRCH-" + row.object.id + (row.isActive ? " ●" : "")
                color: row.isActive ? BriechTheme.goldAccent : BriechTheme.textColor
                font.bold: true
            }
            RowCell { Layout.fillWidth: true; text: String(row.object.vehicleTypeString).toUpperCase(); color: BriechTheme.mutedColor }
            RowCell { cellWidth: 96; text: FleetFormat.firmwareText(row.object) }
            RowCell { cellWidth: 84; text: String(row.object.flightMode).toUpperCase(); color: BriechTheme.okColor }
            RowCell {
                cellWidth: 64
                text: row.object.armed ? "ARMED" : "STANDBY"
                color: row.object.armed ? BriechTheme.okColor : BriechTheme.blueColor
            }
            RowCell {
                cellWidth: 52
                text: FleetFormat.batteryText(row.battery)
                color: FleetFormat.batteryTone(row.battery, BriechTheme)
            }
            RowCell { cellWidth: 92; text: FleetFormat.gpsText(row.object) }
            RowCell {
                cellWidth: 44
                text: isNaN(row.link) ? "--" : row.link + "%"
                color: FleetFormat.linkTone(row.link, BriechTheme)
            }
            RowCell {
                cellWidth: 52
                text: row.commsLost ? "LOST" : "OK"
                color: row.commsLost ? BriechTheme.errColor : BriechTheme.okColor
            }
            RowCell {
                cellWidth: 40
                text: FleetFormat.ageText(FleetFormat.vehicleAgeSeconds(FleetDataAge.seconds, row.object.id)) + (row.stale ? "!" : "")
                color: FleetFormat.ageTone(row.ageLevel, BriechTheme)
                font.bold: row.ageLevel === FleetFormat.ageAmber || row.stale
            }
            RowCell {
                // The last Hold all / Return all / approved proposal and what the vehicle answered.
                readonly property string fleetCommand: FleetDispatch.vehicleStatus[String(row.object.id)] || ""
                cellWidth: 140
                text: fleetCommand.length > 0 ? fleetCommand : "--"
                color: fleetCommand.indexOf("CONFIRMED") >= 0 ? BriechTheme.okColor
                     : fleetCommand.indexOf("REFUSED") >= 0 ? BriechTheme.errColor
                     : fleetCommand.indexOf("NO RESPONSE") >= 0 ? BriechTheme.warnColor
                     : BriechTheme.mutedColor
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.05)
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectedVehicle = row.object
        }
    }

    component RowCell: Text {
        /// Fixed column width; must match the HeaderCell above it.
        property real cellWidth: implicitWidth

        Layout.preferredWidth: cellWidth
        color: BriechTheme.textColor
        elide: Text.ElideRight
        font.pixelSize: 11
        font.family: "Share Tech Mono"
    }

    // Detail panel for the selected vehicle.
    component VehicleDetail: Rectangle {
        id: detail

        property var vehicle: null

        readonly property var health: vehicle ? vehicle.healthAndArmingCheckReport : null
        readonly property real battery: FleetFormat.batteryPercent(vehicle)

        color: root.panelColor
        border.color: root.hairline
        border.width: 1

        Text {
            anchors.centerIn: parent
            visible: !detail.vehicle
            text: "SELECT A VEHICLE"
            color: BriechTheme.mutedColor
            font.pixelSize: 11
            font.letterSpacing: 1.5
            font.family: "Share Tech Mono"
        }

        Flickable {
            id: detailFlick
            anchors.fill: parent
            anchors.margins: 14
            visible: !!detail.vehicle
            clip: true
            contentHeight: detailColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: detailColumn
                width: detailFlick.width
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: detail.vehicle ? "BRCH-" + detail.vehicle.id : ""
                        color: BriechTheme.textColor
                        font.pixelSize: 22
                        font.bold: true
                        font.family: "Barlow Condensed"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: detail.vehicle && detail.vehicle === root.activeVehicle ? "ACTIVE VEHICLE" : ""
                        color: BriechTheme.goldAccent
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.5
                        font.family: "Share Tech Mono"
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: detail.vehicle
                          ? String(detail.vehicle.vehicleTypeString).toUpperCase() + " · " + FleetFormat.firmwareText(detail.vehicle)
                          : ""
                    color: BriechTheme.mutedColor
                    elide: Text.ElideRight
                    font.pixelSize: 10
                    font.family: "Share Tech Mono"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 8
                    columnSpacing: 8

                    DetailValue { label: "ALT (REL)"; value: detail.vehicle ? FleetFormat.factText(detail.vehicle.altitudeRelative, 1, " m") : "--" }
                    DetailValue { label: "CLIMB"; value: detail.vehicle ? FleetFormat.factText(detail.vehicle.climbRate, 1, " m/s") : "--" }
                    DetailValue { label: "GROUND SPD"; value: detail.vehicle ? FleetFormat.factText(detail.vehicle.groundSpeed, 1, " m/s") : "--" }
                    DetailValue { label: "HEADING"; value: FleetFormat.headingText(detail.vehicle) }
                    DetailValue { label: "DIST HOME"; value: detail.vehicle ? FleetFormat.factText(detail.vehicle.distanceToHome, 0, " m") : "--" }
                    DetailValue {
                        label: "BATTERY"
                        value: FleetFormat.batteryText(detail.battery)
                        tone: FleetFormat.batteryTone(detail.battery, BriechTheme)
                    }
                    DetailValue { label: "MODE"; value: detail.vehicle ? String(detail.vehicle.flightMode).toUpperCase() : "--"; tone: BriechTheme.okColor }
                    DetailValue {
                        label: "STATE"
                        value: !detail.vehicle ? "--" : (detail.vehicle.flying ? "AIRBORNE" : (detail.vehicle.armed ? "ARMED" : "STANDBY"))
                        tone: detail.vehicle && detail.vehicle.armed ? BriechTheme.okColor : BriechTheme.blueColor
                    }
                    DetailValue { label: "GPS"; value: FleetFormat.gpsText(detail.vehicle) }
                }

                // Health and arming checks, when the firmware reports them.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.preferredHeight: 1
                    color: root.hairline
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "HEALTH"
                        color: BriechTheme.goldAccent
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.5
                        font.family: "Share Tech Mono"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: !detail.health || !detail.health.supported ? "NOT REPORTED"
                              : (detail.health.canArm ? "READY TO ARM" : "NOT READY TO ARM")
                        color: !detail.health || !detail.health.supported ? BriechTheme.mutedColor
                               : (detail.health.canArm ? BriechTheme.okColor : BriechTheme.warnColor)
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1
                        font.family: "Share Tech Mono"
                    }
                }

                Repeater {
                    model: detail.health && detail.health.supported ? detail.health.problemsForCurrentMode : null

                    delegate: Text {
                        required property var object

                        Layout.fillWidth: true
                        text: "• " + object.message
                        color: object.severity === "error" ? BriechTheme.errColor
                               : (object.severity === "warning" ? BriechTheme.warnColor : BriechTheme.mutedColor)
                        wrapMode: Text.WordWrap
                        font.pixelSize: 10
                        font.family: "Share Tech Mono"
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: !detail.health || !detail.health.supported
                    text: "This firmware does not report health and arming checks to QGC."
                    color: BriechTheme.mutedColor
                    wrapMode: Text.WordWrap
                    font.pixelSize: 10
                    font.family: "Share Tech Mono"
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.preferredHeight: 1
                    color: root.hairline
                }

                // Actions. None of these send a command to the vehicle.
                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ActionButton {
                        text: "MAKE ACTIVE VEHICLE"
                        primary: true
                        enabled: !!detail.vehicle && detail.vehicle !== root.activeVehicle
                        onClicked: QGroundControl.multiVehicleManager.activeVehicle = detail.vehicle
                    }

                    ActionButton {
                        text: "SHOW ON MAP"
                        enabled: !!detail.vehicle && detail.vehicle.coordinate.isValid
                        onClicked: root.showOnMapRequested(detail.vehicle)
                    }

                    ActionButton {
                        text: "OPEN VEHICLE SETUP"
                        enabled: !!detail.vehicle
                        onClicked: root.openVehicleSetupRequested(detail.vehicle)
                    }
                }
            }
        }
    }

    component DetailValue: Column {
        id: detailValue

        property string label
        property string value: "--"
        property color tone: BriechTheme.textColor

        Layout.fillWidth: true
        spacing: 2

        Text {
            text: detailValue.label
            color: BriechTheme.mutedColor
            font.pixelSize: 8
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }

        Text {
            text: detailValue.value
            color: detailValue.tone
            font.pixelSize: 13
            font.bold: true
            font.family: "Share Tech Mono"
        }
    }
}
