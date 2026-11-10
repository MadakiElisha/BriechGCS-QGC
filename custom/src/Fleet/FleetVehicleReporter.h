#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QTimer>

#include "FleetVehicleState.h"

class FleetLink;
class Vehicle;

/// Tells the coordinator what QGC's vehicles are doing: one vehicle.state
/// every second while FleetLink is connected, with every vehicle QGC has.
/// The coordinator uses it only to suggest a drone for an alert; flight data
/// itself never goes through the coordinator.
///
/// Runs on the main thread. FleetLink adds the envelope and owns the socket;
/// this class only reads QGC's vehicles and hands FleetLink the data.
class FleetVehicleReporter : public QObject
{
    Q_OBJECT

public:
    explicit FleetVehicleReporter(FleetLink *link, QObject *parent = nullptr);

    /// What QGC knows about vehicle right now, as plain values.
    static FleetVehicleSample sample(Vehicle *vehicle);

private:
    void _onLinkState();
    void _report();

    QPointer<FleetLink> _link;
    QTimer _timer;
};
