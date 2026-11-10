#pragma once

#include <functional>

#include <QtCore/QHash>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVariantMap>

/// How long ago each drone was last heard, for the handoff's data-age rule:
/// a drone report older than 3 s is amber, older than 10 s is grey and stale.
///
/// QGC only says "communication lost" after its own timeout, so this keeps the
/// time of the last MAVLink message from each system id (CustomPlugin feeds it
/// from MAVLinkProtocol::messageReceived) and publishes the ages once a second.
/// QML reads one small map instead of binding to every telemetry update.
///
/// Qt only, no QGC types, so it is tested on its own (custom/test/Fleet).
class FleetDataAge : public QObject
{
    Q_OBJECT
    /// Vehicle id (as a string) -> whole seconds since it was last heard.
    /// A vehicle never heard since tracking started is absent: show "--".
    Q_PROPERTY(QVariantMap seconds READ seconds NOTIFY secondsChanged)
    /// Vehicle id (as a string) -> Level (Fresh, Amber, Grey), from the exact age.
    Q_PROPERTY(QVariantMap levels READ levels NOTIFY secondsChanged)
    Q_PROPERTY(int amberAfter READ amberAfter CONSTANT)
    Q_PROPERTY(int greyAfter READ greyAfter CONSTANT)

public:
    enum Level { Unknown = -1, Fresh = 0, Amber = 1, Grey = 2 };
    Q_ENUM(Level)

    static constexpr int kAmberAfterS = 3;
    static constexpr int kGreyAfterS = 10;

    explicit FleetDataAge(QObject *parent = nullptr);

    /// The level for an age in milliseconds: Amber when older than 3 s, Grey
    /// when older than 10 s; Unknown for a negative age (never heard).
    static Level levelForMs(qint64 ageMs);

    /// Record a message from this system id, now.
    void heard(int id);
    /// Forget a vehicle QGC no longer has.
    void forget(int id);
    /// Whole seconds since id was heard, or -1 when never heard.
    Q_INVOKABLE int secondsFor(int id) const;
    /// The level of id's data now, as an int for QML and C++ callers.
    Q_INVOKABLE int levelOf(int id) const { return levelForMs(ageMs(id)); }

    QVariantMap seconds() const { return _seconds; }
    QVariantMap levels() const { return _levels; }
    int amberAfter() const { return kAmberAfterS; }
    int greyAfter() const { return kGreyAfterS; }

    /// Start or stop publishing; stopping forgets everything (Fleet turned off).
    void setActive(bool active);
    bool active() const { return _timer.isActive(); }

    /// Recompute the published map now (the timer does this once a second).
    void refresh();

    /// For tests: milliseconds since some fixed point.
    void setClock(std::function<qint64()> clock) { _clock = std::move(clock); }

signals:
    void secondsChanged();

private:
    qint64 now() const;
    qint64 ageMs(int id) const;     ///< -1 when never heard

    std::function<qint64()> _clock;
    QHash<int, qint64> _heardMs;
    QVariantMap _seconds;
    QVariantMap _levels;
    QTimer _timer;
};
