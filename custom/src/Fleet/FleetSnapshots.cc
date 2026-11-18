#include "FleetSnapshots.h"

#include <QtCore/QCryptographicHash>
#include <QtCore/QLoggingCategory>
#include <QtCore/QRegularExpression>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslCertificate>
#include <QtNetwork/QSslConfiguration>

Q_LOGGING_CATEGORY(FleetSnapshotsLog, "Briech.FleetSnapshots")

bool FleetSnapshots::validId(const QString &snapshotId)
{
    static const QRegularExpression pattern(QStringLiteral("^snap-[a-z0-9]{6,32}$"));
    return pattern.match(snapshotId).hasMatch();
}

QUrl FleetSnapshots::snapshotUrl(const QUrl &operatorUrl, const QString &snapshotId)
{
    QUrl url;
    url.setScheme(operatorUrl.scheme() == QLatin1String("wss") ? QStringLiteral("https") : QStringLiteral("http"));
    url.setHost(operatorUrl.host());
    url.setPort(operatorUrl.port());
    url.setPath(QStringLiteral("/api/v1/snapshots/") + snapshotId);
    return url;
}

QString FleetSnapshots::stateName(State state)
{
    switch (state) {
    case State::None:
        return QStringLiteral("none");
    case State::Loading:
        return QStringLiteral("loading");
    case State::Ready:
        return QStringLiteral("ready");
    case State::Unavailable:
        return QStringLiteral("unavailable");
    }
    return QString();
}

FleetSnapshots::FleetSnapshots(QObject *parent)
    : QObject(parent)
    , _network(new QNetworkAccessManager(this))
{
}

void FleetSnapshots::setSource(const QUrl &operatorUrl, const QString &token, const QString &caFile)
{
    _operatorUrl = operatorUrl;
    _token = token;
    _caFile = caFile;
}

void FleetSnapshots::request(const QString &snapshotId, bool retry)
{
    const State current = _entries.value(snapshotId).state;
    if (current == State::Loading || current == State::Ready || (current == State::Unavailable && !retry)) {
        return;
    }
    if (!validId(snapshotId)) {
        _set(snapshotId, {State::Unavailable, {}, {}, QStringLiteral("not a snapshot id")});
        return;
    }
    if (!_operatorUrl.isValid() || _operatorUrl.host().isEmpty()) {
        _set(snapshotId, {State::Unavailable, {}, {}, QStringLiteral("coordinator address not set")});
        return;
    }
    _set(snapshotId, {State::Loading, {}, {}, {}});
    _fetch(snapshotId);
}

