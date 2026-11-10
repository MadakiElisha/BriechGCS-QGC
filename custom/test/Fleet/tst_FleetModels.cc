#include <QtCore/QDateTime>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QTimeZone>
#include <QtTest/QSignalSpy>
#include <QtTest/QTest>

#include "FleetLink.h"
#include "FleetModels.h"

namespace {

/// A message from schemas/examples, the files the coordinator's CI checks.
QJsonObject example(const QString &name)
{
    QFile file(QStringLiteral(BRIECH_REPO_DIR "/schemas/examples/") + name + QStringLiteral(".json"));
    if (!file.open(QIODevice::ReadOnly)) {
        qFatal("missing schemas/examples/%s.json", qPrintable(name));
    }
    return QJsonDocument::fromJson(file.readAll()).object();
}

QJsonObject msg(const QString &type, const QJsonObject &data)
{
    return {{"v", 1}, {"type", type}, {"id", "m-1"}, {"ts", "2026-10-26T10:30:05.400Z"}, {"src", "coordinator"}, {"data", data}};
}

QJsonObject object(const QString &id, const QString &ts, double lat = 6.5251)
{
    return {{"object_id", id}, {"class", "person"}, {"confidence", 0.88},
            {"pos", QJsonObject{{"lat", lat}, {"lon", 3.3801}, {"error_m", 6.0}}},
            {"seen_by", QJsonArray{"tower-01"}}, {"last_seen_ts", ts}, {"status", "active"}};
}

QJsonObject alert(const QString &id, const QString &status)
{
    QJsonObject a = example(QStringLiteral("alert.new.valid"))["data"].toObject();
    a["alert_id"] = id;
    a["status"] = status;
    return a;
}

QString ts(qint64 ms)
{
    return QDateTime::fromMSecsSinceEpoch(ms, QTimeZone::UTC).toString(Qt::ISODateWithMs);
}

QVariant value(const FleetKeyedModel &model, const QString &key, const QByteArray &role)
{
    return model.data(model.index(model.rowOf(key)), model.roleFor(role));
}

/// The roles of every dataChanged a spy caught.
QList<QByteArray> changedRoles(const FleetKeyedModel &model, const QSignalSpy &spy)
{
    QList<QByteArray> names;
    for (const QList<QVariant> &args : spy) {
        for (int role : args.at(2).value<QList<int>>()) {
            names.append(model.roleNames().value(role));
        }
    }
    return names;
}

const qint64 kT0 = QDateTime(QDate(2026, 10, 26), QTime(10, 30, 5, 400), QTimeZone::UTC).toMSecsSinceEpoch();

} // namespace

class TestFleetModels : public QObject
{
    Q_OBJECT

private slots:
    void snapshotReplacesEverything()
    {
        FleetModels models;
        models.applyBatch({msg("object.update", object("o-old", ts(kT0)))});
        QCOMPARE(models.objects()->count(), 1);

        QSignalSpy reset(models.objects(), &QAbstractItemModel::modelReset);
        models.applySnapshot(example(QStringLiteral("snapshot.valid"))["data"].toObject());
        QCOMPARE(reset.count(), 1);
        QCOMPARE(models.assets()->count(), 1);
        QCOMPARE(models.objects()->count(), 1);
        QCOMPARE(models.alerts()->count(), 1);
        QCOMPARE(models.objects()->rowOf("o-old"), -1);     // not merged across snapshots
        QCOMPARE(models.objects()->rowOf("o-45"), 0);
        QCOMPARE(models.alerts()->activeCount(), 1);

        models.applySnapshot(example(QStringLiteral("snapshot.valid.empty"))["data"].toObject());
        QCOMPARE(models.assets()->count(), 0);
        QCOMPARE(models.objects()->count(), 0);
        QCOMPARE(models.alerts()->count(), 0);
        QCOMPARE(models.alerts()->activeCount(), 0);
    }

