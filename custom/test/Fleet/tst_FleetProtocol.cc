#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QRegularExpression>
#include <QtTest/QTest>

#include "FleetProtocol.h"

namespace {

QJsonObject msg(const QString &type, const QJsonObject &data, const QString &id = QStringLiteral("m-1"))
{
    return {{"v", 1}, {"type", type}, {"id", id}, {"ts", "2026-10-26T10:30:05.400Z"}, {"src", "coordinator"}, {"data", data}};
}

QByteArray json(const QJsonObject &o)
{
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

} // namespace

class TestFleetProtocol : public QObject
{
    Q_OBJECT

private slots:
    /// The same example files the coordinator's CI checks (handoff section 5).
    void readsSchemaExamples()
    {
        const QDir dir(QStringLiteral(BRIECH_REPO_DIR "/schemas/examples"));
        const QStringList files = dir.entryList({QStringLiteral("*.valid*.json")}, QDir::Files);
        QVERIFY2(files.size() >= 10, "schemas/examples not found");
        int incoming = 0;
        for (const QString &name : files) {
            QFile file(dir.filePath(name));
            QVERIFY(file.open(QIODevice::ReadOnly));
            const QString type = name.section(QStringLiteral(".valid"), 0, 0);
            const FleetProtocol::ParseResult r = FleetProtocol::parse(file.readAll());
            if (FleetProtocol::incomingTypes().contains(type)) {
                QVERIFY2(r.error.isEmpty(), qPrintable(name + QStringLiteral(": ") + r.error));
                QCOMPARE(r.message.value("type").toString(), type);
                ++incoming;
            } else {
                // Messages QGC never receives (detection, hello, vehicle.state, ...).
                QCOMPARE(r.error, QStringLiteral("type"));
            }
        }
        QVERIFY(incoming >= 6);

        QFile wrongVersion(dir.filePath(QStringLiteral("heartbeat.invalid.version.json")));
        QVERIFY(wrongVersion.open(QIODevice::ReadOnly));
        QCOMPARE(FleetProtocol::parse(wrongVersion.readAll()).error, QStringLiteral("version"));
    }

    void parseErrors_data()
    {
        QTest::addColumn<QByteArray>("frame");
        QTest::addColumn<QString>("error");
        const QJsonObject good = msg("object.update", {{"object_id", "o-1"}});
        QJsonObject v2 = good;
        v2["v"] = 2;
        QJsonObject noData = good;
        noData.remove("data");
        QTest::newRow("ok") << json(good) << QString();
        QTest::newRow("not json") << QByteArray("{nope") << QStringLiteral("json");
        QTest::newRow("array") << QByteArray("[1]") << QStringLiteral("json");
        QTest::newRow("version 2") << json(v2) << QStringLiteral("version");
        QTest::newRow("unknown type") << json(msg("object.delete", {})) << QStringLiteral("type");
        QTest::newRow("outgoing type") << json(msg("vehicle.state", {{"vehicles", QJsonArray()}})) << QStringLiteral("type");
        QTest::newRow("no data") << json(noData) << QStringLiteral("shape");
        QTest::newRow("no object_id") << json(msg("object.update", {{"class", "person"}})) << QStringLiteral("shape");
        QTest::newRow("no alert_id") << json(msg("alert.update", {{"status", "open"}})) << QStringLiteral("shape");
        QTest::newRow("unknown fields kept") << json(msg("heartbeat", {{"seq", 1}, {"future", true}})) << QString();
    }

    void parseErrors()
    {
        QFETCH(QByteArray, frame);
        QFETCH(QString, error);
        QCOMPARE(FleetProtocol::parse(frame).error, error);
    }

    void coalesceKeys()
    {
        QCOMPARE(FleetProtocol::coalesceKey(msg("object.update", {{"object_id", "o-1"}})), QStringLiteral("object.update|o-1"));
        QCOMPARE(FleetProtocol::coalesceKey(msg("asset.state", {{"asset_id", "tower-01"}})), QStringLiteral("asset.state|tower-01"));
        QCOMPARE(FleetProtocol::coalesceKey(msg("alert.new", {{"alert_id", "a-1"}})), QStringLiteral("alert.new|a-1"));
        QCOMPARE(FleetProtocol::coalesceKey(msg("alert.update", {{"alert_id", "a-1"}})), QStringLiteral("alert.update|a-1"));
        QCOMPARE(FleetProtocol::coalesceKey(msg("heartbeat", {{"seq", 4}})), QStringLiteral("heartbeat"));
    }

