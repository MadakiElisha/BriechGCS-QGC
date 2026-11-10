#include "FleetDispatch.h"

#include <cmath>

#include <QtCore/QJsonArray>
#include <QtCore/QLoggingCategory>

#include "FleetAudit.h"
#include "FleetDataAge.h"
#include "FleetLink.h"
#include "FleetModels.h"
#include "FleetProtocol.h"
#include "FleetVehicleState.h"
#include "FlyViewSettings.h"
#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "SettingsManager.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

Q_LOGGING_CATEGORY(FleetDispatchLog, "Briech.FleetDispatch")

namespace {

using Command = FleetOperatorActions::Command;
using Outcome = FleetOperatorActions::Outcome;

/// The MAV_CMD whose COMMAND_ACK answers each command on PX4.
int ackedCommand(Command command)
{
    switch (command) {
    case Command::Hold:
    case Command::Goto:
        return MAV_CMD_DO_REPOSITION;
    case Command::Orbit:
        return MAV_CMD_DO_ORBIT;
    case Command::Return:
        return MAV_CMD_DO_SET_MODE;
    }
    return -1;
}

QString ackText(int result)
{
    switch (result) {
    case MAV_RESULT_TEMPORARILY_REJECTED:
        return QStringLiteral("vehicle temporarily rejected the command");
    case MAV_RESULT_DENIED:
        return QStringLiteral("vehicle denied the command");
    case MAV_RESULT_UNSUPPORTED:
        return QStringLiteral("vehicle does not support the command");
    case MAV_RESULT_FAILED:
        return QStringLiteral("vehicle reported the command failed");
    default:
        return QStringLiteral("vehicle answered with result %1").arg(result);
    }
}

QString upper(Command command)
{
    return FleetOperatorActions::commandName(command).toUpper();
}

} // namespace

FleetDispatch::FleetDispatch(FleetLink *link, FleetAlertModel *alerts, FleetDataAge *ages, QObject *parent)
    : QObject(parent)
    , _actions([this](const QString &type, const QJsonObject &data) {
          // Local record first: it must exist even when the coordinator is down.
          if (_audit) {
              _audit->append(type, data);
          }
          if (_link) {
              _link->sendMessage(type, data);
          }
      }, this)
    , _link(link)
    , _alerts(alerts)
    , _ages(ages)
{
    connect(&_actions, &FleetOperatorActions::outcomeReported, this, &FleetDispatch::_onOutcome);

    MultiVehicleManager *manager = MultiVehicleManager::instance();
    for (int i = 0; i < manager->vehicles()->count(); ++i) {
        _watch(qobject_cast<Vehicle *>(manager->vehicles()->get(i)));
    }
    connect(manager, &MultiVehicleManager::vehicleAdded, this, &FleetDispatch::_watch);
    connect(manager, &MultiVehicleManager::vehicleRemoved, this, [this](Vehicle *vehicle) {
        _actions.resolve(vehicle->id(), Outcome::NoResponse, QStringLiteral("vehicle disconnected from this ground station"));
    });
}

QStringList FleetDispatch::fleetCommandTargets() const
{
    QStringList names;
    QmlObjectListModel *vehicles = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vehicles->count(); ++i) {
        auto *vehicle = qobject_cast<Vehicle *>(vehicles->get(i));
        if (vehicle && vehicle->flying()) {
            names.append(FleetVehicleState::displayName(vehicle->id()));
        }
    }
    return names;
}

void FleetDispatch::holdAll()
{
    _fleetCommand(Command::Hold);
}

void FleetDispatch::returnAll()
{
    _fleetCommand(Command::Return);
}

void FleetDispatch::_fleetCommand(Command command)
{
    _refreshOperatorId();
    QList<Vehicle *> targets;
    QmlObjectListModel *vehicles = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vehicles->count(); ++i) {
        auto *vehicle = qobject_cast<Vehicle *>(vehicles->get(i));
        // Only vehicles already in the air: a fleet command never takes off.
        if (vehicle && vehicle->flying()) {
            targets.append(vehicle);
        }
    }
    if (targets.isEmpty()) {
        emit notice(QStringLiteral("Fleet"), QStringLiteral("No vehicle is flying; %1 ALL sent nothing.").arg(upper(command)),
                    QStringLiteral("info"));
        return;
    }

    // One press, one id per vehicle under it: act-holdall-<n>-v<id>.
    const QString pressId = _actions.newActionId(command == Command::Hold ? QStringLiteral("holdall") : QStringLiteral("returnall"));
    int sent = 0;
    for (Vehicle *vehicle : std::as_const(targets)) {
        const QString problem = _problem(vehicle, command, QJsonObject());
        const QString name = FleetVehicleState::displayName(vehicle->id());
        if (!problem.isEmpty()) {
            emit notice(QStringLiteral("Fleet"), QStringLiteral("%1: %2, not sent.").arg(name, problem), QStringLiteral("warn"));
            continue;
        }
        _actions.command(pressId + QStringLiteral("-v") + QString::number(vehicle->id()), vehicle->id(), command);
        _send(vehicle, command, QJsonObject());
        ++sent;
    }
    if (sent > 0) {
        emit notice(QStringLiteral("Fleet"), QStringLiteral("%1 sent to %2 vehicle(s).").arg(upper(command)).arg(sent),
                    QStringLiteral("info"));
    }
}

