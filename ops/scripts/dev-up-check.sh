#!/usr/bin/env bash
# Proves the one-command start-up works as a developer would use it (handoff,
# definition of done: "make -C ops dev-up starts the broker, coordinator and
# fake publisher"). CI runs this on every push; it needs make, Docker and
# Python 3 (Linux or macOS; on Windows follow ops/README.md instead).
#
#   ops/scripts/dev-up-check.sh
#
# 1. make -C ops setup     virtualenv, dev certificates, MQTT logins, tokens
# 2. make -C ops dev-up    broker, coordinator and fake tower in the background
# 3. sim/probe.py          a stand-in QGC for 25 s: it must get a snapshot,
#                          tower-01 online, and object.update tracks, and no
#                          message may break its schema
# 4. make -C ops dev-down  always, also after a failure
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
run="$repo/ground-core/var/dev"
py="$repo/ground-core/.venv/bin/python"

finish() {
  status=$?
  if [[ $status -ne 0 ]]; then
    for name in coordinator publisher; do
      echo "--- $name log (last 30 lines)"; tail -n 30 "$run/$name.log" 2>/dev/null || true
    done
    echo "--- broker log (last 20 lines)"; docker logs --tail 20 briech-broker 2>&1 || true
  fi
  make -C "$repo/ops" dev-down >/dev/null 2>&1 || true
  exit $status
}
trap finish EXIT

make -C "$repo/ops" setup
make -C "$repo/ops" dev-up

# Ready when the coordinator listens and has the broker.
for _ in $(seq 1 60); do
  if grep -q "operator WebSocket on" "$run/coordinator.log" 2>/dev/null \
     && grep -q "MQTT: connected" "$run/coordinator.log" 2>/dev/null; then
    break
  fi
  sleep 0.5
done
grep -q "MQTT: connected" "$run/coordinator.log" || { echo "FAIL: coordinator did not reach the broker in 30 s"; exit 1; }

out="$(timeout 60 "$py" "$repo/sim/probe.py" --seconds 25 --hide-heartbeat 2>&1 || true)"
echo "$out"

failed=0
check() {
  if grep -q -- "$2" <<<"$out"; then echo "PASS  $1"; else echo "FAIL  $1"; failed=1; fi
}
check "operator gets a snapshot" "snapshot:"
check "tower-01 reports online" "asset.state tower-01 link=online"
check "fake tower's detections arrive as tracks" "object.update o-tower-01-"
if grep -q "INVALID" <<<"$out"; then echo "FAIL  a message broke its schema"; failed=1; else echo "PASS  every message valid against schemas/"; fi
[[ $failed -eq 0 ]] && echo "make -C ops dev-up works"
exit $failed
