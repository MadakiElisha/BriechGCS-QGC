# QGC Simulation Tools

Tools for testing QGroundControl without physical hardware.

## Quick Start

| Tool | Use Case | Setup |
|------|----------|-------|
| `mock_vehicle.py` | UI testing, quick checks | `pip install pymavlink` |
| `run-px4-sitl-docker.sh` | PX4 flight simulation and mission testing | Local PX4 SIH Docker image |

## Mock Vehicle (Lightweight)

A minimal MAVLink simulator for UI testing. Does not simulate flight dynamics.

```bash
# Install
pip install pymavlink

# Run (QGC connects to UDP 14550)
./mock_vehicle.py

# Multiple vehicles
./mock_vehicle.py --system-id 1 --port 14550 &
./mock_vehicle.py --system-id 2 --port 14551 &

# TCP mode (mock MAVLink only; no simulated flight dynamics)
./mock_vehicle.py --tcp --port 5760
```

**Features:**
- Heartbeat, GPS, attitude, battery telemetry
- Arm/disarm commands
- Mode changes
- Basic parameter support

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--host` | 127.0.0.1 | Host address |
| `--port` | 14550 | Port number |
| `--tcp` | off | Use TCP instead of UDP |
| `--system-id` | 1 | MAVLink system ID |
| `--rate` | 10 | Telemetry rate (Hz) |
| `--sitl` | off | SITL-compatible mode (TCP:5760) |

**Limitations:** No flight dynamics, no mission execution, limited MAVLink support.

## PX4 SIH (Full Simulation)

Full PX4 Software-in-Hardware simulation through the local Docker image. Briech GCS connects over UDP 14550 and starts the mission using the PX4 vehicle's native mission mode.

```bash
# Start the default quadrotor model
./run-px4-sitl-docker.sh

# Select another vehicle type and home position
./run-px4-sitl-docker.sh --model sihsim_airplane --home 9.0765,7.3986,50,270
./run-px4-sitl-docker.sh --model sihsim_standard_vtol --speed-factor 1

# Several drones at once: each needs its own system ID and container name,
# otherwise QGC merges drones that share an ID into one vehicle
./run-px4-sitl-docker.sh --system-id 1 --name px4-1 --home 42.3898,-71.1476,14,270
./run-px4-sitl-docker.sh --system-id 2 --name px4-2 --home 42.3898,-71.1472,14,270

# Briech GCS connects automatically to UDP 14550
```

Options: `--model`, `--home LAT,LON,ALT,HEADING`, `--speed-factor N`, `--system-id ID` (1-255, default 250, the ID the Briech GCS simulation panel uses) and `--name CONTAINER` (default `briech-px4-sitl`).

Supported models: `sihsim_quadx` (multirotor), `sihsim_airplane` (fixed wing), and `sihsim_standard_vtol` (VTOL).

The launcher expects the local `px4io/px4-sitl-sih:latest` image and does not build or pull it. The Briech GCS simulation controls use the same image, choose a model from the Plan vehicle type, and use the first mission waypoint as home when available.

**Docker commands:**
```bash
docker logs -f briech-px4-sitl   # View logs
docker rm -f briech-px4-sitl     # Stop and remove simulation
```

On Docker Desktop (Windows and macOS) PX4 runs as a daemon (`px4 -d`), with no interactive shell. With the shell, a container without input redraws its prompt endlessly (about 100 MB of log every five minutes), and once its input closes, for example after `docker start`, the shell exits and stops PX4. On Linux the image's own entrypoint is used, so the container keeps its input open with `docker run -i`. Logs are capped at 10 MB.

**Requirements:** Docker

## Connecting QGC

### Mock Vehicle (UDP)
1. Start `./mock_vehicle.py`
2. QGC auto-connects to UDP 14550

### PX4 SIH
1. Start `./run-px4-sitl-docker.sh` or use the Briech GCS simulation panel.
2. QGC connects on UDP 14550 automatically.

## Comparison

| Feature | mock_vehicle.py | PX4 SIH |
|---------|-----------------|-----------------|
| Setup time | Seconds | Starts from the local image |
| Dependencies | pymavlink | Docker and PX4 SIH image |
| Flight dynamics | ❌ | ✓ |
| Mission execution | ❌ | ✓ |
| Geofence support | ❌ | ✓ |
| All MAVLink commands | ❌ | ✓ |
| Resource usage | Low | Medium |
| Best for | UI testing | PX4 integration and mission testing |

## Other Simulators

For more advanced PX4 simulation:
- [PX4 SIH simulation](https://docs.px4.io/main/en/sim_sih/) - Flight dynamics inside PX4
- [PX4 Gazebo simulation](https://docs.px4.io/main/en/sim_gazebo_gz/) - 3D physics simulation
- [Gazebo](https://gazebosim.org/) - 3D physics simulation
