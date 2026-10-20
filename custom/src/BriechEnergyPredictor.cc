#include "BriechEnergyPredictor.h"

#include <QtCore/QtMath>

namespace {
constexpr double kReservePercent = 20.0;
constexpr double kDefaultPercentPerMeter = 0.004;
constexpr double kMinimumConfidence = 0.35;
constexpr double kFallbackBandPercent = 8.0;

double coordinateValue(const QVariantMap &coordinate, const QString &key)
{
    bool ok = false;
    const double value = coordinate.value(key).toDouble(&ok);
    return ok ? value : qQNaN();
}

double clampPercent(double value)
{
    return qBound(0.0, value, 100.0);
}
}

BriechEnergyPredictor::BriechEnergyPredictor(QObject *parent)
    : QObject(parent)
{
}

double BriechEnergyPredictor::distanceMeters(const QVariantMap &a, const QVariantMap &b)
{
    const double lat1 = coordinateValue(a, QStringLiteral("latitude"));
    const double lon1 = coordinateValue(a, QStringLiteral("longitude"));
    const double lat2 = coordinateValue(b, QStringLiteral("latitude"));
    const double lon2 = coordinateValue(b, QStringLiteral("longitude"));
    if (qIsNaN(lat1) || qIsNaN(lon1) || qIsNaN(lat2) || qIsNaN(lon2)) {
        return 0.0;
    }

    constexpr double earthRadiusMeters = 6371000.0;
    const double dLat = qDegreesToRadians(lat2 - lat1);
    const double dLon = qDegreesToRadians(lon2 - lon1);
    const double aValue = qSin(dLat / 2) * qSin(dLat / 2)
        + qCos(qDegreesToRadians(lat1)) * qCos(qDegreesToRadians(lat2))
        * qSin(dLon / 2) * qSin(dLon / 2);
    return earthRadiusMeters * 2.0 * qAtan2(qSqrt(aValue), qSqrt(qMax(0.0, 1.0 - aValue)));
}

void BriechEnergyPredictor::recompute(const QVariantList &waypoints,
                                      const QVariantMap &current,
                                      const QVariantMap &home,
                                      double currentBatteryPercent,
                                      double observedUsedPercent,
                                      double flownMeters,
                                      double groundSpeedMps)
{
    _waypointPredictions.clear();
    _rtlWaypointIndex = -1;
    _homePredictedPercent = qQNaN();
    _homeLowerPercent = qQNaN();
    _homeUpperPercent = qQNaN();

    if (waypoints.isEmpty() || qIsNaN(currentBatteryPercent) || currentBatteryPercent < 0.0 || currentBatteryPercent > 100.0) {
        setStatus(QStringLiteral("ENERGY · WAITING FOR TELEMETRY"));
        emit predictionsChanged();
        return;
    }

    double percentPerMeter = kDefaultPercentPerMeter;
    bool observed = observedUsedPercent >= 2.0 && flownMeters >= 500.0 && observedUsedPercent > 0.0;
    if (observed) {
        percentPerMeter = observedUsedPercent / flownMeters;
    }

    double pathMeters = 0.0;
    QVariantMap previous = current;
    for (int i = 0; i < waypoints.size(); ++i) {
        const QVariantMap waypoint = waypoints.at(i).toMap();
        pathMeters += distanceMeters(previous, waypoint);
        const double estimate = clampPercent(currentBatteryPercent - pathMeters * percentPerMeter);
        const double band = observed ? qBound(3.0, estimate * 0.06, 8.0) : kFallbackBandPercent;
        QVariantMap prediction;
        prediction.insert(QStringLiteral("index"), i);
        prediction.insert(QStringLiteral("predictedPercent"), estimate);
        prediction.insert(QStringLiteral("lowerPercent"), clampPercent(estimate - band));
        prediction.insert(QStringLiteral("upperPercent"), clampPercent(estimate + band));
        prediction.insert(QStringLiteral("confidence"), observed ? 0.62 : kMinimumConfidence);
        prediction.insert(QStringLiteral("fallback"), !observed);
        _waypointPredictions.append(prediction);
        previous = waypoint;
    }

    const double returnMeters = distanceMeters(previous, home);
    const double homeEstimate = clampPercent(currentBatteryPercent - (pathMeters + returnMeters) * percentPerMeter);
    const double homeBand = observed ? qBound(3.0, homeEstimate * 0.06, 8.0) : kFallbackBandPercent;
    _homePredictedPercent = homeEstimate;
    _homeLowerPercent = clampPercent(homeEstimate - homeBand);
    _homeUpperPercent = clampPercent(homeEstimate + homeBand);

    double waypointToHome = returnMeters;
    for (int i = waypoints.size() - 1; i >= 0; --i) {
        const QVariantMap waypoint = waypoints.at(i).toMap();
        const double predicted = _waypointPredictions.at(i).toMap().value(QStringLiteral("predictedPercent")).toDouble();
        if (predicted - waypointToHome * percentPerMeter - homeBand >= kReservePercent) {
            _rtlWaypointIndex = i;
            break;
        }
        if (i > 0) {
            waypointToHome += distanceMeters(waypoints.at(i - 1).toMap(), waypoint);
        }
    }

    Q_UNUSED(groundSpeedMps)
    const QString source = observed ? QStringLiteral("OBSERVED") : QStringLiteral("FALLBACK LINEAR");
    setStatus(QStringLiteral("ENERGY · %1 · ADVISORY ONLY").arg(source));
    emit predictionsChanged();
}

void BriechEnergyPredictor::clear()
{
    _waypointPredictions.clear();
    _homePredictedPercent = qQNaN();
    _homeLowerPercent = qQNaN();
    _homeUpperPercent = qQNaN();
    _rtlWaypointIndex = -1;
    setStatus(QStringLiteral("ENERGY · WAITING FOR TELEMETRY"));
    emit predictionsChanged();
}

void BriechEnergyPredictor::setStatus(const QString &status)
{
    if (_status == status) {
        return;
    }
    _status = status;
    emit statusChanged();
}
