#include <QtTest/QSignalSpy>
#include <QtTest/QTest>

#include "FleetDataAge.h"

/// The handoff's data-age rule for drones: amber when the last report is older
/// than 3 s, grey (stale) when older than 10 s, "--" when never heard.
class tst_FleetDataAge : public QObject
{
    Q_OBJECT

private slots:
    void levelsFollowTheHandoffThresholds_data()
    {
        QTest::addColumn<qint64>("ageMs");
        QTest::addColumn<int>("level");
        QTest::newRow("never heard") << qint64(-1) << int(FleetDataAge::Unknown);
        QTest::newRow("just now") << qint64(0) << int(FleetDataAge::Fresh);
        QTest::newRow("3.0 s") << qint64(3000) << int(FleetDataAge::Fresh);
        QTest::newRow("3.1 s") << qint64(3100) << int(FleetDataAge::Amber);
        QTest::newRow("10.0 s") << qint64(10000) << int(FleetDataAge::Amber);
        QTest::newRow("10.1 s") << qint64(10100) << int(FleetDataAge::Grey);
    }

    void levelsFollowTheHandoffThresholds()
    {
        QFETCH(qint64, ageMs);
        QFETCH(int, level);
        QCOMPARE(int(FleetDataAge::levelForMs(ageMs)), level);
    }

    void agesAndLevelsArePublishedPerVehicle()
    {
        qint64 now = 1000;
        FleetDataAge ages;
        ages.setClock([&now] { return now; });
        ages.setActive(true);
        QSignalSpy changed(&ages, &FleetDataAge::secondsChanged);

        ages.heard(1);
        ages.heard(2);
        ages.refresh();
        QCOMPARE(changed.count(), 1);
        QCOMPARE(ages.seconds().value("1").toInt(), 0);
        QCOMPARE(ages.levels().value("2").toInt(), int(FleetDataAge::Fresh));
        QVERIFY(!ages.seconds().contains("3"));                  // never heard: "--"
        QCOMPARE(ages.secondsFor(3), -1);

        now += 4000;                                              // drone 2 goes quiet
        ages.heard(1);
        ages.refresh();
        QCOMPARE(ages.levelOf(1), int(FleetDataAge::Fresh));
        QCOMPARE(ages.levelOf(2), int(FleetDataAge::Amber));
        QCOMPARE(ages.seconds().value("2").toInt(), 4);

        now += 7000;
        ages.heard(1);
        ages.refresh();
        QCOMPARE(ages.levels().value("2").toInt(), int(FleetDataAge::Grey));

        ages.heard(2);                                            // and comes back
        ages.refresh();
        QCOMPARE(ages.levelOf(2), int(FleetDataAge::Fresh));
    }

    void noSignalWhenNothingShownChanges()
    {
        qint64 now = 0;
        FleetDataAge ages;
        ages.setClock([&now] { return now; });
        ages.setActive(true);
        ages.heard(1);
        ages.refresh();
        QSignalSpy changed(&ages, &FleetDataAge::secondsChanged);
        now += 400;
        ages.heard(1);
        ages.refresh();
        QCOMPARE(changed.count(), 0);                             // still 0 s and fresh
    }

    void inactiveTracksNothingAndStoppingForgets()
    {
        qint64 now = 0;
        FleetDataAge ages;
        ages.setClock([&now] { return now; });
        ages.heard(1);                                            // Fleet off
        QCOMPARE(ages.secondsFor(1), -1);
        ages.setActive(true);
        ages.heard(1);
        ages.refresh();
        QVERIFY(ages.seconds().contains("1"));
        ages.setActive(false);
        QVERIFY(ages.seconds().isEmpty());
        QCOMPARE(ages.secondsFor(1), -1);
    }

    void forgetRemovesAVehicle()
    {
        qint64 now = 0;
        FleetDataAge ages;
        ages.setClock([&now] { return now; });
        ages.setActive(true);
        ages.heard(4);
        ages.refresh();
        ages.forget(4);
        QVERIFY(!ages.seconds().contains("4"));
    }
};

QTEST_GUILESS_MAIN(tst_FleetDataAge)
#include "tst_FleetDataAge.moc"
