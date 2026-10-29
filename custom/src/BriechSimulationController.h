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
    Q_PROPERTY(int systemId READ systemId CONSTANT)

public:
    explicit BriechSimulationController(QObject *parent = nullptr);

    bool running() const { return _running; }
    bool busy() const { return _busy; }
    QString status() const { return _status; }
    QString lastError() const { return _lastError; }
    int systemId() const { return 250; }

    Q_INVOKABLE void startPX4SITL(const QString &home, double speedFactor, const QString &simulationModel);
    Q_INVOKABLE void stopSimulation();

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
    void launchContainer();
    void verifyContainerRunning();
    void runDockerCommand(const QStringList &arguments, const std::function<void(int, const QString &)> &finished);

    QProcess *_process = nullptr;
    bool _running = false;
    bool _busy = false;
    QString _status = QStringLiteral("SIM OFFLINE");
    QString _lastError;
    QString _home = QStringLiteral("8.893321,7.264172,400.0,0.0");
    QString _simulationModel = QStringLiteral("sihsim_quadx");
    double _speedFactor = 1.0;
};
