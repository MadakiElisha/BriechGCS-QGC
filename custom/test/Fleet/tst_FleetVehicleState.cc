#include <cmath>

#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtTest/QTest>

#include "FleetProtocol.h"
#include "FleetVehicleState.h"

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

/// The drone in vehicle.state.valid.json, as QGC would see it.
FleetVehicleSample exampleSample()
{
    FleetVehicleSample s;
    s.id = 3;
    s.mode = QStringLiteral("Auto");
    s.armed = true;
    s.flying = true;
    s.lat = 6.5244;
    s.lon = 3.3792;
    s.altRelM = 80.0;
    s.altAmslM = 112.0;
    s.headingDeg = 212.0;
    s.groundSpeedMs = 11.2;
    s.batteryPct = 74.0;
    s.linkLossPct = 8.0;
    s.canArm = true;
    return s;
}

/// Only the five fields the schema requires; nothing else known.
FleetVehicleSample bareSample(int id)
{
    FleetVehicleSample s;
    s.id = id;
    s.mode = QStringLiteral("Hold");
    return s;
}

QStringList sortedKeys(const QJsonObject &o)
{
    QStringList keys = o.keys();
    keys.sort();
    return keys;
}

} // namespace

class TestFleetVehicleState : public QObject
{
    Q_OBJECT

private slots:
    void matchesTheSchemaExample()
    {
        const QJsonObject expected = example(QStringLiteral("vehicle.state.valid"));
        const QJsonObject expectedVehicle = expected["data"]["vehicles"].toArray().at(0).toObject();

        const QJsonObject message = FleetProtocol::makeMessage(QStringLiteral("vehicle.state"), QStringLiteral("qgc-op-001"),
                                                               FleetVehicleState::reportData({exampleSample()}));
        QCOMPARE(sortedKeys(message), sortedKeys(expected));
        QCOMPARE(sortedKeys(message["data"].toObject()), sortedKeys(expected["data"].toObject()));

        QJsonObject vehicle = message["data"]["vehicles"].toArray().at(0).toObject();
        QCOMPARE(sortedKeys(vehicle), sortedKeys(expectedVehicle));
        QCOMPARE(vehicle["name"].toString(), QStringLiteral("BRCH-3"));     // the name the Fleet pages use
        vehicle["name"] = expectedVehicle["name"];
        QCOMPARE(vehicle, expectedVehicle);
    }

    void missingDataIsLeftOut()
    {
        const QJsonObject vehicle = FleetVehicleState::vehicleJson(bareSample(2));
        QCOMPARE(sortedKeys(vehicle), QStringList({"armed", "flying", "mode", "name", "vehicle_id"}));
        QCOMPARE(vehicle["vehicle_id"].toInt(), 2);
        QCOMPARE(vehicle["armed"].toBool(), false);

        // A position without altitudes carries only lat and lon; never a bare alt.
        FleetVehicleSample s = bareSample(2);
        s.lat = 8.89;
        s.lon = 7.26;
        const QJsonObject pos = FleetVehicleState::vehicleJson(s)["pos"].toObject();
        QCOMPARE(sortedKeys(pos), QStringList({"lat", "lon"}));

        // Altitudes without a position are not sent either.
        s = bareSample(2);
        s.altRelM = 10.0;
        QVERIFY(!FleetVehicleState::vehicleJson(s).contains("pos"));
    }

    void notANumberIsLeftOut()
    {
        FleetVehicleSample s = bareSample(1);
        s.batteryPct = NAN;
        s.headingDeg = NAN;
        s.groundSpeedMs = INFINITY;
        s.linkLossPct = NAN;
        s.lat = NAN;
        s.lon = 7.26;
        const QJsonObject vehicle = FleetVehicleState::vehicleJson(s);
        QCOMPARE(sortedKeys(vehicle), QStringList({"armed", "flying", "mode", "name", "vehicle_id"}));
    }

