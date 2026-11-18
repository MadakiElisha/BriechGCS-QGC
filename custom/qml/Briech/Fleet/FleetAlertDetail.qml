pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// One alert, everything the operator needs to decide in one place: the camera
// picture (or why there is none), what was seen where and when, the drone the
// coordinator proposes, any warning, and APPROVE / REJECT. Slides in from the
// right of the Modern view (BriechModernView owns it; not a new window).
//
// Keys while open: A approve, R reject, Esc close. Approving and rejecting go
// through the Modern view's existing confirmation (requestAlertApproval and
// requestAlertRejection), so the safety checks are the same as before: the
// stale-data second confirmation, "not flying" and the photo notice included.
// After a decision the panel stays and shows the outcome.
Rectangle {
    id: root

    /// The alert shown; empty hides the panel.
    property string alertId

    signal closeRequested()
    signal approveRequested(string alertId)
    signal rejectRequested(string alertId)
    signal showOnMapRequested(real lat, real lon)

    property var alert: ({})
    property var proposal: ({})
    property int tick: 0        // one per second: countdown and ages

    readonly property string status: alert.status || "open"
    readonly property bool open: status === "open" || status === "acknowledged"
    readonly property bool decidable: open && !!proposal.command
    readonly property string snapshotId: alert.snapshot_id || ""
    readonly property string photoState: FleetSnapshots.revision >= 0 && snapshotId !== "" ? FleetSnapshots.state(snapshotId) : "none"
    readonly property int secondsLeft: {
        const ignored = tick
        const ends = Date.parse(alert.expires_ts || "")
        return isNaN(ends) ? -1 : Math.max(0, Math.round((ends - Date.now()) / 1000))
    }
    readonly property var pos: alert.pos || ({})
    readonly property var proposed: alert.proposal || ({})
    readonly property string vehicleStatusText: {
        const id = proposal.vehicleId || proposed.vehicle_id
        const all = FleetDispatch.vehicleStatus
        return id && all && all[String(id)] ? all[String(id)] : ""
    }

    function refresh() {
        if (alertId === "") {
            alert = ({})
            proposal = ({})
            return
        }
        alert = FleetAlertModel.get(alertId)
        proposal = FleetDispatch.proposalFor(alertId)
        if (snapshotId !== "") {
            FleetSnapshots.request(snapshotId)
        }
    }

    function approve() {
        if (decidable) {
            root.approveRequested(alertId)
        }
    }

    function reject() {
        if (decidable) {
            root.rejectRequested(alertId)
        }
    }

    onAlertIdChanged: {
        refresh()
        if (alertId !== "") {
            forceActiveFocus()
        }
    }

    visible: alertId !== ""
    width: 440
    color: "#0b0f15"
    border.color: Qt.rgba(1, 1, 1, 0.10)
    border.width: 1
    focus: visible

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested()
        } else if (event.key === Qt.Key_A) {
            root.approve()
        } else if (event.key === Qt.Key_R) {
            root.reject()
        } else {
            return
        }
        event.accepted = true
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: {
            root.tick++
            root.refresh()      // ages, stale and the proposal's checks change with time
        }
    }

    Connections {
        target: FleetAlertModel
        function onDataChanged() { root.refresh() }
        function onModelReset() { root.refresh() }
        function onRowsRemoved() { root.refresh() }
    }

    // Swallow clicks so they do not reach the map underneath.
    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 16
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 14

            // Header: severity, alert id, time left, close.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 4
                    Layout.preferredHeight: 22
                    color: FleetFormat.severityTone(root.alert.severity, BriechTheme)
                }
                Text {
                    text: FleetFormat.wordText(root.alert.severity) + " ALERT"
                    color: FleetFormat.severityTone(root.alert.severity, BriechTheme)
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1
                    font.family: "Share Tech Mono"
                }
                Text {
                    Layout.fillWidth: true
                    text: root.alertId
                    color: BriechTheme.mutedColor
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    font.family: "Share Tech Mono"
                }
                Text {
                    visible: root.open && root.secondsLeft >= 0
                    text: Math.floor(root.secondsLeft / 60) + ":" + String(root.secondsLeft % 60).padStart(2, "0") + " LEFT"
                    color: root.secondsLeft <= 30 ? BriechTheme.errColor : BriechTheme.warnColor
                    font.pixelSize: 13
                    font.bold: true
                    font.family: "Share Tech Mono"
                }
                Text {
                    text: "✕"
                    color: closeArea.containsMouse ? BriechTheme.textColor : BriechTheme.mutedColor
                    font.pixelSize: 16
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            // The camera picture, or what stands in for it. Never a placeholder picture.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: width * 0.75
                color: "#05070a"
                border.color: root.photoState === "unavailable" ? BriechTheme.warnColor : Qt.rgba(1, 1, 1, 0.12)
                border.width: 1

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: root.photoState === "ready"
                    source: visible ? "image://fleetsnapshot/" + root.snapshotId + "?r=" + FleetSnapshots.revision : ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    visible: root.photoState !== "ready"
                    spacing: 8

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.photoState === "loading" ? "LOADING PHOTO…"
                              : root.photoState === "unavailable" ? "PHOTO UNAVAILABLE"
                              : "NO PHOTO WITH THIS ALERT"
                        color: root.photoState === "unavailable" ? BriechTheme.warnColor : BriechTheme.mutedColor
                        font.pixelSize: 15
                        font.bold: true
                        font.family: "Share Tech Mono"
                    }
                    Text {
                        width: parent.width
                        visible: root.photoState === "unavailable"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: FleetSnapshots.revision >= 0 ? FleetSnapshots.reason(root.snapshotId) : ""
                        color: BriechTheme.mutedColor
                        font.pixelSize: 12
                        font.family: "Share Tech Mono"
                    }
                    PanelButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.photoState === "unavailable"
                        text: "RETRY"
                        tone: BriechTheme.warnColor
                        onClicked: FleetSnapshots.request(root.snapshotId, true)
                    }
                }
            }

            Text {
                visible: root.photoState === "ready"
                Layout.fillWidth: true
                text: "SHA-256 " + (FleetSnapshots.revision >= 0 ? FleetSnapshots.sha256(root.snapshotId).substring(0, 24) + "…" : "")
                color: BriechTheme.mutedColor
                elide: Text.ElideRight
                font.pixelSize: 11
                font.family: "Share Tech Mono"
            }

            // What, where, when.
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 6

                Fact { label: "WHAT" }
                Value { text: FleetFormat.wordText(root.alert.className || root.alert["class"]) + "  " + FleetFormat.confidenceText(root.alert.confidence) }
                Fact { label: "ZONE" }
                Value { text: FleetFormat.has(root.alert.zone_id) ? root.alert.zone_id : "--" }
                Fact { label: "WHY" }
                Value { text: FleetFormat.has(root.alert.reason) ? root.alert.reason : "--" }
                Fact { label: "WHERE" }
                Value {
                    text: root.pos.lat !== undefined
                          ? root.pos.lat.toFixed(5) + ", " + root.pos.lon.toFixed(5) + (root.pos.error_m !== undefined ? "  ±" + Math.round(root.pos.error_m) + " m" : "")
                          : "--"
                }
                Fact { label: "SEEN BY" }
                Value { text: root.alert.seen_by ? root.alert.seen_by.join(", ") : "--" }
                Fact { label: "UPDATED" }
                Value {
                    text: root.alert.ageSeconds !== undefined ? FleetFormat.ageText(root.alert.ageSeconds) + " ago" + (root.alert.stale ? "  STALE" : "") : "--"
                    color: root.alert.stale ? BriechTheme.warnColor : BriechTheme.textColor
                }
            }

            PanelButton {
                visible: root.pos.lat !== undefined
                text: "SHOW ON MAP"
                tone: BriechTheme.blueColor
                onClicked: root.showOnMapRequested(root.pos.lat, root.pos.lon)
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(1, 1, 1, 0.08) }

            // The coordinator's proposal.
            Text {
                text: "PROPOSAL"
                color: BriechTheme.goldAccent
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.5
                font.family: "Share Tech Mono"
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: !root.proposed.vehicle_id ? "No drone proposed (none free with enough battery)."
                      : (root.proposal.vehicleName || ("BRCH-" + root.proposed.vehicle_id)) + " · "
                        + FleetFormat.wordText(root.proposed.action)
                        + (root.proposed.radius_m !== undefined ? " " + Math.round(root.proposed.radius_m) + " m" : "")
                        + (root.proposed.alt_rel_m !== undefined ? " at " + Math.round(root.proposed.alt_rel_m) + " m" : "")
                color: BriechTheme.textColor
                font.pixelSize: 14
                font.family: "Share Tech Mono"
            }
            Text {
                visible: !!root.proposed.vehicle_id
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: (root.proposed.eta_s !== undefined ? "ETA " + Math.round(root.proposed.eta_s) + " s" : "ETA --")
                      + " · battery after " + (root.proposed.battery_after_pct !== undefined ? Math.round(root.proposed.battery_after_pct) + " %" : "--")
                color: BriechTheme.mutedColor
                font.pixelSize: 12
                font.family: "Share Tech Mono"
            }
            Text {
                visible: !!root.proposed.alternatives && root.proposed.alternatives.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: {
                    const alts = root.proposed.alternatives || []
                    return "Alternatives: " + alts.map(a => "BRCH-" + a.vehicle_id
                        + (a.eta_s !== undefined ? " (" + Math.round(a.eta_s) + " s" : " (--")
                        + (a.battery_after_pct !== undefined ? ", " + Math.round(a.battery_after_pct) + " %)" : ")")).join(", ")
                }
                color: BriechTheme.mutedColor
                font.pixelSize: 12
                font.family: "Share Tech Mono"
            }

            // Warnings, before deciding rather than after.
            Repeater {
                model: {
                    const list = []
                    if (root.open && root.proposal.problem) {
                        list.push(root.proposal.problem + ": approving records the decision only, nothing is sent.")
                    }
                    if (root.open && root.proposal.stale) {
                        list.push("Data is not current" + (root.proposal.staleReason ? ": " + root.proposal.staleReason : "") + ". A second confirmation will be asked.")
                    }
                    if (root.open && root.snapshotId !== "" && root.photoState !== "ready") {
                        list.push("You would be deciding without the camera picture.")
                    }
                    return list
                }
                delegate: Text {
                    required property string modelData
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "⚠ " + modelData
                    color: BriechTheme.warnColor
                    font.pixelSize: 12
                    font.family: "Share Tech Mono"
                }
            }

            // Decide, or the result once decided.
            RowLayout {
                visible: root.decidable
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12

                PanelButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    text: "APPROVE  (A)"
                    tone: BriechTheme.okColor
                    filled: true
                    onClicked: root.approve()
                }
                PanelButton {
                    Layout.preferredWidth: 130
                    Layout.preferredHeight: 40
                    text: "REJECT  (R)"
                    tone: BriechTheme.mutedColor
                    onClicked: root.reject()
                }
            }

            Text {
                visible: root.open && !root.decidable
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Nothing to approve: the coordinator has not proposed a drone for this alert."
                color: BriechTheme.mutedColor
                font.pixelSize: 12
                font.family: "Share Tech Mono"
            }

            Column {
                visible: !root.open
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: FleetFormat.wordText(root.status) + (root.alert.operator_id ? " by " + root.alert.operator_id : "")
                    color: root.status === "approved" ? BriechTheme.okColor : BriechTheme.mutedColor
                    font.pixelSize: 15
                    font.bold: true
                    font.family: "Share Tech Mono"
                }
                Text {
                    visible: root.vehicleStatusText !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Vehicle: " + root.vehicleStatusText
                    color: BriechTheme.textColor
                    font.pixelSize: 12
                    font.family: "Share Tech Mono"
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: "Keys: A approve · R reject · Esc close"
                color: Qt.rgba(1, 1, 1, 0.35)
                font.pixelSize: 11
                font.family: "Share Tech Mono"
            }
        }
    }

    component Fact: Text {
        property string label
        text: label
        color: BriechTheme.mutedColor
        font.pixelSize: 12
        font.letterSpacing: 1
        font.family: "Share Tech Mono"
    }

    component Value: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: BriechTheme.textColor
        font.pixelSize: 13
        font.family: "Share Tech Mono"
    }

    component PanelButton: Rectangle {
        id: button

        signal clicked()
        property string text
        property color tone
        property bool filled: false

        implicitWidth: buttonText.implicitWidth + 28
        implicitHeight: 32
        radius: 3
        color: filled ? Qt.rgba(tone.r, tone.g, tone.b, buttonArea.containsMouse ? 0.32 : 0.22)
                      : (buttonArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        border.color: tone
        border.width: 1

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.text
            color: button.tone
            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 1
            font.family: "Share Tech Mono"
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
