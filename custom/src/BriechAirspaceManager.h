#pragma once

#include <QtCore/QJsonArray>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonValue>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QUrl>
#include <QtCore/QVariantMap>
#include <QtCore/QVariantList>
#include <QtNetwork/QNetworkReply>

class QNetworkAccessManager;

class BriechAirspaceManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString apiKey READ apiKey WRITE setApiKey NOTIFY apiKeyChanged)
    Q_PROPERTY(QString apiKeyHeader READ apiKeyHeader WRITE setApiKeyHeader NOTIFY apiKeyHeaderChanged)
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl WRITE setSourceUrl NOTIFY sourceUrlChanged)
    Q_PROPERTY(QVariantList zones READ zones NOTIFY zonesChanged)
    Q_PROPERTY(QVariantList weatherAlerts READ weatherAlerts NOTIFY weatherAlertsChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(int minRequestIntervalMs READ minRequestIntervalMs WRITE setMinRequestIntervalMs NOTIFY minRequestIntervalMsChanged)
    Q_PROPERTY(int rateLimitCooldownMs READ rateLimitCooldownMs WRITE setRateLimitCooldownMs NOTIFY rateLimitCooldownMsChanged)
    Q_PROPERTY(bool hasData READ hasData NOTIFY hasDataChanged)

public:
    explicit BriechAirspaceManager(QObject *parent = nullptr);

    QString apiKey() const { return _apiKey; }
    void setApiKey(const QString &apiKey);

    QString apiKeyHeader() const { return _apiKeyHeader; }
    void setApiKeyHeader(const QString &apiKeyHeader);

    QUrl sourceUrl() const { return _sourceUrl; }
    void setSourceUrl(const QUrl &sourceUrl);

    QVariantList zones() const { return _zones; }
    QVariantList weatherAlerts() const { return _weatherAlerts; }
    QString status() const { return _status; }
    QString lastError() const { return _lastError; }

    int minRequestIntervalMs() const { return _minRequestIntervalMs; }
    void setMinRequestIntervalMs(int minRequestIntervalMs);

    int rateLimitCooldownMs() const { return _rateLimitCooldownMs; }
    void setRateLimitCooldownMs(int rateLimitCooldownMs);

    bool hasData() const { return !_zones.isEmpty() || !_weatherAlerts.isEmpty(); }

    Q_INVOKABLE void loadFromUrl(const QUrl &url);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void clear();

signals:
    void apiKeyChanged();
    void apiKeyHeaderChanged();
    void sourceUrlChanged();
    void zonesChanged(const QVariantList &zones);
    void weatherAlertsChanged(const QVariantList &weatherAlerts);
    void hasDataChanged();
    void statusChanged();
    void lastErrorChanged();
    void minRequestIntervalMsChanged();
    void rateLimitCooldownMsChanged();
    void refreshed();
    void failed(const QString &message);
    void deferred(int delayMs);

private slots:
    void _replyFinished();

private:
    void _setStatus(const QString &status);
    void _setLastError(const QString &error);
    void _setZones(const QVariantList &zones);
    void _setWeatherAlerts(const QVariantList &weatherAlerts);
    void _fail(const QString &message);
    void _applyPayload(const QJsonDocument &document);

    QVariantList _firstArrayPayload(const QJsonValue &value) const;
    QVariantMap _normalizeFeature(const QJsonObject &feature, int index) const;
    QVariantMap _normalizeZone(const QJsonObject &zone, int index) const;
    QVariantMap _normalizeAlert(const QJsonObject &alert, int index) const;
    QVariantMap _pointFromZone(const QJsonObject &zone) const;
    QVariantList _circlePath(const QVariantMap &center, double radiusMeters) const;
    QVariantList _pathFromGeometry(const QJsonObject &geometry) const;
    QVariantList _pathFromValue(const QJsonValue &value) const;
    QVariantMap _coordinateFromValue(const QJsonValue &value) const;
    QString _classifiedZoneKind(const QString &value) const;

    QNetworkAccessManager *_networkManager = nullptr;
    QPointer<QNetworkReply> _reply;
    QUrl _sourceUrl;
    QString _apiKey;
    QString _apiKeyHeader = QStringLiteral("x-openaip-api-key");
    QVariantList _zones;
    QVariantList _weatherAlerts;
    QString _status = QStringLiteral("idle");
    QString _lastError;
    int _minRequestIntervalMs = 20000;
    int _rateLimitCooldownMs = 120000;
    qint64 _lastRequestMs = 0;
    qint64 _cooldownUntilMs = 0;
};
