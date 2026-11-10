#!/usr/bin/env bash
# Start N simulated PX4 drones (SIH: physics inside the autopilot, no 3D world)
# in Docker, each with its own MAVLink system id, all reporting to QGC on UDP
# 14550 of this machine. QGC's default UDP link shows them all at once.
#
#   sim/px4-sitl.sh up [N]      start drones 1..N (default 3)
#   sim/px4-sitl.sh down        stop and remove them
#   sim/px4-sitl.sh status
#
# Settings (environment):
#   PX4_IMAGE        default px4io/px4-sitl-sih:latest (the image the app's simulation button uses)
#   HOME_LAT/LON     first drone's home, default the Briech test field
#   SPACING_DEG      longitude step between homes, default 0.0003 (about 33 m)
#   SPEED_FACTOR     simulation speed, default 1
#   FIRST_ID         system id of the first drone, default 1. Use it to add
#                    drones next to ones already running (for example two
#                    started by the app's simulation button or by hand):
#                    FIRST_ID=3 sim/px4-sitl.sh up 8 starts ids 3..10.
#
# Each container runs PX4 instance 0 on its own Docker network, so there are no
# port clashes; the vehicles are told apart only by system id (1..N). Spike S5
# (ten drones) is this script with N=10: record CPU and what QGC does in
# sim/README.md.
set -euo pipefail
# Git Bash on Windows rewrites arguments that look like POSIX paths
# (--entrypoint /bin/sh became "C:/Program Files/Git/usr/bin/sh" and the
# container failed to start). The paths here are inside the container, so turn
# that off; other shells ignore the variable.
export MSYS_NO_PATHCONV=1

IMAGE="${PX4_IMAGE:-px4io/px4-sitl-sih:latest}"
HOME_LAT="${HOME_LAT:-8.8929377}"
HOME_LON="${HOME_LON:-7.2639897}"
SPACING_DEG="${SPACING_DEG:-0.0003}"
SPEED_FACTOR="${SPEED_FACTOR:-1}"
FIRST_ID="${FIRST_ID:-1}"
PREFIX="briech-sitl-"

# Same start-up as BriechSimulationController: PX4's MAVLink and DDS go to the
# Docker host instead of the container's own broadcast address.
ENTRY='host_ip=$(getent ahostsv4 host.docker.internal | awk '"'"'NR==1{print $1}'"'"')
if [ -z "$host_ip" ]; then exec /opt/px4/bin/px4-entrypoint.sh; fi
sed -i "s/mavlink start -x -u/mavlink start -x -t $host_ip -u/g" /opt/px4/etc/init.d-posix/px4-rc.mavlink
sed -i "s|uxrce_dds_client start -t udp|uxrce_dds_client start -t udp -h $host_ip|" /opt/px4/etc/init.d-posix/rcS
exec /opt/px4/bin/px4'

up() {
  local n="${1:-3}"
  if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > 20 )); then
    echo "N must be 1 to 20" >&2; exit 1
  fi
  # MAVLink system ids are 1..255; 255 is QGC's own, so stop at 254.
  if ! [[ "$FIRST_ID" =~ ^[0-9]+$ ]] || (( FIRST_ID < 1 || FIRST_ID + n - 1 > 254 )); then
    echo "FIRST_ID must be 1 or more, and FIRST_ID + N - 1 at most 254" >&2; exit 1
  fi
  for i in $(seq "$FIRST_ID" $((FIRST_ID + n - 1))); do
    local name="$PREFIX$i"
    docker rm -f "$name" >/dev/null 2>&1 || true
    local lon
    lon=$(awk -v l="$HOME_LON" -v s="$SPACING_DEG" -v i="$i" 'BEGIN { printf "%.7f", l + (i - 1) * s }')
    docker run -d -i --name "$name" \
      --add-host=host.docker.internal:host-gateway \
      -e PX4_SIM_MODEL=sihsim_quadx \
      -e PX4_PARAM_MAV_SYS_ID="$i" \
      -e PX4_HOME_LAT="$HOME_LAT" -e PX4_HOME_LON="$lon" -e PX4_HOME_ALT=0.00 \
      -e PX4_SIM_SPEED_FACTOR="$SPEED_FACTOR" \
      --entrypoint /bin/sh "$IMAGE" -c "$ENTRY" >/dev/null
    echo "drone $i: $name, system id $i, home $HOME_LAT,$lon"
  done
  echo "QGC: keep the default UDP 14550 link (auto-connect). Vehicles appear within a few seconds."
}

down() {
  local ids
  ids=$(docker ps -aq --filter "name=^$PREFIX")
  if [[ -n "$ids" ]]; then
    docker rm -f $ids >/dev/null
    echo "removed $(wc -w <<<"$ids" | tr -d ' ') simulated drones"
  else
    echo "no simulated drones running"
  fi
}

status() {
  docker ps --filter "name=^$PREFIX" --format '{{.Names}}\t{{.Status}}'
}

case "${1:-}" in
  up) up "${2:-3}" ;;
  down) down ;;
  status) status ;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