QVariantMap FleetDispatch::proposalFor(const QString &alertId) const
{
    QVariantMap info;
    const QJsonObject alert = _alerts ? _alerts->row(alertId) : QJsonObject();
    const QJsonObject proposal = alert.value(QLatin1String("proposal")).toObject();
    const std::optional<Command> command = FleetOperatorActions::commandFromName(proposal.value(QLatin1String("action")).toString());
    const int vehicleId = proposal.value(QLatin1String("vehicle_id")).toInt();
    if (alert.isEmpty() || !command || vehicleId <= 0) {
        info.insert(QStringLiteral("problem"), alert.isEmpty() ? QStringLiteral("alert not found") : QStringLiteral("alert has no proposal"));
        return info;
    }

    Vehicle *vehicle = _vehicle(vehicleId);
    info.insert(QStringLiteral("vehicleId"), vehicleId);
    info.insert(QStringLiteral("vehicleName"), FleetVehicleState::displayName(vehicleId));
    info.insert(QStringLiteral("command"), FleetOperatorActions::commandName(*command));
    for (const char *field : {"eta_s", "battery_after_pct", "radius_m", "alt_rel_m"}) {
        if (proposal.contains(QLatin1String(field))) {
            info.insert(QString::fromLatin1(field), proposal.value(QLatin1String(field)).toDouble());
        }
    }
    // Stale: this ground station has lost the vehicle or not heard it for more
    // than 10 s (grey in the fleet list), or the alert is no longer being updated
    // because the coordinator link is down.
    const bool commsLost = vehicle && vehicle->vehicleLinkManager() && vehicle->vehicleLinkManager()->communicationLost();
    const bool grey = _ages && _ages->levelOf(vehicleId) == FleetDataAge::Grey;
    const bool alertStale = !_link || _link->state() != FleetLink::Connected;
    QStringList reasons;
    if (commsLost || grey) {
        const int seconds = _ages ? _ages->secondsFor(vehicleId) : -1;
        reasons.append(seconds >= 0 ? QStringLiteral("%1 last heard %2 s ago").arg(FleetVehicleState::displayName(vehicleId)).arg(seconds)
                                    : QStringLiteral("%1 communication lost").arg(FleetVehicleState::displayName(vehicleId)));
    }
    if (alertStale) {
        reasons.append(QStringLiteral("coordinator offline, the alert is not being updated"));
    }
    info.insert(QStringLiteral("stale"), !reasons.isEmpty());
    if (!reasons.isEmpty()) {
        info.insert(QStringLiteral("staleReason"), reasons.join(QStringLiteral("; ")));
    }
    info.insert(QStringLiteral("problem"), _problem(vehicle, *command, alert));
    return info;
}

void FleetDispatch::approveAlert(const QString &alertId, bool extraConfirmation)
{
    _refreshOperatorId();
    const QVariantMap info = proposalFor(alertId);
    if (!info.contains(QStringLiteral("command"))) {
        emit notice(QStringLiteral("Fleet"), QStringLiteral("%1: %2.").arg(alertId, info.value(QStringLiteral("problem")).toString()),
                    QStringLiteral("crit"));
        return;
    }
    if (info.value(QStringLiteral("stale")).toBool() && !extraConfirmation) {
        // The UI asks twice for stale data; refuse a single confirmation from anywhere else.
        emit notice(QStringLiteral("Fleet"), QStringLiteral("%1: data is stale, a second confirmation is required.").arg(alertId),
                    QStringLiteral("crit"));
        return;
    }

    const Command command = *FleetOperatorActions::commandFromName(info.value(QStringLiteral("command")).toString());
    const int vehicleId = info.value(QStringLiteral("vehicleId")).toInt();
    const QString problem = info.value(QStringLiteral("problem")).toString();
    const QString actionId = _actions.newActionId(alertId);

    _actions.decision(actionId, alertId, true, vehicleId, command, extraConfirmation,
                      problem.isEmpty() ? QString() : problem + QStringLiteral("; no command sent"));
    if (!problem.isEmpty()) {
        emit notice(QStringLiteral("Fleet"),
                    QStringLiteral("Approved, but %1: %2. No command sent.").arg(FleetVehicleState::displayName(vehicleId), problem),
                    QStringLiteral("warn"));
        return;
    }
    _actions.command(actionId, vehicleId, command, alertId, extraConfirmation);
    _send(_vehicle(vehicleId), command, _alerts->row(alertId));
}

