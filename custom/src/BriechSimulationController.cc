#include "BriechSimulationController.h"

#include <QtCore/QRegularExpression>

namespace {
constexpr auto kImageName = "ardupilot-sitl-4.5.6";
constexpr auto kContainerName = "arducopter-sitl";
}

BriechSimulationController::BriechSimulationController(QObject *parent)
    : QObject(parent)
    , _process(new QProcess(this))
{
    _process->setProcessChannelMode(QProcess::MergedChannels);
}

void BriechSimulationController::setRunning(bool running)
{
    if (_running != running) {
        _running = running;
        emit runningChanged();
    }
}

void BriechSimulationController::setBusy(bool busy)
{
    if (_busy != busy) {
        _busy = busy;
        emit busyChanged();
    }
}

void BriechSimulationController::setStatus(const QString &status)
{
    if (_status != status) {
        _status = status;
        emit statusChanged();
    }
}

void BriechSimulationController::setLastError(const QString &error)
{
    if (_lastError != error) {
        _lastError = error;
        emit lastErrorChanged();
    }
}

void BriechSimulationController::runDockerCommand(const QStringList &arguments, const std::function<void(int, const QString &)> &finished)
{
    if (_process->state() != QProcess::NotRunning) {
        setLastError(QStringLiteral("A Docker operation is already running."));
        setBusy(false);
        return;
    }

    auto *completion = new std::function<void(int, const QString &)>(finished);
    connect(_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this, completion](int exitCode, QProcess::ExitStatus) {
                const QString output = QString::fromLocal8Bit(_process->readAll());
                const auto callback = *completion;
                delete completion;
                if (exitCode != 0 && _lastError.isEmpty()) {
                    setLastError(output.trimmed().isEmpty() ? QStringLiteral("Docker command failed.") : output.trimmed());
                }
                if (exitCode != 0 && output.contains(QStringLiteral("dockerDesktopLinuxEngine"), Qt::CaseInsensitive)) {
                    setStatus(QStringLiteral("DOCKER OFFLINE"));
                }
                callback(exitCode, output.trimmed());
            }, Qt::SingleShotConnection);
    _process->start(QStringLiteral("docker"), arguments);
    if (!_process->waitForStarted(1000)) {
        delete completion;
        setStatus(QStringLiteral("DOCKER OFFLINE"));
        setLastError(QStringLiteral("Docker CLI could not be started. Install Docker Desktop and make sure it is running."));
        setBusy(false);
    }
}

void BriechSimulationController::startArduCopter(const QString &home, double speedup, bool withLatency)
{
    if (_running || _busy) {
        return;
    }

    setLastError(QString());
    _home = home.trimmed().isEmpty() ? QStringLiteral("42.3898,-71.1476,14.0,270.0") : home.trimmed();
    _speedup = qBound(0.1, speedup, 20.0);
    setBusy(true);
    setStatus(QStringLiteral("CHECKING SITL IMAGE"));
    inspectImage();
    Q_UNUSED(withLatency)
}

void BriechSimulationController::inspectImage()
{
    runDockerCommand({QStringLiteral("image"), QStringLiteral("inspect"), QString::fromLatin1(kImageName)},
                     [this](int exitCode, const QString &) {
        if (exitCode == 0) {
            setLastError(QString());
            launchContainer();
        } else {
            // A missing image is the normal first-run path, not a user error.
            // The image will be built immediately below.
            setLastError(QString());
            buildImage();
        }
    });
}

void BriechSimulationController::buildImage()
{
    setStatus(QStringLiteral("BUILDING SITL IMAGE"));
    runDockerCommand({QStringLiteral("build"), QStringLiteral("--tag"), QString::fromLatin1(kImageName),
                      QStringLiteral("--build-arg"), QStringLiteral("COPTER_TAG=Copter-4.5.6"),
                     QStringLiteral("https://github.com/radarku/ardupilot-sitl-docker.git")},
                     [this](int exitCode, const QString &) {
        if (exitCode == 0) {
            setLastError(QString());
            launchContainer();
        } else {
            setStatus(_lastError.contains(QStringLiteral("dockerDesktopLinuxEngine"), Qt::CaseInsensitive)
                          ? QStringLiteral("DOCKER OFFLINE")
                          : QStringLiteral("SIM ERROR"));
            setBusy(false);
        }
    });
}