    void insertsFromExampleMessages()
    {
        FleetModels models;
        QSignalSpy inserted(models.alerts(), &QAbstractItemModel::rowsInserted);
        models.applyBatch({example(QStringLiteral("asset.state.valid")), example(QStringLiteral("object.update.valid")),
                           example(QStringLiteral("alert.new.valid")), example(QStringLiteral("alert.update.valid"))});
        QCOMPARE(inserted.count(), 1);
        QCOMPARE(models.assets()->count(), 1);
        QCOMPARE(models.objects()->count(), 1);
        QCOMPARE(models.alerts()->count(), 1);
        QCOMPARE(value(*models.alerts(), "a-102", "status").toString(), QStringLiteral("approved"));
        QCOMPARE(value(*models.objects(), "o-45", "className").toString(), QStringLiteral("person"));
        QCOMPARE(value(*models.objects(), "o-45", "pos").toMap().value("lat").toDouble(), 6.5251);
    }

    void updateSignalsOnlyChangedRoles()
    {
        FleetObjectModel model;
        model.upsert(object("o-1", ts(kT0)));
        QSignalSpy changed(&model, &QAbstractItemModel::dataChanged);
        QSignalSpy reset(&model, &QAbstractItemModel::modelReset);
        QSignalSpy inserted(&model, &QAbstractItemModel::rowsInserted);

        model.upsert(object("o-1", ts(kT0 + 500), 6.5260));
        QCOMPARE(changed.count(), 1);
        QCOMPARE(reset.count(), 0);
        QCOMPARE(inserted.count(), 0);
        const QList<QByteArray> roles = changedRoles(model, changed);
        QVERIFY(roles.contains("pos"));
        QVERIFY(roles.contains("last_seen_ts"));
        QVERIFY(roles.contains("ageSeconds"));
        QVERIFY(roles.contains("stale"));
        QVERIFY(!roles.contains("className"));
        QVERIFY(!roles.contains("confidence"));
        QVERIFY(!roles.contains("seen_by"));
    }

    void unknownFieldsAreIgnored()
    {
        FleetObjectModel model;
        model.upsert(object("o-1", ts(kT0)));
        QSignalSpy changed(&model, &QAbstractItemModel::dataChanged);

        QJsonObject withExtra = object("o-1", ts(kT0));
        withExtra["future_field"] = QStringLiteral("from schema v1.1");
        model.upsert(withExtra);
        QCOMPARE(changed.count(), 0);       // nothing QML reads changed
        QVERIFY(!model.roleNames().values().contains("future_field"));
        QCOMPARE(model.rejectedCount(), 0);
    }

    void removedObjectLeavesTheModel()
    {
        FleetModels models;
        models.applyBatch({msg("object.update", object("o-1", ts(kT0))), msg("object.update", object("o-2", ts(kT0)))});
        QSignalSpy removed(models.objects(), &QAbstractItemModel::rowsRemoved);

        QJsonObject gone = object("o-1", ts(kT0 + 1000));
        gone["status"] = QStringLiteral("removed");
        models.applyBatch({msg("object.update", gone)});
        QCOMPARE(removed.count(), 1);
        QCOMPARE(models.objects()->count(), 1);
        QCOMPARE(models.objects()->rowOf("o-1"), -1);
        QCOMPARE(models.objects()->rowOf("o-2"), 0);   // index kept right after a removal

        gone["object_id"] = QStringLiteral("o-unknown");
        models.applyBatch({msg("object.update", gone)});
        QCOMPARE(removed.count(), 1);
    }

    void objectCapDropsLeastRecentlySeen()
    {
        FleetObjectModel model;
        for (int i = 0; i < 500; ++i) {
            model.upsert(object(QStringLiteral("o-%1").arg(i), ts(kT0 + 1000 + i)));
        }
        model.upsert(object("o-0", ts(kT0 + 5000)));        // seen again: now the newest
        model.upsert(object("o-new", ts(kT0 + 6000)));
        QCOMPARE(model.count(), 500);
        QVERIFY(model.rowOf("o-0") >= 0);
        QCOMPARE(model.rowOf("o-1"), -1);                     // the least recently seen went
        QVERIFY(model.rowOf("o-new") >= 0);
    }

    void alertCapKeepsActiveAlerts()
    {
        FleetAlertModel model;
        model.upsert(alert("a-closed", "resolved"));
        for (int i = 0; i < 99; ++i) {
            model.upsert(alert(QStringLiteral("a-%1").arg(i), "open"));
        }
        model.upsert(alert("a-new", "open"));
        QCOMPARE(model.count(), 100);
        QCOMPARE(model.rowOf("a-closed"), -1);
        QVERIFY(model.rowOf("a-0") >= 0);
        QCOMPARE(model.activeCount(), 100);
    }

