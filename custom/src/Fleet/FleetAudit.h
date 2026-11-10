#pragma once

#include <functional>

#include <QtCore/QDateTime>
#include <QtCore/QJsonObject>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

/// A local, append-only log of every operator action this ground station
/// records (Hold all, Return all, approve, reject, and each outcome), kept
/// even while the coordinator is offline.
///
/// One JSON object per line:
///   {"seq":N,"ts":"...","kind":"operator.action","payload":{...},"prev":"<hash>","hash":"<hash>"}
/// hash = sha256("seq|ts|kind|payload|prev"), payload as compact JSON with
/// sorted keys, and prev of the first entry is 64 zeros. That is the same chain
/// rule as the coordinator's audit log (ground-core/coordinator/audit.py), so
/// editing, removing or reordering any line breaks verify() from that line on.
///
/// Qt only, no QGC types, so it is tested on its own (custom/test/Fleet).
class FleetAudit : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)

public:
    static QString genesis() { return QString(64, QLatin1Char('0')); }
    static QString entryHash(qint64 seq, const QString &ts, const QString &kind, const QString &payload,
                             const QString &prevHash);
    /// Compact JSON with sorted keys (QJsonObject keeps its keys sorted).
    static QString canonical(const QJsonObject &payload);

    explicit FleetAudit(const QString &path, QObject *parent = nullptr);

    /// Append one entry; false (and lastError set) if the file cannot be written.
    bool append(const QString &kind, const QJsonObject &payload);

    /// {ok, entries, firstBroken (seq, or -1 when ok), error}
    Q_INVOKABLE QVariantMap verify() const;
    /// The newest entries first, at most limit: {seq, ts, kind, payload} maps for a view.
    Q_INVOKABLE QVariantList recent(int limit = 50) const;

    int count() const { return static_cast<int>(_lastSeq); }
    QString path() const { return _path; }
    QString lastError() const { return _lastError; }

    /// For tests: the time stamp source.
    void setClock(std::function<QDateTime()> clock) { _clock = std::move(clock); }

signals:
    void changed();

private:
    void _load();

    QString _path;
    qint64 _lastSeq = 0;
    QString _lastHash;
    QString _lastError;
    std::function<QDateTime()> _clock;
};
