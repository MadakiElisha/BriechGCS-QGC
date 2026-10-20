#pragma once

#include <QtCore/QDateTime>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

class BriechSafetyMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY assessmentChanged)
    Q_PROPERTY(QString summary READ summary NOTIFY assessmentChanged)
    Q_PROPERTY(QString guidance READ guidance NOTIFY assessmentChanged)
    Q_PROPERTY(int score READ score NOTIFY assessmentChanged)
    Q_PROPERTY(int issueCount READ issueCount NOTIFY assessmentChanged)
    Q_PROPERTY(bool stale READ stale NOTIFY assessmentChanged)
    Q_PROPERTY(QString lastUpdated READ lastUpdated NOTIFY assessmentChanged)
    Q_PROPERTY(QVariantList findings READ findings NOTIFY assessmentChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(bool localOnly READ localOnly CONSTANT)

public:
    explicit BriechSafetyMonitor(QObject *parent = nullptr);

    QString state() const { return _state; }
    QString summary() const { return _summary; }
    QString guidance() const { return _guidance; }
    int score() const { return _score; }
    int issueCount() const { return _issueCount; }
    bool stale() const { return _stale; }
    QString lastUpdated() const { return _lastUpdated; }
    QVariantList findings() const { return _findings; }
    QVariantList history() const { return _history; }
    bool localOnly() const { return true; }

    Q_INVOKABLE void evaluate(const QVariantMap &snapshot);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void clearHistory();

signals:
    void assessmentChanged();
    void historyChanged();

private:
    void _assess();
    void _publish(const QString &state, const QString &summary, const QString &guidance,
                  int score, bool stale, const QVariantList &findings, int issueCount);
    void _appendHistory(const QString &state, const QString &summary, int score, int issueCount);
    void _loadHistory();
    void _saveHistory() const;
    static void _addFinding(QVariantList &findings, const QString &id, const QString &title,
                            const QString &severity, const QString &evidence,
                            const QString &action, int impact);
    static double _number(const QVariantMap &snapshot, const QString &key, double fallback);

    QVariantMap _snapshot;
    QVariantList _findings;
    QVariantList _history;
    QTimer _staleTimer;
    QDateTime _lastSnapshotUtc;
    QDateTime _lastTelemetryProgressUtc;
    qulonglong _lastMessagesReceived = 0;
    bool _haveMessageCounter = false;
    QString _state = QStringLiteral("UNKNOWN");
    QString _summary = QStringLiteral("Waiting for local telemetry");
    QString _guidance = QStringLiteral("Connect a vehicle to begin readiness assessment.");
    QString _lastUpdated;
    int _score = 0;
    int _issueCount = 0;
    bool _stale = false;
};
