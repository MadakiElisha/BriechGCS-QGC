#pragma once

#include <optional>

#include <QtCore/QJsonObject>
#include <QtCore/QList>
#include <QtCore/QString>

/// What QGC knows about one vehicle at one moment, as plain values. An empty
/// optional means QGC has no real value for it, so it is left out of the report.
/// Filled from a QGC Vehicle by FleetVehicleReporter; kept free of QGC types so
/// the report can be tested on its own (custom/test/Fleet).
struct FleetVehicleSample
{
    int id = 0;                         ///< MAVLink system id
    QString mode;
    bool armed = false;
    bool flying = false;
    bool commsLost = false;
    std::optional<double> lat;          ///< position, only with a valid fix
    std::optional<double> lon;
    std::optional<double> altRelM;
    std::optional<double> altAmslM;
    std::optional<double> headingDeg;
    std::optional<double> groundSpeedMs;
    std::optional<double> batteryPct;   ///< lowest pack
    std::optional<double> linkLossPct;  ///< MAVLink packets lost, percent
    std::optional<bool> canArm;         ///< empty when the firmware does not report arming checks
};

/// vehicle.state (schemas/vehicle.state.schema.json) built from samples.
namespace FleetVehicleState {

/// Below this battery percentage a vehicle cannot take a task. Same value as
/// lowBatteryPercent in FleetFormat.js, the BATT LOW count on the Fleet pages.
constexpr int kLowBatteryPercent = 20;
/// The schema's maxItems for vehicles.
constexpr int kMaxVehicles = 64;

/// "BRCH-<id>", as the Fleet panel, map tags and FLEET page name vehicles.
QString displayName(int id);

/// Whether the coordinator may propose this vehicle for a task, or empty when
/// that cannot be known (battery or arming checks not reported). False when the
/// battery is at or below kLowBatteryPercent. Otherwise true when the vehicle is
/// already armed (its checks passed when it armed) or reports it can arm now.
std::optional<bool> canTakeTask(const FleetVehicleSample &sample);

/// One entry of data.vehicles, or an empty object when the vehicle must not be
/// reported: a system id outside 1..255, or communication lost (nothing about
/// it is current, so the coordinator's last_seen_ts is left to age).
QJsonObject vehicleJson(const FleetVehicleSample &sample);

/// data for vehicle.state: {"vehicles": [...]}, at most kMaxVehicles entries.
QJsonObject reportData(const QList<FleetVehicleSample> &samples);

} // namespace FleetVehicleState