    void valuesFitTheSchema()
    {
        // The two mistakes vehicle.state.invalid.battery-and-heading.json makes.
        FleetVehicleSample s = bareSample(3);
        s.headingDeg = 360.0;
        s.batteryPct = 74.5;
        QJsonObject vehicle = FleetVehicleState::vehicleJson(s);
        QCOMPARE(vehicle["heading_deg"].toDouble(), 0.0);
        QCOMPARE(vehicle["battery_pct"].toDouble(), 75.0);
        QCOMPARE(vehicle["battery_pct"].toDouble(), std::floor(vehicle["battery_pct"].toDouble()));

        s.headingDeg = -10.0;
        s.groundSpeedMs = -0.2;     // noise around zero
        s.linkLossPct = 7.6;
        s.batteryPct = 140.0;
        vehicle = FleetVehicleState::vehicleJson(s);
        QCOMPARE(vehicle["heading_deg"].toDouble(), 350.0);
        QCOMPARE(vehicle["groundspeed_ms"].toDouble(), 0.0);
        QCOMPARE(vehicle["link_quality_pct"].toInt(), 92);
        QCOMPARE(vehicle["battery_pct"].toInt(), 100);

        s.mode = QString(100, QLatin1Char('x'));
        QCOMPARE(FleetVehicleState::vehicleJson(s)["mode"].toString().size(), 64);
    }

    void unreportableVehiclesAreSkipped()
    {
        FleetVehicleSample lost = exampleSample();
        lost.commsLost = true;
        QVERIFY(FleetVehicleState::vehicleJson(lost).isEmpty());
        QVERIFY(FleetVehicleState::vehicleJson(bareSample(0)).isEmpty());
        QVERIFY(FleetVehicleState::vehicleJson(bareSample(256)).isEmpty());
        QVERIFY(!FleetVehicleState::vehicleJson(bareSample(255)).isEmpty());

        const QJsonArray vehicles = FleetVehicleState::reportData({lost, bareSample(1), bareSample(0)})["vehicles"].toArray();
        QCOMPARE(vehicles.size(), 1);
        QCOMPARE(vehicles.at(0)["vehicle_id"].toInt(), 1);
    }

    void reportIsCappedAtTheSchemaLimit()
    {
        QList<FleetVehicleSample> samples;
        for (int id = 1; id <= 70; ++id) {
            samples.append(bareSample(id));
        }
        QCOMPARE(FleetVehicleState::reportData(samples)["vehicles"].toArray().size(), FleetVehicleState::kMaxVehicles);
    }

    void canTakeTask_data()
    {
        QTest::addColumn<QVariant>("battery");     // invalid: unknown
        QTest::addColumn<bool>("armed");
        QTest::addColumn<QVariant>("canArm");      // invalid: not reported
        QTest::addColumn<QVariant>("expected");    // invalid: left out

        QTest::newRow("battery unknown") << QVariant() << false << QVariant(true) << QVariant();
        QTest::newRow("battery at the low mark") << QVariant(20.0) << true << QVariant(true) << QVariant(false);
        QTest::newRow("armed, battery fine") << QVariant(21.0) << true << QVariant() << QVariant(true);
        QTest::newRow("ready to arm") << QVariant(80.0) << false << QVariant(true) << QVariant(true);
        QTest::newRow("not ready to arm") << QVariant(80.0) << false << QVariant(false) << QVariant(false);
        QTest::newRow("checks not reported") << QVariant(80.0) << false << QVariant() << QVariant();
    }

    void canTakeTask()
    {
        QFETCH(QVariant, battery);
        QFETCH(bool, armed);
        QFETCH(QVariant, canArm);
        QFETCH(QVariant, expected);

        FleetVehicleSample s = bareSample(4);
        if (battery.isValid()) {
            s.batteryPct = battery.toDouble();
        }
        s.armed = armed;
        if (canArm.isValid()) {
            s.canArm = canArm.toBool();
        }
        const QJsonObject vehicle = FleetVehicleState::vehicleJson(s);
        QCOMPARE(vehicle.contains("can_take_task"), expected.isValid());
        if (expected.isValid()) {
            QCOMPARE(vehicle["can_take_task"].toBool(), expected.toBool());
        }
    }
};

QTEST_GUILESS_MAIN(TestFleetVehicleState)
#include "tst_FleetVehicleState.moc"
