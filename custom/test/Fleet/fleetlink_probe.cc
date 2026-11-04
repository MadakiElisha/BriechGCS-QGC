// Runs FleetLink against a real coordinator and prints what QML and FleetModels would see.
//
//   fleetlink_probe --url wss://localhost:8443/ws/v1/operator --ca ops/certs/ca.crt \
//                   --token-file ops/secrets/operator.tokens [--vehicles 3] [--seconds 30]

#include <QtCore/QCommandLineParser>
#include <QtCore/QCoreApplication>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QTextStream>
#include <QtCore/QTime>
#include <QtCore/QTimer>

#include "FleetLink.h"

namespace {

QTextStream out(stdout);

void say(const QString &line)
{
    out << QTime::currentTime().toString(QStringLiteral("hh:mm:ss.zzz")) << ' ' << line << Qt::endl;
}

QJsonObject fakeVehicles(int count, int seq)
{
    QJsonArray vehicles;
    for (int i = 1; i <= count; ++i) {
        vehicles.append(QJsonObject{
            {"vehicle_id", i}, {"name", QStringLiteral("CPP-%1").arg(i, 2, 10, QLatin1Char('0'))},
            {"pos", QJsonObject{{"lat", 6.524 + 0.001 * i}, {"lon", 3.379}, {"alt_rel_m", 60.0}}},
            {"heading_deg", (seq * 5 + i * 30) % 360}, {"mode", "Hold"}, {"armed", true}, {"flying", true},
            {"battery_pct", 90}, {"link_quality_pct", 100}, {"can_take_task", true},
        });
    }
    return {{"vehicles", vehicles}};
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationVersion(QStringLiteral("probe"));

    QCommandLineParser cli;
    cli.setApplicationDescription(QStringLiteral("Run FleetLink against a coordinator."));
    cli.addHelpOption();
    cli.addOptions({
        {"url", "Coordinator WebSocket URL.", "url", "wss://localhost:8443/ws/v1/operator"},
        {"ca", "CA certificate (PEM) to trust.", "file"},
        {"token-file", "File whose first line is the operator token.", "file"},
        {"operator", "Operator id.", "id", "op-cpp-probe"},
        {"vehicles", "Report N fake vehicles every second.", "n", "0"},
        {"seconds", "Exit after N seconds (0: run until stopped).", "n", "0"},
    });
    cli.process(app);

    FleetLinkConfig config;
    config.url = QUrl(cli.value("url"));
    config.caFile = cli.value("ca");
    config.operatorId = cli.value("operator");
    config.clientVersion = QStringLiteral("fleetlink_probe");
    if (cli.isSet("token-file")) {
        QFile f(cli.value("token-file"));
        if (!f.open(QIODevice::ReadOnly)) {
            say(QStringLiteral("cannot read the token file"));
            return 2;
        }
        config.token = QString::fromUtf8(f.readLine()).trimmed();
    }

    FleetLink link;
    QObject::connect(&link, &FleetLink::stateChanged, &app, [&link] {
        static QString last;
        const QString now = link.stateText() + (link.lastError().isEmpty() ? QString() : QStringLiteral(" (") + link.lastError() + QLatin1Char(')'));
        if (now != last) {
            say(QStringLiteral("state: ") + now);
            last = now;
        }
    });
    QObject::connect(&link, &FleetLink::silentChanged, &app, [&link] {
        say(link.coordinatorSilent() ? QStringLiteral("OFFLINE BANNER: coordinator silent") : QStringLiteral("coordinator heard again"));
    });
    QObject::connect(&link, &FleetLink::snapshotReceived, &app, [](const QJsonObject &data) {
        say(QStringLiteral("snapshot: %1 assets, %2 vehicles, %3 objects, %4 alerts")
                .arg(data["assets"].toArray().size()).arg(data["vehicles"].toArray().size())
                .arg(data["objects"].toArray().size()).arg(data["alerts"].toArray().size()));
    });
    QObject::connect(&link, &FleetLink::batchReceived, &app, [](const QList<QJsonObject> &batch) {
        QStringList parts;
        for (const QJsonObject &m : batch) {
            const QJsonObject d = m["data"].toObject();
            const QString type = m["type"].toString();
            if (type == QLatin1String("object.update")) {
                parts << QStringLiteral("%1 %2,%3").arg(d["object_id"].toString())
                             .arg(d["pos"]["lat"].toDouble(), 0, 'f', 6).arg(d["pos"]["lon"].toDouble(), 0, 'f', 6);
            } else if (type == QLatin1String("asset.state")) {
                parts << QStringLiteral("%1 link=%2").arg(d["asset_id"].toString(), d["link"].toString());
            } else if (type == QLatin1String("heartbeat")) {
                parts << QStringLiteral("heartbeat #%1").arg(d["seq"].toInt());
            } else {
                parts << type;
            }
        }
        say(QStringLiteral("batch of %1: ").arg(batch.size()) + parts.join(QStringLiteral(" | ")));
    });

    const int vehicles = cli.value("vehicles").toInt();
    QTimer reporter;
    int seq = 0;
    QObject::connect(&reporter, &QTimer::timeout, &app, [&] { link.sendMessage("vehicle.state", fakeVehicles(vehicles, seq++)); });
    if (vehicles > 0) {
        reporter.start(1000);
    }
    if (const int seconds = cli.value("seconds").toInt(); seconds > 0) {
        QTimer::singleShot(seconds * 1000, &app, [&] {
            say(QStringLiteral("done, %1 messages dropped by FleetLink").arg(link.droppedCount()));
            link.stop();
            app.quit();
        });
    }

    link.startWith(config);
    return app.exec();
}
