#pragma once

#include <functional>

#include <QtCore/QByteArray>
#include <QtCore/QHash>
#include <QtCore/QJsonObject>
#include <QtCore/QList>
#include <QtCore/QString>
#include <QtCore/QStringList>

/// Wire rules for the coordinator link (schemas/ in the repo root).
///
/// Kept free of sockets, threads and QGC types so the rules can be tested on
/// their own (custom/test/Fleet).
namespace FleetProtocol {

constexpr int kVersion = 1;

/// Message types the coordinator sends to QGC.
const QStringList &incomingTypes();

/// Message types QGC sends to the coordinator after hello.
const QStringList &outgoingTypes();

struct ParseResult
{
    QJsonObject message;    ///< The whole message (envelope and data); valid when error is empty.
    QString error;          ///< Empty, or why it was dropped: json, version, type, shape.
};

/// Checks one text frame: a JSON object with v == 1, a type QGC receives, an
/// object in data, and the id the batch key needs. Full schema checks are the
/// coordinator's job; this guards only what QGC relies on.
ParseResult parse(const QByteArray &frame);

/// What a batch keeps only the newest message for: the type plus the id the
/// message is about (object_id, asset_id, alert_id). Heartbeats share one key.
QString coalesceKey(const QJsonObject &message);

/// UTC now, ISO 8601 with milliseconds, ending in Z.
QString utcNowIso();

/// A complete message around data, with a fresh id and the current time.
QJsonObject makeMessage(const QString &type, const QString &src, const QJsonObject &data);

/// A source or operator id as the schemas allow it: lower case letters, digits
/// and hyphens, at most 63 characters. Anything else becomes a hyphen.
QString sanitizeId(const QString &id);

} // namespace FleetProtocol

/// Holds incoming messages between hand-overs to the main thread, keeping only
/// the newest per coalesce key, in the order each key first arrived.
class FleetBatcher
{
public:
    void add(const QJsonObject &message);
    QList<QJsonObject> take();
    void clear();
    bool isEmpty() const { return _order.isEmpty(); }
    qsizetype size() const { return _order.size(); }

private:
    QStringList _order;
    QHash<QString, QJsonObject> _latest;
};

/// Reconnect delays: 1, 2, 4, 8, 16 s, then 30 s for every later attempt, each
/// with +/-20 % jitter so many clients do not reconnect in step.
class FleetBackoff
{
public:
    /// random returns a value in [0, 1); the default uses QRandomGenerator.
    explicit FleetBackoff(std::function<double()> random = {});

    int nextDelayMs();
    int maxDelayMs() const;
    void reset() { _attempt = 0; }
    int attempt() const { return _attempt; }

private:
    std::function<double()> _random;
    int _attempt = 0;
};
