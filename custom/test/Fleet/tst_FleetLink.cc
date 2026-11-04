#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QSettings>
#include <QtCore/QTemporaryDir>
#include <QtNetwork/QTcpServer>
#include <QtNetwork/QTcpSocket>
#include <QtTest/QSignalSpy>
#include <QtTest/QTest>
#include <QtWebSockets/QWebSocket>
#include <QtWebSockets/QWebSocketServer>

#include "FleetLink.h"

namespace {

constexpr int kWaitMs = 5000;   // first reconnect is 0.8 to 1.2 s; this leaves room for a slow CI machine

QJsonObject message(const QString &type, const QJsonObject &data)
{
    static int n = 0;
    return {{"v", 1}, {"type", type}, {"id", QStringLiteral("t-%1").arg(++n)},
            {"ts", "2026-10-26T10:30:05.400Z"}, {"src", "coordinator"}, {"data", data}};
}

/// data.<key> of a message.
QJsonValue field(const QJsonObject &m, const char *key)
{
    return m.value("data").toObject().value(QLatin1String(key));
}

QJsonObject objectUpdate(const QString &id, int n)
{
    return message("object.update", {{"object_id", id}, {"n", n}});
}

QJsonObject snapshot()
{
    return message("snapshot", {{"assets", QJsonArray{QJsonObject{{"asset_id", "tower-01"}}}},
                                {"vehicles", QJsonArray()}, {"objects", QJsonArray()}, {"alerts", QJsonArray()}});
}

} // namespace

/// A coordinator stand-in: answers hello with a snapshot and records what QGC sends.
class FakeCoordinator : public QObject
{
    Q_OBJECT

public:
    FakeCoordinator()
    {
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        connect(&server, &QWebSocketServer::newConnection, this, [this] {
            client = server.nextPendingConnection();
            ++connections;
            authorization = client->request().rawHeader("Authorization");
            connect(client, &QWebSocket::textMessageReceived, this, [this](const QString &text) {
                const QJsonObject m = QJsonDocument::fromJson(text.toUtf8()).object();
                received.append(m);
                if (m["type"].toString() == "hello" && answerHello) {
                    send(snapshot());
                }
            });
        });
    }

    QUrl url() const { return QUrl(QStringLiteral("ws://127.0.0.1:%1/ws/v1/operator").arg(server.serverPort())); }
    void send(const QJsonObject &m) { client->sendTextMessage(QString::fromUtf8(QJsonDocument(m).toJson(QJsonDocument::Compact))); }
    void sendRaw(const QString &text) { client->sendTextMessage(text); }
    QStringList receivedTypes() const
    {
        QStringList t;
        for (const QJsonObject &m : received) {
            t << m["type"].toString();
        }
        return t;
    }

    QWebSocketServer server{QStringLiteral("fake-coordinator"), QWebSocketServer::NonSecureMode};
    QWebSocket *client = nullptr;
    QList<QJsonObject> received;
    QByteArray authorization;
    int connections = 0;
    bool answerHello = true;
};

class TestFleetLink : public QObject
{
    Q_OBJECT

private:
    FleetLinkConfig config(const QUrl &url)
    {
        FleetLinkConfig c;
        c.url = url;
        c.token = QStringLiteral("test-token");
        c.operatorId = QStringLiteral("op-test");
        c.clientVersion = QStringLiteral("test");
        return c;
    }

