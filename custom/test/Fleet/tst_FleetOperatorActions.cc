#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QRegularExpression>
#include <QtTest/QSignalSpy>
#include <QtTest/QTest>
#include <QtWebSockets/QWebSocket>
#include <QtWebSockets/QWebSocketServer>

#include "FleetLink.h"
#include "FleetOperatorActions.h"

namespace {

using Command = FleetOperatorActions::Command;
using Outcome = FleetOperatorActions::Outcome;

constexpr int kWaitMs = 5000;

/// data of a message from schemas/examples, the files the coordinator's CI checks.
QJsonObject exampleData(const QString &name)
{
    QFile file(QStringLiteral(BRIECH_REPO_DIR "/schemas/examples/") + name + QStringLiteral(".json"));
    if (!file.open(QIODevice::ReadOnly)) {
        qFatal("missing schemas/examples/%s.json", qPrintable(name));
    }
    return QJsonDocument::fromJson(file.readAll()).object().value("data").toObject();
}

QStringList sortedKeys(const QJsonObject &o)
{
    QStringList keys = o.keys();
    keys.sort();
    return keys;
}

/// Collects what FleetOperatorActions hands to FleetLink.
struct Recorder
{
    QList<QJsonObject> records;
    FleetOperatorActions::Sender sender()
    {
        return [this](const QString &type, const QJsonObject &data) {
            QCOMPARE(type, QStringLiteral("operator.action"));
            records.append(data);
        };
    }
    QStringList phases() const
    {
        QStringList p;
        for (const QJsonObject &r : records) {
            p << r["phase"].toString();
        }
        return p;
    }
};

} // namespace

class TestFleetOperatorActions : public QObject
{
    Q_OBJECT

private slots:
    void approvalRunsDecisionCommandOutcomeUnderOneId()
    {
        Recorder rec;
        FleetOperatorActions actions(rec.sender());
        actions.setOperatorId(QStringLiteral("op-001"));
        QSignalSpy outcomes(&actions, &FleetOperatorActions::outcomeReported);

        const QString id = actions.newActionId(QStringLiteral("a-102"));
        actions.decision(id, QStringLiteral("a-102"), true, 3, Command::Orbit, false);
        actions.command(id, 3, Command::Orbit, QStringLiteral("a-102"));
        QCOMPARE(actions.pending(3), std::optional<Command>(Command::Orbit));
        actions.resolve(3, Outcome::Confirmed);
        QVERIFY(!actions.pending(3));

        QCOMPARE(rec.phases(), QStringList({"decision", "command", "outcome"}));
        for (const QJsonObject &r : rec.records) {
            QCOMPARE(r["action_id"].toString(), id);
            QCOMPARE(r["operator_id"].toString(), QStringLiteral("op-001"));
            QCOMPARE(r["alert_id"].toString(), QStringLiteral("a-102"));
        }
        // Field for field the shape of the schema's own examples.
        QCOMPARE(sortedKeys(rec.records[0]), sortedKeys(exampleData("operator.action.valid")));
        QCOMPARE(sortedKeys(rec.records[2]), sortedKeys(exampleData("operator.action.valid.outcome")));
        QCOMPARE(rec.records[2]["outcome"].toString(), QStringLiteral("confirmed"));
        QCOMPARE(rec.records[2]["command"].toString(), QStringLiteral("orbit"));
        QCOMPARE(outcomes.count(), 1);
    }

    void holdAllUsesOneIdPerVehicle()
    {
        Recorder rec;
        FleetOperatorActions actions(rec.sender());
        actions.setOperatorId(QStringLiteral("op-001"));
        const QString press = actions.newActionId(QStringLiteral("holdall"));
        actions.command(press + "-v1", 1, Command::Hold);
        actions.command(press + "-v2", 2, Command::Hold);
        actions.resolve(2, Outcome::Refused, QStringLiteral("vehicle denied the command"));
        actions.resolve(1, Outcome::Confirmed);

        QCOMPARE(rec.phases(), QStringList({"command", "command", "outcome", "outcome"}));
        QCOMPARE(sortedKeys(rec.records[0]), sortedKeys(exampleData("operator.action.valid.hold-all")));
        QCOMPARE(rec.records[2]["action_id"].toString(), press + "-v2");
        QCOMPARE(rec.records[2]["outcome"].toString(), QStringLiteral("refused"));
        QCOMPARE(rec.records[2]["detail"].toString(), QStringLiteral("vehicle denied the command"));
        QCOMPARE(rec.records[3]["action_id"].toString(), press + "-v1");
        QVERIFY(!rec.records[0].contains("alert_id"));
    }

