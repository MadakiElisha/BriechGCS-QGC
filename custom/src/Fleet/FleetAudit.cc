#include "FleetAudit.h"

#include <QtCore/QCryptographicHash>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonDocument>
#include <QtCore/QTimeZone>

namespace {

QString isoMs(const QDateTime &at)
{
    return at.toTimeZone(QTimeZone::UTC).toString(Qt::ISODateWithMs);
}

/// Every line of the file, or an empty list when it does not exist yet.
QList<QByteArray> readLines(const QString &path, QString *error)
{
    QFile file(path);
    if (!file.exists()) {
        return {};
    }
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) {
            *error = file.errorString();
        }
        return {};
    }
    QList<QByteArray> lines;
    for (const QByteArray &line : file.readAll().split('\n')) {
        if (!line.trimmed().isEmpty()) {
            lines.append(line);
        }
    }
    return lines;
}

} // namespace

QString FleetAudit::entryHash(qint64 seq, const QString &ts, const QString &kind, const QString &payload,
                              const QString &prevHash)
{
    const QString input = QStringLiteral("%1|%2|%3|%4|%5").arg(seq).arg(ts, kind, payload, prevHash);
    return QString::fromLatin1(QCryptographicHash::hash(input.toUtf8(), QCryptographicHash::Sha256).toHex());
}

QString FleetAudit::canonical(const QJsonObject &payload)
{
    return QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

FleetAudit::FleetAudit(const QString &path, QObject *parent)
    : QObject(parent)
    , _path(path)
    , _lastHash(genesis())
{
    _load();
}

void FleetAudit::_load()
{
    // Continue the chain from the last line as written. If someone has edited
    // the file, verify() says where; the log keeps recording either way.
    const QList<QByteArray> lines = readLines(_path, &_lastError);
    for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
        const QJsonObject entry = QJsonDocument::fromJson(*it).object();
        if (entry.contains(QLatin1String("seq")) && entry.contains(QLatin1String("hash"))) {
            _lastSeq = entry.value(QLatin1String("seq")).toInteger();
            _lastHash = entry.value(QLatin1String("hash")).toString();
            return;
        }
    }
}

bool FleetAudit::append(const QString &kind, const QJsonObject &payload)
{
    const qint64 seq = _lastSeq + 1;
    const QString ts = isoMs(_clock ? _clock() : QDateTime::currentDateTimeUtc());
    const QString hash = entryHash(seq, ts, kind, canonical(payload), _lastHash);
    const QJsonObject entry{{QStringLiteral("seq"), seq},
                            {QStringLiteral("ts"), ts},
                            {QStringLiteral("kind"), kind},
                            {QStringLiteral("payload"), payload},
                            {QStringLiteral("prev"), _lastHash},
                            {QStringLiteral("hash"), hash}};

    QDir().mkpath(QFileInfo(_path).absolutePath());
    QFile file(_path);
    if (!file.open(QIODevice::Append | QIODevice::Text)) {
        _lastError = file.errorString();
        emit changed();
        return false;
    }
    const QByteArray line = QJsonDocument(entry).toJson(QJsonDocument::Compact) + '\n';
    if (file.write(line) != line.size() || !file.flush()) {
        _lastError = file.errorString();
        emit changed();
        return false;
    }
    _lastSeq = seq;
    _lastHash = hash;
    _lastError.clear();
    emit changed();
    return true;
}

QVariantMap FleetAudit::verify() const
{
    QString error;
    const QList<QByteArray> lines = readLines(_path, &error);
    QString prev = genesis();
    qint64 expectedSeq = 1;
    for (const QByteArray &line : lines) {
        const QJsonObject entry = QJsonDocument::fromJson(line).object();
        const qint64 seq = entry.value(QLatin1String("seq")).toInteger(-1);
        const QString recomputed = entryHash(seq, entry.value(QLatin1String("ts")).toString(),
                                             entry.value(QLatin1String("kind")).toString(),
                                             canonical(entry.value(QLatin1String("payload")).toObject()), prev);
        if (entry.isEmpty() || seq != expectedSeq || entry.value(QLatin1String("prev")).toString() != prev
            || entry.value(QLatin1String("hash")).toString() != recomputed) {
            return {{QStringLiteral("ok"), false},
                    {QStringLiteral("entries"), lines.size()},
                    {QStringLiteral("firstBroken"), expectedSeq},
                    {QStringLiteral("error"), error}};
        }
        prev = recomputed;
        ++expectedSeq;
    }
    return {{QStringLiteral("ok"), error.isEmpty()},
            {QStringLiteral("entries"), lines.size()},
            {QStringLiteral("firstBroken"), -1},
            {QStringLiteral("error"), error}};
}

QVariantList FleetAudit::recent(int limit) const
{
    const QList<QByteArray> lines = readLines(_path, nullptr);
    QVariantList out;
    for (auto it = lines.crbegin(); it != lines.crend() && out.size() < limit; ++it) {
        const QJsonObject entry = QJsonDocument::fromJson(*it).object();
        if (!entry.isEmpty()) {
            out.append(entry.toVariantMap());
        }
    }
    return out;
}
