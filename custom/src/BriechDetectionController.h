#pragma once

#include <QtCore/QDateTime>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtNetwork/QUdpSocket>

class BriechDetectionController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList detections READ detections NOTIFY detectionsChanged)
    Q_PROPERTY(double confidenceThreshold READ confidenceThreshold WRITE setConfidenceThreshold NOTIFY confidenceThresholdChanged)
    Q_PROPERTY(int lastFrameAgeMs READ lastFrameAgeMs NOTIFY lastFrameAgeMsChanged)
    Q_PROPERTY(QString transportStatus READ transportStatus NOTIFY transportStatusChanged)

public:
    explicit BriechDetectionController(QObject *parent = nullptr);

    QVariantList detections() const { return _detections; }
    double confidenceThreshold() const { return _confidenceThreshold; }
    int lastFrameAgeMs() const { return _lastFrameAgeMs; }
    QString transportStatus() const { return _transportStatus; }

    void setConfidenceThreshold(double threshold);

    // Accepts one JSON detection frame. This is also useful for deterministic
    // integration tests without opening a video or companion link.
    Q_INVOKABLE bool ingestJson(const QString &json);

signals:
    void detectionsChanged();
    void confidenceThresholdChanged();
    void lastFrameAgeMsChanged();
    void transportStatusChanged();

private slots:
    void readDatagrams();
    void expireDetections();

private:
    void setTransportStatus(const QString &status);

    QUdpSocket _socket;
    QTimer _expiryTimer;
    QVariantList _detections;
    double _confidenceThreshold = 0.45;
    int _lastFrameAgeMs = -1;
    qint64 _lastFrameTimestampMs = 0;
    QString _transportStatus = QStringLiteral("LISTENING UDP 5801");
};
