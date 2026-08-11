#include "BriechAirspaceManager.h"

#include "QGCNetworkHelper.h"

#include <QtCore/QDateTime>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonParseError>
#include <QtCore/QtMath>
#include <QtCore/QUrlQuery>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslConfiguration>

namespace {
constexpr int kMaxErrorBytes = 160;

QString stringFromJson(const QJsonObject &object, std::initializer_list<const char*> keys, const QString &fallback = {})
{
    for (const char *key : keys) {
        const QJsonValue value = object.value(QLatin1String(key));
        if (value.isString() && !value.toString().isEmpty()) {
            return value.toString();
        }
        if (value.isDouble()) {
            return QString::number(value.toDouble());
        }
    }
    return fallback;
}

bool boolFromJson(const QJsonObject &object, std::initializer_list<const char*> keys, bool fallback = true)
{
    for (const char *key : keys) {
        const QJsonValue value = object.value(QLatin1String(key));
        if (value.isBool()) {
            return value.toBool();
        }
    }
    return fallback;
}

double doubleFromJson(const QJsonObject &object, std::initializer_list<const char*> keys, double fallback = 0)
{
    for (const char *key : keys) {
        const QJsonValue value = object.value(QLatin1String(key));
        if (value.isDouble()) {
            return value.toDouble();
        }
    }
    return fallback;
}
}

BriechAirspaceManager::BriechAirspaceManager(QObject *parent)
    : QObject(parent)
    , _networkManager(QGCNetworkHelper::createNetworkManager(this))
{
}

void BriechAirspaceManager::setApiKey(const QString &apiKey)
{
    if (_apiKey == apiKey) {
        return;
    }
    _apiKey = apiKey.trimmed();
    emit apiKeyChanged();
}

void BriechAirspaceManager::setApiKeyHeader(const QString &apiKeyHeader)
{
    if (_apiKeyHeader == apiKeyHeader) {
        return;
    }
    _apiKeyHeader = apiKeyHeader.trimmed();
    emit apiKeyHeaderChanged();
}

void BriechAirspaceManager::setSourceUrl(const QUrl &sourceUrl)
{
    if (_sourceUrl == sourceUrl) {
        return;
    }
    _sourceUrl = sourceUrl;
    emit sourceUrlChanged();
}

void BriechAirspaceManager::setMinRequestIntervalMs(int minRequestIntervalMs)
{
    const int value = qMax(0, minRequestIntervalMs);
    if (_minRequestIntervalMs == value) {
        return;
    }
    _minRequestIntervalMs = value;
    emit minRequestIntervalMsChanged();
}

void BriechAirspaceManager::setRateLimitCooldownMs(int rateLimitCooldownMs)
{
    const int value = qMax(1000, rateLimitCooldownMs);
    if (_rateLimitCooldownMs == value) {
        return;
    }
    _rateLimitCooldownMs = value;
    emit rateLimitCooldownMsChanged();
}

void BriechAirspaceManager::loadFromUrl(const QUrl &url)
{
    setSourceUrl(url);
    refresh();
}

