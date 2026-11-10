#pragma once

#include <functional>

#include <QtCore/QAbstractListModel>
#include <QtCore/QHash>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonObject>
#include <QtCore/QList>
#include <QtCore/QPointer>
#include <QtCore/QStringList>
#include <QtCore/QTimer>

class FleetLink;

/// Coordinator rows keyed by one id field, for QML (schemas/common.schema.json).
///
/// One role per schema field, named as in the schema except "class", which
/// QML cannot use as a name and is served as "className". A field the
/// message left out reads as an invalid QVariant, so QML shows "--". Nested
/// fields (pos, velocity, proposal) arrive as maps: model.pos.lat.
///
/// Two computed roles on every model:
///   ageSeconds  now minus last_seen_ts, or minus the time the row was last
///               received when it has no last_seen_ts (alerts)
///   stale       the link is not connected, or ageSeconds passed staleAfterSeconds
///
/// Updates emit dataChanged with only the roles that changed. Rows are
/// inserted and removed one by one; only a snapshot resets the model.
class FleetKeyedModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(int count READ count NOTIFY countChanged)
    /// Rows refused: a required field missing or malformed, or an update for an unknown id.
    Q_PROPERTY(int rejectedCount READ rejectedCount NOTIFY rejectedCountChanged)
    /// 0 means rows never go stale by age, only when the link is down.
    Q_PROPERTY(int staleAfterSeconds READ staleAfterSeconds CONSTANT)

public:
    /// Milliseconds since the epoch, UTC. Replaceable for tests.
    using Clock = std::function<qint64()>;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return static_cast<int>(_rows.size()); }
    int rejectedCount() const { return _rejected; }
    int staleAfterSeconds() const { return _staleAfterSeconds; }

    /// The whole picture from a snapshot: the one place the model is reset.
    void replaceAll(const QJsonArray &rows);
    /// A new row, or a changed one. merge replaces only the fields given
    /// (alert.update); otherwise the row is replaced whole.
    void upsert(const QJsonObject &row, bool merge = false);
    void removeKey(const QString &key);
    /// Removes every row one by one (the link was turned off).
    void clear();
    /// While the link is down every row reads stale.
    void setLinkUp(bool up);
    /// Re-evaluates ageSeconds and stale on every row. Called by FleetModels' one timer.
    void refreshAges();

    /// The stored row for key, or an empty object. For C++ callers and tests.
    QJsonObject row(const QString &key) const;
    int rowOf(const QString &key) const { return _index.value(key, -1); }
    int roleFor(const QByteArray &name) const { return roleNames().key(name, -1); }
    void setClock(Clock clock);

signals:
    void countChanged();
    void rejectedCountChanged();

protected:
    FleetKeyedModel(const QString &keyField, const QStringList &fields, const QStringList &required,
                    int cap, int staleAfterSeconds, QObject *parent);

    struct Row
    {
        QJsonObject data;
        qint64 seenMs = 0;  ///< last_seen_ts, or when the row was last received
    };

    /// Checks the fields this model relies on. merge: a partial update.
    virtual bool accepts(const QJsonObject &row, bool merge, QString *why) const;
    /// The row to drop when a new one would pass the cap.
    virtual int evictionRow() const;
    /// Extra computed roles a subclass adds after ageSeconds and stale.
    virtual QStringList extraRoles() const { return {}; }
    virtual QVariant extraData(int extra, const Row &row) const;
    /// Extra roles that change when these fields change.
    virtual QList<int> extraRolesFor(const QStringList &fields) const;

    void reject(const QString &why);
    qint64 now() const { return _clock(); }
    const QList<Row> &rows() const { return _rows; }

private:
    qint64 _seenMs(const QJsonObject &row) const;
    int _ageSeconds(const Row &row) const;
    bool _stale(const Row &row) const;
    void _rebuildIndex();
    void _removeRow(int row);

    QString _keyField;
    QStringList _fields;
    QStringList _required;
    int _cap;
    int _staleAfterSeconds;
    QList<Row> _rows;
    QHash<QString, int> _index;
    int _rejected = 0;
    bool _linkUp = false;
    Clock _clock;
};

/// Fixed assets such as towers, from asset.state. The coordinator always
/// sends the whole asset, so an update replaces the row.
class FleetAssetModel : public FleetKeyedModel
{
    Q_OBJECT

public:
    explicit FleetAssetModel(QObject *parent = nullptr);
};

/// Tracked objects (detections) from object.update. Capped at 500, the least
/// recently seen dropped first, as the coordinator does. status "removed"
/// takes the row out.
class FleetObjectModel : public FleetKeyedModel
{
    Q_OBJECT

public:
    explicit FleetObjectModel(QObject *parent = nullptr);

protected:
    bool accepts(const QJsonObject &row, bool merge, QString *why) const override;
};

/// Alerts from alert.new (whole) and alert.update (only the fields given).
/// Capped at 100; a closed alert is dropped before an active one.
class FleetAlertModel : public FleetKeyedModel
{
    Q_OBJECT

    /// Alerts not yet closed: status open, acknowledged or approved.
    Q_PROPERTY(int activeCount READ activeCount NOTIFY activeCountChanged)

public:
    explicit FleetAlertModel(QObject *parent = nullptr);

    int activeCount() const { return _activeCount; }
    static bool isActiveStatus(const QString &status);

signals:
    void activeCountChanged();

protected:
    bool accepts(const QJsonObject &row, bool merge, QString *why) const override;
    int evictionRow() const override;
    QStringList extraRoles() const override { return {QStringLiteral("active")}; }
    QVariant extraData(int extra, const Row &row) const override;
    QList<int> extraRolesFor(const QStringList &fields) const override;

private:
    void _recount();

    int _activeCount = 0;
};

/// Feeds the three models from FleetLink and keeps their ages current with
/// one timer. Lives on the main thread, like FleetLink's signals.
class FleetModels : public QObject
{
    Q_OBJECT

public:
    explicit FleetModels(QObject *parent = nullptr);

    FleetAssetModel *assets() { return &_assets; }
    FleetObjectModel *objects() { return &_objects; }
    FleetAlertModel *alerts() { return &_alerts; }

    /// Connects to link: snapshot, batches, and state (cleared when Disabled).
    void attach(FleetLink *link);

    /// snapshot data: assets, objects, alerts. vehicles are QGC's own and are skipped.
    void applySnapshot(const QJsonObject &data);
    /// Full messages, routed by type. heartbeat and unknown types are skipped.
    void applyBatch(const QList<QJsonObject> &messages);
    void clear();
    void setLinkUp(bool up);

private:
    FleetAssetModel _assets;
    FleetObjectModel _objects;
    FleetAlertModel _alerts;
    QTimer _ageTimer;
    QPointer<FleetLink> _link;
};
