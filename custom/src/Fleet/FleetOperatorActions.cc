#include "FleetOperatorActions.h"

#include <QtCore/QDateTime>
#include <QtCore/QTimer>

namespace {

constexpr int kMaxActionIdLength = 96;      // ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$
constexpr int kMaxDetailLength = 200;

} // namespace

FleetOperatorActions::FleetOperatorActions(Sender sender, QObject *parent)
    : QObject(parent)
    , _sender(std::move(sender))
    , _next(QDateTime::currentMSecsSinceEpoch())
{
}

FleetOperatorActions::~FleetOperatorActions()
{
    for (const Waiting &waiting : std::as_const(_waiting)) {
        delete waiting.timer;
    }
}

QString FleetOperatorActions::commandName(Command command)
{
    switch (command) {
    case Command::Goto:
        return QStringLiteral("goto");
    case Command::Orbit:
        return QStringLiteral("orbit");
    case Command::Hold:
        return QStringLiteral("hold");
    case Command::Return:
        return QStringLiteral("return");
    }
    return QString();
}

QString FleetOperatorActions::outcomeName(Outcome outcome)
{
    switch (outcome) {
    case Outcome::Confirmed:
        return QStringLiteral("confirmed");
    case Outcome::Refused:
        return QStringLiteral("refused");
    case Outcome::NoResponse:
        return QStringLiteral("no_response");
    }
    return QString();
}

std::optional<FleetOperatorActions::Command> FleetOperatorActions::commandFromName(const QString &name)
{
    for (Command command : {Command::Goto, Command::Orbit, Command::Hold, Command::Return}) {
        if (commandName(command) == name) {
            return command;
        }
    }
    return std::nullopt;
}

QString FleetOperatorActions::newActionId(const QString &stem)
{
    // Shorten the stem, never the counter, so ids stay unique at the length limit.
    const QString counter = QLatin1Char('-') + QString::number(_next++);
    const QString prefix = QStringLiteral("act-");
    return prefix + stem.left(kMaxActionIdLength - prefix.size() - counter.size()) + counter;
}

QJsonObject FleetOperatorActions::_record(const QString &actionId, const QString &phase, const QString &alertId) const
{
    QJsonObject data{
        {QStringLiteral("action_id"), actionId},
        {QStringLiteral("operator_id"), _operatorId},
        {QStringLiteral("phase"), phase},
    };
    if (!alertId.isEmpty()) {
        data.insert(QStringLiteral("alert_id"), alertId);
    }
    return data;
}

void FleetOperatorActions::decision(const QString &actionId, const QString &alertId, bool approve, int vehicleId,
                                    std::optional<Command> command, bool extraConfirmation, const QString &detail)
{
    QJsonObject data = _record(actionId, QStringLiteral("decision"), alertId);
    data.insert(QStringLiteral("decision"), approve ? QStringLiteral("approve") : QStringLiteral("reject"));
    if (vehicleId > 0) {
        data.insert(QStringLiteral("vehicle_id"), vehicleId);
    }
    if (command) {
        data.insert(QStringLiteral("command"), commandName(*command));
    }
    if (extraConfirmation) {
        data.insert(QStringLiteral("extra_confirmation"), true);
    }
    if (!detail.isEmpty()) {
        data.insert(QStringLiteral("detail"), detail.left(kMaxDetailLength));
    }
    _sender(QStringLiteral("operator.action"), data);
}

void FleetOperatorActions::command(const QString &actionId, int vehicleId, Command command,
                                   const QString &alertId, bool extraConfirmation)
{
    resolve(vehicleId, Outcome::NoResponse, QStringLiteral("superseded by a newer command"));

    QJsonObject data = _record(actionId, QStringLiteral("command"), alertId);
    data.insert(QStringLiteral("vehicle_id"), vehicleId);
    data.insert(QStringLiteral("command"), commandName(command));
    if (extraConfirmation) {
        data.insert(QStringLiteral("extra_confirmation"), true);
    }
    _sender(QStringLiteral("operator.action"), data);

    auto *timer = new QTimer;
    timer->setSingleShot(true);
    timer->setInterval(_timeoutMs);
    connect(timer, &QTimer::timeout, this, [this, vehicleId, timer] {
        // Only the timer of the command still waiting may settle it.
        if (_waiting.contains(vehicleId) && _waiting.value(vehicleId).timer == timer) {
            resolve(vehicleId, Outcome::NoResponse, QStringLiteral("no answer within %1 s").arg(_timeoutMs / 1000));
        }
    });
    _waiting.insert(vehicleId, {actionId, command, alertId, extraConfirmation, timer});
    timer->start();
}

std::optional<FleetOperatorActions::Command> FleetOperatorActions::pending(int vehicleId) const
{
    if (!_waiting.contains(vehicleId)) {
        return std::nullopt;
    }
    return _waiting.value(vehicleId).command;
}

void FleetOperatorActions::resolve(int vehicleId, Outcome outcome, const QString &detail)
{
    if (!_waiting.contains(vehicleId)) {
        return;
    }
    const Waiting waiting = _waiting.take(vehicleId);
    waiting.timer->stop();
    waiting.timer->deleteLater();

    QJsonObject data = _record(waiting.actionId, QStringLiteral("outcome"), waiting.alertId);
    data.insert(QStringLiteral("vehicle_id"), vehicleId);
    data.insert(QStringLiteral("command"), commandName(waiting.command));
    data.insert(QStringLiteral("outcome"), outcomeName(outcome));
    if (waiting.extraConfirmation) {
        data.insert(QStringLiteral("extra_confirmation"), true);
    }
    if (!detail.isEmpty()) {
        data.insert(QStringLiteral("detail"), detail.left(kMaxDetailLength));
    }
    _sender(QStringLiteral("operator.action"), data);
    emit outcomeReported(vehicleId, commandName(waiting.command), outcomeName(outcome), detail);
}
