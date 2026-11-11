#include "FleetVehicleReporter.h"

#include <cmath>

#include "BatteryFactGroupListModel.h"
#include "FleetLink.h"
#include "HealthAndArmingCheckReport.h"
#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

namespace {

constexpr int kReportIntervalMs = 1000;    // the schema's "every 1 s"

// The value, or empty when it is NaN or infinite. Deliberately not called
// "finite": glibc declares ::finite(double) and GCC found the call ambiguous
// (it broke the Linux CI build; MSVC has no such function).
std::optional<double> finiteOrEmpty(double value)
{
    return std::isfinite(value) ? std::optional<double>(value) : std::nullopt;
}

} // namespace

FleetVehicleReporter::FleetVehicleReporter(FleetLink *link, QObject *parent)
    : QObject(parent)
    , _link(link)
    , _timer(this)
{
    _timer.setInterval(kReportIntervalMs);
    connect(&_timer, &QTimer::timeout, this, &FleetVehicleReporter::_report);
    connect(link, &FleetLink::stateChanged, this, &FleetVehicleReporter::_onLinkState);
    _onLinkState();
}

void FleetVehicleReporter::_onLinkState()
{
    // FleetLink drops vehicle.state while offline anyway; not sending keeps its
    // dropped count meaning "something went wrong" rather than "we were offline".
    const bool connected = _link && _link->state() == FleetLink::Connected;
    if (connected && !_timer.isActive()) {
        _timer.start();
        _report();
    } else if (!connected) {
        _timer.stop();
    }
}

void FleetVehicleReporter::_report()
{
    QmlObjectListModel *vehicles = MultiVehicleManager::instance()->vehicles();
    if (!_link || vehicles->count() == 0) {
        return;
    }
    QList<FleetVehicleSample> samples;
    for (int i = 0; i < vehicles->count(); ++i) {
        if (Vehicle *vehicle = qobject_cast<Vehicle *>(vehicles->get(i))) {
            samples.append(sample(vehicle));
        }
    }
    _link->sendMessage(QStringLiteral("vehicle.state"), FleetVehicleState::reportData(samples));
}

FleetVehicleSample FleetVehicleReporter::sample(Vehicle *vehicle)
{
    FleetVehicleSample s;
    s.id = vehicle->id();
    s.mode = vehicle->flightMode();
    s.armed = vehicle->armed();
    s.flying = vehicle->flying();
    s.commsLost = vehicle->vehicleLinkManager() && vehicle->vehicleLinkManager()->communicationLost();

    // QGC's altitude, heading and speed facts start at 0 and say nothing about
    // whether a value has arrived. They come in the same telemetry as the
    // position, so they are reported only once the position is valid; a fresh
    // vehicle sends no 0 m, 0 deg or 0 m/s that it never measured.
    const QGeoCoordinate position = vehicle->coordinate();
    if (position.isValid()) {
        s.lat = position.latitude();
        s.lon = position.longitude();
        s.altRelM = finiteOrEmpty(vehicle->altitudeRelative()->rawValue().toDouble());
        s.altAmslM = finiteOrEmpty(vehicle->altitudeAMSL()->rawValue().toDouble());
        s.headingDeg = finiteOrEmpty(vehicle->heading()->rawValue().toDouble());
        s.groundSpeedMs = finiteOrEmpty(vehicle->groundSpeed()->rawValue().toDouble());
    }

    // Lowest pack, as the Fleet pages show it. A pack reads NaN until it reports.
    QmlObjectListModel *batteries = vehicle->batteries();
    for (int i = 0; i < batteries->count(); ++i) {
        auto *battery = qobject_cast<BatteryFactGroup *>(batteries->get(i));
        const double percent = battery ? battery->percentRemaining()->rawValue().toDouble() : NAN;
        if (std::isfinite(percent) && (!s.batteryPct || percent < *s.batteryPct)) {
            s.batteryPct = percent;
        }
    }

    s.linkLossPct = finiteOrEmpty(vehicle->mavlinkLossPercent());

    const HealthAndArmingCheckReport *health = vehicle->healthAndArmingCheckReport();
    if (health && health->supported()) {
        s.canArm = health->canArm();
    }
    return s;
}
