# FleetLink interface: proposal for sign-off

Status: **built to this proposal, awaiting Miracle's sign-off.** FleetLink
is in `custom/src/Fleet/` and tested (`custom/test/Fleet/`). If anything below
does not suit FleetModels, say so before you build on it; once both boxes at
the bottom are ticked it is fixed the way the schemas are: change it together
or not at all.

FleetLink is the only Fleet class that talks to the coordinator. It owns the
WebSocket on a worker thread. Everything it gives Miracle's classes arrives on
the **main thread** through the signals below, so FleetModels,
FleetVehicleReporter and FleetDispatch never touch a socket or a thread.

The coordinator side of this already runs and is tested (`ground-core/`,
`make -C ops coordinator`). `sim/probe.py` does what FleetLink will do on
connect, so its output shows exactly what FleetLink will receive.

## What crosses the boundary

```cpp
// custom/src/Fleet/FleetLink.h (main-thread facade; FleetLinkWorker lives on its own QThread)
class FleetLink : public QObject
{
    Q_OBJECT
    // Registered in CustomPlugin with qmlRegisterSingletonInstance; C++ gets it from CustomPlugin::fleetLink().

public:
    enum State { Disabled, Connecting, Connected, Retrying, Unauthorized };
    Q_ENUM(State)

    Q_PROPERTY(State   state            READ state            NOTIFY stateChanged)
    Q_PROPERTY(int     retryInSeconds   READ retryInSeconds   NOTIFY stateChanged)   // countdown while Retrying
    Q_PROPERTY(int     retryAttempt     READ retryAttempt     NOTIFY stateChanged)
    Q_PROPERTY(QString lastError        READ lastError        NOTIFY stateChanged)   // never contains the token or full URL
    Q_PROPERTY(bool    coordinatorSilent READ coordinatorSilent NOTIFY silentChanged) // nothing heard for 10 s: offline banner
    Q_PROPERTY(QStringList recentMessages READ recentMessages NOTIFY recentMessagesChanged) // last 50, newest first, "hh:mm:ss.zzz type key", for the FLEET page debug list
    Q_PROPERTY(QString stateText READ stateText NOTIFY stateChanged)        // added: CONNECTED, RETRYING IN 4 S, ... for status rows
    Q_PROPERTY(int     droppedCount READ droppedCount NOTIFY droppedCountChanged) // added: messages FleetLink dropped

public slots:
    void start();   // reads Fleet/url, Fleet/token, Fleet/operatorId, Fleet/caFile; no-op unless Fleet/enabled
    void stop();    // closes the socket, stops the worker, state -> Disabled

    // Outgoing, from FleetVehicleReporter and FleetDispatch. FleetLink adds the
    // envelope (v, id, ts, src = "qgc-<operatorId>") so senders build only data.
    void sendMessage(const QString &type, const QJsonObject &data);

signals:
    void stateChanged();
    void silentChanged();
    void recentMessagesChanged();

    // Once per connection, right after hello. The whole picture: FleetModels
    // replaces everything it holds (this is the one place a model reset is right).
    void snapshotReceived(const QJsonObject &data);

    // Every 200 ms when anything arrived. Full messages (envelope + data), in
    // arrival order, newest only per (type, key). Never empty.
    void batchReceived(const QList<QJsonObject> &messages);
};
```

## Rules both sides rely on

| Rule | Detail |
|---|---|
| Threads | The QWebSocket and JSON parsing live on the worker. Signals are emitted on the main thread (queued). FleetLink never touches a Vehicle or a QML object. |
| Batching keys | `object.update` by `object_id`, `asset.state` by `asset_id`, `alert.new` and `alert.update` by `alert_id` (each type separately, so a new alert and its update in one batch both arrive, new first), `heartbeat` single key. |
| Checks | FleetLink drops and counts any message that is not JSON, has `v` other than 1, or has a type it does not know. Unknown *fields* are passed through untouched. |
| Snapshot order | `snapshotReceived` always comes before the first `batchReceived` of a connection. After a reconnect a new snapshot comes first, so FleetModels never merges across a gap. |
| Outgoing while not Connected | `vehicle.state` is dropped (it is stale by the next second anyway). `operator.action` is queued, at most 100, oldest dropped and counted, and sent after the next hello. |
| Reconnect | Delays 1, 2, 4, 8, 16, 30 s (cap), with ±20 % jitter, reset once a snapshot arrives. HTTP 401 means `Unauthorized`, retried at the 30 s cap. Close code 4400 (bad hello) is a bug and is logged as one. |
| Silence | `coordinatorSilent` turns true after 10 s with no message at all. The coordinator sends a `heartbeat` every 2 s, so this means the link or the coordinator is gone, not just quiet. |
| Settings (QSettings) | `Fleet/enabled`, `Fleet/url` (default `wss://localhost:8443/ws/v1/operator`), `Fleet/token`, `Fleet/operatorId`, `Fleet/caFile` (the dev CA, `ops/certs/ca.crt`, added to the socket's TLS config; never disable verification). |
| Hold all / Return all | Do not depend on FleetLink. FleetDispatch sends them to vehicles directly, then reports them with `sendMessage("operator.action", ...)`, which queues if offline. |

## What was decided while building, for Miracle to confirm

1. One `batchReceived(QList<QJsonObject>)` rather than a signal per type: it
   keeps arrival order across types (an `alert.new` before the
   `object.update` it is about). FleetModels routes by `type`.
2. FleetLink and FleetSettings are created in `CustomPlugin` and registered
   with `qmlRegisterSingletonInstance`, so C++ and QML share one instance.
   `FleetSettings.enabledChanged` starts and stops the link. This replaced the
   `qmlRegisterSingletonType` factory for FleetSettings.
3. `recentMessages` is a plain string list (newest first) for a debug view.
4. `FleetConnectionStatus.qml` now binds `connected` to `FleetLink.state` and
   shows `FleetLink.stateText`. That is the only QML touched. The message
   list on the FLEET page is still to be drawn: bind a `ListView` to
   `FleetLink.recentMessages`.

## Setting it up locally

```sh
make -C ops broker && make -C ops coordinator     # and make -C ops publisher for data
python3 ops/scripts/qgc-fleet-settings.py         # quit QGC first; writes [Fleet] in "BriechUAS Daily.ini"
```

Without QGC, `fleetlink_probe` (built with the tests) runs the same class:

```sh
cmake -S custom/test/Fleet -B build/fleet-tests -DCMAKE_PREFIX_PATH=~/Qt/6.10.1/macos
cmake --build build/fleet-tests && ctest --test-dir build/fleet-tests
build/fleet-tests/fleetlink_probe --ca ops/certs/ca.crt --token-file ops/secrets/operator.tokens --vehicles 3
```

## Sign-off

- [ ] George
- [ ] Miracle
