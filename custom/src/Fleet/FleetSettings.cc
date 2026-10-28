#include "FleetSettings.h"

#include <QtCore/QSettings>

namespace {
constexpr auto kEnabledKey = "Fleet/enabled";
}

FleetSettings::FleetSettings(QObject *parent)
    : QObject(parent)
    , _enabled(QSettings().value(QString::fromLatin1(kEnabledKey), false).toBool())
{
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
