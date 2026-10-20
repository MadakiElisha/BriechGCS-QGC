#pragma once

#include <QtCore/QObject>
#include <QtCore/QProcess>

#include <functional>

class BriechSimulationController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit BriechSimulationController(QObject *parent = nullptr);

    bool running() const { return _running; }
    bool busy() const { return _busy; }
    QString status() const { return _status; }
    QString lastError() const { return _lastError; }

    Q_INVOKABLE void startArduCopter(const QString &home, double speedup, bool withLatency);
    Q_INVOKABLE void stopArduCopter();

signals:
    void runningChanged();
    void busyChanged();
    void statusChanged();
    void lastErrorChanged();

private:
    void setRunning(bool running);
    void setBusy(bool busy);
    void setStatus(const QString &status);
    void setLastError(const QString &error);
    void inspectImage();
    void buildImage();
    void launchContainer();
    void verifyContainerRunning();
    void runDockerCommand(const QStringList &arguments, const std::function<void(int, const QString &)> &finished);

    QProcess *_process = nullptr;
    bool _running = false;
    bool _busy = false;
    QString _status = QStringLiteral("SIM OFFLINE");
    QString _lastError;
    QString _home = QStringLiteral("42.3898,-71.1476,14.0,270.0");
    double _speedup = 1.0;
};
