#!/usr/bin/env bash
# Start the local PX4 SIH image used by Briech GCS.

set -euo pipefail

IMAGE_NAME="${PX4_SITL_IMAGE:-px4io/px4-sitl-sih:latest}"
CONTAINER_NAME="${PX4_SITL_CONTAINER:-briech-px4-sitl}"
SIMULATION_MODEL="${PX4_SIM_MODEL:-sihsim_quadx}"
HOME_POSITION="${PX4_HOME:-42.3898,-71.1476,14.0,270.0}"
SPEED_FACTOR="${PX4_SIM_SPEED_FACTOR:-1}"
SYSTEM_ID=250

while (($#)); do
    case "$1" in
        --model)
            SIMULATION_MODEL="${2:?--model requires a PX4 SIH model}"
            shift 2
            ;;
        --home)
            HOME_POSITION="${2:?--home requires LAT,LON,ALT,HEADING}"
            shift 2
            ;;
        --speed-factor)
            SPEED_FACTOR="${2:?--speed-factor requires a number}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--model MODEL] [--home LAT,LON,ALT,HEADING] [--speed-factor N]" >&2
            exit 2
            ;;
    esac
done

case "$SIMULATION_MODEL" in
    sihsim_quadx|sihsim_airplane|sihsim_standard_vtol) ;;
    *)
        echo "Unsupported PX4 SIH model: $SIMULATION_MODEL" >&2
        echo "Use sihsim_quadx, sihsim_airplane, or sihsim_standard_vtol." >&2
        exit 2
        ;;
esac

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed or not in PATH." >&2
    exit 1
fi

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "PX4 SITL image $IMAGE_NAME is not available locally." >&2
    echo "Load the PX4 SIH Docker image first; this script does not build or pull images." >&2
    exit 1
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

DOCKER_ARGS=(run -d --name "$CONTAINER_NAME"
    -e "PX4_SIM_MODEL=$SIMULATION_MODEL"
    -e "PX4_SIM_SPEED_FACTOR=$SPEED_FACTOR"
    -e "PX4_HOME_LAT=${HOME_POSITION%%,*}"
    -e "PX4_HOME_LON=$(cut -d, -f2 <<<"$HOME_POSITION")"
    -e "PX4_HOME_ALT=$(cut -d, -f3 <<<"$HOME_POSITION")"
    -e "PX4_HOME_YAW=$(awk -F, '{printf "%.8f", $4 * atan2(0, -1) / 180}' <<<"$HOME_POSITION")"
    -e "PX4_PARAM_MAV_SYS_ID=$SYSTEM_ID")

# PX4's prebuilt image sends MAVLink to localhost on Linux. On Docker Desktop
# the image's entrypoint resolves host.docker.internal, which can return an
# IPv6 address that PX4's MAVLink target option rejects, so target the IPv4
# host address instead.
if [[ "$(uname -s)" == Linux ]]; then
    DOCKER_ARGS+=(--network host "$IMAGE_NAME")
else
    DOCKER_ARGS+=(--entrypoint /bin/sh "$IMAGE_NAME" -c '
host_ip=$(getent ahostsv4 host.docker.internal | awk "NR==1{print \$1}")
if [ -z "$host_ip" ]; then exec /opt/px4/bin/px4-entrypoint.sh; fi
sed -i "s/mavlink start -x -u/mavlink start -x -t $host_ip -u/g" /opt/px4/etc/init.d-posix/px4-rc.mavlink
sed -i "s|uxrce_dds_client start -t udp|uxrce_dds_client start -t udp -h $host_ip|" /opt/px4/etc/init.d-posix/rcS
exec /opt/px4/bin/px4')
fi

docker "${DOCKER_ARGS[@]}"

echo "PX4 SIH started: model=$SIMULATION_MODEL home=$HOME_POSITION"
echo "QGroundControl receives MAVLink on UDP 14550 (system ID $SYSTEM_ID)."
echo "Logs: docker logs -f $CONTAINER_NAME"
echo "Stop: docker rm -f $CONTAINER_NAME"
