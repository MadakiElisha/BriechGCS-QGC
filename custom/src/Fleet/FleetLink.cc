#include "FleetLink.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QLoggingCategory>
#include <QtCore/QSettings>
#include <QtCore/QTime>

Q_DECLARE_LOGGING_CATEGORY(FleetLinkLog)

namespace {

constexpr auto kEnabledKey = "Fleet/enabled";
constexpr auto kUrlKey = "Fleet/url";
constexpr auto kTokenKey = "Fleet/token";
constexpr auto kOperatorIdKey = "Fleet/operatorId";
constexpr auto kCaFileKey = "Fleet/caFile";
constexpr auto kDefaultUrl = "wss://localhost:8443/ws/v1/operator";
constexpr auto kDefaultOperatorId = "op-local";
constexpr int kRecentMax = 50;

QString timeOfDay()
{
    return QTime::currentTime().toString(QStringLiteral("hh:mm:ss.zzz"));
}

} // namespace

FleetLink::FleetLink(QObject *parent)
    : QObject(parent)
    , _tick(this)
{
    _tick.setInterval(1000);
    connect(&_tick, &QTimer::timeout, this, &FleetLink::_onTick);
}

FleetLink::~FleetLink()
{
    _stopThread();
}

FleetLinkConfig FleetLink::configFromSettings()
{
    const QSettings settings;
    FleetLinkConfig config;
    config.url = QUrl(settings.value(QString::fromLatin1(kUrlKey), QString::fromLatin1(kDefaultUrl)).toString());
    config.token = settings.value(QString::fromLatin1(kTokenKey)).toString().trimmed();
    config.operatorId = settings.value(QString::fromLatin1(kOperatorIdKey), QString::fromLatin1(kDefaultOperatorId)).toString();
    config.caFile = settings.value(QString::fromLatin1(kCaFileKey)).toString();
    config.clientVersion = QCoreApplication::applicationVersion();
    return config;
}

void FleetLink::start()
{
    if (!QSettings().value(QString::fromLatin1(kEnabledKey), false).toBool()) {
        return;
    }
    startWith(configFromSettings());
}

void FleetLink::startWith(const FleetLinkConfig &config)
{
    if (!_worker) {
        _worker = new FleetLinkWorker;
        _worker->moveToThread(&_thread);
        connect(&_thread, &QThread::finished, _worker, &QObject::deleteLater);
        connect(_worker, &FleetLinkWorker::stateChanged, this, &FleetLink::_onWorkerState);
        connect(_worker, &FleetLinkWorker::snapshotReceived, this, &FleetLink::_onSnapshot);
        connect(_worker, &FleetLinkWorker::batchReceived, this, &FleetLink::_onBatch);
        connect(_worker, &FleetLinkWorker::dropped, this, &FleetLink::_onDropped);
        _thread.setObjectName(QStringLiteral("FleetLink"));
        _thread.start();
    }

    _operatorId = FleetProtocol::sanitizeId(config.operatorId);
    _silenceTimeoutMs = config.silenceTimeoutMs;
    _running = true;
    _sinceHeard.start();
    _tick.start();
    QMetaObject::invokeMethod(_worker, [worker = _worker, config] { worker->start(config); }, Qt::QueuedConnection);
}

void FleetLink::stop()
{
    _stopThread();
    _running = false;
    _tick.stop();
    if (_silent) {
        _silent = false;
        emit silentChanged();
    }
    _retryDelayMs = 0;
    _lastError.clear();
    if (_state != Disabled) {
        _state = Disabled;
        emit stateChanged();
    }
}

void FleetLink::_stopThread()
{
    if (!_worker) {
        return;
    }
    // Close the socket on its own thread, then let the thread delete the worker.
    QMetaObject::invokeMethod(_worker, [worker = _worker] { worker->stop(); }, Qt::BlockingQueuedConnection);
    _worker->disconnect(this);
    _thread.quit();
    _thread.wait();
    _worker = nullptr;
}

