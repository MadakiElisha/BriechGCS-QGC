#include "BriechSimulationController.h"

#include <QtCore/QtGlobal>
#include <QtMath>

namespace {
constexpr auto kImageName = "px4io/px4-sitl-sih:latest";
constexpr auto kContainerName = "briech-px4-sitl";
constexpr int kSimulationSystemId = 250;
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

    // The callback is copied into the lambda, so it lives exactly as long as
    // the connection and is released when the single-shot connection fires.
    const QMetaObject::Connection connection = connect(_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this, finished](int exitCode, QProcess::ExitStatus) {
                const QString output = QString::fromLocal8Bit(_process->readAll()).trimmed();
                if (exitCode != 0 && _lastError.isEmpty()) {
                    setLastError(output.isEmpty() ? QStringLiteral("Docker command failed.") : output);
                }
                if (exitCode != 0
                        && (output.contains(QStringLiteral("dockerDesktopLinuxEngine"), Qt::CaseInsensitive)
                            || output.contains(QStringLiteral("cannot connect to the Docker daemon"), Qt::CaseInsensitive)
                            || output.contains(QStringLiteral("error during connect"), Qt::CaseInsensitive))) {
                    setStatus(QStringLiteral("DOCKER OFFLINE"));
                }
                finished(exitCode, output);
            }, Qt::SingleShotConnection);
    _process->start(QStringLiteral("docker"), arguments);
    if (!_process->waitForStarted(1000)) {
        // A failed start must not leave this handler connected, or the next
        // command's exit would run this command's callback. Also stop a
        // process that is still starting so it cannot finish later.
        disconnect(connection);
        _process->kill();
        setStatus(QStringLiteral("DOCKER OFFLINE"));
        setLastError(QStringLiteral("Docker CLI could not be started. Install Docker Desktop and make sure it is running."));
        setBusy(false);
    }
}

void BriechSimulationController::startPX4SITL(const QString &home, double speedFactor, const QString &simulationModel)
{
    if (_running || _busy) {
        return;
    }

    const QStringList homeParts = home.trimmed().split(',', Qt::KeepEmptyParts);
    const QString model = simulationModel.trimmed();
    const QStringList supportedModels = {
        QStringLiteral("sihsim_quadx"),
        QStringLiteral("sihsim_airplane"),
        QStringLiteral("sihsim_standard_vtol")
    };
    if (homeParts.size() != 4 || !supportedModels.contains(model)) {
        setLastError(homeParts.size() != 4
                         ? QStringLiteral("Home must be LAT,LON,ALT,HEADING.")
                         : QStringLiteral("The selected PX4 SIH vehicle model is not supported."));
        setStatus(QStringLiteral("SIM ERROR"));
        return;
    }

    for (const QString &part : homeParts) {
        bool validNumber = false;
        part.trimmed().toDouble(&validNumber);
        if (!validNumber) {
            setLastError(QStringLiteral("Home must contain four numeric values: LAT,LON,ALT,HEADING."));
            setStatus(QStringLiteral("SIM ERROR"));
            return;
        }
    }

    setLastError(QString());
    _home = home.trimmed();
    _simulationModel = model;
    _speedFactor = qBound(0.1, speedFactor, 20.0);
    setBusy(true);
    setStatus(QStringLiteral("CHECKING PX4 SITL IMAGE"));
    inspectImage();
}

void BriechSimulationController::inspectImage()
{
    runDockerCommand({QStringLiteral("image"), QStringLiteral("inspect"), QString::fromLatin1(kImageName)},
                     [this](int exitCode, const QString &) {
        if (exitCode == 0) {
            setLastError(QString());
            launchContainer();
        } else {
            if (_status != QStringLiteral("DOCKER OFFLINE")) {
                setLastError(QStringLiteral("PX4 SITL image %1 was not found locally.").arg(QString::fromLatin1(kImageName)));
                setStatus(QStringLiteral("PX4 IMAGE MISSING"));
            }
            setBusy(false);
        }
    });
}