    void partialAlertUpdateKeepsOtherFields()
    {
        FleetModels models;
        models.applyBatch({example(QStringLiteral("alert.new.valid"))});
        FleetAlertModel *alerts = models.alerts();
        QSignalSpy changed(alerts, &QAbstractItemModel::dataChanged);

        models.applyBatch({example(QStringLiteral("alert.update.valid"))});    // status approved, operator_id
        QCOMPARE(value(*alerts, "a-102", "status").toString(), QStringLiteral("approved"));
        QCOMPARE(value(*alerts, "a-102", "operator_id").toString(), QStringLiteral("op-001"));
        QCOMPARE(value(*alerts, "a-102", "severity").toString(), QStringLiteral("high"));
        QCOMPARE(value(*alerts, "a-102", "proposal").toMap().value("action").toString(), QStringLiteral("orbit"));
        const QList<QByteArray> roles = changedRoles(*alerts, changed);
        QVERIFY(roles.contains("status"));
        QVERIFY(roles.contains("operator_id"));
        QVERIFY(roles.contains("active"));
        QVERIFY(!roles.contains("proposal"));
        QVERIFY(!roles.contains("severity"));
        QCOMPARE(alerts->activeCount(), 1);

        QSignalSpy active(alerts, &FleetAlertModel::activeCountChanged);
        models.applyBatch({msg("alert.update", {{"alert_id", "a-102"}, {"status", "resolved"}})});
        QCOMPARE(alerts->activeCount(), 0);
        QCOMPARE(active.count(), 1);
        QCOMPARE(value(*alerts, "a-102", "active").toBool(), false);
    }

    void updateForUnknownAlertIsCounted()
    {
        FleetModels models;
        models.applyBatch({example(QStringLiteral("alert.update.valid"))});
        QCOMPARE(models.alerts()->count(), 0);
        QCOMPARE(models.alerts()->rejectedCount(), 1);
    }

    void malformedDataIsDropped()
    {
        FleetModels models;
        QJsonObject noPos = object("o-1", ts(kT0));
        noPos.remove("pos");
        QJsonObject badPos = object("o-2", ts(kT0));
        badPos["pos"] = QJsonObject{{"lat", "north"}, {"lon", 3.38}, {"error_m", 6.0}};
        QJsonObject noId = object("o-3", ts(kT0));
        noId.remove("object_id");

        models.applyBatch({msg("object.update", noPos), msg("object.update", badPos), msg("object.update", noId),
                           example(QStringLiteral("asset.state.invalid.no-asset_id"))});
        models.applyBatch({example(QStringLiteral("alert.new.valid"))});
        models.applyBatch({example(QStringLiteral("alert.update.invalid.no-status"))});

        QCOMPARE(models.objects()->count(), 0);
        QCOMPARE(models.objects()->rejectedCount(), 3);
        QCOMPARE(models.assets()->count(), 0);
        QCOMPARE(models.assets()->rejectedCount(), 1);
        QCOMPARE(models.alerts()->rejectedCount(), 1);
        QCOMPARE(value(*models.alerts(), "a-102", "confidence").toDouble(), 0.88);   // the bad update changed nothing

        // A snapshot keeps its good rows and drops the rest.
        models.applySnapshot({{"assets", QJsonArray{"not an object", QJsonObject{{"asset_id", "tower-01"}}}},
                              {"vehicles", QJsonArray{}}, {"objects", QJsonArray{noPos}}, {"alerts", QJsonArray{}}});
        QCOMPARE(models.assets()->count(), 1);
        QCOMPARE(models.assets()->rejectedCount(), 2);
        QCOMPARE(models.objects()->count(), 0);
    }

    void missingOptionalFieldsReadInvalid()
    {
        FleetAssetModel model;
        model.upsert(example(QStringLiteral("asset.state.valid"))["data"].toObject());
        QVERIFY(!value(model, "tower-01", "battery_pct").isValid());
        QVERIFY(!value(model, "tower-01", "name").isValid());
        QCOMPARE(value(model, "tower-01", "mains_power").toBool(), true);
        QVERIFY(!model.data(model.index(0), Qt::DisplayRole).isValid());
    }

