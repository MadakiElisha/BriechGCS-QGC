#include "FleetModels.h"

#include <QtCore/QDateTime>
#include <QtCore/QLoggingCategory>

#include "FleetLink.h"

Q_LOGGING_CATEGORY(FleetModelsLog, "Briech.FleetModels")

namespace {

constexpr int kFirstFieldRole = Qt::UserRole + 1;
constexpr int kAgeTimerMs = 1000;

/// QML cannot use "class" as a role name.
QByteArray roleNameFor(const QString &field)
{
    return field == QLatin1String("class") ? QByteArrayLiteral("className") : field.toUtf8();
}

bool hasLatLon(const QJsonValue &pos)
{
    const QJsonObject p = pos.toObject();
    return pos.isObject() && p.value(QLatin1String("lat")).isDouble() && p.value(QLatin1String("lon")).isDouble();
}

} // namespace

// ---------------------------------------------------------------------------
// FleetKeyedModel

FleetKeyedModel::FleetKeyedModel(const QString &keyField, const QStringList &fields, const QStringList &required,
                                 int cap, int staleAfterSeconds, QObject *parent)
    : QAbstractListModel(parent)
    , _keyField(keyField)
    , _fields(fields)
    , _required(required)
    , _cap(cap)
    , _staleAfterSeconds(staleAfterSeconds)
    , _clock([] { return QDateTime::currentMSecsSinceEpoch(); })
{
}

int FleetKeyedModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : count();
}

QHash<int, QByteArray> FleetKeyedModel::roleNames() const
{
    QHash<int, QByteArray> names;
    int role = kFirstFieldRole;
    for (const QString &field : _fields) {
        names.insert(role++, roleNameFor(field));
    }
    names.insert(role++, QByteArrayLiteral("ageSeconds"));
    names.insert(role++, QByteArrayLiteral("stale"));
    for (const QString &extra : extraRoles()) {
        names.insert(role++, extra.toUtf8());
    }
    return names;
}

QVariant FleetKeyedModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= count()) {
        return QVariant();
    }
    const Row &row = _rows.at(index.row());
    const int field = role - kFirstFieldRole;
    const int fieldCount = static_cast<int>(_fields.size());
    if (field < 0) {
        return QVariant();  // display and other built-in roles: QML uses the named roles
    }
    if (field < fieldCount) {
        const QJsonValue value = row.data.value(_fields.at(field));
        // Left out, or null: invalid, so QML shows "--".
        return (value.isUndefined() || value.isNull()) ? QVariant() : value.toVariant();
    }
    if (field == fieldCount) {
        return _ageSeconds(row);
    }
    if (field == fieldCount + 1) {
        return _stale(row);
    }
    return extraData(field - fieldCount - 2, row);
}

void FleetKeyedModel::replaceAll(const QJsonArray &rows)
{
    beginResetModel();
    _rows.clear();
    _index.clear();
    for (const QJsonValue &value : rows) {
        const QJsonObject row = value.toObject();
        QString why;
        if (!value.isObject() || !accepts(row, false, &why)) {
            reject(QStringLiteral("snapshot row: ") + why);
            continue;
        }
        const QString key = row.value(_keyField).toString();
        const Row entry{row, _seenMs(row)};
        if (_index.contains(key)) {
            _rows[_index.value(key)] = entry;    // a repeated id: the later one wins
        } else {
            _index.insert(key, static_cast<int>(_rows.size()));
            _rows.append(entry);
        }
    }
    while (_cap > 0 && _rows.size() > _cap) {
        _rows.removeAt(evictionRow());
    }
    _rebuildIndex();
    endResetModel();
    emit countChanged();
}

