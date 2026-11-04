#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QJsonObject>
#include <QtCore/QList>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtCore/QUrl>

#include "FleetProtocol.h"

class QWebSocket;

/// Everything FleetLink needs to connect. Read from QSettings on the main
/// thread (FleetLink::configFromSettings) and copied to the worker.
struct FleetLinkConfig
{
    QUrl url;
    QString token;
    QString operatorId;
    QString caFile;                 ///< Extra CA certificate (PEM) to trust, e.g. ops/certs/ca.crt.
    QString clientVersion;
    int batchIntervalMs = 200;
    int silenceTimeoutMs = 10000;   ///< No message for this long: drop the socket and reconnect.
    int maxQueuedActions = 100;     ///< operator.action kept while offline; oldest dropped.
};

/// The coordinator WebSocket. Lives on FleetLink's worker thread and is only
/// driven through queued calls; it never touches a Vehicle or a QML object.
class FleetLinkWorker : public QObject
{
    Q_OBJECT

public:
    /// Same values as FleetLink::State.
    enum State { Disabled, Connecting, Connected, Retrying, Unauthorized };

    explicit FleetLinkWorker(QObject *parent = nullptr);
    ~FleetLinkWorker() override;

    void start(const FleetLinkConfig &config);
    void stop();
    /// keepWhileOffline: queue it (operator.action) rather than drop it (vehicle.state).
    void send(const QByteArray &json, bool keepWhileOffline);

signals:
    void stateChanged(int state, int retryDelayMs, int attempt, const QString &error);
    void snapshotReceived(const QJsonObject &data);
    void batchReceived(const QList<QJsonObject> &messages);
    void dropped(const QString &reason);

private:
    void _open();
    void _onConnected();
    void _onTextMessage(const QString &text);
    void _onSocketGone();
    void _onTick();
    void _scheduleReconnect();
    void _flushBatch();
    void _setState(State state, int retryDelayMs = 0);

    FleetLinkConfig _config;
    QWebSocket *_socket = nullptr;
    QTimer _tick;
    QTimer _reconnectTimer;
    QElapsedTimer _sinceLastMessage;
    FleetBatcher _batcher;
    FleetBackoff _backoff;
    QList<QByteArray> _queuedActions;
    State _state = Disabled;
    QString _error;
    bool _running = false;
    bool _haveSnapshot = false;
};