    /// Every message from every batch so far, in order.
    static QList<QJsonObject> batched(const QSignalSpy &spy)
    {
        QList<QJsonObject> all;
        for (const QList<QVariant> &args : spy) {
            all += args.at(0).value<QList<QJsonObject>>();
        }
        return all;
    }

private slots:
    void connectsWithTokenThenHelloThenSnapshot()
    {
        FakeCoordinator fake;
        FleetLink link;
        QSignalSpy snapshots(&link, &FleetLink::snapshotReceived);
        link.startWith(config(fake.url()));

        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);
        QCOMPARE(fake.authorization, QByteArray("Bearer test-token"));
        QCOMPARE(fake.receivedTypes(), QStringList{"hello"});
        const QJsonObject hello = fake.received.first();
        QCOMPARE(hello["src"].toString(), QStringLiteral("qgc-op-test"));
        QCOMPARE(hello["data"]["operator_id"].toString(), QStringLiteral("op-test"));
        QCOMPARE(hello["data"]["client"].toString(), QStringLiteral("qgc"));
        QCOMPARE(snapshots.count(), 1);
        QCOMPARE(snapshots.first().at(0).toJsonObject()["assets"].toArray().size(), 1);
        QCOMPARE(link.stateText(), QStringLiteral("CONNECTED"));
        QVERIFY(link.lastError().isEmpty());
        QVERIFY(link.recentMessages().first().contains("snapshot 1 assets"));
    }

    void batchesKeepNewestPerObject()
    {
        FakeCoordinator fake;
        FleetLink link;
        QSignalSpy batches(&link, &FleetLink::batchReceived);
        link.startWith(config(fake.url()));
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);

        for (int n = 1; n <= 5; ++n) {
            fake.send(objectUpdate("o-1", n));
            if (n == 2) {
                fake.send(objectUpdate("o-2", 20));
            }
        }
        QTRY_VERIFY_WITH_TIMEOUT(!batches.isEmpty(), kWaitMs);
        QTRY_VERIFY_WITH_TIMEOUT(field(batched(batches).last(), "n").toInt() == 5
                                     || field(batched(batches).last(), "n").toInt() == 20, kWaitMs);
        QTest::qWait(300);

        // Within one batch each object appears once; across batches the last value wins.
        QHash<QString, int> latest;
        for (const QList<QVariant> &args : batches) {
            QSet<QString> seen;
            for (const QJsonObject &m : args.at(0).value<QList<QJsonObject>>()) {
                const QString id = field(m, "object_id").toString();
                QVERIFY2(!seen.contains(id), "a batch carried the same object twice");
                seen.insert(id);
                latest[id] = field(m, "n").toInt();
            }
        }
        QCOMPARE(latest.value("o-1"), 5);
        QCOMPARE(latest.value("o-2"), 20);
        QVERIFY(batched(batches).size() < 6);
    }

    void dropsWhatItCannotUse()
    {
        FakeCoordinator fake;
        FleetLink link;
        QSignalSpy batches(&link, &FleetLink::batchReceived);
        link.startWith(config(fake.url()));
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);

        QJsonObject v2 = objectUpdate("o-9", 1);
        v2["v"] = 2;
        fake.send(v2);
        fake.send(message("object.delete", {{"object_id", "o-9"}}));
        fake.send(message("object.update", {{"class", "person"}}));
        fake.sendRaw(QStringLiteral("{not json"));
        fake.send(objectUpdate("o-1", 1));

        QTRY_COMPARE_WITH_TIMEOUT(link.droppedCount(), 4, kWaitMs);
        QTRY_COMPARE_WITH_TIMEOUT(batched(batches).size(), 1, kWaitMs);
        QCOMPARE(field(batched(batches).first(), "object_id").toString(), QStringLiteral("o-1"));
        QCOMPARE(link.state(), FleetLink::Connected);
    }

    void nothingBeforeTheSnapshot()
    {
        FakeCoordinator fake;
        fake.answerHello = false;
        FleetLink link;
        QSignalSpy batches(&link, &FleetLink::batchReceived);
        QSignalSpy snapshots(&link, &FleetLink::snapshotReceived);
        link.startWith(config(fake.url()));
        QTRY_COMPARE_WITH_TIMEOUT(fake.receivedTypes(), QStringList{"hello"}, kWaitMs);

        fake.send(objectUpdate("o-early", 1));
        QTRY_COMPARE_WITH_TIMEOUT(link.droppedCount(), 1, kWaitMs);
        QCOMPARE(link.state(), FleetLink::Connecting);
        fake.send(snapshot());
        fake.send(objectUpdate("o-1", 1));
        QTRY_COMPARE_WITH_TIMEOUT(batched(batches).size(), 1, kWaitMs);
        QCOMPARE(snapshots.count(), 1);
        QCOMPARE(field(batched(batches).first(), "object_id").toString(), QStringLiteral("o-1"));
    }

    void reconnectsWithoutRestarting()
    {
        FakeCoordinator fake;
        FleetLink link;
        QSignalSpy snapshots(&link, &FleetLink::snapshotReceived);
        link.startWith(config(fake.url()));
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);

        fake.client->close();
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Retrying, kWaitMs);
        QCOMPARE(link.retryAttempt(), 1);
        QVERIFY(link.retryInSeconds() >= 1 && link.retryInSeconds() <= 2);
        QVERIFY(link.stateText().startsWith("RETRYING IN"));

        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);
        QCOMPARE(fake.connections, 2);
        QCOMPARE(snapshots.count(), 2);
        QCOMPARE(fake.receivedTypes(), QStringList({"hello", "hello"}));
        QCOMPARE(link.retryAttempt(), 0);   // reset by the snapshot
    }

    void retriesWithGrowingDelaysWhileTheCoordinatorIsDown()
    {
        auto *fake = new FakeCoordinator;
        const QUrl url = fake->url();
        FleetLink link;
        link.startWith(config(url));
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);

        delete fake;    // the coordinator is gone: listener closed and connection dropped
        QTRY_COMPARE_WITH_TIMEOUT(link.retryAttempt(), 1, kWaitMs);
        QTRY_COMPARE_WITH_TIMEOUT(link.retryAttempt(), 2, kWaitMs);
        QCOMPARE(link.state(), FleetLink::Retrying);
        QVERIFY2(link.retryInSeconds() >= 2, "second retry should wait about 2 s");
        QVERIFY(!link.lastError().isEmpty());
    }

    void unauthorizedIsItsOwnState_data()
    {
        QTest::addColumn<QByteArray>("response");
        QTest::newRow("bearer challenge, as the coordinator sends")
            << QByteArray("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Bearer\r\nContent-Length: 0\r\n\r\n");
        QTest::newRow("no challenge") << QByteArray("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n");
    }

    void unauthorizedIsItsOwnState()
    {
        QFETCH(QByteArray, response);
        QTcpServer http;
        QVERIFY(http.listen(QHostAddress::LocalHost, 0));
        connect(&http, &QTcpServer::newConnection, this, [&http, response] {
            QTcpSocket *s = http.nextPendingConnection();
            connect(s, &QTcpSocket::readyRead, s, [s, response] {
                s->readAll();
                s->write(response);
                s->disconnectFromHost();
            });
        });
        FleetLink link;
        link.startWith(config(QUrl(QStringLiteral("ws://127.0.0.1:%1/ws/v1/operator").arg(http.serverPort()))));
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Unauthorized, kWaitMs);
        QVERIFY2(link.lastError().contains("401"), qPrintable(link.lastError()));
        QVERIFY(link.retryInSeconds() > 20);    // retried slowly, at the 30 s cap
        QVERIFY(!link.lastError().contains("test-token"));
    }

    void noTokenNoConnection()
    {
        FakeCoordinator fake;
        FleetLink link;
        FleetLinkConfig c = config(fake.url());
        c.token.clear();
        link.startWith(c);
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Unauthorized, kWaitMs);
        QVERIFY(link.lastError().contains("Fleet/token"));
        QTest::qWait(200);
        QCOMPARE(fake.connections, 0);
    }

    void operatorActionWaitsForTheConnection()
    {
        FakeCoordinator fake;
        fake.answerHello = false;
        FleetLink link;
        link.startWith(config(fake.url()));
        QTRY_COMPARE_WITH_TIMEOUT(fake.receivedTypes(), QStringList{"hello"}, kWaitMs);

        // Connected at TCP level, but no snapshot yet: not Connected.
        link.sendMessage("vehicle.state", {{"vehicles", QJsonArray()}});
        link.sendMessage("operator.action", {{"action_id", "act-1"}, {"operator_id", "op-test"}, {"phase", "command"},
                                             {"vehicle_id", 3}, {"command", "hold"}});
        QTRY_COMPARE_WITH_TIMEOUT(link.droppedCount(), 1, kWaitMs);    // the vehicle.state
        QTest::qWait(100);
        QCOMPARE(fake.receivedTypes(), QStringList{"hello"});

        fake.send(snapshot());
        QTRY_COMPARE_WITH_TIMEOUT(fake.receivedTypes(), QStringList({"hello", "operator.action"}), kWaitMs);
        const QJsonObject action = fake.received.last();
        QCOMPARE(action["src"].toString(), QStringLiteral("qgc-op-test"));
        QCOMPARE(action["data"]["command"].toString(), QStringLiteral("hold"));

        link.sendMessage("vehicle.state", {{"vehicles", QJsonArray()}});
        link.sendMessage("hello", {});      // not something QGC sends after connecting: refused
        QTRY_COMPARE_WITH_TIMEOUT(fake.receivedTypes().last(), QStringLiteral("vehicle.state"), kWaitMs);
        QTest::qWait(100);
        QCOMPARE(fake.receivedTypes(), QStringList({"hello", "operator.action", "vehicle.state"}));
    }

    void silenceDropsTheSocketAndRaisesTheBanner()
    {
        FakeCoordinator fake;
        FleetLink link;
        FleetLinkConfig c = config(fake.url());
        c.silenceTimeoutMs = 1500;
        link.startWith(c);
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);
        QVERIFY(!link.coordinatorSilent());

        // The fake sends nothing after the snapshot: no heartbeat.
        QTRY_VERIFY_WITH_TIMEOUT(link.coordinatorSilent(), kWaitMs);
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Retrying, kWaitMs);
        QVERIFY2(link.lastError().contains("nothing heard"), qPrintable(link.lastError()));

        // It reconnects, the next snapshot clears the banner.
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);
        QVERIFY(!link.coordinatorSilent());
    }

    void stopIsFinal()
    {
        FakeCoordinator fake;
        FleetLink link;
        link.startWith(config(fake.url()));
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);
        link.stop();
        QCOMPARE(link.state(), FleetLink::Disabled);
        QCOMPARE(link.stateText(), QStringLiteral("DISABLED"));
        QTest::qWait(1500);
        QCOMPARE(fake.connections, 1);
        QCOMPARE(link.state(), FleetLink::Disabled);

        // And it can be started again.
        link.startWith(config(fake.url()));
        QTRY_COMPARE_WITH_TIMEOUT(link.state(), FleetLink::Connected, kWaitMs);
        QCOMPARE(fake.connections, 2);
    }

    void startObeysFleetEnabled()
    {
        // Settings go to a throwaway ini file, as in QGC (which uses IniFormat), never the user's own.
        QTemporaryDir dir;
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, dir.path());
        QCoreApplication::setOrganizationName(QStringLiteral("BriechFleetTest"));
        QCoreApplication::setApplicationName(QStringLiteral("tst_FleetLink"));
        QSettings().setValue("Fleet/enabled", false);
        FleetLink link;
        link.start();
        QTest::qWait(100);
        QCOMPARE(link.state(), FleetLink::Disabled);
    }
};

QTEST_GUILESS_MAIN(TestFleetLink)
#include "tst_FleetLink.moc"
