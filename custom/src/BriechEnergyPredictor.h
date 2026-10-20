#pragma once

#include <QtCore/QObject>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

class BriechEnergyPredictor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList waypointPredictions READ waypointPredictions NOTIFY predictionsChanged)
    Q_PROPERTY(double homePredictedPercent READ homePredictedPercent NOTIFY predictionsChanged)
    Q_PROPERTY(double homeLowerPercent READ homeLowerPercent NOTIFY predictionsChanged)
    Q_PROPERTY(double homeUpperPercent READ homeUpperPercent NOTIFY predictionsChanged)
    Q_PROPERTY(int rtlWaypointIndex READ rtlWaypointIndex NOTIFY predictionsChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool modelAvailable READ modelAvailable CONSTANT)

public:
    explicit BriechEnergyPredictor(QObject *parent = nullptr);

    QVariantList waypointPredictions() const { return _waypointPredictions; }
    double homePredictedPercent() const { return _homePredictedPercent; }
    double homeLowerPercent() const { return _homeLowerPercent; }
    double homeUpperPercent() const { return _homeUpperPercent; }
    int rtlWaypointIndex() const { return _rtlWaypointIndex; }
    QString status() const { return _status; }
    bool modelAvailable() const { return false; }

    // Coordinates are maps containing latitude and longitude in degrees.
    // This deliberately remains advisory: it never dispatches a vehicle command.
    Q_INVOKABLE void recompute(const QVariantList &waypoints,
                               const QVariantMap &current,
                               const QVariantMap &home,
                               double currentBatteryPercent,
                               double observedUsedPercent,
                               double flownMeters,
                               double groundSpeedMps);
    Q_INVOKABLE void clear();

signals:
    void predictionsChanged();
    void statusChanged();

private:
    static double distanceMeters(const QVariantMap &a, const QVariantMap &b);
    void setStatus(const QString &status);

    QVariantList _waypointPredictions;
    double _homePredictedPercent = qQNaN();
    double _homeLowerPercent = qQNaN();
    double _homeUpperPercent = qQNaN();
    int _rtlWaypointIndex = -1;
    QString _status = QStringLiteral("ENERGY · WAITING FOR TELEMETRY");
};