void BriechSimulationController::launchContainer()
{
    const QStringList homeParts = _home.split(',', Qt::KeepEmptyParts);
    const double latitude = homeParts.at(0).trimmed().toDouble();
    const double longitude = homeParts.at(1).trimmed().toDouble();
    const double altitude = homeParts.at(2).trimmed().toDouble();
    const double headingDegrees = homeParts.at(3).trimmed().toDouble();
    const double headingRadians = qDegreesToRadians(headingDegrees);

    setStatus(QStringLiteral("STARTING PX4 SITL"));
    runDockerCommand({QStringLiteral("rm"), QStringLiteral("-f"), QString::fromLatin1(kContainerName)},
                     [this, latitude, longitude, altitude, headingRadians](int, const QString &) {
        // A missing old container is the normal startup path.
        setLastError(QString());

        QStringList runArguments = {
            // -i keeps stdin open for PX4's pxh shell: without it the shell redraws
            // its prompt forever (~100 MB of log every 5 minutes). The Docker Desktop
            // branch below also runs PX4 as a daemon. Cap the log too.
            QStringLiteral("run"), QStringLiteral("-d"), QStringLiteral("-i"),
            QStringLiteral("--log-opt"), QStringLiteral("max-size=10m"),
            QStringLiteral("--log-opt"), QStringLiteral("max-file=2"),
            QStringLiteral("--name"), QString::fromLatin1(kContainerName),
            QStringLiteral("-e"), QStringLiteral("PX4_SIM_MODEL=%1").arg(_simulationModel),
            QStringLiteral("-e"), QStringLiteral("PX4_SIM_SPEED_FACTOR=%1").arg(QString::number(_speedFactor, 'f', 2)),
            QStringLiteral("-e"), QStringLiteral("PX4_HOME_LAT=%1").arg(QString::number(latitude, 'f', 7)),
            QStringLiteral("-e"), QStringLiteral("PX4_HOME_LON=%1").arg(QString::number(longitude, 'f', 7)),
            QStringLiteral("-e"), QStringLiteral("PX4_HOME_ALT=%1").arg(QString::number(altitude, 'f', 2)),
            QStringLiteral("-e"), QStringLiteral("PX4_HOME_YAW=%1").arg(QString::number(headingRadians, 'f', 8)),
            QStringLiteral("-e"), QStringLiteral("PX4_PARAM_MAV_SYS_ID=%1").arg(kSimulationSystemId)
        };
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
        // The PX4 image uses localhost as its MAVLink destination on Linux.
        runArguments << QStringLiteral("--network") << QStringLiteral("host");
        runArguments << QString::fromLatin1(kImageName);
#else
        // The image's entrypoint targets whatever host.docker.internal resolves
        // to first, which Docker Desktop may return as IPv6. PX4's MAVLink
        // target option only accepts IPv4, so apply the same rewrite with the
        // IPv4 host address.
        runArguments << QStringLiteral("--entrypoint") << QStringLiteral("/bin/sh")
                     << QString::fromLatin1(kImageName) << QStringLiteral("-c")
                     << QStringLiteral(
                            "host_ip=$(getent ahostsv4 host.docker.internal | awk 'NR==1{print $1}')\n"
                            "if [ -z \"$host_ip\" ]; then exec /opt/px4/bin/px4-entrypoint.sh; fi\n"
                            "sed -i \"s/mavlink start -x -u/mavlink start -x -t $host_ip -u/g\" /opt/px4/etc/init.d-posix/px4-rc.mavlink\n"
                            "sed -i \"s|uxrce_dds_client start -t udp|uxrce_dds_client start -t udp -h $host_ip|\" /opt/px4/etc/init.d-posix/rcS\n"
                            // Daemon mode: no pxh shell to flood the log or to exit
                            // (and stop PX4) when stdin closes.
                            "exec /opt/px4/bin/px4 -d");
#endif

        runDockerCommand(runArguments,
                         [this](int exitCode, const QString &) {
            if (exitCode == 0) {
                setStatus(QStringLiteral("VERIFYING PX4 SITL"));
                verifyContainerRunning();
            } else {
                setBusy(false);
                if (_status != QStringLiteral("DOCKER OFFLINE")) {
                    setStatus(QStringLiteral("SIM ERROR"));
                }
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
            setStatus(QStringLiteral("PX4 SITL RUNNING - UDP 14550"));
        } else {
            setRunning(false);
            if (exitCode == 0) {
                setLastError(QStringLiteral("PX4 SITL exited during startup. Check Docker logs for briech-px4-sitl."));
            }
            setStatus(QStringLiteral("SITL EXITED"));
        }
    });
}

void BriechSimulationController::stopSimulation()
{
    if (_busy) {
        return;
    }

    setBusy(true);
    setLastError(QString());
    setStatus(QStringLiteral("STOPPING PX4 SITL"));
    runDockerCommand({QStringLiteral("rm"), QStringLiteral("-f"), QString::fromLatin1(kContainerName)},
                     [this](int, const QString &) {
        setLastError(QString());
        setRunning(false);
        setBusy(false);
        setStatus(QStringLiteral("SIM OFFLINE"));
    });
}
