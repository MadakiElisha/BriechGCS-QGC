#include "FleetVehicleState.h"

#include <cmath>

#include <QtCore/QJsonArray>

namespace {

bool usable(const std::optional<double> &value)
{
    return value.has_value() && std::isfinite(*value);
}

/// A whole percent, as the schema's percent type requires.
int wholePercent(double value)
{
    return static_cast<int>(std::lround(qBound(0.0, value, 100.0)));
}

} // namespace

namespace FleetVehicleState {

QString displayName(int id)
{
    return QStringLiteral("BRCH-%1").arg(id);
}

std::optional<bool> canTakeTask(const FleetVehicleSample &sample)
{
    if (!usable(sample.batteryPct)) {
        return std::nullopt;
    }
    if (*sample.batteryPct <= kLowBatteryPercent) {
        return false;
    }
    if (sample.armed) {
        return true;
    }
    return sample.canArm;
}

QJsonObject vehicleJson(const FleetVehicleSample &sample)
{
    if (sample.id < 1 || sample.id > 255 || sample.commsLost) {
        return {};
    }

    QJsonObject vehicle{
        {QStringLiteral("vehicle_id"), sample.id},
        {QStringLiteral("name"), displayName(sample.id)},
        {QStringLiteral("mode"), sample.mode.left(64)},
        {QStringLiteral("armed"), sample.armed},
        {QStringLiteral("flying"), sample.flying},
    };

    if (usable(sample.lat) && usable(sample.lon)) {
        QJsonObject pos{{QStringLiteral("lat"), *sample.lat}, {QStringLiteral("lon"), *sample.lon}};
        if (usable(sample.altRelM)) {
            pos.insert(QStringLiteral("alt_rel_m"), *sample.altRelM);
        }
        if (usable(sample.altAmslM)) {
            pos.insert(QStringLiteral("alt_amsl_m"), *sample.altAmslM);
        }
        vehicle.insert(QStringLiteral("pos"), pos);
    }
    if (usable(sample.headingDeg)) {
        // 0 to under 360: 360 and negative headings wrap.
        double heading = std::fmod(*sample.headingDeg, 360.0);
        if (heading < 0) {
            heading += 360.0;
        }
        if (heading >= 360.0) {
            heading = 0.0;
        }
        vehicle.insert(QStringLiteral("heading_deg"), heading);
    }
    if (usable(sample.groundSpeedMs)) {
        vehicle.insert(QStringLiteral("groundspeed_ms"), qMax(0.0, *sample.groundSpeedMs));
    }
    if (usable(sample.batteryPct)) {
        vehicle.insert(QStringLiteral("battery_pct"), wholePercent(*sample.batteryPct));
    }
    if (usable(sample.linkLossPct)) {
        vehicle.insert(QStringLiteral("link_quality_pct"), wholePercent(100.0 - *sample.linkLossPct));
    }
    if (const std::optional<bool> task = canTakeTask(sample)) {
        vehicle.insert(QStringLiteral("can_take_task"), *task);
    }
    return vehicle;
}

QJsonObject reportData(const QList<FleetVehicleSample> &samples)
{
    QJsonArray vehicles;
    for (const FleetVehicleSample &sample : samples) {
        if (vehicles.size() >= kMaxVehicles) {
            break;
        }
        const QJsonObject vehicle = vehicleJson(sample);
        if (!vehicle.isEmpty()) {
            vehicles.append(vehicle);
        }
    }
    return {{QStringLiteral("vehicles"), vehicles}};
}

} // namespace FleetVehicleState
