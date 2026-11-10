#include "FleetSettings.h"

#include <QtCore/QSettings>

namespace {
constexpr auto kEnabledKey = "Fleet/enabled";
constexpr auto kAttitudeViewOpenKey = "Fleet/attitudeViewOpen";
constexpr auto kPrefer3DKey = "Fleet/prefer3D";
}

FleetSettings::FleetSettings(QObject *parent)
    : QObject(parent)
    , _enabled(QSettings().value(QString::fromLatin1(kEnabledKey), false).toBool())
    , _attitudeViewOpen(QSettings().value(QString::fromLatin1(kAttitudeViewOpenKey), false).toBool())
    , _prefer3D(QSettings().value(QString::fromLatin1(kPrefer3DKey), true).toBool())
{
}

void FleetSettings::setAttitudeViewOpen(bool open)
{
    if (_attitudeViewOpen == open) {
        return;
    }
    _attitudeViewOpen = open;
    QSettings().setValue(QString::fromLatin1(kAttitudeViewOpenKey), _attitudeViewOpen);
    emit attitudeViewOpenChanged();
}

void FleetSettings::setPrefer3D(bool prefer)
{
    if (_prefer3D == prefer) {
        return;
    }
    _prefer3D = prefer;
    QSettings().setValue(QString::fromLatin1(kPrefer3DKey), _prefer3D);
    emit prefer3DChanged();
}

void FleetSettings::setEnabled(bool enabled)
{
    if (_enabled == enabled) {
        return;
    }

    _enabled = enabled;
    QSettings().setValue(QString::fromLatin1(kEnabledKey), _enabled);
    emit enabledChanged();
}

bool FleetSettings::quick3DAvailable() const
{
#ifdef BRIECH_FLEET_3D
    return true;
#else
    return false;
#endif
}
