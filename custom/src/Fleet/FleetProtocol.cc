#include "FleetProtocol.h"

#include <QtCore/QDateTime>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonParseError>
#include <QtCore/QRandomGenerator>
#include <QtCore/QUuid>

namespace {

constexpr int kBaseDelayMs = 1000;
constexpr int kMaxDelayMs = 30000;
constexpr double kJitter = 0.2;

/// The data field each keyed type is about.
QString keyField(const QString &type)
{
    if (type == QLatin1String("object.update")) {
        return QStringLiteral("object_id");
    }
    if (type == QLatin1String("asset.state")) {
        return QStringLiteral("asset_id");
    }
    if (type == QLatin1String("alert.new") || type == QLatin1String("alert.update")) {
        return QStringLiteral("alert_id");
    }
    return QString();
}

} // namespace

namespace FleetProtocol {

const QStringList &incomingTypes()
{
    static const QStringList types = {
        QStringLiteral("snapshot"),
        QStringLiteral("asset.state"),
        QStringLiteral("object.update"),
        QStringLiteral("alert.new"),
        QStringLiteral("alert.update"),
        QStringLiteral("heartbeat"),
    };
    return types;
}

const QStringList &outgoingTypes()
{
    static const QStringList types = {
        QStringLiteral("vehicle.state"),
        QStringLiteral("operator.action"),
    };
    return types;
}

ParseResult parse(const QByteArray &frame)
{
    QJsonParseError jsonError;
    const QJsonDocument doc = QJsonDocument::fromJson(frame, &jsonError);
    if (jsonError.error != QJsonParseError::NoError || !doc.isObject()) {
        return {{}, QStringLiteral("json")};
    }

    const QJsonObject message = doc.object();
    if (message.value(QLatin1String("v")).toInt(-1) != kVersion) {
        return {{}, QStringLiteral("version")};
    }

    const QString type = message.value(QLatin1String("type")).toString();
    if (!incomingTypes().contains(type)) {
        return {{}, QStringLiteral("type")};
    }

    const QJsonValue data = message.value(QLatin1String("data"));
    if (!data.isObject()) {
        return {{}, QStringLiteral("shape")};
    }
    const QString field = keyField(type);
    if (!field.isEmpty() && data.toObject().value(field).toString().isEmpty()) {
        return {{}, QStringLiteral("shape")};
    }

    return {message, QString()};
}

QString coalesceKey(const QJsonObject &message)
{
    const QString type = message.value(QLatin1String("type")).toString();
    const QString field = keyField(type);
    if (!field.isEmpty()) {
        return type + QLatin1Char('|') + message.value(QLatin1String("data")).toObject().value(field).toString();
    }
    if (type == QLatin1String("heartbeat")) {
        return type;
    }
    // Unkeyed: never merged with another message.
    return type + QLatin1Char('|') + message.value(QLatin1String("id")).toString();
}

QString utcNowIso()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

QJsonObject makeMessage(const QString &type, const QString &src, const QJsonObject &data)
{
    const QString id = QStringLiteral("%1-%2").arg(src, QUuid::createUuid().toString(QUuid::Id128).left(16));
    return QJsonObject{
        {QStringLiteral("v"), kVersion},
        {QStringLiteral("type"), type},
        {QStringLiteral("id"), id},
        {QStringLiteral("ts"), utcNowIso()},
        {QStringLiteral("src"), src},
        {QStringLiteral("data"), data},
    };
}

QString sanitizeId(const QString &id)
{
    QString out;
    out.reserve(id.size());
    for (const QChar c : id.toLower()) {
        const bool allowed = (c >= QLatin1Char('a') && c <= QLatin1Char('z'))
            || (c >= QLatin1Char('0') && c <= QLatin1Char('9')) || c == QLatin1Char('-');
        out.append(allowed ? c : QLatin1Char('-'));
    }
    while (out.startsWith(QLatin1Char('-'))) {
        out.remove(0, 1);
    }
    return out.left(63);
}

} // namespace FleetProtocol

void FleetBatcher::add(const QJsonObject &message)
{
    const QString key = FleetProtocol::coalesceKey(message);
    if (!_latest.contains(key)) {
        _order.append(key);
    }
    _latest.insert(key, message);
}

QList<QJsonObject> FleetBatcher::take()
{
    QList<QJsonObject> batch;
    batch.reserve(_order.size());
    for (const QString &key : std::as_const(_order)) {
        batch.append(_latest.value(key));
    }
    clear();
    return batch;
}

void FleetBatcher::clear()
{
    _order.clear();
    _latest.clear();
}

FleetBackoff::FleetBackoff(std::function<double()> random)
    : _random(random ? std::move(random) : [] { return QRandomGenerator::global()->generateDouble(); })
{
}

int FleetBackoff::nextDelayMs()
{
    const int base = _attempt >= 5 ? kMaxDelayMs : kBaseDelayMs << _attempt;
    ++_attempt;
    const double factor = 1.0 - kJitter + 2.0 * kJitter * _random();
    return static_cast<int>(base * factor);
}

int FleetBackoff::maxDelayMs() const
{
    return kMaxDelayMs;
}