    void actionIdsMatchTheSchemaAndNeverRepeat()
    {
        Recorder rec;
        FleetOperatorActions actions(rec.sender());
        const QRegularExpression pattern(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$"));
        QSet<QString> seen;
        for (int i = 0; i < 50; ++i) {
            const QString id = actions.newActionId(i % 2 ? QStringLiteral("holdall") : QStringLiteral("a-%1").arg(QString(120, 'x')));
            QVERIFY2(pattern.match(id).hasMatch(), qPrintable(id));
            QVERIFY(!seen.contains(id));
            seen.insert(id);
        }
    }

    void rejectionIsADecisionOnly()
    {
        Recorder rec;
        FleetOperatorActions actions(rec.sender());
        actions.decision(actions.newActionId("a-7"), "a-7", false, 2, Command::Goto, false);
        QCOMPARE(rec.phases(), QStringList({"decision"}));
        QCOMPARE(rec.records[0]["decision"].toString(), QStringLiteral("reject"));
        QVERIFY(!actions.pending(2));
    }

    void staleDataIsMarkedOnEveryPhase()
    {
        Recorder rec;
        FleetOperatorActions actions(rec.sender());
        actions.decision("act-1", "a-1", true, 3, Command::Goto, true);
        actions.command("act-1", 3, Command::Goto, "a-1", true);
        actions.resolve(3, Outcome::Confirmed);
        for (const QJsonObject &r : rec.records) {
            QCOMPARE(r["extra_confirmation"].toBool(), true);
        }
    }

    void noAnswerTimesOutAsNoResponse()
    {
        Recorder rec;
        FleetOperatorActions actions(rec.sender());
        actions.setOutcomeTimeoutMs(200);
        QSignalSpy outcomes(&actions, &FleetOperatorActions::outcomeReported);
        actions.command("act-2", 4, Command::Return);
        QTRY_COMPARE_WITH_TIMEOUT(outcomes.count(), 1, 2000);
        QCOMPARE(rec.records.last()["outcome"].toString(), QStringLiteral("no_response"));
        QCOMPARE(outcomes.first().at(2).toString(), QStringLiteral("no_response"));
        QVERIFY(!actions.pending(4));

        // A late answer after the timeout changes nothing.
        actions.resolve(4, Outcome::Confirmed);
        QCOMPARE(rec.records.size(), 2);
    }

    void newerCommandSupersedesAWaitingOne()
    {
        Recorder rec;
        FleetOperatorActions actions(rec.sender());
        actions.setOutcomeTimeoutMs(300);
        actions.command("act-a", 5, Command::Hold);
        actions.command("act-b", 5, Command::Return);
        QCOMPARE(rec.phases(), QStringList({"command", "outcome", "command"}));
        QCOMPARE(rec.records[1]["action_id"].toString(), QStringLiteral("act-a"));
        QCOMPARE(rec.records[1]["outcome"].toString(), QStringLiteral("no_response"));
        QCOMPARE(actions.pending(5), std::optional<Command>(Command::Return));

        // Only the newer command's timer may settle it.
        QTest::qWait(450);
        QCOMPARE(rec.phases(), QStringList({"command", "outcome", "command", "outcome"}));
        QCOMPARE(rec.records[3]["action_id"].toString(), QStringLiteral("act-b"));
    }

    void recordsQueueInFleetLinkWhileOffline()
    {
        // A coordinator that accepts the socket but has not sent its snapshot:
        // FleetLink is not Connected yet, so it must queue operator.action.
        QWebSocketServer server(QStringLiteral("fake-coordinator"), QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        QWebSocket *client = nullptr;
        QList<QJsonObject> received;
        connect(&server, &QWebSocketServer::newConnection, this, [&] {
            client = server.nextPendingConnection();
            connect(client, &QWebSocket::textMessageReceived, this, [&](const QString &text) {
                received.append(QJsonDocument::fromJson(text.toUtf8()).object());
            });
        });

        FleetLink link;
        FleetLinkConfig config;
        config.url = QUrl(QStringLiteral("ws://127.0.0.1:%1/ws/v1/operator").arg(server.serverPort()));
        config.token = QStringLiteral("test-token");
        config.operatorId = QStringLiteral("op-test");
        link.startWith(config);
        QTRY_VERIFY_WITH_TIMEOUT(!received.isEmpty(), kWaitMs);     // hello
        QCOMPARE(received.first()["type"].toString(), QStringLiteral("hello"));
        QVERIFY(link.state() != FleetLink::Connected);

        FleetOperatorActions actions([&link](const QString &type, const QJsonObject &data) { link.sendMessage(type, data); });
        actions.setOperatorId(QStringLiteral("op-test"));
        actions.command("act-q", 1, Command::Hold);
        actions.resolve(1, Outcome::Confirmed);
        QTest::qWait(300);
        QCOMPARE(received.size(), 1);                                // nothing sent yet
        QCOMPARE(link.droppedCount(), 0);                            // and nothing dropped

        const QJsonObject snapshot{{"v", 1}, {"type", "snapshot"}, {"id", "s-1"}, {"ts", "2026-10-26T10:30:05.400Z"},
                                   {"src", "coordinator"},
                                   {"data", QJsonObject{{"assets", QJsonArray()}, {"vehicles", QJsonArray()},
                                                        {"objects", QJsonArray()}, {"alerts", QJsonArray()}}}};
        client->sendTextMessage(QString::fromUtf8(QJsonDocument(snapshot).toJson(QJsonDocument::Compact)));
        QTRY_COMPARE_WITH_TIMEOUT(received.size(), 3, kWaitMs);
        QCOMPARE(received[1]["type"].toString(), QStringLiteral("operator.action"));
        QCOMPARE(received[1]["data"].toObject()["phase"].toString(), QStringLiteral("command"));
        QCOMPARE(received[2]["data"].toObject()["phase"].toString(), QStringLiteral("outcome"));
        QCOMPARE(received[2]["src"].toString(), QStringLiteral("qgc-op-test"));
        link.stop();
    }
};

QTEST_GUILESS_MAIN(TestFleetOperatorActions)
#include "tst_FleetOperatorActions.moc"