void BriechSimulationController::launchContainer()
{
    const QStringList homeParts = _home.split(',', Qt::KeepEmptyParts);
    if (homeParts.size() != 4) {
        setLastError(QStringLiteral("Home must be LAT,LON,ALT,HEADING."));
        setStatus(QStringLiteral("SIM ERROR"));
        setBusy(false);
        return;
    }

    setStatus(QStringLiteral("STARTING SITL"));
    runDockerCommand({QStringLiteral("rm"), QStringLiteral("-f"), QString::fromLatin1(kContainerName)},
                     [this, homeParts](int, const QString &) {
        // Removing a previous container commonly returns non-zero when no
        // container exists. That is expected during a clean first launch.
        setLastError(QString());
        const QStringList runArguments = {
            QStringLiteral("run"), QStringLiteral("-d"), QStringLiteral("-t"),
            QStringLiteral("--name"), QString::fromLatin1(kContainerName),
            QStringLiteral("-p"), QStringLiteral("5760:5760"),
            QStringLiteral("-p"), QStringLiteral("14550:14550/udp"),
            QStringLiteral("-e"), QStringLiteral("VEHICLE=ArduCopter"),
            QStringLiteral("-e"), QStringLiteral("INSTANCE=0"),
            QStringLiteral("-e"), QStringLiteral("LAT=%1").arg(homeParts.at(0).trimmed()),
            QStringLiteral("-e"), QStringLiteral("LON=%1").arg(homeParts.at(1).trimmed()),
            QStringLiteral("-e"), QStringLiteral("ALT=%1").arg(homeParts.at(2).trimmed()),
            QStringLiteral("-e"), QStringLiteral("DIR=%1").arg(homeParts.at(3).trimmed()),
            QStringLiteral("-e"), QStringLiteral("MODEL=+"),
            // sim_vehicle.py accepts an integer speedup only.
            QStringLiteral("-e"), QStringLiteral("SPEEDUP=%1").arg(QString::number(qBound(1, qRound(_speedup), 20))),
            QStringLiteral("-e"), QStringLiteral("SITL_UDP_OUTPUT_ADDRESS=udp:host.docker.internal:14550"),
            QString::fromLatin1(kImageName)
        };

        runDockerCommand(runArguments,
                         [this](int exitCode, const QString &) {
            if (exitCode == 0) {
                setStatus(QStringLiteral("VERIFYING SITL"));
                verifyContainerRunning();
                setStatus(QStringLiteral("SITL RUNNING - TCP 5760"));
            } else {
                setStatus(_lastError.contains(QStringLiteral("dockerDesktopLinuxEngine"), Qt::CaseInsensitive)
                              ? QStringLiteral("DOCKER OFFLINE")
                              : QStringLiteral("SIM ERROR"));
            }
        });
    });
}

void BriechSimulationController::verifyContainerRunning()
{
    runDockerCommand({QStringLiteral("inspect"), QStringLiteral("--format={{.State.Running}}"), QString::fromLatin1(kContainerName)},
                     [this](int exitCode, const QString &output) {
        setBusy(false);
        if (exitCode == 0 && output.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0) {
            setLastError(QString());
            setRunning(true);
            setStatus(QStringLiteral("SITL RUNNING - TCP 5760"));
        } else {
            setRunning(false);
            if (exitCode == 0) {
                setLastError(QStringLiteral("SITL container exited during startup. Check Docker logs for arducopter-sitl."));
            }
            setStatus(QStringLiteral("SITL EXITED"));
        }
    });
}

void BriechSimulationController::stopArduCopter()
{
    if (_busy) {
        return;
    }

    setBusy(true);
    setLastError(QString());
    setStatus(QStringLiteral("STOPPING SITL"));
    runDockerCommand({QStringLiteral("rm"), QStringLiteral("-f"), QString::fromLatin1(kContainerName)},
                     [this](int, const QString &) {
        setLastError(QString());
        setRunning(false);
        setBusy(false);
        setStatus(QStringLiteral("SIM OFFLINE"));
    });
}
