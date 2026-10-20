#include "BriechSafetyMonitor.h"

#include <QtCore/QSettings>
#include <QtCore/QtMath>

namespace {
constexpr qint64 kTelemetryStaleMs = 5000;
constexpr int kHistoryLimit = 100;
const char kHistoryKey[] = "Briech/SafetyMonitorHistory";
}

BriechSafetyMonitor::BriechSafetyMonitor(QObject *parent)
    : QObject(parent)
{
    _loadHistory();
    _staleTimer.setInterval(1000);
    _staleTimer.setSingleShot(false);
    connect(&_staleTimer, &QTimer::timeout, this, &BriechSafetyMonitor::_assess);
    _staleTimer.start();
}

double BriechSafetyMonitor::_number(const QVariantMap &snapshot, const QString &key, double fallback)
{
    bool ok = false;
    const double value = snapshot.value(key).toDouble(&ok);
    return ok && qIsFinite(value) ? value : fallback;
}

void BriechSafetyMonitor::_addFinding(QVariantList &findings, const QString &id, const QString &title,
                                      const QString &severity, const QString &evidence,
                                      const QString &action, int impact)
{
    QVariantMap finding;
    finding.insert(QStringLiteral("id"), id);
    finding.insert(QStringLiteral("title"), title);
    finding.insert(QStringLiteral("severity"), severity);
    finding.insert(QStringLiteral("evidence"), evidence);
    finding.insert(QStringLiteral("action"), action);
    finding.insert(QStringLiteral("impact"), impact);
    findings.append(finding);
}

void BriechSafetyMonitor::evaluate(const QVariantMap &snapshot)
{
    _snapshot = snapshot;
    _lastSnapshotUtc = QDateTime::currentDateTimeUtc();

    if (snapshot.value(QStringLiteral("connected")).toBool()) {
        const qulonglong messages = snapshot.value(QStringLiteral("messagesReceived")).toULongLong();
        if (!_haveMessageCounter || messages != _lastMessagesReceived) {
            _lastMessagesReceived = messages;
            _lastTelemetryProgressUtc = _lastSnapshotUtc;
            _haveMessageCounter = true;
        }
    } else {
        _haveMessageCounter = false;
        _lastMessagesReceived = 0;
        _lastTelemetryProgressUtc = QDateTime();
    }

    _assess();
}

