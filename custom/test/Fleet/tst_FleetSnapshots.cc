#include <QtCore/QBuffer>
#include <QtCore/QCryptographicHash>
#include <QtGui/QImage>
#include <QtNetwork/QTcpServer>
#include <QtNetwork/QTcpSocket>
#include <QtTest/QSignalSpy>
#include <QtTest/QTest>

#include "FleetSnapshots.h"

namespace {

QByteArray jpeg(int width = 64, int height = 48)
{
    QImage image(width, height, QImage::Format_RGB32);
    image.fill(QColor(30, 120, 200));
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "JPEG");
    return bytes;
}

QString sha(const QByteArray &bytes)
{
    return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
}

/// One-shot HTTP server: records the request it gets and answers with a fixed response.
class TinyHttp : public QObject
{
public:
    QByteArray request;
    QByteArray response;

    TinyHttp()
    {
        _server.listen(QHostAddress::LocalHost);
        QObject::connect(&_server, &QTcpServer::newConnection, this, [this] {
            QTcpSocket *socket = _server.nextPendingConnection();
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [this, socket] {
                request += socket->readAll();
                if (request.contains("\r\n\r\n")) {
                    socket->write(response);
                    socket->disconnectFromHost();
                }
            });
        });
    }
    quint16 port() const { return _server.serverPort(); }

    static QByteArray reply(int status, const QByteArray &type, const QByteArray &body)
    {
        return "HTTP/1.1 " + QByteArray::number(status) + " X\r\nContent-Type: " + type + "\r\nContent-Length: "
               + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
    }

private:
    QTcpServer _server;
};

} // namespace

class TestFleetSnapshots : public QObject
{
    Q_OBJECT

private slots:
    void idsFollowTheSchema()
    {
        QVERIFY(FleetSnapshots::validId("snap-8f3a2c"));
        QVERIFY(FleetSnapshots::validId("snap-0123456789abcdef"));
        QVERIFY(!FleetSnapshots::validId("snap-8f3a"));          // too short
        QVERIFY(!FleetSnapshots::validId("snap-8F3A2C"));        // upper case
        QVERIFY(!FleetSnapshots::validId("../../etc/passwd"));
        QVERIFY(!FleetSnapshots::validId(""));
    }

    void urlComesFromTheOperatorUrl()
    {
        QCOMPARE(FleetSnapshots::snapshotUrl(QUrl("wss://localhost:8443/ws/v1/operator"), "snap-abc123").toString(),
                 QStringLiteral("https://localhost:8443/api/v1/snapshots/snap-abc123"));
        QCOMPARE(FleetSnapshots::snapshotUrl(QUrl("ws://10.0.0.5:8080/ws/v1/operator"), "snap-abc123").toString(),
                 QStringLiteral("http://10.0.0.5:8080/api/v1/snapshots/snap-abc123"));
    }

    void aJpegIsReadyWithTheHashOfItsBytes()
    {
        FleetSnapshots snapshots;
        QSignalSpy changed(&snapshots, &FleetSnapshots::changed);
        const QByteArray bytes = jpeg();
        snapshots.ingest("snap-abc123", bytes, QString());

        QCOMPARE(snapshots.state("snap-abc123"), QStringLiteral("ready"));
        QCOMPARE(snapshots.sha256("snap-abc123"), sha(bytes));
        QCOMPARE(snapshots.image("snap-abc123").size(), QSize(64, 48));
        QCOMPARE(changed.count(), 1);

        const QJsonObject evidence = snapshots.evidence("snap-abc123");
        QCOMPARE(evidence["snapshot_id"].toString(), QStringLiteral("snap-abc123"));
        QCOMPARE(evidence["snapshot_sha256"].toString(), sha(bytes));
        QCOMPARE(evidence["snapshot_displayed"].toBool(), true);
    }

    void anythingElseIsUnavailableAndSaysWhy()
    {
        FleetSnapshots snapshots;
        snapshots.ingest("snap-aaaaaa", "not a picture", QString());
        QCOMPARE(snapshots.state("snap-aaaaaa"), QStringLiteral("unavailable"));
        QCOMPARE(snapshots.reason("snap-aaaaaa"), QStringLiteral("not a readable JPEG"));

        snapshots.ingest("snap-bbbbbb", QByteArray(), QString());
        QCOMPARE(snapshots.reason("snap-bbbbbb"), QStringLiteral("empty picture"));

        snapshots.ingest("snap-cccccc", QByteArray(FleetSnapshots::kMaxBytes + 1, 'x'), QString());
        QCOMPARE(snapshots.reason("snap-cccccc"), QStringLiteral("picture too large"));

        snapshots.ingest("snap-dddddd", QByteArray(), "coordinator not reachable");
        QCOMPARE(snapshots.reason("snap-dddddd"), QStringLiteral("coordinator not reachable"));

        for (const char *id : {"snap-aaaaaa", "snap-bbbbbb", "snap-cccccc", "snap-dddddd"}) {
            QVERIFY(snapshots.image(id).isNull());
            QVERIFY(snapshots.sha256(id).isEmpty());
            const QJsonObject evidence = snapshots.evidence(id);
            QCOMPARE(evidence["snapshot_displayed"].toBool(), false);
            QCOMPARE(evidence["snapshot_state"].toString(), QStringLiteral("unavailable"));
            QVERIFY(!evidence.contains("snapshot_sha256"));     // nothing was shown, so no hash
        }
    }

