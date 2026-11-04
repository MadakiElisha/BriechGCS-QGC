#include "FleetLinkWorker.h"

#include <QtCore/QJsonDocument>
#include <QtCore/QLoggingCategory>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslCertificate>
#include <QtNetwork/QSslConfiguration>
#include <QtWebSockets/QWebSocket>

Q_LOGGING_CATEGORY(FleetLinkLog, "Briech.FleetLink")

namespace {

constexpr int kCloseBadHello = 4400;
constexpr qint64 kMaxIncomingMessage = 4 * 1024 * 1024; // a snapshot of 500 objects and 100 alerts fits easily

/// Host and port only: the URL is never logged whole (handoff section 6).
QString describe(const QUrl &url)
{
    return url.host() + QLatin1Char(':') + QString::number(url.port(url.scheme() == QLatin1String("wss") ? 443 : 80));
}

} // namespace

FleetLinkWorker::FleetLinkWorker(QObject *parent)
    : QObject(parent)
    , _tick(this)
    , _reconnectTimer(this)
{
    _reconnectTimer.setSingleShot(true);
    connect(&_reconnectTimer, &QTimer::timeout, this, &FleetLinkWorker::_open);
    connect(&_tick, &QTimer::timeout, this, &FleetLinkWorker::_onTick);
}

FleetLinkWorker::~FleetLinkWorker()
{
    stop();
}

void FleetLinkWorker::start(const FleetLinkConfig &config)
{
    stop();
    _config = config;
    _backoff.reset();
    _queuedActions.clear();
    _error.clear();

    if (_config.token.isEmpty()) {
        _error = QStringLiteral("no operator token set (Fleet/token)");
        _setState(Unauthorized);
        return;
    }
    const QString scheme = _config.url.scheme();
    if (!_config.url.isValid() || (scheme != QLatin1String("wss") && scheme != QLatin1String("ws"))) {
        _error = QStringLiteral("Fleet/url must be a ws:// or wss:// URL");
        _setState(Disabled);
        return;
    }
    if (scheme == QLatin1String("ws")) {
        qCWarning(FleetLinkLog) << "plain ws:// to" << describe(_config.url) << "- for local development only";
    }

    _running = true;
    _tick.start(_config.batchIntervalMs);
    _open();
}

void FleetLinkWorker::stop()
{
    const bool wasRunning = _running;
    _running = false;
    _tick.stop();
    _reconnectTimer.stop();
    _batcher.clear();
    _haveSnapshot = false;
    if (_socket) {
        QWebSocket *socket = _socket;
        _socket = nullptr;
        socket->disconnect(this);
        socket->close();
        socket->deleteLater();
    }
    if (wasRunning) {
        _error.clear();
        _setState(Disabled);
    }
}

void FleetLinkWorker::send(const QByteArray &json, bool keepWhileOffline)
{
    if (_state == Connected && _socket) {
        _socket->sendTextMessage(QString::fromUtf8(json));
        return;
    }
    if (!keepWhileOffline) {
        emit dropped(QStringLiteral("offline"));
        return;
    }
    if (_queuedActions.size() >= _config.maxQueuedActions) {
        _queuedActions.removeFirst();
        emit dropped(QStringLiteral("offline_queue_full"));
    }
    _queuedActions.append(json);
}

void FleetLinkWorker::_open()
{
    if (!_running) {
        return;
    }
    // Each attempt is judged on its own errors, so an old 401 cannot mislabel a later failure.
    _error.clear();
    if (_socket) {
        _socket->disconnect(this);
        _socket->abort();
        _socket->deleteLater();
    }
    _socket = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);
    _socket->setMaxAllowedIncomingMessageSize(kMaxIncomingMessage);
    connect(_socket, &QWebSocket::connected, this, &FleetLinkWorker::_onConnected);
    connect(_socket, &QWebSocket::textMessageReceived, this, &FleetLinkWorker::_onTextMessage);
    connect(_socket, &QWebSocket::disconnected, this, &FleetLinkWorker::_onSocketGone);
    connect(_socket, &QWebSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        if (_socket) {
            _error = _socket->errorString();
            if (_socket->state() == QAbstractSocket::UnconnectedState) {
                _onSocketGone();
            }
        }
    });
    connect(_socket, &QWebSocket::sslErrors, this, [this](const QList<QSslError> &errors) {
        // Never ignored: a certificate we do not trust means we do not connect.
        QStringList text;
        for (const QSslError &e : errors) {
            text.append(e.errorString());
        }
        _error = QStringLiteral("TLS: ") + text.join(QStringLiteral("; "));
    });

    if (_config.url.scheme() == QLatin1String("wss") && !_config.caFile.isEmpty()) {
        const QList<QSslCertificate> ca = QSslCertificate::fromPath(_config.caFile, QSsl::Pem);
        if (ca.isEmpty()) {
            _error = QStringLiteral("cannot read CA certificate from Fleet/caFile");
            _scheduleReconnect();
            return;
        }
        QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
        ssl.addCaCertificates(ca);
        _socket->setSslConfiguration(ssl);
    }

    QNetworkRequest request(_config.url);
    request.setRawHeader("Authorization", "Bearer " + _config.token.toUtf8());
    _haveSnapshot = false;
    _sinceLastMessage.start();
    _setState(Connecting);
    qCDebug(FleetLinkLog) << "connecting to" << describe(_config.url) << "attempt" << _backoff.attempt() + 1;
    _socket->open(request);
}