void BriechSafetyMonitor::_assess()
{
    const bool connected = _snapshot.value(QStringLiteral("connected")).toBool();
    if (!connected) {
        QVariantList findings;
        _addFinding(findings, QStringLiteral("vehicle"), QStringLiteral("Vehicle link"), QStringLiteral("info"),
                    QStringLiteral("No active vehicle is connected."),
                    QStringLiteral("Connect or configure a telemetry link."), 0);
        _publish(QStringLiteral("UNKNOWN"), QStringLiteral("No vehicle data"),
                 QStringLiteral("Connect a vehicle; offline planning remains available."), 0, false, findings, 0);
        return;
    }

    const QDateTime now = QDateTime::currentDateTimeUtc();
    const bool stale = !_lastTelemetryProgressUtc.isValid()
        || _lastTelemetryProgressUtc.msecsTo(now) > kTelemetryStaleMs;
    QVariantList findings;
    int score = 100;
    int issueCount = 0;
    bool critical = false;
    bool warning = false;

    auto add = [&](const QString &id, const QString &title, const QString &severity,
                   const QString &evidence, const QString &action, int impact) {
        _addFinding(findings, id, title, severity, evidence, action, impact);
        score -= impact;
        if (severity == QStringLiteral("critical")) {
            critical = true;
            ++issueCount;
        } else if (severity == QStringLiteral("warning")) {
            warning = true;
            ++issueCount;
        }
    };

    if (stale) {
        add(QStringLiteral("telemetry-stale"), QStringLiteral("Telemetry freshness"), QStringLiteral("critical"),
            QStringLiteral("No new MAVLink messages for more than 5 seconds."),
            QStringLiteral("Treat displayed position and status as stale; restore the link before continuing."), 45);
    } else {
        add(QStringLiteral("telemetry-fresh"), QStringLiteral("Telemetry freshness"), QStringLiteral("ok"),
            QStringLiteral("MAVLink traffic is advancing."), QStringLiteral("No action required."), 0);
    }

    const double linkQuality = _number(_snapshot, QStringLiteral("linkQuality"), -1.0);
    if (linkQuality < 0.0) {
        add(QStringLiteral("link-quality"), QStringLiteral("Command link"), QStringLiteral("warning"),
            QStringLiteral("Packet-delivery quality is unavailable."),
            QStringLiteral("Confirm the primary telemetry link before flight."), 12);
    } else if (linkQuality < 70.0) {
        add(QStringLiteral("link-quality"), QStringLiteral("Command link"), QStringLiteral("critical"),
            QStringLiteral("Packet delivery is %1%.").arg(qRound(linkQuality)),
            QStringLiteral("Recover link margin or use a safe lost-link action."), 30);
    } else if (linkQuality < 90.0) {
        add(QStringLiteral("link-quality"), QStringLiteral("Command link"), QStringLiteral("warning"),
            QStringLiteral("Packet delivery is %1%.").arg(qRound(linkQuality)),
            QStringLiteral("Improve antenna placement or reduce range before continuing."), 14);
    } else {
        add(QStringLiteral("link-quality"), QStringLiteral("Command link"), QStringLiteral("ok"),
            QStringLiteral("Packet delivery is %1%.").arg(qRound(linkQuality)), QStringLiteral("No action required."), 0);
    }

    const bool armed = _snapshot.value(QStringLiteral("armed")).toBool();
    const int gpsLock = qRound(_number(_snapshot, QStringLiteral("gpsLock"), 0.0));
    const int satellites = qRound(_number(_snapshot, QStringLiteral("satellites"), 0.0));
    const double hdop = _number(_snapshot, QStringLiteral("hdop"), -1.0);
    if (gpsLock < 3) {
        add(QStringLiteral("gnss-fix"), QStringLiteral("GNSS integrity"), armed ? QStringLiteral("critical") : QStringLiteral("warning"),
            QStringLiteral("No 3D position fix is available."),
            QStringLiteral("Do not rely on position modes until a stable 3D fix is restored."), armed ? 35 : 20);
    } else if (satellites < 6 || (hdop > 0.0 && hdop > 3.0)) {
        add(QStringLiteral("gnss-quality"), QStringLiteral("GNSS integrity"), QStringLiteral("warning"),
            QStringLiteral("3D fix, %1 satellites, HDOP %2.").arg(satellites).arg(hdop > 0.0 ? QString::number(hdop, 'f', 1) : QStringLiteral("unknown")),
            QStringLiteral("Wait for stronger geometry and cross-check position before flight."), 16);
    } else {
        add(QStringLiteral("gnss-quality"), QStringLiteral("GNSS integrity"), QStringLiteral("ok"),
            QStringLiteral("3D fix, %1 satellites, HDOP %2.").arg(satellites).arg(hdop > 0.0 ? QString::number(hdop, 'f', 1) : QStringLiteral("unknown")),
            QStringLiteral("Continue monitoring for abrupt changes."), 0);
    }

    const double battery = _number(_snapshot, QStringLiteral("batteryPercent"), -1.0);
    if (battery < 0.0) {
        add(QStringLiteral("battery"), QStringLiteral("Energy reserve"), QStringLiteral("warning"),
            QStringLiteral("Battery percentage is unavailable."),
            QStringLiteral("Verify battery telemetry before arming."), 14);
    } else if (battery <= 15.0) {
        add(QStringLiteral("battery"), QStringLiteral("Energy reserve"), QStringLiteral("critical"),
            QStringLiteral("Battery is %1%.").arg(qRound(battery)),
            QStringLiteral("Land or recover immediately; do not begin a mission."), 35);
    } else if (battery <= 30.0) {
        add(QStringLiteral("battery"), QStringLiteral("Energy reserve"), QStringLiteral("warning"),
            QStringLiteral("Battery is %1%.").arg(qRound(battery)),
            QStringLiteral("Shorten the mission and preserve return reserve."), 18);
    } else {
        add(QStringLiteral("battery"), QStringLiteral("Energy reserve"), QStringLiteral("ok"),
            QStringLiteral("Battery is %1%.").arg(qRound(battery)), QStringLiteral("No action required."), 0);
    }

    const double homeLower = _number(_snapshot, QStringLiteral("homeLowerPercent"), -1.0);
    if (homeLower >= 0.0 && homeLower < 10.0) {
        add(QStringLiteral("return-energy"), QStringLiteral("Safe-return margin"), QStringLiteral("critical"),
            QStringLiteral("Conservative home estimate is %1%.").arg(qRound(homeLower)),
            QStringLiteral("Return or land now; the predicted reserve is insufficient."), 30);
    } else if (homeLower >= 0.0 && homeLower < 20.0) {
        add(QStringLiteral("return-energy"), QStringLiteral("Safe-return margin"), QStringLiteral("warning"),
            QStringLiteral("Conservative home estimate is %1%.").arg(qRound(homeLower)),
            QStringLiteral("Plan an early return and monitor energy trend."), 16);
    }

    const bool homeValid = _snapshot.value(QStringLiteral("homeValid")).toBool();
    if (!homeValid) {
        add(QStringLiteral("home"), QStringLiteral("Recovery reference"), armed ? QStringLiteral("critical") : QStringLiteral("warning"),
            QStringLiteral("A valid home position is not available."),
            QStringLiteral("Establish and verify the recovery point before relying on RTL."), armed ? 25 : 12);
    }

    const int healthProblems = qRound(_number(_snapshot, QStringLiteral("healthProblems"), 0.0));
    const bool healthSupported = _snapshot.value(QStringLiteral("healthSupported")).toBool();
    const bool canArm = _snapshot.value(QStringLiteral("canArm")).toBool();
    if (healthSupported && (!canArm || healthProblems > 0)) {
        add(QStringLiteral("vehicle-health"), QStringLiteral("Vehicle health"), armed ? QStringLiteral("warning") : QStringLiteral("critical"),
            QStringLiteral("%1 active preflight issue(s); arm clearance is %2.").arg(healthProblems).arg(canArm ? QStringLiteral("available") : QStringLiteral("blocked")),
            QStringLiteral("Open vehicle messages and resolve every preflight issue."), armed ? 15 : 25);
    } else {
        add(QStringLiteral("vehicle-health"), QStringLiteral("Vehicle health"), QStringLiteral("ok"),
            healthSupported ? QStringLiteral("No active preflight blockers.") : QStringLiteral("No firmware health report; local checks only."),
            healthSupported ? QStringLiteral("No action required.") : QStringLiteral("Confirm the flight stack checklist manually."), 0);
    }

    const bool simulation = _snapshot.value(QStringLiteral("simulation")).toBool();
    const bool signedLink = _snapshot.value(QStringLiteral("signedLink")).toBool();
    if (!signedLink && !simulation) {
        add(QStringLiteral("link-security"), QStringLiteral("Link authentication"), QStringLiteral("warning"),
            QStringLiteral("MAVLink signing is not active."),
            QStringLiteral("Enable signed MAVLink for operational deployments."), 10);
    } else {
        add(QStringLiteral("link-security"), QStringLiteral("Link authentication"), QStringLiteral("ok"),
            simulation ? QStringLiteral("Simulation link exception is active.") : QStringLiteral("MAVLink signing is active."),
            simulation ? QStringLiteral("Do not use this exception for field operations.") : QStringLiteral("No action required."), 0);
    }

    score = qBound(0, score, 100);
    QString state = QStringLiteral("READY");
    QString summary = QStringLiteral("Local checks are clear");
    QString guidance = QStringLiteral("Continue monitoring; the operator remains responsible for the flight decision.");
    if (critical) {
        state = QStringLiteral("UNSAFE");
        summary = stale ? QStringLiteral("Telemetry is stale") : QStringLiteral("Critical readiness condition");
        guidance = QStringLiteral("Do not start or continue the mission until critical findings are resolved.");
    } else if (warning) {
        state = QStringLiteral("CAUTION");
        summary = QStringLiteral("Operational review required");
        guidance = QStringLiteral("Review each warning and apply the recommended mitigation before proceeding.");
    }

    _publish(state, summary, guidance, score, stale, findings, issueCount);
}