void BriechAirspaceManager::refresh()
{
    if (!_sourceUrl.isValid() || _sourceUrl.isEmpty()) {
        _setStatus(QStringLiteral("idle"));
        _setZones({});
        _setWeatherAlerts({});
        return;
    }

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (_cooldownUntilMs > now) {
        const int delayMs = static_cast<int>(qMax<qint64>(1000, _cooldownUntilMs - now));
        _setStatus(QStringLiteral("error"));
        _setLastError(tr("Risk data rate limited. Cooling down for %1s").arg(qCeil(delayMs / 1000.0)));
        emit deferred(delayMs);
        return;
    }

    const qint64 elapsed = now - _lastRequestMs;
    if (_lastRequestMs > 0 && elapsed < _minRequestIntervalMs) {
        emit deferred(static_cast<int>(qMax<qint64>(1000, _minRequestIntervalMs - elapsed)));
        return;
    }

    if (_reply) {
        _reply->abort();
        _reply->deleteLater();
        _reply = nullptr;
    }

    QUrl requestUrl = _sourceUrl;
    if (!_apiKey.isEmpty()) {
        QUrlQuery query(requestUrl);
        if (!query.hasQueryItem(QStringLiteral("apiKey"))) {
            query.addQueryItem(QStringLiteral("apiKey"), _apiKey);
            requestUrl.setQuery(query);
        }
    }

    QNetworkRequest request(requestUrl);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("BriechUAS/QGroundControl"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("Accept-Encoding", "identity");
    if (!_apiKey.isEmpty() && !_apiKeyHeader.isEmpty()) {
        request.setRawHeader(_apiKeyHeader.toUtf8(), _apiKey.toUtf8());
    }
    QGCNetworkHelper::applySslConfig(request, QGCNetworkHelper::createSslConfig());

    _lastRequestMs = now;
    _setStatus(QStringLiteral("loading"));
    _setZones({});
    _setWeatherAlerts({});

    _reply = _networkManager->get(request);
    QGCNetworkHelper::ignoreSslErrorsIfNeeded(_reply);
    connect(_reply, &QNetworkReply::finished, this, &BriechAirspaceManager::_replyFinished);
}

void BriechAirspaceManager::clear()
{
    if (_reply) {
        _reply->abort();
        _reply->deleteLater();
        _reply = nullptr;
    }
    _setStatus(QStringLiteral("idle"));
    _setLastError({});
    _setZones({});
    _setWeatherAlerts({});
}

void BriechAirspaceManager::_replyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        return;
    }
    reply->deleteLater();
    if (_reply == reply) {
        _reply = nullptr;
    }

    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray body = reply->readAll();

    if (reply->error() != QNetworkReply::NoError || (httpStatus > 0 && (httpStatus < 200 || httpStatus >= 300))) {
        QString responseMessage;
        QJsonParseError parseError;
        const QJsonDocument errorDoc = QJsonDocument::fromJson(body, &parseError);
        if (parseError.error == QJsonParseError::NoError && errorDoc.isObject()) {
            const QJsonObject object = errorDoc.object();
            responseMessage = stringFromJson(object, {"message", "error", "detail"});
        }
        if (responseMessage.isEmpty() && !body.isEmpty()) {
            responseMessage = QString::fromUtf8(body.left(kMaxErrorBytes)).simplified();
        }
        if (responseMessage.isEmpty()) {
            responseMessage = reply->errorString();
        }

        if (httpStatus == 429) {
            _cooldownUntilMs = QDateTime::currentMSecsSinceEpoch() + _rateLimitCooldownMs;
            const QString message = tr("Risk data request failed: HTTP 429 - provider rate limit. Waiting %1s before retry.")
                .arg(qCeil(_rateLimitCooldownMs / 1000.0));
            _fail(message);
            emit deferred(_rateLimitCooldownMs);
        } else if (httpStatus > 0) {
            _fail(tr("Risk data request failed: HTTP %1%2").arg(httpStatus).arg(responseMessage.isEmpty() ? QString() : QStringLiteral(" - ") + responseMessage));
        } else {
            _fail(tr("Risk data request failed: %1").arg(responseMessage));
        }
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        _fail(tr("Risk data parse failed: %1").arg(parseError.errorString()));
        return;
    }

    _applyPayload(document);
}

void BriechAirspaceManager::_setStatus(const QString &status)
{
    if (_status == status) {
        return;
    }
    _status = status;
    emit statusChanged();
}

void BriechAirspaceManager::_setLastError(const QString &error)
{
    if (_lastError == error) {
        return;
    }
    _lastError = error;
    emit lastErrorChanged();
}

void BriechAirspaceManager::_setZones(const QVariantList &zones)
{
    const bool hadData = hasData();
    _zones = zones;
    emit zonesChanged(_zones);
    if (hadData != hasData()) {
        emit hasDataChanged();
    }
}

void BriechAirspaceManager::_setWeatherAlerts(const QVariantList &weatherAlerts)
{
    const bool hadData = hasData();
    _weatherAlerts = weatherAlerts;
    emit weatherAlertsChanged(_weatherAlerts);
    if (hadData != hasData()) {
        emit hasDataChanged();
    }
}

void BriechAirspaceManager::_fail(const QString &message)
{
    _setStatus(QStringLiteral("error"));
    _setLastError(message);
    emit failed(message);
}