void FleetLink::sendMessage(const QString &type, const QJsonObject &data)
{
    if (!FleetProtocol::outgoingTypes().contains(type)) {
        qCWarning(FleetLinkLog) << "not a message QGC sends:" << type;
        return;
    }
    if (!_worker) {
        _onDropped(QStringLiteral("not_started"));
        return;
    }
    const QJsonObject message = FleetProtocol::makeMessage(type, QStringLiteral("qgc-") + _operatorId, data);
    const QByteArray json = QJsonDocument(message).toJson(QJsonDocument::Compact);
    const bool keep = type == QLatin1String("operator.action");
    QMetaObject::invokeMethod(_worker, [worker = _worker, json, keep] { worker->send(json, keep); }, Qt::QueuedConnection);
}

QString FleetLink::stateText() const
{
    switch (_state) {
    case Disabled:
        return QStringLiteral("DISABLED");
    case Connecting:
        return QStringLiteral("CONNECTING");
    case Connected:
        return QStringLiteral("CONNECTED");
    case Retrying:
        return QStringLiteral("RETRYING IN %1 S").arg(retryInSeconds());
    case Unauthorized:
        return QStringLiteral("UNAUTHORIZED");
    }
    return QString();
}

int FleetLink::retryInSeconds() const
{
    if (_state != Retrying && _state != Unauthorized) {
        return 0;
    }
    const qint64 left = _retryDelayMs - _retryClock.elapsed();
    return left > 0 ? static_cast<int>((left + 999) / 1000) : 0;
}

void FleetLink::_onWorkerState(int state, int retryDelayMs, int attempt, const QString &error)
{
    _state = static_cast<State>(state);
    _retryDelayMs = retryDelayMs;
    _retryAttempt = attempt;
    _retryClock.start();
    // Connecting starts with no error yet; keep showing why the last attempt failed.
    if (_state == Connected || _state == Disabled || !error.isEmpty()) {
        _lastError = error;
    }
    emit stateChanged();
}

void FleetLink::_onSnapshot(const QJsonObject &data)
{
    _markHeard();
    _remember(QStringLiteral("%1 snapshot %2 assets, %3 vehicles, %4 objects, %5 alerts")
                  .arg(timeOfDay())
                  .arg(data.value(QLatin1String("assets")).toArray().size())
                  .arg(data.value(QLatin1String("vehicles")).toArray().size())
                  .arg(data.value(QLatin1String("objects")).toArray().size())
                  .arg(data.value(QLatin1String("alerts")).toArray().size()));
    emit recentMessagesChanged();
    emit snapshotReceived(data);
}

void FleetLink::_onBatch(const QList<QJsonObject> &messages)
{
    _markHeard();
    const QString now = timeOfDay();
    for (const QJsonObject &message : messages) {
        const QString key = FleetProtocol::coalesceKey(message);
        _remember(now + QLatin1Char(' ') + key.section(QLatin1Char('|'), 0, 0) + QLatin1Char(' ')
                  + key.section(QLatin1Char('|'), 1));
    }
    emit recentMessagesChanged();
    emit batchReceived(messages);
}

void FleetLink::_onDropped(const QString &reason)
{
    ++_droppedCount;
    qCDebug(FleetLinkLog) << "dropped a message:" << reason;
    emit droppedCountChanged();
}

void FleetLink::_onTick()
{
    const bool silent = _running && _sinceHeard.elapsed() > _silenceTimeoutMs;
    if (silent != _silent) {
        _silent = silent;
        emit silentChanged();
    }
    if (_state == Retrying || _state == Unauthorized) {
        emit stateChanged();    // the countdown in retryInSeconds and stateText moved
    }
}

void FleetLink::_markHeard()
{
    _sinceHeard.start();
    if (_silent) {
        _silent = false;
        emit silentChanged();
    }
}

void FleetLink::_remember(const QString &line)
{
    _recent.prepend(line.trimmed());
    while (_recent.size() > kRecentMax) {
        _recent.removeLast();
    }
}
