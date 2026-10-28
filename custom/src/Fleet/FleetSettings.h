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

public:
    explicit FleetSettings(QObject *parent = nullptr);

    bool enabled() const { return _enabled; }
    void setEnabled(bool enabled);

    bool quick3DAvailable() const;

signals:
    void enabledChanged();

private:
    bool _enabled = false;
};
