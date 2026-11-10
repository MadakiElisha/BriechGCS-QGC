#include <QtCore/QFile>
#include <QtCore/QTemporaryDir>
#include <QtCore/QTimeZone>
#include <QtTest/QTest>

#include "FleetAudit.h"

/// FleetAudit: the local hash-chained log of operator actions.
class tst_FleetAudit : public QObject
{
    Q_OBJECT

private:
    static QDateTime at(int ms)
    {
        return QDateTime(QDate(2026, 10, 26), QTime(10, 30, 5, 400), QTimeZone::UTC).addMSecs(ms);
    }

    static QJsonObject action(const QString &id, const QString &decision)
    {
        return {{"action_id", id}, {"operator_id", "op-001"}, {"phase", "decision"}, {"decision", decision}};
    }

private slots:
    void hashMatchesTheCoordinatorsRule()
    {
        // Same value as Python: sha256("1|2026-10-26T10:30:05.400Z|operator.action|{\"a\":1}|" + "0"*64)
        QCOMPARE(FleetAudit::entryHash(1, "2026-10-26T10:30:05.400Z", "operator.action", "{\"a\":1}", FleetAudit::genesis()),
                 QStringLiteral("5ae8572b7877a059d29b36c54493d106565a29d2dbf10b667c470cd62feb12c7"));
        QCOMPARE(FleetAudit::canonical({{"b", 2}, {"a", 1}}), QStringLiteral("{\"a\":1,\"b\":2}"));
    }

    void appendsAChainThatVerifiesAndSurvivesARestart()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("sub/fleet-audit.jsonl");     // folder created on first write
        {
            FleetAudit audit(path);
            int ms = 0;
            audit.setClock([&ms] { return at(ms += 100); });
            QVERIFY(audit.append("operator.action", action("act-1", "approve")));
            QVERIFY(audit.append("operator.action", action("act-2", "reject")));
            QCOMPARE(audit.count(), 2);
            QCOMPARE(audit.verify().value("ok").toBool(), true);
        }
        FleetAudit reopened(path);                                       // continues the chain
        QCOMPARE(reopened.count(), 2);
        QVERIFY(reopened.append("operator.action", action("act-3", "approve")));
        const QVariantMap result = reopened.verify();
        QCOMPARE(result.value("ok").toBool(), true);
        QCOMPARE(result.value("entries").toInt(), 3);
        QCOMPARE(result.value("firstBroken").toInt(), -1);

        const QVariantList newest = reopened.recent(2);
        QCOMPARE(newest.size(), 2);
        QCOMPARE(newest.first().toMap().value("seq").toInt(), 3);
    }

    void anEditedLineIsReportedAsTheFirstBroken()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("fleet-audit.jsonl");
        FleetAudit audit(path);
        for (int i = 1; i <= 3; ++i) {
            QVERIFY(audit.append("operator.action", action(QStringLiteral("act-%1").arg(i), "approve")));
        }
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QByteArray text = file.readAll();
        file.close();
        text.replace("\"act-2\"", "\"act-X\"");                         // change entry 2's payload
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write(text);
        file.close();

        const QVariantMap result = audit.verify();
        QCOMPARE(result.value("ok").toBool(), false);
        QCOMPARE(result.value("firstBroken").toInt(), 2);
    }

    void aRemovedLineBreaksTheChain()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("fleet-audit.jsonl");
        FleetAudit audit(path);
        for (int i = 1; i <= 3; ++i) {
            QVERIFY(audit.append("operator.action", action(QStringLiteral("act-%1").arg(i), "approve")));
        }
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QList<QByteArray> lines = file.readAll().split('\n');
        file.close();
        lines.removeAt(0);
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write(lines.join('\n'));
        file.close();
        QCOMPARE(audit.verify().value("firstBroken").toInt(), 1);
    }

    void anUnwritableFileReportsAnError()
    {
        QTemporaryDir dir;
        FleetAudit audit(dir.path());                                    // a folder, not a file
        QVERIFY(!audit.append("operator.action", action("act-1", "approve")));
        QVERIFY(!audit.lastError().isEmpty());
        QCOMPARE(audit.count(), 0);
    }
};

QTEST_GUILESS_MAIN(tst_FleetAudit)
#include "tst_FleetAudit.moc"
