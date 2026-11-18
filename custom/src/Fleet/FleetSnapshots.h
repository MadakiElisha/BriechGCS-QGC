#pragma once

#include <QtCore/QHash>
#include <QtCore/QJsonObject>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QUrl>
#include <QtGui/QImage>

class QNetworkAccessManager;
class QNetworkReply;

/// The camera picture attached to an alert (alert.new snapshot_id), fetched
/// from the coordinator for the operator to see before deciding.
///
/// GET <coordinator>/api/v1/snapshots/<snapshot_id>, with the operator token
/// in the Authorization header (never in the URL) and the Fleet CA trusted,
/// the same settings FleetLink uses. Each picture is kept with the SHA-256 of
/// the exact bytes received, so an operator decision can record which picture
/// was on screen (FleetDispatch adds evidence() to the local audit entry).
///
/// A picture is optional: when it cannot be fetched or decoded the alert works
/// as before and the UI says "PHOTO UNAVAILABLE". Nothing here blocks a
/// decision. Qt only, no QGC types, so it is tested on its own (custom/test/Fleet).
class FleetSnapshots : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    /// none: not requested; loading; ready: decoded and shown; unavailable: see reason().
    enum class State { None, Loading, Ready, Unavailable };

    /// The coordinator refuses bigger uploads (ground-core SNAPSHOT_MAX).
    static constexpr qint64 kMaxBytes = 300 * 1024;
    static constexpr int kTimeoutMs = 8000;
    /// Pictures kept in memory; the oldest are dropped first (alerts are capped at 100).
    static constexpr int kMaxKept = 100;

    /// The schema's snapshot id: ^snap-[a-z0-9]{6,32}$.
    static bool validId(const QString &snapshotId);
    /// The picture's URL from the operator WebSocket URL: wss becomes https,
    /// ws becomes http, same host and port, path /api/v1/snapshots/<id>.
    static QUrl snapshotUrl(const QUrl &operatorUrl, const QString &snapshotId);
    static QString stateName(State state);

    explicit FleetSnapshots(QObject *parent = nullptr);

    /// Where and how to fetch. FleetLink::configFromSettings() supplies these in the app.
    void setSource(const QUrl &operatorUrl, const QString &token, const QString &caFile);

    /// Fetch the picture unless it is already loading or ready. retry also
    /// fetches one that is unavailable.
    Q_INVOKABLE void request(const QString &snapshotId, bool retry = false);
    /// "none", "loading", "ready" or "unavailable".
    Q_INVOKABLE QString state(const QString &snapshotId) const;
    /// Why it is unavailable, short and without URLs or tokens.
    Q_INVOKABLE QString reason(const QString &snapshotId) const;
    /// SHA-256 (hex) of the bytes shown, or empty when not ready.
    Q_INVOKABLE QString sha256(const QString &snapshotId) const;
    /// The decoded picture, or a null image when not ready.
    QImage image(const QString &snapshotId) const;

    /// What the audit records about the picture when the operator decides:
    ///   no snapshot id            {}
    ///   picture on screen         {snapshot_id, snapshot_sha256, snapshot_displayed: true}
    ///   otherwise                 {snapshot_id, snapshot_displayed: false, snapshot_state}
    QJsonObject evidence(const QString &snapshotId) const;

    /// The result of one fetch: body, or a non-empty error. Public for tests.
    void ingest(const QString &snapshotId, const QByteArray &body, const QString &error);

    int revision() const { return _revision; }

signals:
    /// A picture changed state; revision changed too (QML binds to it).
    void changed(const QString &snapshotId);

private:
    struct Entry
    {
        State state = State::None;
        QImage image;
        QString sha256;
        QString reason;
    };

    void _set(const QString &snapshotId, Entry entry);
    void _fetch(const QString &snapshotId);
    void _onFinished(const QString &snapshotId, QNetworkReply *reply);

    QNetworkAccessManager *_network = nullptr;
    QUrl _operatorUrl;
    QString _token;
    QString _caFile;
    QHash<QString, Entry> _entries;
    QStringList _order;     ///< oldest first, for kMaxKept
    int _revision = 0;
};