    void evidenceForNoPictureOrOneNeverFetched()
    {
        FleetSnapshots snapshots;
        QVERIFY(snapshots.evidence(QString()).isEmpty());      // the alert had no picture
        const QJsonObject never = snapshots.evidence("snap-eeeeee");
        QCOMPARE(never["snapshot_displayed"].toBool(), false);
        QCOMPARE(never["snapshot_state"].toString(), QStringLiteral("none"));
    }

    void badIdsAndMissingAddressNeverTouchTheNetwork()
    {
        FleetSnapshots snapshots;
        snapshots.request("../secret");
        QCOMPARE(snapshots.state("../secret"), QStringLiteral("unavailable"));
        snapshots.request("snap-abc123");     // no setSource yet
        QCOMPARE(snapshots.state("snap-abc123"), QStringLiteral("unavailable"));
        QCOMPARE(snapshots.reason("snap-abc123"), QStringLiteral("coordinator address not set"));
    }

    void fetchesWithTheTokenInAHeaderNotTheUrl()
    {
        TinyHttp http;
        const QByteArray bytes = jpeg();
        http.response = TinyHttp::reply(200, "image/jpeg", bytes);

        FleetSnapshots snapshots;
        snapshots.setSource(QUrl(QStringLiteral("ws://127.0.0.1:%1/ws/v1/operator").arg(http.port())), "tok-secret", QString());
        snapshots.request("snap-abc123");
        QCOMPARE(snapshots.state("snap-abc123"), QStringLiteral("loading"));
        QTRY_COMPARE_WITH_TIMEOUT(snapshots.state("snap-abc123"), QStringLiteral("ready"), 5000);

        const QByteArray requestLine = http.request.left(http.request.indexOf("\r\n"));
        QCOMPARE(requestLine, QByteArray("GET /api/v1/snapshots/snap-abc123 HTTP/1.1"));
        QVERIFY(http.request.contains("\r\nAuthorization: Bearer tok-secret\r\n"));
        QVERIFY(!requestLine.contains("tok-secret"));
        QCOMPARE(snapshots.sha256("snap-abc123"), sha(bytes));

        // Ready pictures are not fetched again.
        snapshots.request("snap-abc123", true);
        QCOMPARE(snapshots.state("snap-abc123"), QStringLiteral("ready"));
    }

    void serverAnswersBecomeReasons()
    {
        struct Case { int status; QByteArray type; QByteArray body; QString reason; };
        const QList<Case> cases = {
            {404, "text/plain", "missing", QStringLiteral("not on the coordinator")},
            {401, "text/plain", "no", QStringLiteral("not authorised (check Fleet/token)")},
            {200, "text/html", "<html/>", QStringLiteral("not a JPEG")},
        };
        for (const Case &c : cases) {
            TinyHttp http;
            http.response = TinyHttp::reply(c.status, c.type, c.body);
            FleetSnapshots snapshots;
            snapshots.setSource(QUrl(QStringLiteral("ws://127.0.0.1:%1/ws/v1/operator").arg(http.port())), "t", QString());
            snapshots.request("snap-abc123");
            QTRY_COMPARE_WITH_TIMEOUT(snapshots.state("snap-abc123"), QStringLiteral("unavailable"), 5000);
            QCOMPARE(snapshots.reason("snap-abc123"), c.reason);
        }
    }

    void unavailableIsNotRetriedUnlessAsked()
    {
        TinyHttp http;
        http.response = TinyHttp::reply(404, "text/plain", "x");
        FleetSnapshots snapshots;
        snapshots.setSource(QUrl(QStringLiteral("ws://127.0.0.1:%1/ws/v1/operator").arg(http.port())), "t", QString());
        snapshots.request("snap-abc123");
        QTRY_COMPARE_WITH_TIMEOUT(snapshots.state("snap-abc123"), QStringLiteral("unavailable"), 5000);
        snapshots.request("snap-abc123");
        QCOMPARE(snapshots.state("snap-abc123"), QStringLiteral("unavailable"));
        snapshots.request("snap-abc123", true);
        QCOMPARE(snapshots.state("snap-abc123"), QStringLiteral("loading"));
    }

    void keepsAtMostTheCap()
    {
        FleetSnapshots snapshots;
        for (int i = 0; i <= FleetSnapshots::kMaxKept; ++i) {
            snapshots.ingest(QStringLiteral("snap-%1").arg(i, 6, 10, QLatin1Char('0')), QByteArray(), "x");
        }
        QCOMPARE(snapshots.state("snap-000000"), QStringLiteral("none"));       // the oldest went
        QCOMPARE(snapshots.state(QStringLiteral("snap-%1").arg(FleetSnapshots::kMaxKept, 6, 10, QLatin1Char('0'))),
                 QStringLiteral("unavailable"));
    }
};

QTEST_GUILESS_MAIN(TestFleetSnapshots)
#include "tst_FleetSnapshots.moc"
