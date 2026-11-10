#pragma once

#include <functional>
#include <optional>

#include <QtCore/QHash>
#include <QtCore/QJsonObject>
#include <QtCore/QObject>
#include <QtCore/QString>

class QTimer;

/// The operator.action record of every fleet command (schemas/operator.action.schema.json).
///
/// One action_id ties the phases of one operator decision together:
///   decision  a named operator approved or rejected an alert
///   command   QGC sent a command to a vehicle (from an approval, or Hold all / Return all)
///   outcome   the vehicle confirmed, refused, or did not answer within the timeout
///
/// This class only builds and sends the records and waits for outcomes; it never
/// commands a vehicle. FleetDispatch sends the commands and reports what the
/// vehicles answer. Kept free of QGC types so it can be tested on its own.
class FleetOperatorActions : public QObject
{
    Q_OBJECT

public:
    enum class Command { Goto, Orbit, Hold, Return };
    enum class Outcome { Confirmed, Refused, NoResponse };

    /// Hands a record to FleetLink (sendMessage("operator.action", data)), which
    /// queues it while the coordinator is offline.
    using Sender = std::function<void(const QString &type, const QJsonObject &data)>;

    explicit FleetOperatorActions(Sender sender, QObject *parent = nullptr);
    ~FleetOperatorActions() override;

    static QString commandName(Command command);
    static QString outcomeName(Outcome outcome);
    static std::optional<Command> commandFromName(const QString &name);

    void setOperatorId(const QString &operatorId) { _operatorId = operatorId; }
    QString operatorId() const { return _operatorId; }
    /// How long a vehicle has to answer before the outcome is no_response.
    void setOutcomeTimeoutMs(int ms) { _timeoutMs = ms; }
    int outcomeTimeoutMs() const { return _timeoutMs; }

    /// "act-<stem>-<n>", unique across restarts (n starts from the clock).
    QString newActionId(const QString &stem);

    void decision(const QString &actionId, const QString &alertId, bool approve, int vehicleId,
                  std::optional<Command> command, bool extraConfirmation, const QString &detail = QString());

    /// Records that command was sent to vehicleId and waits for its outcome. A
    /// command still waiting on the same vehicle is settled as no_response first.
    void command(const QString &actionId, int vehicleId, Command command,
                 const QString &alertId = QString(), bool extraConfirmation = false);

    /// The command waiting for an outcome from vehicleId, if any.
    std::optional<Command> pending(int vehicleId) const;

    /// Settles the command waiting on vehicleId. Does nothing if none is waiting.
    void resolve(int vehicleId, Outcome outcome, const QString &detail = QString());

signals:
    /// An outcome was recorded, for the UI.
    void outcomeReported(int vehicleId, const QString &command, const QString &outcome, const QString &detail);

private:
    struct Waiting
    {
        QString actionId;
        Command command;
        QString alertId;
        bool extraConfirmation = false;
        QTimer *timer = nullptr;
    };

    QJsonObject _record(const QString &actionId, const QString &phase, const QString &alertId) const;

    Sender _sender;
    QString _operatorId = QStringLiteral("op-local");
    int _timeoutMs = 10000;
    qint64 _next = 0;
    QHash<int, Waiting> _waiting;
};