void FleetKeyedModel::upsert(const QJsonObject &row, bool merge)
{
    QString why;
    if (!accepts(row, merge, &why)) {
        reject(why);
        return;
    }
    const QString key = row.value(_keyField).toString();
    const int at = _index.value(key, -1);

    if (at < 0) {
        if (merge) {
            reject(QStringLiteral("update for unknown %1 %2").arg(_keyField, key));
            return;
        }
        if (_cap > 0 && count() >= _cap) {
            _removeRow(evictionRow());
        }
        const int end = count();
        beginInsertRows(QModelIndex(), end, end);
        _rows.append({row, _seenMs(row)});
        _index.insert(key, end);
        endInsertRows();
        emit countChanged();
        return;
    }

    Row &current = _rows[at];
    QJsonObject next = merge ? current.data : row;
    if (merge) {
        for (auto it = row.begin(); it != row.end(); ++it) {
            next.insert(it.key(), it.value());
        }
    }

    QStringList changed;
    QList<int> roles;
    for (int i = 0; i < _fields.size(); ++i) {
        if (current.data.value(_fields.at(i)) != next.value(_fields.at(i))) {
            changed.append(_fields.at(i));
            roles.append(kFirstFieldRole + i);
        }
    }
    const qint64 seenMs = _seenMs(next);
    if (seenMs != current.seenMs) {
        roles.append(kFirstFieldRole + static_cast<int>(_fields.size()));       // ageSeconds
        roles.append(kFirstFieldRole + static_cast<int>(_fields.size()) + 1);   // stale
    }
    roles.append(extraRolesFor(changed));

    current.data = next;
    current.seenMs = seenMs;
    if (!roles.isEmpty()) {
        const QModelIndex i = index(at);
        emit dataChanged(i, i, roles);
    }
}

void FleetKeyedModel::removeKey(const QString &key)
{
    const int at = _index.value(key, -1);
    if (at >= 0) {
        _removeRow(at);
    }
}

void FleetKeyedModel::clear()
{
    if (_rows.isEmpty()) {
        return;
    }
    beginRemoveRows(QModelIndex(), 0, count() - 1);
    _rows.clear();
    _index.clear();
    endRemoveRows();
    emit countChanged();
}

void FleetKeyedModel::setLinkUp(bool up)
{
    if (_linkUp != up) {
        _linkUp = up;
        refreshAges();
    }
}

void FleetKeyedModel::refreshAges()
{
    if (_rows.isEmpty()) {
        return;
    }
    const int age = kFirstFieldRole + static_cast<int>(_fields.size());
    emit dataChanged(index(0), index(count() - 1), {age, age + 1});
}

QJsonObject FleetKeyedModel::row(const QString &key) const
{
    const int at = _index.value(key, -1);
    return at < 0 ? QJsonObject() : _rows.at(at).data;
}

void FleetKeyedModel::setClock(Clock clock)
{
    _clock = std::move(clock);
}

bool FleetKeyedModel::accepts(const QJsonObject &row, bool merge, QString *why) const
{
    if (!row.value(_keyField).isString() || row.value(_keyField).toString().isEmpty()) {
        *why = QStringLiteral("no %1").arg(_keyField);
        return false;
    }
    if (merge) {
        return true;
    }
    for (const QString &field : _required) {
        const QJsonValue value = row.value(field);
        if (value.isUndefined() || value.isNull()) {
            *why = QStringLiteral("%1 %2: no %3").arg(_keyField, row.value(_keyField).toString(), field);
            return false;
        }
    }
    return true;
}

int FleetKeyedModel::evictionRow() const
{
    int oldest = 0;
    for (int i = 1; i < _rows.size(); ++i) {
        if (_rows.at(i).seenMs < _rows.at(oldest).seenMs) {
            oldest = i;
        }
    }
    return oldest;
}

QVariant FleetKeyedModel::extraData(int, const Row &) const
{
    return QVariant();
}

QList<int> FleetKeyedModel::extraRolesFor(const QStringList &) const
{
    return {};
}

void FleetKeyedModel::reject(const QString &why)
{
    ++_rejected;
    qCDebug(FleetModelsLog) << metaObject()->className() << "rejected:" << why;
    emit rejectedCountChanged();
}

qint64 FleetKeyedModel::_seenMs(const QJsonObject &row) const
{
    const QDateTime ts = QDateTime::fromString(row.value(QLatin1String("last_seen_ts")).toString(), Qt::ISODateWithMs);
    return ts.isValid() ? ts.toMSecsSinceEpoch() : now();
}

int FleetKeyedModel::_ageSeconds(const Row &row) const
{
    // Never negative: the coordinator's clock may run a little ahead of this one.
    return static_cast<int>(qMax<qint64>(0, now() - row.seenMs) / 1000);
}

bool FleetKeyedModel::_stale(const Row &row) const
{
    return !_linkUp || (_staleAfterSeconds > 0 && _ageSeconds(row) > _staleAfterSeconds);
}

void FleetKeyedModel::_rebuildIndex()
{
    _index.clear();
    for (int i = 0; i < _rows.size(); ++i) {
        _index.insert(_rows.at(i).data.value(_keyField).toString(), i);
    }
}

