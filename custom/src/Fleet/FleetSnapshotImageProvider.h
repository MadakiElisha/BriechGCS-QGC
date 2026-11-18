#pragma once

#include <QtCore/QPointer>
#include <QtQuick/QQuickImageProvider>

#include "FleetSnapshots.h"

/// Serves FleetSnapshots' decoded pictures to QML as
///   image://fleetsnapshot/<snapshot_id>?r=<FleetSnapshots.revision>
/// (the r query only makes QML ask again after a picture arrives). Returns a
/// null image when the picture is not ready; the QML then shows its own text.
/// Kept apart from FleetSnapshots because it needs Qt Quick, which the Fleet
/// unit tests do not link. Registered in CustomPlugin::createQmlApplicationEngine.
class FleetSnapshotImageProvider : public QQuickImageProvider
{
public:
    explicit FleetSnapshotImageProvider(FleetSnapshots *snapshots)
        : QQuickImageProvider(QQuickImageProvider::Image)
        , _snapshots(snapshots)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        const QString snapshotId = id.section(QLatin1Char('?'), 0, 0);
        QImage image = _snapshots ? _snapshots->image(snapshotId) : QImage();
        if (!image.isNull() && requestedSize.isValid()) {
            image = image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
        if (size) {
            *size = image.size();
        }
        return image;
    }

private:
    QPointer<FleetSnapshots> _snapshots;
};
