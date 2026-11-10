#pragma once

#include <QtCore/QObject>

/// Persistent on/off switch for the Briech Fleet layer.
///
/// Fleet is off by default. While it is off, the Modern view creates no fleet
/// QML and nothing fleet-related runs, so QGC behaves as it does without Fleet.
class FleetSettings : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    /// True when this build was compiled with Qt Quick 3D, so the 3D view can
    /// be offered. When false, fleet QML must fall back to the 2D indicator.
    Q_PROPERTY(bool quick3DAvailable READ quick3DAvailable CONSTANT)
    /// The attitude view beside the fleet panel is open. Remembered between runs.
    Q_PROPERTY(bool attitudeViewOpen READ attitudeViewOpen WRITE setAttitudeViewOpen NOTIFY attitudeViewOpenChanged)
    /// The operator's choice for that view: true for 3D (when quick3DAvailable),
    /// false for the flat 2D attitude indicator. Remembered between runs.
    Q_PROPERTY(bool prefer3D READ prefer3D WRITE setPrefer3D NOTIFY prefer3DChanged)

public:
    explicit FleetSettings(QObject *parent = nullptr);

    bool enabled() const { return _enabled; }
    void setEnabled(bool enabled);

    bool quick3DAvailable() const;

    bool attitudeViewOpen() const { return _attitudeViewOpen; }
    void setAttitudeViewOpen(bool open);

    bool prefer3D() const { return _prefer3D; }
    void setPrefer3D(bool prefer);

signals:
    void enabledChanged();
    void attitudeViewOpenChanged();
    void prefer3DChanged();

private:
    bool _enabled = false;
    bool _attitudeViewOpen = false;
    bool _prefer3D = true;
};