void FleetSnapshots::_fetch(const QString &snapshotId)
{
    QNetworkRequest request(snapshotUrl(_operatorUrl, snapshotId));
    // The token goes in a header: URLs end up in logs and proxies.
    request.setRawHeader("Authorization", "Bearer " + _token.toUtf8());
    request.setRawHeader("Accept", "image/jpeg");
    request.setTransferTimeout(kTimeoutMs);
    if (request.url().scheme() == QLatin1String("https") && !_caFile.isEmpty()) {
        const QList<QSslCertificate> ca = QSslCertificate::fromPath(_caFile, QSsl::Pem);
        if (ca.isEmpty()) {
            ingest(snapshotId, {}, QStringLiteral("cannot read the Fleet CA certificate"));
            return;
        }
        QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
        ssl.addCaCertificates(ca);
        request.setSslConfiguration(ssl);
    }

    QNetworkReply *reply = _network->get(request);
    // Stop as soon as it is bigger than any picture the coordinator accepts.
    connect(reply, &QNetworkReply::downloadProgress, reply, [reply](qint64 received, qint64) {
        if (received > kMaxBytes) {
            reply->setProperty("tooLarge", true);
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, snapshotId, reply] { _onFinished(snapshotId, reply); });
}

void FleetSnapshots::_onFinished(const QString &snapshotId, QNetworkReply *reply)
{
    reply->deleteLater();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QString error;
    if (reply->property("tooLarge").toBool()) {
        error = QStringLiteral("picture too large");
    } else if (reply->error() == QNetworkReply::OperationCanceledError) {
        error = QStringLiteral("no answer within %1 s").arg(kTimeoutMs / 1000);
    } else if (status == 404) {
        error = QStringLiteral("not on the coordinator");
    } else if (status == 401 || status == 403) {
        error = QStringLiteral("not authorised (check Fleet/token)");
    } else if (reply->error() != QNetworkReply::NoError) {
        error = status > 0 ? QStringLiteral("HTTP %1").arg(status) : QStringLiteral("coordinator not reachable");
    } else if (!reply->header(QNetworkRequest::ContentTypeHeader).toString().startsWith(QLatin1String("image/jpeg"))) {
        error = QStringLiteral("not a JPEG");
    }
    if (!error.isEmpty()) {
        // The id only: never the full URL.
        qCInfo(FleetSnapshotsLog) << "snapshot" << snapshotId << "unavailable:" << error;
    }
    ingest(snapshotId, error.isEmpty() ? reply->readAll() : QByteArray(), error);
}

void FleetSnapshots::ingest(const QString &snapshotId, const QByteArray &body, const QString &error)
{
    if (!error.isEmpty()) {
        _set(snapshotId, {State::Unavailable, {}, {}, error});
        return;
    }
    if (body.isEmpty()) {
        _set(snapshotId, {State::Unavailable, {}, {}, QStringLiteral("empty picture")});
        return;
    }
    if (body.size() > kMaxBytes) {
        _set(snapshotId, {State::Unavailable, {}, {}, QStringLiteral("picture too large")});
        return;
    }
    const QImage image = QImage::fromData(body, "JPEG");
    if (image.isNull()) {
        _set(snapshotId, {State::Unavailable, {}, {}, QStringLiteral("not a readable JPEG")});
        return;
    }
    // The hash of exactly these bytes: what the operator is shown.
    const QString hash = QString::fromLatin1(QCryptographicHash::hash(body, QCryptographicHash::Sha256).toHex());
    _set(snapshotId, {State::Ready, image, hash, {}});
}

void FleetSnapshots::_set(const QString &snapshotId, Entry entry)
{
    if (!_entries.contains(snapshotId)) {
        _order.append(snapshotId);
        while (_order.size() > kMaxKept) {
            _entries.remove(_order.takeFirst());
        }
    }
    _entries.insert(snapshotId, std::move(entry));
    ++_revision;
    emit changed(snapshotId);
}

QString FleetSnapshots::state(const QString &snapshotId) const
{
    return stateName(_entries.value(snapshotId).state);
}

QString FleetSnapshots::reason(const QString &snapshotId) const
{
    return _entries.value(snapshotId).reason;
}

QString FleetSnapshots::sha256(const QString &snapshotId) const
{
    const Entry entry = _entries.value(snapshotId);
    return entry.state == State::Ready ? entry.sha256 : QString();
}

QImage FleetSnapshots::image(const QString &snapshotId) const
{
    const Entry entry = _entries.value(snapshotId);
    return entry.state == State::Ready ? entry.image : QImage();
}

QJsonObject FleetSnapshots::evidence(const QString &snapshotId) const
{
    if (snapshotId.isEmpty()) {
        return {};
    }
    const Entry entry = _entries.value(snapshotId);
    if (entry.state == State::Ready) {
        return {{QStringLiteral("snapshot_id"), snapshotId},
                {QStringLiteral("snapshot_sha256"), entry.sha256},
                {QStringLiteral("snapshot_displayed"), true}};
    }
    return {{QStringLiteral("snapshot_id"), snapshotId},
            {QStringLiteral("snapshot_displayed"), false},
            {QStringLiteral("snapshot_state"), stateName(entry.state)}};
}
