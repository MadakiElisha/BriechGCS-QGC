#include "FleetDataAge.h"

#include <QtCore/QElapsedTimer>

namespace {

constexpr int kRefreshMs = 1000;

qint64 monotonicMs()
{
    static QElapsedTimer timer;
    if (!timer.isValid()) {
        timer.start();
    }
    return timer.elapsed();
}

} // namespace

FleetDataAge::FleetDataAge(QObject *parent)
    : QObject(parent)
    , _timer(this)
{
    _timer.setInterval(kRefreshMs);
    connect(&_timer, &QTimer::timeout, this, &FleetDataAge::refresh);
}

FleetDataAge::Level FleetDataAge::levelForMs(qint64 ageMs)
{
    if (ageMs < 0) {
        return Unknown;
    }
    if (ageMs > kGreyAfterS * 1000) {
        return Grey;
    }
    return ageMs > kAmberAfterS * 1000 ? Amber : Fresh;
}

qint64 FleetDataAge::now() const
{
    return _clock ? _clock() : monotonicMs();
}

void FleetDataAge::heard(int id)
{
    if (!_timer.isActive()) {
        return;     // Fleet is off: track nothing, so QGC behaves as before
    }
    _heardMs.insert(id, now());
}

void FleetDataAge::forget(int id)
{
    if (_heardMs.remove(id) > 0) {
        refresh();
    }
}

qint64 FleetDataAge::ageMs(int id) const
{
    const auto it = _heardMs.constFind(id);
    return it == _heardMs.constEnd() ? -1 : qMax<qint64>(0, now() - it.value());
}

int FleetDataAge::secondsFor(int id) const
{
    const qint64 ms = ageMs(id);
    return ms < 0 ? -1 : static_cast<int>(ms / 1000);
}

void FleetDataAge::setActive(bool active)
{
    if (active && !_timer.isActive()) {
        _timer.start();
    } else if (!active && _timer.isActive()) {
        _timer.stop();
        _heardMs.clear();
        refresh();
    }
}

void FleetDataAge::refresh()
{
    QVariantMap seconds;
    QVariantMap levels;
    for (auto it = _heardMs.constBegin(); it != _heardMs.constEnd(); ++it) {
        const QString key = QString::number(it.key());
        seconds.insert(key, secondsFor(it.key()));
        levels.insert(key, static_cast<int>(levelOf(it.key())));
    }
    // Most seconds nothing changes for a drone that is talking (age 0); only
    // notify QML when something it shows actually moves.
    if (seconds != _seconds || levels != _levels) {
        _seconds = seconds;
        _levels = levels;
        emit secondsChanged();
    }
}
