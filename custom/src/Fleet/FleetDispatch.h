#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QVariantMap>

#include "FleetOperatorActions.h"

class FleetAlertModel;
class FleetAudit;
class FleetDataAge;
class FleetLink;
class Vehicle;

/// Fleet commands from the operator: Hold all, Return all, and approving or
/// rejecting an alert's proposal.
///
/// Commands go straight to QGC's vehicles through QGC's own guided actions
/// (pauseVehicle, setFlightMode(rtlFlightMode), guidedModeGotoLocation, guidedModeOrbit), with
/// the same checks QGC's buttons use. They never depend on the coordinator
/// link: each is then reported as operator.action through FleetLink, which
/// queues the record while offline. Nothing here arms a vehicle or takes off;
/// fleet commands only go to vehicles that are already flying.
///
/// Outcomes come from the vehicle: its COMMAND_ACK (mavCommandResult) or, for
/// Hold and Return, its flight mode actually changing. No answer within
/// FleetOperatorActions' timeout is reported as no_response.
class FleetDispatch : public QObject
{
    Q_OBJECT

    /// Per vehicle id (as a string), the last fleet command and its state, e.g.
    /// "HOLD SENT", "RETURN CONFIRMED", "ORBIT REFUSED". For roster rows.
    Q_PROPERTY(QVariantMap vehicleStatus READ vehicleStatus NOTIFY vehicleStatusChanged)

public:
    /// ages may be null (tests): then only QGC's communication-lost flag marks a vehicle stale.
    FleetDispatch(FleetLink *link, FleetAlertModel *alerts, FleetDataAge *ages, QObject *parent = nullptr);

    QVariantMap vehicleStatus() const { return _status; }

    /// Names of the vehicles Hold all and Return all would command: those flying now.
    Q_INVOKABLE QStringList fleetCommandTargets() const;
    Q_INVOKABLE void holdAll();
    Q_INVOKABLE void returnAll();

    /// What approving alertId would do, for the confirmation dialog:
    ///   vehicleId, vehicleName, command, etaSeconds, batteryAfter (when known)
    ///   stale: true when the vehicle's or the alert's data is not current,
    ///          so the operator must confirm a second time
    ///   staleReason: why, in words, when stale
    ///   problem: why it cannot be sent (empty when it can)
    Q_INVOKABLE QVariantMap proposalFor(const QString &alertId) const;
    Q_INVOKABLE void approveAlert(const QString &alertId, bool extraConfirmation);
    Q_INVOKABLE void rejectAlert(const QString &alertId);

    /// Every operator.action record is also appended here (local, hash-chained),
    /// whether or not the coordinator is reachable. May be null.
    void setAudit(FleetAudit *audit) { _audit = audit; }

    /// For tests and tools: the record builder underneath.
    FleetOperatorActions *actions() { return &_actions; }

signals:
    void vehicleStatusChanged();
    /// Something the operator should see as a toast. tone: ok, warn, crit or info.
    void notice(const QString &title, const QString &message, const QString &tone);

private:
    using Command = FleetOperatorActions::Command;

    void _fleetCommand(Command command);
    void _send(Vehicle *vehicle, Command command, const QJsonObject &alert);
    QString _problem(Vehicle *vehicle, Command command, const QJsonObject &alert) const;
    void _watch(Vehicle *vehicle);
    void _onCommandResult(Vehicle *vehicle, int command, int ackResult, int failureCode);
    void _onFlightMode(Vehicle *vehicle);
    void _onOutcome(int vehicleId, const QString &command, const QString &outcome, const QString &detail);
    void _setStatus(int vehicleId, const QString &text);
    void _refreshOperatorId();
    Vehicle *_vehicle(int id) const;

    FleetOperatorActions _actions;
    QPointer<FleetLink> _link;
    FleetAlertModel *_alerts = nullptr;
    QPointer<FleetDataAge> _ages;
    QPointer<FleetAudit> _audit;
    QVariantMap _status;
};