    void batcherKeepsNewestInFirstArrivalOrder()
    {
        FleetBatcher batcher;
        for (int i = 1; i <= 5; ++i) {
            batcher.add(msg("object.update", {{"object_id", "o-1"}, {"n", i}}));
            if (i == 2) {
                batcher.add(msg("alert.new", {{"alert_id", "a-1"}}));
                batcher.add(msg("object.update", {{"object_id", "o-2"}, {"n", 20}}));
                batcher.add(msg("alert.update", {{"alert_id", "a-1"}, {"status", "acknowledged"}}));
            }
        }
        batcher.add(msg("alert.update", {{"alert_id", "a-1"}, {"status", "approved"}}));
        QCOMPARE(batcher.size(), 4);

        const QList<QJsonObject> batch = batcher.take();
        QVERIFY(batcher.isEmpty());
        QStringList keys;
        for (const QJsonObject &m : batch) {
            keys << FleetProtocol::coalesceKey(m);
        }
        QCOMPARE(keys, QStringList({"object.update|o-1", "alert.new|a-1", "object.update|o-2", "alert.update|a-1"}));
        QCOMPARE(batch[0]["data"].toObject()["n"].toInt(), 5);
        QCOMPARE(batch[3]["data"].toObject()["status"].toString(), QStringLiteral("approved"));
    }

    void backoffGrowsToThirtySeconds()
    {
        FleetBackoff middle([] { return 0.5; });
        QList<int> delays;
        for (int i = 0; i < 8; ++i) {
            delays << middle.nextDelayMs();
        }
        QCOMPARE(delays, QList<int>({1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000}));
        QCOMPARE(middle.attempt(), 8);
        middle.reset();
        QCOMPARE(middle.nextDelayMs(), 1000);

        FleetBackoff low([] { return 0.0; });
        QCOMPARE(low.nextDelayMs(), 800);
        FleetBackoff high([] { return 0.9999; });
        QVERIFY(high.nextDelayMs() <= 1200);
        FleetBackoff real;
        const int d = real.nextDelayMs();
        QVERIFY(d >= 800 && d <= 1200);
    }

    void makeMessageHasAFullEnvelope()
    {
        const QJsonObject a = FleetProtocol::makeMessage("vehicle.state", "qgc-op-001", {{"vehicles", QJsonArray()}});
        const QJsonObject b = FleetProtocol::makeMessage("vehicle.state", "qgc-op-001", {});
        QCOMPARE(a["v"].toInt(), 1);
        QCOMPARE(a["type"].toString(), QStringLiteral("vehicle.state"));
        QCOMPARE(a["src"].toString(), QStringLiteral("qgc-op-001"));
        QVERIFY(a["data"].isObject());
        QVERIFY(a["id"].toString() != b["id"].toString());
        static const QRegularExpression ts(QStringLiteral("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\\.\\d{3}Z$"));
        QVERIFY2(ts.match(a["ts"].toString()).hasMatch(), qPrintable(a["ts"].toString()));
        static const QRegularExpression id(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$"));
        QVERIFY(id.match(a["id"].toString()).hasMatch());
    }

    void sanitizeIds()
    {
        QCOMPARE(FleetProtocol::sanitizeId("op-001"), QStringLiteral("op-001"));
        QCOMPARE(FleetProtocol::sanitizeId("Op 001!"), QStringLiteral("op-001-"));
        QCOMPARE(FleetProtocol::sanitizeId("--x"), QStringLiteral("x"));
        QCOMPARE(FleetProtocol::sanitizeId(QString(80, 'a')).size(), 63);
    }
};

QTEST_GUILESS_MAIN(TestFleetProtocol)
#include "tst_FleetProtocol.moc"