    void ageAndStaleness()
    {
        qint64 now = kT0 + 4000;
        FleetObjectModel model;
        model.setClock([&now] { return now; });
        model.setLinkUp(true);
        model.upsert(object("o-1", ts(kT0)));
        QCOMPARE(value(model, "o-1", "ageSeconds").toInt(), 4);
        QCOMPARE(value(model, "o-1", "stale").toBool(), false);

        QSignalSpy changed(&model, &QAbstractItemModel::dataChanged);
        now = kT0 + 11000;
        model.refreshAges();
        QCOMPARE(changed.count(), 1);
        QCOMPARE(changedRoles(model, changed), QList<QByteArray>({"ageSeconds", "stale"}));
        QCOMPARE(value(model, "o-1", "stale").toBool(), true);    // past 10 s

        now = kT0 + 1000;
        model.upsert(object("o-1", ts(kT0 + 1000)));
        QCOMPARE(value(model, "o-1", "stale").toBool(), false);
        model.setLinkUp(false);
        QCOMPARE(value(model, "o-1", "stale").toBool(), true);    // link down: everything is stale

        now = kT0 - 2000;                                          // coordinator clock ahead of ours
        QCOMPARE(value(model, "o-1", "ageSeconds").toInt(), 0);
    }

    void towersGoStaleAfterFifteenSeconds()
    {
        qint64 now = kT0 + 14000;
        FleetAssetModel model;
        model.setClock([&now] { return now; });
        model.setLinkUp(true);
        QJsonObject tower = example(QStringLiteral("asset.state.valid"))["data"].toObject();
        tower["last_seen_ts"] = ts(kT0);
        model.upsert(tower);
        const QString id = tower["asset_id"].toString();
        QCOMPARE(model.staleAfterSeconds(), 15);
        QCOMPARE(value(model, id, "stale").toBool(), false);   // 14 s: still fresh
        now = kT0 + 16000;
        model.refreshAges();
        QCOMPARE(value(model, id, "stale").toBool(), true);    // past 15 s
    }

    void alertsAgeSinceReceivedAndNeverStaleByAge()
    {
        qint64 now = kT0;
        FleetAlertModel model;
        model.setClock([&now] { return now; });
        model.setLinkUp(true);
        model.upsert(alert("a-1", "open"));
        now = kT0 + 600000;
        QCOMPARE(value(model, "a-1", "ageSeconds").toInt(), 600);
        QCOMPARE(value(model, "a-1", "stale").toBool(), false);
    }

    void clearRemovesRowsWithoutReset()
    {
        FleetModels models;
        models.applySnapshot(example(QStringLiteral("snapshot.valid"))["data"].toObject());
        QSignalSpy reset(models.alerts(), &QAbstractItemModel::modelReset);
        QSignalSpy removed(models.alerts(), &QAbstractItemModel::rowsRemoved);
        models.clear();
        QCOMPARE(reset.count(), 0);
        QCOMPARE(removed.count(), 1);
        QCOMPARE(models.alerts()->count(), 0);
        QCOMPARE(models.alerts()->activeCount(), 0);
    }

    void ignoresALinkThatIsOff()
    {
        // Signals queued before FleetLink stopped can still be delivered after it.
        FleetLink link;
        FleetModels models;
        models.attach(&link);
        QCOMPARE(link.state(), FleetLink::Disabled);
        emit link.snapshotReceived(example(QStringLiteral("snapshot.valid"))["data"].toObject());
        emit link.batchReceived({example(QStringLiteral("object.update.valid"))});
        QCOMPARE(models.assets()->count(), 0);
        QCOMPARE(models.objects()->count(), 0);
    }

    void roleNamesAreStable()
    {
        FleetAlertModel alerts;
        const QList<QByteArray> names = alerts.roleNames().values();
        for (const char *name : {"alert_id", "object_id", "severity", "reason", "zone_id", "className", "confidence", "pos",
                                 "seen_by", "snapshot_id", "expires_ts", "status", "operator_id", "proposal", "ageSeconds",
                                 "stale", "active"}) {
            QVERIFY2(names.contains(name), name);
        }
        QVERIFY(!names.contains("class"));
        FleetAssetModel assets;
        for (const char *name : {"asset_id", "kind", "name", "pos", "health", "camera_heading_deg", "battery_pct",
                                 "mains_power", "temp_c", "note", "link", "last_seen_ts", "ageSeconds", "stale"}) {
            QVERIFY2(assets.roleNames().values().contains(name), name);
        }
    }
};

QTEST_GUILESS_MAIN(TestFleetModels)
#include "tst_FleetModels.moc"