void BriechSafetyMonitor::_publish(const QString &state, const QString &summary, const QString &guidance,
                                   int score, bool stale, const QVariantList &findings, int issueCount)
{
    const bool stateTransition = _state != state || _summary != summary;
    const QString updated = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"));
    const bool changed = stateTransition || _guidance != guidance || _score != score || _stale != stale
        || _findings != findings || _issueCount != issueCount;
    _state = state;
    _summary = summary;
    _guidance = guidance;
    _score = score;
    _stale = stale;
    _findings = findings;
    _issueCount = issueCount;
    _lastUpdated = updated;
    if (changed) {
        emit assessmentChanged();
    }
    if (stateTransition) {
        _appendHistory(state, summary, score, issueCount);
    }
}

void BriechSafetyMonitor::_appendHistory(const QString &state, const QString &summary, int score, int issueCount)
{
    QVariantMap event;
    event.insert(QStringLiteral("timestamp"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    event.insert(QStringLiteral("state"), state);
    event.insert(QStringLiteral("summary"), summary);
    event.insert(QStringLiteral("score"), score);
    event.insert(QStringLiteral("issueCount"), issueCount);
    _history.prepend(event);
    while (_history.size() > kHistoryLimit) {
        _history.removeLast();
    }
    _saveHistory();
    emit historyChanged();
}

void BriechSafetyMonitor::_loadHistory()
{
    QSettings settings;
    _history = settings.value(QString::fromLatin1(kHistoryKey)).toList();
    while (_history.size() > kHistoryLimit) {
        _history.removeLast();
    }
}

void BriechSafetyMonitor::_saveHistory() const
{
    QSettings settings;
    settings.setValue(QString::fromLatin1(kHistoryKey), _history);
}

void BriechSafetyMonitor::clear()
{
    _snapshot.clear();
    _lastSnapshotUtc = QDateTime();
    _lastTelemetryProgressUtc = QDateTime();
    _haveMessageCounter = false;
    _lastMessagesReceived = 0;
    _assess();
}

void BriechSafetyMonitor::clearHistory()
{
    if (_history.isEmpty()) {
        return;
    }
    _history.clear();
    _saveHistory();
    emit historyChanged();
}