void FleetDispatch::rejectAlert(const QString &alertId)
{
    _refreshOperatorId();
    const QVariantMap info = proposalFor(alertId);
    const std::optional<Command> command = FleetOperatorActions::commandFromName(info.value(QStringLiteral("command")).toString());
    _actions.decision(_actions.newActionId(alertId), alertId, false, info.value(QStringLiteral("vehicleId")).toInt(), command, false);
    emit notice(QStringLiteral("Fleet"), QStringLiteral("%1 rejected. Nothing was sent to any vehicle.").arg(alertId), QStringLiteral("info"));
}

QString FleetDispatch::_problem(Vehicle *vehicle, Command command, const QJsonObject &alert) const
{
    if (!vehicle) {
        return QStringLiteral("vehicle not connected to this ground station");
    }
    if (!vehicle->flying()) {
        return QStringLiteral("vehicle is not flying");
    }
    switch (command) {
    case Command::Hold:
        if (!vehicle->pauseVehicleSupported()) {
            return QStringLiteral("hold not supported by this vehicle");
        }
        return QString();
    case Command::Return:
        if (!vehicle->guidedModeSupported()) {
            return QStringLiteral("guided commands not supported by this vehicle");
        }
        return QString();
    case Command::Goto:
    case Command::Orbit:
        break;
    }

    if (command == Command::Goto && !vehicle->guidedModeSupported()) {
        return QStringLiteral("guided commands not supported by this vehicle");
    }
    if (command == Command::Orbit && !vehicle->orbitModeSupported()) {
        return QStringLiteral("orbit not supported by this vehicle");
    }
    const QJsonObject pos = alert.value(QLatin1String("pos")).toObject();
    const QGeoCoordinate target(pos.value(QLatin1String("lat")).toDouble(NAN), pos.value(QLatin1String("lon")).toDouble(NAN));
    if (!target.isValid()) {
        return QStringLiteral("alert has no position");
    }
    if (!vehicle->coordinate().isValid()) {
        return QStringLiteral("vehicle position unknown");
    }
    if (command == Command::Goto) {
        // QGC's own limit; guidedModeGotoLocation would otherwise refuse silently.
        const double maxDistance = SettingsManager::instance()->flyViewSettings()->maxGoToLocationDistance()->rawValue().toDouble();
        const double distance = vehicle->coordinate().distanceTo(target);
        if (distance > maxDistance) {
            return QStringLiteral("target is %1 m away, over QGC's %2 m go-to limit").arg(qRound(distance)).arg(qRound(maxDistance));
        }
    }
    if (command == Command::Orbit && !(alert.value(QLatin1String("proposal")).toObject().value(QLatin1String("radius_m")).toDouble() > 0)) {
        return QStringLiteral("proposal has no orbit radius");
    }
    return QString();
}

void FleetDispatch::_send(Vehicle *vehicle, Command command, const QJsonObject &alert)
{
    _setStatus(vehicle->id(), upper(command) + QStringLiteral(" SENT"));
    switch (command) {
    case Command::Hold:
        vehicle->pauseVehicle();
        break;
    case Command::Return:
        // Not guidedModeRTL(): for PX4 (and ArduPilot) that calls
        // FirmwarePlugin::_setFlightModeAndValidate, which waits on the UI thread
        // (100 ms sleeps, up to 3 x 1.3 s) for the mode to change. RETURN ALL
        // loops over the fleet, so each drone waited for the one before it:
        // about 1 s per answering drone, up to 3.9 s per silent one, with the UI
        // stalled meanwhile. setFlightMode() sends MAV_CMD_DO_SET_MODE through
        // sendMavCommand (QGC's own retries and no-response report) without
        // waiting; _onCommandResult and _onFlightMode settle the outcome.
        vehicle->setFlightMode(vehicle->rtlFlightMode());
        // Already returning: no mode change follows, so settle it now.
        if (vehicle->flightMode() == vehicle->rtlFlightMode()) {
            _actions.resolve(vehicle->id(), Outcome::Confirmed, QStringLiteral("flight mode %1").arg(vehicle->flightMode()));
        }
        break;
    case Command::Goto:
    case Command::Orbit: {
        const QJsonObject pos = alert.value(QLatin1String("pos")).toObject();
        const QGeoCoordinate target(pos.value(QLatin1String("lat")).toDouble(), pos.value(QLatin1String("lon")).toDouble());
        if (command == Command::Goto) {
            vehicle->guidedModeGotoLocation(target);
            break;
        }
        const QJsonObject proposal = alert.value(QLatin1String("proposal")).toObject();
        // The proposal's height is above takeoff; the orbit command wants AMSL.
        // Without one, keep the vehicle's current altitude.
        double amsl = vehicle->altitudeAMSL()->rawValue().toDouble();
        if (proposal.contains(QLatin1String("alt_rel_m")) && vehicle->homePosition().isValid()) {
            amsl = vehicle->homePosition().altitude() + proposal.value(QLatin1String("alt_rel_m")).toDouble();
        }
        vehicle->guidedModeOrbit(target, proposal.value(QLatin1String("radius_m")).toDouble(), amsl);
        break;
    }
    }
    qCInfo(FleetDispatchLog) << "sent" << FleetOperatorActions::commandName(command) << "to vehicle" << vehicle->id();
}

