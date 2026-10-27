#pragma once

#include "FirmwarePluginFactory.h"
#include "QGCMAVLink.h"

class CustomFirmwarePlugin;
class FirmwarePlugin;

/// This custom implementation supports PX4 firmware across the vehicle classes
/// used by the PX4 SIH simulator and exposes the standard PX4 flight modes.
class CustomFirmwarePluginFactory : public FirmwarePluginFactory
{
    Q_OBJECT

public:
    CustomFirmwarePluginFactory();
    QList<QGCMAVLink::FirmwareClass_t> supportedFirmwareClasses() const final;
    QList<QGCMAVLink::VehicleClass_t> supportedVehicleClasses() const final;
    FirmwarePlugin *firmwarePluginForAutopilot(MAV_AUTOPILOT autopilotType, MAV_TYPE vehicleType) final;

private:
    CustomFirmwarePlugin *_pluginInstance = nullptr;
};

extern CustomFirmwarePluginFactory CustomFirmwarePluginFactoryImp;
