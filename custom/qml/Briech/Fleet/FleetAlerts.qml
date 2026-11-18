pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models

import Custom.Widgets 1.0

import "FleetFormat.js" as FleetFormat

// Fleet alerts section of the Fleet panel: the active alert count and up to
// three active alerts from the coordinator (FleetAlertModel). While the
// coordinator is not connected it says so instead of showing an empty
// "all clear" that nobody actually checked.
Rectangle {
    id: root

    /// Alert rows (FleetAlertModel roles).
    property var model: FleetAlertModel

    /// A line was clicked: show that alert in the alert panel.
    signal openAlertRequested(string alertId)

    readonly property bool connected: FleetLink.state === FleetLink.Connected
    readonly property int activeCount: model ? model.activeCount : 0
    readonly property int shownMax: 3

    height: 30 + alertColumn.height
    color: "transparent"

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(1, 1, 1, 0.075)
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        y: 10
        text: "ALERTS"
        color: BriechTheme.goldAccent
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 1.5
        font.family: "Share Tech Mono"
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 10
        text: root.activeCount > 0 ? root.activeCount + " ACTIVE"
              : (root.connected ? "NONE" : FleetLink.stateText)
        color: root.activeCount > 0 ? BriechTheme.errColor : BriechTheme.mutedColor
        font.pixelSize: 9
        font.letterSpacing: 1
        font.family: "Share Tech Mono"
    }

    // Active alerts only; closed ones are on the FLEET page.
    SortFilterProxyModel {
        id: activeAlerts
        model: root.model
        filters: [
            FunctionFilter {
                function filter(data: AlertData): bool { return data.active }
            }
        ]
    }

    component AlertData: QtObject {
        property bool active
    }

    Column {
        id: alertColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 28
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        Repeater {
            model: activeAlerts

            delegate: Item {
                id: alertLine

                required property int index
                required property string alert_id
                required property var severity
                required property var className
                required property var confidence
                required property int ageSeconds
                required property bool stale

                visible: index < root.shownMax
                width: alertColumn.width
                height: visible ? 16 : 0
                opacity: stale ? 0.55 : 1

                // Click a line to open the alert (picture, proposal, APPROVE / REJECT).
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAlertRequested(alertLine.alert_id)
                }

                Row {
                    spacing: 6

                    Text {
                        width: 46
                        text: FleetFormat.wordText(alertLine.severity)
                        color: FleetFormat.severityTone(alertLine.severity, BriechTheme)
                        font.pixelSize: 9
                        font.bold: true
                        font.family: "Share Tech Mono"
                    }
                    Text {
                        width: 90
                        text: FleetFormat.wordText(alertLine.className)
                        color: BriechTheme.textColor
                        elide: Text.ElideRight
                        font.pixelSize: 9
                        font.family: "Share Tech Mono"
                    }
                    Text {
                        width: 32
                        text: FleetFormat.confidenceText(alertLine.confidence)
                        color: BriechTheme.mutedColor
                        font.pixelSize: 9
                        font.family: "Share Tech Mono"
                    }
                    Text {
                        text: FleetFormat.ageText(alertLine.ageSeconds) + (alertLine.stale ? " STALE" : "")
                        color: alertLine.stale ? BriechTheme.warnColor : BriechTheme.mutedColor
                        font.pixelSize: 9
                        font.family: "Share Tech Mono"
                    }
                }
            }
        }

        Text {
            visible: root.activeCount > root.shownMax
            height: visible ? 16 : 0
            text: "+" + (root.activeCount - root.shownMax) + " MORE ON THE FLEET PAGE"
            color: BriechTheme.mutedColor
            font.pixelSize: 9
            font.family: "Share Tech Mono"
        }

        Item { width: 1; height: root.activeCount > 0 ? 6 : 0 }
    }
}