void BriechAirspaceManager::_applyPayload(const QJsonDocument &document)
{
    const QJsonValue rootValue = document.isArray() ? QJsonValue(document.array()) : QJsonValue(document.object());
    const QVariantList source = _firstArrayPayload(rootValue);
    QVariantList nextZones;

    for (int i = 0; i < source.count(); ++i) {
        const QJsonValue value = QJsonValue::fromVariant(source.at(i));
        if (!value.isObject()) {
            continue;
        }
        const QJsonObject object = value.toObject();
        const QVariantMap zone = object.value(QStringLiteral("type")).toString() == QStringLiteral("Feature")
            ? _normalizeFeature(object, i)
            : _normalizeZone(object, i);
        const QVariant activeValue = zone.value(QStringLiteral("active"));
        const bool active = !activeValue.isValid() || activeValue.toBool();
        if (!zone.isEmpty() && active && zone.value(QStringLiteral("path")).toList().count() >= 3) {
            nextZones.append(zone);
        }
    }

    _setZones(nextZones);
    _setWeatherAlerts({});
    _setStatus(QStringLiteral("ready"));
    _setLastError({});
    emit refreshed();
}

QVariantList BriechAirspaceManager::_firstArrayPayload(const QJsonValue &value) const
{
    if (value.isArray()) {
        return value.toArray().toVariantList();
    }
    if (!value.isObject()) {
        return {};
    }

    const QJsonObject object = value.toObject();
    if (object.value(QStringLiteral("type")).toString() == QStringLiteral("FeatureCollection") && object.value(QStringLiteral("features")).isArray()) {
        return object.value(QStringLiteral("features")).toArray().toVariantList();
    }

    const QStringList keys = {
        QStringLiteral("riskZones"), QStringLiteral("zones"), QStringLiteral("airspace"), QStringLiteral("airspaces"),
        QStringLiteral("items"), QStringLiteral("data"), QStringLiteral("results"), QStringLiteral("features")
    };
    for (const QString &key : keys) {
        const QJsonValue child = object.value(key);
        if (child.isArray()) {
            return child.toArray().toVariantList();
        }
        const QVariantList nested = _firstArrayPayload(child);
        if (!nested.isEmpty()) {
            return nested;
        }
    }
    return {};
}

QVariantMap BriechAirspaceManager::_normalizeFeature(const QJsonObject &feature, int index) const
{
    const QJsonObject properties = feature.value(QStringLiteral("properties")).toObject();
    QJsonObject zone = properties;
    zone.insert(QStringLiteral("id"), feature.value(QStringLiteral("id")));
    zone.insert(QStringLiteral("source"), QStringLiteral("geojson"));
    zone.insert(QStringLiteral("geometry"), feature.value(QStringLiteral("geometry")));
    return _normalizeZone(zone, index);
}

QVariantMap BriechAirspaceManager::_normalizeZone(const QJsonObject &zone, int index) const
{
    const QString rawKind = stringFromJson(zone, {"kind", "type", "category", "airspaceType", "class", "icaoClass"}, QStringLiteral("airspace"));
    const QVariantList path = _pathFromValue(zone.value(QStringLiteral("path")));
    QVariantList finalPath = path;
    if (finalPath.count() < 3) {
        finalPath = _pathFromValue(zone.value(QStringLiteral("coordinates")));
    }
    if (finalPath.count() < 3) {
        finalPath = _pathFromValue(zone.value(QStringLiteral("polygon")));
    }
    if (finalPath.count() < 3) {
        finalPath = _pathFromGeometry(zone.value(QStringLiteral("geometry")).toObject());
    }

    const QVariantMap point = finalPath.count() < 3 ? _pointFromZone(zone) : QVariantMap();
    const bool pointDerivedZone = finalPath.count() < 3 && !point.isEmpty();
    if (pointDerivedZone) {
        const double radiusMeters = qBound(500.0, doubleFromJson(zone, {"riskRadiusMeters", "radiusMeters", "bufferMeters"}, 5000.0), 20000.0);
        finalPath = _circlePath(point, radiusMeters);
    }

    QVariantMap result;
    const QString code = stringFromJson(zone, {"icaoCode", "icao", "ident", "designator"});
    const QString name = stringFromJson(zone, {"label", "name", "title", "designator"}, code);
    result.insert(QStringLiteral("id"), stringFromJson(zone, {"id", "uuid"}, QStringLiteral("zone-%1").arg(index)));
    result.insert(QStringLiteral("kind"), pointDerivedZone ? QStringLiteral("advisory") : _classifiedZoneKind(rawKind));
    result.insert(QStringLiteral("label"), pointDerivedZone ? (code.isEmpty() ? name : QStringLiteral("%1 ADVISORY").arg(code)) : name);
    result.insert(QStringLiteral("active"), boolFromJson(zone, {"active", "enabled"}, true));
    result.insert(QStringLiteral("path"), finalPath);
    result.insert(QStringLiteral("center"), pointDerivedZone ? point : _coordinateFromValue(zone.value(QStringLiteral("center"))));
    result.insert(QStringLiteral("severity"), stringFromJson(zone, {"severity", "level"}, QStringLiteral("advisory")));
    result.insert(QStringLiteral("color"), pointDerivedZone ? QStringLiteral("#3b82f6") : stringFromJson(zone, {"color", "borderColor"}));
    result.insert(QStringLiteral("fillColor"), pointDerivedZone ? QStringLiteral("#183b82f6") : stringFromJson(zone, {"fillColor"}));
    result.insert(QStringLiteral("source"), pointDerivedZone ? QStringLiteral("openaip-airport") : stringFromJson(zone, {"source"}, QStringLiteral("openaip")));
    return result;
}

