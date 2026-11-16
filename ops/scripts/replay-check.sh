#!/usr/bin/env bash
# Scenario replay against the real stack (handoff: "Scenario replay (level 1),
# every push, broker in a container"). CI runs this; so can anyone:
#
#   make -C ops replay-check
#   PYTHON=python3 ops/scripts/replay-check.sh        # without the virtualenv
#   ops/scripts/replay-check.sh --alert-timeout 90    # options go to sim/replay_check.py
#
# 1. dev certificates and secrets, if missing (make-certs.sh, make-secrets.sh)
# 2. the Mosquitto broker in Docker (ops/docker-compose.yml), if not running
# 3. a coordinator with an empty data folder, on port $REPLAY_HTTP_PORT (8444,
#    so a coordinator from make dev-up on 8443 is not disturbed)
# 4. sim/replay_check.py: fake tower, operator clients, the checks
#
# Logs go to ground-core/var/replay/ and are printed when a check fails. The
# coordinator is stopped at the end; the broker is left running unless
# REPLAY_STOP_BROKER=1.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
ops="$repo/ops"
run="$repo/ground-core/var/replay"
port="${REPLAY_HTTP_PORT:-8444}"
py="${PYTHON:-$repo/ground-core/.venv/bin/python}"
# PYTHON may be a path or a command name on PATH (CI passes "python"), so look it up
# rather than test it as a file. Only when neither works, try the Windows virtualenv.
command -v "$py" >/dev/null 2>&1 || py="$repo/ground-core/.venv/Scripts/python.exe"

rm -rf "$run"
mkdir -p "$run"
chmod 700 "$run"

[[ -f "$ops/certs/server.crt" ]] || "$ops/scripts/make-certs.sh"
[[ -f "$ops/secrets/mosquitto.passwd" && -f "$ops/secrets/mqtt/tower-01.password" ]] \
  || "$ops/scripts/make-secrets.sh" tower-01 tower-02

if ! docker ps --format '{{.Names}}' | grep -qx briech-broker; then
  docker compose -f "$ops/docker-compose.yml" up -d broker
fi

# A fresh admin token for the audit check, used only by this run.
openssl rand -hex 24 > "$run/admin.token"
chmod 600 "$run/admin.token"

coordinator_pid=""
cleanup() {
  status=$?
  if [[ -n "$coordinator_pid" ]] && kill -0 "$coordinator_pid" 2>/dev/null; then
    kill "$coordinator_pid" 2>/dev/null || true
    wait "$coordinator_pid" 2>/dev/null || true
  fi
  if [[ $status -ne 0 ]]; then
    echo "--- coordinator log (last 40 lines)"; tail -n 40 "$run/coordinator.log" 2>/dev/null || true
    echo "--- fake tower log (last 20 lines)";  tail -n 20 "$run/publisher.log" 2>/dev/null || true
    echo "--- broker log (last 20 lines)";      docker logs --tail 20 briech-broker 2>&1 || true
  fi
  if [[ "${REPLAY_STOP_BROKER:-0}" == "1" ]]; then
    docker compose -f "$ops/docker-compose.yml" down >/dev/null 2>&1 || true
  fi
  exit $status
}
trap cleanup EXIT

# Secrets come from files, never the command line.
(
  cd "$repo/ground-core"
  BRIECH_MQTT_HOST=localhost \
  BRIECH_MQTT_CA="$ops/certs/ca.crt" \
  BRIECH_MQTT_PASSWORD_FILE="$ops/secrets/mqtt/coordinator.password" \
  BRIECH_TLS_CERT="$ops/certs/server.crt" \
  BRIECH_TLS_KEY="$ops/certs/server.key" \
  BRIECH_OPERATOR_TOKENS_FILE="$ops/secrets/operator.tokens" \
  BRIECH_DEVICE_TOKENS_FILE="$ops/secrets/device.tokens" \
  BRIECH_ADMIN_TOKENS_FILE="$run/admin.token" \
  BRIECH_DATA_DIR="$run/data" \
  BRIECH_HTTP_PORT="$port" \
  exec "$py" -u -m coordinator
) > "$run/coordinator.log" 2>&1 &
coordinator_pid=$!

# Ready when it listens and has the broker.
for _ in $(seq 1 60); do
  if ! kill -0 "$coordinator_pid" 2>/dev/null; then
    echo "coordinator exited during start-up"; exit 1
  fi
  grep -q "operator WebSocket on" "$run/coordinator.log" && grep -q "MQTT: connected" "$run/coordinator.log" && break
  sleep 0.5
done
grep -q "MQTT: connected" "$run/coordinator.log" || { echo "coordinator did not connect to the broker in 30 s"; exit 1; }

"$py" -u "$repo/sim/replay_check.py" \
  --url "wss://localhost:$port/ws/v1/operator" \
  --admin-token-file "$run/admin.token" \
  --publisher-log "$run/publisher.log" \
  "$@"
