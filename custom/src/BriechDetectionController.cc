#include "BriechDetectionController.h"

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonValue>
#include <QtNetwork/QHostAddress>

namespace {
constexpr quint16 kDetectionPort = 5801;
constexpr int kDetectionExpiryMs = 450;
constexpr int kMaximumDetections = 128;

double clamp01(double value)
{
    return qBound(0.0, value, 1.0);
}
}

BriechDetectionController::BriechDetectionController(QObject *parent)
    : QObject(parent)
{
    connect(&_socket, &QUdpSocket::readyRead, this, &BriechDetectionController::readDatagrams);
    connect(&_expiryTimer, &QTimer::timeout, this, &BriechDetectionController::expireDetections);

    if (!_socket.bind(QHostAddress::AnyIPv4, kDetectionPort, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        setTransportStatus(QStringLiteral("DETECTION LINK ERROR"));
    }

    _expiryTimer.start(100);
}

void BriechDetectionController::setConfidenceThreshold(double threshold)
{
    const double bounded = qBound(0.0, threshold, 1.0);
    if (qFuzzyCompare(_confidenceThreshold, bounded)) {
        return;
    }
    _confidenceThreshold = bounded;
    emit confidenceThresholdChanged();
}

bool BriechDetectionController::ingestJson(const QString &json)
{
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setTransportStatus(QStringLiteral("INVALID DETECTION FRAME"));
        return false;
    }

    const QJsonObject frame = document.object();
    const QJsonArray sourceDetections = frame.value(QStringLiteral("detections")).toArray();
    if (sourceDetections.isEmpty()) {
        _detections.clear();
        _lastFrameTimestampMs = QDateTime::currentMSecsSinceEpoch();
        _lastFrameAgeMs = 0;
        emit detectionsChanged();
        setTransportStatus(QStringLiteral("LIVE · NO CONTACTS"));
        return true;
    }

    const double imageWidth = frame.value(QStringLiteral("image_width")).toDouble(1.0);
    const double imageHeight = frame.value(QStringLiteral("image_height")).toDouble(1.0);
    QVariantList normalized;
    normalized.reserve(qMin(sourceDetections.size(), kMaximumDetections));

    for (int index = 0; index < sourceDetections.size() && normalized.size() < kMaximumDetections; ++index) {
        const QJsonObject source = sourceDetections.at(index).toObject();
        const double confidence = source.value(QStringLiteral("confidence")).toDouble(-1.0);
        if (confidence < _confidenceThreshold || confidence > 1.0) {
            continue;
        }

        const bool normalizedInput = source.value(QStringLiteral("normalized")).toBool(false);
        const double divisorX = normalizedInput ? 1.0 : imageWidth;
        const double divisorY = normalizedInput ? 1.0 : imageHeight;
        QVariantMap detection;
        detection.insert(QStringLiteral("trackId"), source.value(QStringLiteral("track_id")).toInt(index + 1));
        detection.insert(QStringLiteral("className"), source.value(QStringLiteral("class")).toString(QStringLiteral("OBJECT")));
        detection.insert(QStringLiteral("confidence"), confidence);
        detection.insert(QStringLiteral("x"), clamp01(source.value(QStringLiteral("x")).toDouble() / divisorX));
        detection.insert(QStringLiteral("y"), clamp01(source.value(QStringLiteral("y")).toDouble() / divisorY));
        detection.insert(QStringLiteral("width"), clamp01(source.value(QStringLiteral("width")).toDouble() / divisorX));
        detection.insert(QStringLiteral("height"), clamp01(source.value(QStringLiteral("height")).toDouble() / divisorY));
        normalized.append(detection);
    }

    _detections = normalized;
    _lastFrameTimestampMs = QDateTime::currentMSecsSinceEpoch();
    _lastFrameAgeMs = 0;
    emit detectionsChanged();
    setTransportStatus(normalized.isEmpty() ? QStringLiteral("LIVE · BELOW THRESHOLD") : QStringLiteral("LIVE · %1 TRACKS").arg(normalized.size()));
    return true;
}

void BriechDetectionController::readDatagrams()
{
    while (_socket.hasPendingDatagrams()) {
        QByteArray datagram;
        datagram.resize(qsizetype(_socket.pendingDatagramSize()));
        _socket.readDatagram(datagram.data(), datagram.size());
        ingestJson(QString::fromUtf8(datagram));
    }
}

void BriechDetectionController::expireDetections()
{
    if (_lastFrameTimestampMs <= 0) {
        return;
    }

    const int age = int(qMax<qint64>(0, QDateTime::currentMSecsSinceEpoch() - _lastFrameTimestampMs));
    if (age != _lastFrameAgeMs) {
        _lastFrameAgeMs = age;
        emit lastFrameAgeMsChanged();
    }
    if (age > kDetectionExpiryMs && !_detections.isEmpty()) {
        _detections.clear();
        emit detectionsChanged();
        setTransportStatus(QStringLiteral("STALE · COMPANION LINK"));
    }
}

void BriechDetectionController::setTransportStatus(const QString &status)
{
    if (_transportStatus == status) {
        return;
    }
    _transportStatus = status;
    emit transportStatusChanged();
}