void FleetKeyedModel::_removeRow(int row)
{
    beginRemoveRows(QModelIndex(), row, row);
    _rows.removeAt(row);
    _rebuildIndex();
    endRemoveRows();
    emit countChanged();
}

// ---------------------------------------------------------------------------
// The three models. Fields and required fields follow schemas/common.schema.json.

FleetAssetModel::FleetAssetModel(QObject *parent)
    : FleetKeyedModel(QStringLiteral("asset_id"),
                      {QStringLiteral("asset_id"), QStringLiteral("kind"), QStringLiteral("name"), QStringLiteral("pos"),
                       QStringLiteral("health"), QStringLiteral("camera_heading_deg"), QStringLiteral("battery_pct"),
                       QStringLiteral("mains_power"), QStringLiteral("temp_c"), QStringLiteral("note"),
                       QStringLiteral("link"), QStringLiteral("last_seen_ts")},
                      {QStringLiteral("asset_id")},
                      0,      // a handful of fixed assets: no cap
                      15,     // handoff data-age rule for towers; the coordinator marks them offline at 15 s too
                      parent)
{
}

FleetObjectModel::FleetObjectModel(QObject *parent)
    : FleetKeyedModel(QStringLiteral("object_id"),
                      {QStringLiteral("object_id"), QStringLiteral("class"), QStringLiteral("confidence"),
                       QStringLiteral("pos"), QStringLiteral("velocity"), QStringLiteral("seen_by"),
                       QStringLiteral("last_seen_ts"), QStringLiteral("snapshot_id"), QStringLiteral("status")},
                      {QStringLiteral("object_id"), QStringLiteral("class"), QStringLiteral("confidence"),
                       QStringLiteral("pos"), QStringLiteral("seen_by"), QStringLiteral("last_seen_ts")},
                      500,    // the coordinator's own cap and the snapshot's maxItems
                      10,     // updated on every detection; quiet for 10 s means not seen
                      parent)
{
}

bool FleetObjectModel::accepts(const QJsonObject &row, bool merge, QString *why) const
{
    if (!FleetKeyedModel::accepts(row, merge, why)) {
        return false;
    }
    if (!hasLatLon(row.value(QLatin1String("pos"))) || !row.value(QLatin1String("confidence")).isDouble()) {
        *why = QStringLiteral("object %1: pos or confidence malformed").arg(row.value(QLatin1String("object_id")).toString());
        return false;
    }
    return true;
}

FleetAlertModel::FleetAlertModel(QObject *parent)
    : FleetKeyedModel(QStringLiteral("alert_id"),
                      {QStringLiteral("alert_id"), QStringLiteral("object_id"), QStringLiteral("severity"),
                       QStringLiteral("reason"), QStringLiteral("zone_id"), QStringLiteral("class"),
                       QStringLiteral("confidence"), QStringLiteral("pos"), QStringLiteral("seen_by"),
                       QStringLiteral("snapshot_id"), QStringLiteral("expires_ts"), QStringLiteral("status"),
                       QStringLiteral("operator_id"), QStringLiteral("proposal")},
                      {QStringLiteral("alert_id"), QStringLiteral("object_id"), QStringLiteral("severity"),
                       QStringLiteral("reason"), QStringLiteral("class"), QStringLiteral("confidence"),
                       QStringLiteral("pos"), QStringLiteral("seen_by")},
                      100,    // the snapshot's maxItems
                      0,      // alerts do not age out; their status says when they end
                      parent)
{
    connect(this, &QAbstractItemModel::modelReset, this, &FleetAlertModel::_recount);
    connect(this, &QAbstractItemModel::rowsInserted, this, &FleetAlertModel::_recount);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &FleetAlertModel::_recount);
    connect(this, &QAbstractItemModel::dataChanged, this, &FleetAlertModel::_recount);
}

bool FleetAlertModel::isActiveStatus(const QString &status)
{
    // Not yet rejected, expired or resolved. A new alert without a status is open.
    return status.isEmpty() || status == QLatin1String("open") || status == QLatin1String("acknowledged")
        || status == QLatin1String("approved");
}

bool FleetAlertModel::accepts(const QJsonObject &row, bool merge, QString *why) const
{
    if (!FleetKeyedModel::accepts(row, merge, why)) {
        return false;
    }
    const QString id = row.value(QLatin1String("alert_id")).toString();
    if (merge) {
        // alert.update: only alert_id and status are required.
        if (!row.value(QLatin1String("status")).isString()) {
            *why = QStringLiteral("alert.update %1: no status").arg(id);
            return false;
        }
        return true;
    }
    if (!hasLatLon(row.value(QLatin1String("pos"))) || !row.value(QLatin1String("confidence")).isDouble()) {
        *why = QStringLiteral("alert %1: pos or confidence malformed").arg(id);
        return false;
    }
    return true;
}