QVariantMap BriechAirspaceManager::_normalizeAlert(const QJsonObject &alert, int index) const
{
    QVariantMap result;
    result.insert(QStringLiteral("id"), stringFromJson(alert, {"id", "uuid"}, QStringLiteral("alert-%1").arg(index)));
    result.insert(QStringLiteral("type"), stringFromJson(alert, {"type", "category"}));
    result.insert(QStringLiteral("label"), stringFromJson(alert, {"label", "title"}));
    result.insert(QStringLiteral("message"), stringFromJson(alert, {"message", "description"}));
    result.insert(QStringLiteral("active"), boolFromJson(alert, {"active", "enabled"}, true));
    result.insert(QStringLiteral("severity"), stringFromJson(alert, {"severity", "level"}, QStringLiteral("info")));
    result.insert(QStringLiteral("source"), stringFromJson(alert, {"source"}, QStringLiteral("risk-data")));
    return result;
}

QVariantList BriechAirspaceManager::_pathFromGeometry(const QJsonObject &geometry) const
{
    if (geometry.isEmpty()) {
        return {};
    }
    return _pathFromValue(geometry.value(QStringLiteral("coordinates")));
}

QVariantMap BriechAirspaceManager::_pointFromZone(const QJsonObject &zone) const
{
    const QStringList coordinateKeys = {
        QStringLiteral("center"), QStringLiteral("coordinate"), QStringLiteral("position"), QStringLiteral("location"), QStringLiteral("coordinates")
    };
    for (const QString &key : coordinateKeys) {
        const QVariantMap coordinate = _coordinateFromValue(zone.value(key));
        if (coordinate.contains(QStringLiteral("lat")) && coordinate.contains(QStringLiteral("lon"))) {
            return coordinate;
        }
    }

    const QJsonObject geometry = zone.value(QStringLiteral("geometry")).toObject();
    if (!geometry.isEmpty()) {
        const QVariantMap coordinate = _coordinateFromValue(geometry.value(QStringLiteral("coordinates")));
        if (coordinate.contains(QStringLiteral("lat")) && coordinate.contains(QStringLiteral("lon"))) {
            return coordinate;
        }
    }

    return {};
}

QVariantList BriechAirspaceManager::_circlePath(const QVariantMap &center, double radiusMeters) const
{
    QVariantList path;
    const double latitude = center.value(QStringLiteral("lat")).toDouble();
    const double longitude = center.value(QStringLiteral("lon")).toDouble();
    if (qAbs(latitude) > 90 || qAbs(longitude) > 180 || radiusMeters <= 0) {
        return path;
    }

    constexpr int segments = 48;
    constexpr double earthRadiusMeters = 6378137.0;
    const double angularDistance = radiusMeters / earthRadiusMeters;
    const double lat1 = qDegreesToRadians(latitude);
    const double lon1 = qDegreesToRadians(longitude);

    constexpr double twoPi = 6.28318530717958647692;
    for (int i = 0; i <= segments; ++i) {
        const double bearing = twoPi * i / segments;
        const double lat2 = qAsin(qSin(lat1) * qCos(angularDistance) + qCos(lat1) * qSin(angularDistance) * qCos(bearing));
        const double lon2 = lon1 + qAtan2(qSin(bearing) * qSin(angularDistance) * qCos(lat1),
                                          qCos(angularDistance) - qSin(lat1) * qSin(lat2));

        QVariantMap coordinate;
        coordinate.insert(QStringLiteral("lat"), qRadiansToDegrees(lat2));
        coordinate.insert(QStringLiteral("lon"), qRadiansToDegrees(lon2));
        coordinate.insert(QStringLiteral("alt"), center.value(QStringLiteral("alt"), 0));
        path.append(coordinate);
    }

    return path;
}

