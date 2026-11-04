#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QJsonObject>
#include <QtCore/QList>
#include <QtCore/QObject>
#include <QtCore/QStringList>
#include <QtCore/QThread>
#include <QtCore/QTimer>

#include "FleetLinkWorker.h"

/// The coordinator link, as QML and the other Fleet classes see it.
///
/// Lives on the main thread. The WebSocket itself runs in FleetLinkWorker on
/// a thread this object owns, started only by start(). Every signal here is
/// emitted on the main thread. Interface: briech-docs/fleetlink-interface.md.
class FleetLink : public QObject
{
    Q_OBJECT

    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    /// Short upper-case text for status rows: CONNECTED, RETRYING IN 4 S, ...
    Q_PROPERTY(QString stateText READ stateText NOTIFY stateChanged)
    Q_PROPERTY(int retryInSeconds READ retryInSeconds NOTIFY stateChanged)
    Q_PROPERTY(int retryAttempt READ retryAttempt NOTIFY stateChanged)
    /// Why the link is not up. Never contains the token or the full URL.
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    /// True once nothing has been heard for 10 s while running: show the offline banner.
    Q_PROPERTY(bool coordinatorSilent READ coordinatorSilent NOTIFY silentChanged)
    /// Last 50 messages, newest first, as "hh:mm:ss.zzz type key".
    Q_PROPERTY(QStringList recentMessages READ recentMessages NOTIFY recentMessagesChanged)
    /// Messages dropped by FleetLink (bad JSON, wrong version, unknown type, offline).
    Q_PROPERTY(int droppedCount READ droppedCount NOTIFY droppedCountChanged)

public:
    enum State { Disabled, Connecting, Connected, Retrying, Unauthorized };
    Q_ENUM(State)

    explicit FleetLink(QObject *parent = nullptr);
    ~FleetLink() override;

    /// Fleet/url, Fleet/token, Fleet/operatorId and Fleet/caFile from QSettings.
    static FleetLinkConfig configFromSettings();

    /// Starts with an explicit config, ignoring Fleet/enabled. For tests and tools.
    void startWith(const FleetLinkConfig &config);

    State state() const { return _state; }
    QString stateText() const;
    int retryInSeconds() const;
    int retryAttempt() const { return _retryAttempt; }
    QString lastError() const { return _lastError; }
    bool coordinatorSilent() const { return _silent; }
    QStringList recentMessages() const { return _recent; }
    int droppedCount() const { return _droppedCount; }

public slots:
    /// Connects using QSettings. Does nothing unless Fleet/enabled is true.
    void start();
    /// Closes the socket and stops the worker thread. State becomes Disabled.
    void stop();
    /// Sends vehicle.state or operator.action. FleetLink adds the envelope.
    /// While not connected, vehicle.state is dropped and operator.action is
    /// queued (at most 100) until the next connection.
    void sendMessage(const QString &type, const QJsonObject &data);

signals:
    void stateChanged();
    void silentChanged();
    void recentMessagesChanged();
    void droppedCountChanged();

    /// Once per connection, before any batch: the whole picture. Replace everything.
    void snapshotReceived(const QJsonObject &data);
    /// Every 200 ms when anything arrived: full messages in arrival order,
    /// newest only per (type, key). Never empty.
    void batchReceived(const QList<QJsonObject> &messages);

private:
    void _onWorkerState(int state, int retryDelayMs, int attempt, const QString &error);
    void _onSnapshot(const QJsonObject &data);
    void _onBatch(const QList<QJsonObject> &messages);
    void _onDropped(const QString &reason);
    void _onTick();
    void _markHeard();
    void _remember(const QString &line);
    void _stopThread();

    QThread _thread;
    FleetLinkWorker *_worker = nullptr;
    QTimer _tick;
    QElapsedTimer _sinceHeard;
    QElapsedTimer _retryClock;
    QString _operatorId;
    State _state = Disabled;
    int _retryDelayMs = 0;
    int _retryAttempt = 0;
    int _silenceTimeoutMs = 10000;
    int _droppedCount = 0;
    QString _lastError;
    QStringList _recent;
    bool _running = false;
    bool _silent = false;
};
