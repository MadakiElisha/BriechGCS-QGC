// Writes every kind of message QGC sends to the coordinator, built by the same
// code the app uses, one JSON object per line: {"case": "...", "message": {...}}.
//
// check_outgoing.py validates each message with the coordinator's own schema
// validator (ground-core/coordinator/schemas.py), so a QGC message that the
// coordinator would drop fails CI instead of failing in the field.
//
// The cases cover normal use and the edges: missing, NaN and out-of-range
// values, long and odd operator ids, too many vehicles, every phase, command
// and outcome of operator.action.
//
//   fleet_outgoing_samples <out.jsonl>     (no argument: standard output)

#include <cmath>
#include <limits>

#include <QtCore/QCoreApplication>
#include <QtCore/QFile>
#include <QtCore/QJsonDocument>
#include <QtCore/QTextStream>

#include "FleetOperatorActions.h"
#include "FleetProtocol.h"
#include "FleetVehicleState.h"

namespace {

constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();
constexpr double kInf = std::numeric_limits<double>::infinity();

QFile *g_out = nullptr;
int g_count = 0;

void emitMessage(const QString &caseName, const QJsonObject &message)
{
    const QJsonObject line{{QStringLiteral("case"), caseName}, {QStringLiteral("message"), message}};
    g_out->write(QJsonDocument(line).toJson(QJsonDocument::Compact));
    g_out->write("\n");
    ++g_count;
}

/// Operator ids as a user might type them in Fleet settings.
const QList<QPair<QString, QString>> &operatorIds()
{
    static const QList<QPair<QString, QString>> ids = {
        {QStringLiteral("default"), QStringLiteral("op-local")},
        {QStringLiteral("plain"), QStringLiteral("op-001")},
        {QStringLiteral("upper-and-space"), QStringLiteral("Miracle Elisha")},
        {QStringLiteral("underscore"), QStringLiteral("OPERATOR_01")},
        {QStringLiteral("leading-hyphen"), QStringLiteral("-lead")},
        {QStringLiteral("non-ascii"), QStringLiteral("Æsa Øye")},
        {QStringLiteral("only-symbols"), QStringLiteral("***")},
        {QStringLiteral("empty"), QString()},
        {QStringLiteral("59-chars"), QString(59, QLatin1Char('a'))},
        {QStringLiteral("60-chars"), QString(60, QLatin1Char('b'))},
        {QStringLiteral("63-chars"), QString(63, QLatin1Char('c'))},
        {QStringLiteral("100-chars"), QString(100, QLatin1Char('d'))},
    };
    return ids;
}

void hellos()
{
    const QList<QPair<QString, QString>> versions = {
        {QStringLiteral("version"), QStringLiteral("5.0.0")},
        {QStringLiteral("no-version"), QString()},
        {QStringLiteral("long-version"), QString(100, QLatin1Char('9'))},
    };
    for (const auto &[idCase, id] : operatorIds()) {
        for (const auto &[versionCase, version] : versions) {
            emitMessage(QStringLiteral("hello/%1/%2").arg(idCase, versionCase), FleetProtocol::makeHello(id, version));
        }
    }
}

FleetVehicleSample fullSample(int id)
{
    FleetVehicleSample s;
    s.id = id;
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

void vehicleStates()
{
    // Every message goes out under each operator id: src must be valid for all of them.
    QList<QPair<QString, QList<FleetVehicleSample>>> cases;
    auto one = [&cases](const QString &name, const FleetVehicleSample &s) { cases.append({name, {s}}); };

    one(QStringLiteral("full"), fullSample(3));
    {
        FleetVehicleSample s;
        s.id = 1;
        s.mode = QStringLiteral("Hold");
        one(QStringLiteral("bare"), s);
    }
    {
        FleetVehicleSample s;
        s.id = 2;
        s.mode = QString();
        one(QStringLiteral("empty-mode"), s);
    }
    {
        FleetVehicleSample s = fullSample(4);
        s.mode = QString(100, QLatin1Char('M'));
        one(QStringLiteral("long-mode"), s);
    }
    for (int id : {0, 1, 255, 256, -1}) {
        one(QStringLiteral("id-%1").arg(id), fullSample(id));
    }
    {
        FleetVehicleSample s = fullSample(5);
        s.commsLost = true;
        one(QStringLiteral("comms-lost"), s);
    }
    {
        FleetVehicleSample s = fullSample(6);
        s.lat = s.lon = s.altRelM = s.altAmslM = s.headingDeg = s.groundSpeedMs = s.batteryPct = s.linkLossPct = kNaN;
        one(QStringLiteral("all-nan"), s);
    }
    {
        FleetVehicleSample s = fullSample(7);
        s.lat = s.lon = s.altRelM = s.altAmslM = s.headingDeg = s.groundSpeedMs = s.batteryPct = s.linkLossPct = kInf;
        one(QStringLiteral("all-inf"), s);
    }
    {
        FleetVehicleSample s = fullSample(8);
        s.lat = kNaN;
        one(QStringLiteral("lat-nan-lon-valid"), s);
    }
    {
        FleetVehicleSample s = fullSample(8);
        s.lat.reset();
        one(QStringLiteral("lat-missing"), s);
    }
    {
        FleetVehicleSample s = fullSample(9);
        s.altRelM.reset();
        s.altAmslM.reset();
        one(QStringLiteral("pos-without-altitude"), s);
    }
    for (double lat : {-90.0, 90.0, 90.5, -91.0, 1000.0}) {
        FleetVehicleSample s = fullSample(10);
        s.lat = lat;
        one(QStringLiteral("lat-%1").arg(lat), s);
    }
    for (double lon : {-180.0, 180.0, 180.5, -200.0}) {
        FleetVehicleSample s = fullSample(11);
        s.lon = lon;
        one(QStringLiteral("lon-%1").arg(lon), s);
    }
    for (double heading : {0.0, 359.9999999999, 360.0, 720.0, -10.0, -360.0, -0.0000000001, 1e9}) {
        FleetVehicleSample s = fullSample(12);
        s.headingDeg = heading;
        one(QStringLiteral("heading-%1").arg(heading, 0, 'g', 15), s);
    }
    for (double speed : {0.0, -1.0, 1e6}) {
        FleetVehicleSample s = fullSample(13);
        s.groundSpeedMs = speed;
        one(QStringLiteral("speed-%1").arg(speed), s);
    }
    for (double battery : {-5.0, 0.0, 19.6, 20.0, 20.4, 99.6, 100.0, 150.0}) {
        for (bool armed : {false, true}) {
            FleetVehicleSample s = fullSample(14);
            s.batteryPct = battery;
            s.armed = armed;
            one(QStringLiteral("battery-%1-armed-%2").arg(battery).arg(armed), s);
        }
    }
    for (double loss : {-10.0, 0.0, 50.5, 100.0, 150.0}) {
        FleetVehicleSample s = fullSample(15);
        s.linkLossPct = loss;
        one(QStringLiteral("link-loss-%1").arg(loss), s);
    }
    {
        FleetVehicleSample s = fullSample(16);
        s.canArm.reset();
        s.armed = false;
        one(QStringLiteral("can-arm-unknown"), s);
        s.canArm = false;
        one(QStringLiteral("can-arm-false"), s);
        s.batteryPct.reset();
        one(QStringLiteral("battery-unknown"), s);
    }
    {
        QList<FleetVehicleSample> many;
        for (int id = 1; id <= 70; ++id) {
            many.append(fullSample(id));
        }
        cases.append({QStringLiteral("70-vehicles"), many});
        cases.append({QStringLiteral("no-vehicles"), {}});
    }

    for (const auto &[idCase, id] : operatorIds()) {
        for (const auto &[name, samples] : std::as_const(cases)) {
            emitMessage(QStringLiteral("vehicle.state/%1/%2").arg(idCase, name),
                        FleetProtocol::makeMessage(QStringLiteral("vehicle.state"), FleetProtocol::clientSrc(id),
                                                   FleetVehicleState::reportData(samples)));
        }
    }
}

void operatorActions()
{
    using Command = FleetOperatorActions::Command;
    using Outcome = FleetOperatorActions::Outcome;
    const QList<Command> commands = {Command::Goto, Command::Orbit, Command::Hold, Command::Return};
    const QList<Outcome> outcomes = {Outcome::Confirmed, Outcome::Refused, Outcome::NoResponse};
    const QString longDetail = QString(300, QLatin1Char('x'));
    // 199 ASCII characters then an emoji: cutting at 200 UTF-16 units splits the pair.
    const QString emojiDetail = QString(199, QLatin1Char('y')) + QString::fromUtf8("\xF0\x9F\x9A\x81") + QStringLiteral(" tail");
    const QList<QString> alertIds = {
        QStringLiteral("a-0001"),
        QStringLiteral("a-") + QString(96, QLatin1Char('z')),   // the longest alert id the schema allows
        QStringLiteral("a-tower-01:obj_7.2"),
    };

    for (const auto &[idCase, id] : operatorIds()) {
        QString caseName;
        FleetOperatorActions actions([&](const QString &type, const QJsonObject &data) {
            emitMessage(QStringLiteral("operator.action/%1/%2").arg(idCase, caseName),
                        FleetProtocol::makeMessage(type, FleetProtocol::clientSrc(id), data));
        });
        // The id exactly as typed in Fleet settings: setOperatorId applies the rule.
        actions.setOperatorId(id);

        int vehicle = 1;
        for (const QString &alertId : alertIds) {
            for (Command command : commands) {
                for (bool approve : {true, false}) {
                    for (bool extra : {false, true}) {
                        caseName = QStringLiteral("decision/%1/%2/%3/%4").arg(alertId.left(12), FleetOperatorActions::commandName(command))
                                       .arg(approve ? "approve" : "reject").arg(extra ? "extra" : "plain");
                        const QString actionId = actions.newActionId(alertId);
                        actions.decision(actionId, alertId, approve, vehicle, command, extra);
                        if (approve) {
                            caseName.replace(QStringLiteral("decision/"), QStringLiteral("command/"));
                            actions.command(actionId, vehicle, command, alertId, extra);
                            for (Outcome outcome : {outcomes.at(vehicle % outcomes.size())}) {
                                caseName = QStringLiteral("outcome/%1/%2").arg(FleetOperatorActions::commandName(command),
                                                                                FleetOperatorActions::outcomeName(outcome));
                                actions.resolve(vehicle, outcome, QStringLiteral("flight mode Hold"));
                            }
                        }
                        vehicle = vehicle % 255 + 1;
                    }
                }
            }
        }

        caseName = QStringLiteral("decision/reject-no-vehicle-no-command");
        actions.decision(actions.newActionId(alertIds.first()), alertIds.first(), false, 0, std::nullopt, false);
        caseName = QStringLiteral("decision/long-detail");
        actions.decision(actions.newActionId(alertIds.first()), alertIds.first(), true, 3, Command::Goto, false, longDetail);
        caseName = QStringLiteral("decision/emoji-detail");
        actions.decision(actions.newActionId(alertIds.first()), alertIds.first(), true, 3, Command::Goto, false, emojiDetail);

        // Hold all / Return all: no alert, one command per vehicle (FleetDispatch.cc).
        for (Command command : {Command::Hold, Command::Return}) {
            const QString pressId = actions.newActionId(command == Command::Hold ? QStringLiteral("holdall") : QStringLiteral("returnall"));
            for (int v : {1, 2, 255}) {
                caseName = QStringLiteral("command/%1-all/v%2").arg(FleetOperatorActions::commandName(command)).arg(v);
                actions.command(pressId + QStringLiteral("-v") + QString::number(v), v, command);
            }
            for (int v : {1, 2, 255}) {
                for (Outcome outcome : outcomes) {
                    if (!actions.pending(v)) {
                        break;
                    }
                    caseName = QStringLiteral("outcome/%1-all/%2").arg(FleetOperatorActions::commandName(command),
                                                                       FleetOperatorActions::outcomeName(outcome));
                    actions.resolve(v, outcome, outcome == Outcome::Refused ? longDetail : emojiDetail);
                }
            }
        }

        // A newer command on the same vehicle settles the older one as no_response.
        caseName = QStringLiteral("command/superseded");
        actions.command(actions.newActionId(QStringLiteral("holdall")), 9, Command::Hold);
        actions.command(actions.newActionId(QStringLiteral("returnall")), 9, Command::Return);
        caseName = QStringLiteral("outcome/after-superseded");
        actions.resolve(9, Outcome::Confirmed);

        // Action ids from odd stems are cut to the schema's length.
        caseName = QStringLiteral("command/long-stem");
        actions.command(actions.newActionId(QString(200, QLatin1Char('s'))), 10, Command::Orbit);
        actions.resolve(10, Outcome::Confirmed);
    }
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);

    QFile out;
    const QStringList args = app.arguments();
    if (args.size() > 1) {
        out.setFileName(args.at(1));
        if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            qCritical("cannot write %s", qPrintable(args.at(1)));
            return 2;
        }
    } else if (!out.open(stdout, QIODevice::WriteOnly)) {
        return 2;
    }
    g_out = &out;

    hellos();
    vehicleStates();
    operatorActions();

    out.flush();
    QTextStream(stderr) << "fleet_outgoing_samples: " << g_count << " messages\n";
    return 0;
}