void FleetDispatch::_watch(Vehicle *vehicle)
{
    if (!vehicle) {
        return;
    }
    connect(vehicle, &Vehicle::mavCommandResult, this,
            [this, vehicle](int, int, int command, int ackResult, int failureCode) {
                _onCommandResult(vehicle, command, ackResult, failureCode);
            });
    connect(vehicle, &Vehicle::flightModeChanged, this, [this, vehicle] { _onFlightMode(vehicle); });
}

void FleetDispatch::_onCommandResult(Vehicle *vehicle, int command, int ackResult, int failureCode)
{
    const std::optional<Command> waiting = _actions.pending(vehicle->id());
    // A duplicate is QGC declining to resend while the same command is still out
    // (its mode-change retries do this); the answer to the one already sent decides.
    if (!waiting || ackedCommand(*waiting) != command || ackResult == MAV_RESULT_IN_PROGRESS
        || failureCode == Vehicle::MavCmdResultFailureDuplicateCommand) {
        return;
    }
    if (failureCode == Vehicle::MavCmdResultFailureNoResponseToCommand) {
        _actions.resolve(vehicle->id(), Outcome::NoResponse, QStringLiteral("vehicle did not answer after QGC's retries"));
    } else if (ackResult == MAV_RESULT_ACCEPTED) {
        _actions.resolve(vehicle->id(), Outcome::Confirmed, QStringLiteral("command accepted"));
    } else {
        _actions.resolve(vehicle->id(), Outcome::Refused, ackText(ackResult));
    }
}

void FleetDispatch::_onFlightMode(Vehicle *vehicle)
{
    const std::optional<Command> waiting = _actions.pending(vehicle->id());
    const QString mode = vehicle->flightMode();
    if ((waiting == Command::Hold && mode == vehicle->pauseFlightMode())
        || (waiting == Command::Return && mode == vehicle->rtlFlightMode())) {
        _actions.resolve(vehicle->id(), Outcome::Confirmed, QStringLiteral("flight mode %1").arg(mode));
    }
}

void FleetDispatch::_onOutcome(int vehicleId, const QString &command, const QString &outcome, const QString &detail)
{
    const QString state = outcome == QLatin1String("no_response") ? QStringLiteral("NO RESPONSE") : outcome.toUpper();
    _setStatus(vehicleId, command.toUpper() + QLatin1Char(' ') + state);
    const QString tone = outcome == QLatin1String("confirmed") ? QStringLiteral("ok")
                       : outcome == QLatin1String("refused") ? QStringLiteral("crit")
                       : QStringLiteral("warn");
    emit notice(QStringLiteral("Fleet"),
                QStringLiteral("%1: %2 %3%4").arg(FleetVehicleState::displayName(vehicleId), command.toUpper(), state,
                                                  detail.isEmpty() ? QString() : QStringLiteral(" (") + detail + QLatin1Char(')')),
                tone);
}

void FleetDispatch::_setStatus(int vehicleId, const QString &text)
{
    _status.insert(QString::number(vehicleId), text);
    emit vehicleStatusChanged();
}

void FleetDispatch::_refreshOperatorId()
{
    // The id the coordinator saw in hello (FleetLink sanitises it the same way).
    _actions.setOperatorId(FleetProtocol::sanitizeId(FleetLink::configFromSettings().operatorId));
}

Vehicle *FleetDispatch::_vehicle(int id) const
{
    QmlObjectListModel *vehicles = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vehicles->count(); ++i) {
        auto *vehicle = qobject_cast<Vehicle *>(vehicles->get(i));
        if (vehicle && vehicle->id() == id) {
            return vehicle;
        }
    }
    return nullptr;
}