QVariantList BriechAirspaceManager::_pathFromValue(const QJsonValue &value) const
{
    QVariantList path;
    if (!value.isArray()) {
        return path;
    }

    QJsonArray array = value.toArray();
    while (!array.isEmpty() && array.first().isArray()) {
        const QJsonArray first = array.first().toArray();
        if (!first.isEmpty() && first.first().isDouble()) {
            break;
        }
        array = first;
    }

    for (const QJsonValue &coordinateValue : array) {
        const QVariantMap coordinate = _coordinateFromValue(coordinateValue);
        if (coordinate.contains(QStringLiteral("lat")) && coordinate.contains(QStringLiteral("lon"))) {
            path.append(coordinate);
        }
    }
    return path;
}

QVariantMap BriechAirspaceManager::_coordinateFromValue(const QJsonValue &value) const
{
    QVariantMap coordinate;
    if (value.isObject()) {
        const QJsonObject object = value.toObject();
        const QJsonValue latitude = object.value(QStringLiteral("latitude")).isUndefined() ? object.value(QStringLiteral("lat")) : object.value(QStringLiteral("latitude"));
        const QJsonValue longitude = object.value(QStringLiteral("longitude")).isUndefined() ? object.value(QStringLiteral("lon")) : object.value(QStringLiteral("longitude"));
        if (latitude.isDouble() && longitude.isDouble()) {
            coordinate.insert(QStringLiteral("lat"), latitude.toDouble());
            coordinate.insert(QStringLiteral("lon"), longitude.toDouble());
            coordinate.insert(QStringLiteral("alt"), object.value(QStringLiteral("altitude")).toDouble(object.value(QStringLiteral("alt")).toDouble(0)));
        }
        return coordinate;
    }

    if (value.isArray()) {
        const QJsonArray array = value.toArray();
        if (array.count() >= 2 && array.at(0).isDouble() && array.at(1).isDouble()) {
            coordinate.insert(QStringLiteral("lat"), array.at(1).toDouble());
            coordinate.insert(QStringLiteral("lon"), array.at(0).toDouble());
            coordinate.insert(QStringLiteral("alt"), array.count() > 2 ? array.at(2).toDouble() : 0);
        }
    }
    return coordinate;
}

QString BriechAirspaceManager::_classifiedZoneKind(const QString &value) const
{
    const QString key = value.toLower();
    if (key.contains(QStringLiteral("nfz")) || key.contains(QStringLiteral("no-fly")) || key.contains(QStringLiteral("nofly")) || key.contains(QStringLiteral("prohibited")) || key.contains(QStringLiteral("danger"))) {
        return QStringLiteral("nfz");
    }
    if (key.contains(QStringLiteral("restricted")) || key == QStringLiteral("r") || key.contains(QStringLiteral("temporary")) || key.contains(QStringLiteral("military"))) {
        return QStringLiteral("restricted");
    }
    if (key.contains(QStringLiteral("radar")) || key.contains(QStringLiteral("radio")) || key.contains(QStringLiteral("transponder"))) {
        return QStringLiteral("radar");
    }
    if (key.contains(QStringLiteral("advisory")) || key.contains(QStringLiteral("airspace")) || key.contains(QStringLiteral("control")) || key.contains(QStringLiteral("ctr")) || key.contains(QStringLiteral("tmz")) || key.contains(QStringLiteral("rmz"))) {
        return QStringLiteral("advisory");
    }
    return key.isEmpty() ? QStringLiteral("advisory") : key;
}