void FleetLinkWorker::_onConnected()
{
    const QString operatorId = FleetProtocol::sanitizeId(_config.operatorId);
    const QJsonObject hello = FleetProtocol::makeMessage(
        QStringLiteral("hello"), QStringLiteral("qgc-") + operatorId,
        QJsonObject{
            {QStringLiteral("operator_id"), operatorId},
            {QStringLiteral("client"), QStringLiteral("qgc")},
            {QStringLiteral("client_version"), _config.clientVersion.left(64)},
        });
    _socket->sendTextMessage(QString::fromUtf8(QJsonDocument(hello).toJson(QJsonDocument::Compact)));
    _sinceLastMessage.start();
    qCDebug(FleetLinkLog) << "connected, hello sent as" << operatorId;
}

void FleetLinkWorker::_onTextMessage(const QString &text)
{
    _sinceLastMessage.start();
    const FleetProtocol::ParseResult parsed = FleetProtocol::parse(text.toUtf8());
    if (!parsed.error.isEmpty()) {
        emit dropped(parsed.error);
        return;
    }

    const QJsonObject &message = parsed.message;
    if (message.value(QLatin1String("type")).toString() == QLatin1String("snapshot")) {
        // A snapshot replaces everything; nothing queued before it still matters.
        _batcher.clear();
        _haveSnapshot = true;
        _backoff.reset();
        _error.clear();
        _setState(Connected);
        emit snapshotReceived(message.value(QLatin1String("data")).toObject());
        for (const QByteArray &json : std::as_const(_queuedActions)) {
            _socket->sendTextMessage(QString::fromUtf8(json));
        }
        _queuedActions.clear();
        return;
    }
    if (!_haveSnapshot) {
        emit dropped(QStringLiteral("before_snapshot"));
        return;
    }
    _batcher.add(message);
}

void FleetLinkWorker::_onTick()
{
    _flushBatch();
    if (_socket && (_state == Connecting || _state == Connected)
        && _sinceLastMessage.elapsed() > _config.silenceTimeoutMs) {
        _error = QStringLiteral("nothing heard from the coordinator for %1 s").arg(_config.silenceTimeoutMs / 1000.0);
        qCWarning(FleetLinkLog) << _error;
        _socket->abort();   // disconnected() follows and schedules the reconnect
    }
}

void FleetLinkWorker::_onSocketGone()
{
    if (!_running || _reconnectTimer.isActive()) {
        return;
    }
    if (_socket && static_cast<int>(_socket->closeCode()) == kCloseBadHello) {
        qCCritical(FleetLinkLog) << "the coordinator refused our hello: this is a FleetLink bug";
    }
    if (_socket && !_socket->closeReason().isEmpty() && _error.isEmpty()) {
        _error = _socket->closeReason();
    }
    _scheduleReconnect();
}

void FleetLinkWorker::_scheduleReconnect()
{
    _flushBatch();
    _haveSnapshot = false;
    // QWebSocket reports a refused handshake only as text: "... status code: 401 (Unauthorized)" when
    // the 401 has no challenge, "Unsupported WWW-Authenticate challenge" when it asks for a Bearer token
    // (the coordinator does). Either way the token was refused.
    const bool unauthorized = _error.contains(QLatin1String("401")) || _error.contains(QLatin1String("WWW-Authenticate"));
    if (unauthorized) {
        _error = QStringLiteral("operator token refused (HTTP 401)");
    }
    const int delay = unauthorized ? _backoff.maxDelayMs() : _backoff.nextDelayMs();
    if (_error.isEmpty() && _socket && _socket->error() != QAbstractSocket::UnknownSocketError) {
        _error = _socket->errorString();
    }
    if (_error.isEmpty()) {
        _error = QStringLiteral("connection closed");
    }
    qCInfo(FleetLinkLog) << "link down:" << _error << "- retrying in" << delay << "ms";
    _setState(unauthorized ? Unauthorized : Retrying, delay);
    _reconnectTimer.start(delay);
}

void FleetLinkWorker::_flushBatch()
{
    if (!_batcher.isEmpty()) {
        emit batchReceived(_batcher.take());
    }
}

void FleetLinkWorker::_setState(State state, int retryDelayMs)
{
    _state = state;
    emit stateChanged(state, retryDelayMs, _backoff.attempt(), _error);
}