int FleetAlertModel::evictionRow() const
{
    // Drop the oldest closed alert first, so an active one is never pushed out while a closed one remains.
    int oldest = -1;
    for (int i = 0; i < rows().size(); ++i) {
        const Row &r = rows().at(i);
        if (!isActiveStatus(r.data.value(QLatin1String("status")).toString())
            && (oldest < 0 || r.seenMs < rows().at(oldest).seenMs)) {
            oldest = i;
        }
    }
    return oldest >= 0 ? oldest : FleetKeyedModel::evictionRow();
}

QVariant FleetAlertModel::extraData(int extra, const Row &row) const
{
    if (extra == 0) {
        return isActiveStatus(row.data.value(QLatin1String("status")).toString());
    }
    return QVariant();
}

QList<int> FleetAlertModel::extraRolesFor(const QStringList &fields) const
{
    if (fields.contains(QLatin1String("status"))) {
        return {roleFor(QByteArrayLiteral("active"))};
    }
    return {};
}

void FleetAlertModel::_recount()
{
    int active = 0;
    for (const Row &r : rows()) {
        if (isActiveStatus(r.data.value(QLatin1String("status")).toString())) {
            ++active;
        }
    }
    if (active != _activeCount) {
        _activeCount = active;
        emit activeCountChanged();
    }
}

// ---------------------------------------------------------------------------
// FleetModels

FleetModels::FleetModels(QObject *parent)
    : QObject(parent)
    , _ageTimer(this)
{
    _ageTimer.setInterval(kAgeTimerMs);
    connect(&_ageTimer, &QTimer::timeout, this, [this] {
        _assets.refreshAges();
        _objects.refreshAges();
        _alerts.refreshAges();
    });
}

void FleetModels::attach(FleetLink *link)
{
    _link = link;
    // Signals queued before FleetLink stopped can still arrive after it; a
    // stopped link's data is ignored so cleared models stay empty.
    connect(link, &FleetLink::snapshotReceived, this, [this](const QJsonObject &data) {
        if (_link && _link->state() != FleetLink::Disabled) {
            applySnapshot(data);
        }
    });
    connect(link, &FleetLink::batchReceived, this, [this](const QList<QJsonObject> &messages) {
        if (_link && _link->state() != FleetLink::Disabled) {
            applyBatch(messages);
        }
    });
    connect(link, &FleetLink::stateChanged, this, [this] {
        if (!_link) {
            return;
        }
        if (_link->state() == FleetLink::Disabled) {
            clear();
        }
        setLinkUp(_link->state() == FleetLink::Connected);
    });
    setLinkUp(link->state() == FleetLink::Connected);
    _ageTimer.start();
}

void FleetModels::applySnapshot(const QJsonObject &data)
{
    _assets.replaceAll(data.value(QLatin1String("assets")).toArray());
    _objects.replaceAll(data.value(QLatin1String("objects")).toArray());
    _alerts.replaceAll(data.value(QLatin1String("alerts")).toArray());
}

void FleetModels::applyBatch(const QList<QJsonObject> &messages)
{
    for (const QJsonObject &message : messages) {
        const QString type = message.value(QLatin1String("type")).toString();
        const QJsonObject data = message.value(QLatin1String("data")).toObject();
        if (type == QLatin1String("asset.state")) {
            _assets.upsert(data);
        } else if (type == QLatin1String("object.update")) {
            if (data.value(QLatin1String("status")).toString() == QLatin1String("removed")) {
                _objects.removeKey(data.value(QLatin1String("object_id")).toString());
            } else {
                _objects.upsert(data);
            }
        } else if (type == QLatin1String("alert.new")) {
            _alerts.upsert(data);
        } else if (type == QLatin1String("alert.update")) {
            _alerts.upsert(data, true);
        }
        // heartbeat: FleetLink already tracks silence. Unknown types never get past FleetLink.
    }
}

void FleetModels::clear()
{
    _assets.clear();
    _objects.clear();
    _alerts.clear();
}

void FleetModels::setLinkUp(bool up)
{
    _assets.setLinkUp(up);
    _objects.setLinkUp(up);
    _alerts.setLinkUp(up);
}
