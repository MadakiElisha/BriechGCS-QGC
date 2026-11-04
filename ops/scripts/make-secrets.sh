#!/usr/bin/env bash
# Make the development secrets in ops/secrets/ (not in git):
#
#   mqtt/<device>.password   one MQTT password per device login
#   mosquitto.passwd         the same, hashed, for the broker
#   operator.tokens          operator token(s) QGC sends in Authorization
#   device.tokens            device-id=token lines for POST /api/v1/snapshots
#
#   ops/scripts/make-secrets.sh [device-id ...]     default: tower-01
#
# The coordinator login is always made. Existing passwords and tokens are
# kept, so re-running only adds devices. Hashing uses the broker image, so
# Docker must be running.
set -euo pipefail

ops="$(cd "$(dirname "$0")/.." && pwd)"
dir="$ops/secrets"
image="eclipse-mosquitto:2.0.20"
mkdir -p "$dir/mqtt"
chmod 700 "$dir" "$dir/mqtt"

devices=("$@")
[[ ${#devices[@]} -eq 0 ]] && devices=(tower-01)

new_secret() { openssl rand -hex 24; }

for login in coordinator "${devices[@]}"; do
  if [[ ! "$login" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
    echo "bad device id '$login': lower case letters, digits and hyphens only" >&2
    exit 1
  fi
  f="$dir/mqtt/$login.password"
  [[ -f "$f" ]] || { new_secret > "$f"; chmod 600 "$f"; echo "made MQTT login $login"; }
done

[[ -f "$dir/operator.tokens" ]] || { new_secret > "$dir/operator.tokens"; echo "made operator token"; }
touch "$dir/device.tokens"
for device in "${devices[@]}"; do
  grep -q "^$device=" "$dir/device.tokens" || { echo "$device=$(new_secret)" >> "$dir/device.tokens"; echo "made device token for $device"; }
done
chmod 600 "$dir/operator.tokens" "$dir/device.tokens"

# Rebuild the hashed password file from every login in mqtt/.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/passwd"
for f in "$dir"/mqtt/*.password; do
  printf '%s:%s\n' "$(basename "$f" .password)" "$(cat "$f")" >> "$tmp/passwd"
done
docker run --rm -v "$tmp:/work" "$image" mosquitto_passwd -U /work/passwd >/dev/null
mv "$tmp/passwd" "$dir/mosquitto.passwd"
# The broker container must read it; it holds only salted hashes.
chmod 644 "$dir/mosquitto.passwd"
echo "wrote $dir/mosquitto.passwd ($(wc -l < "$dir/mosquitto.passwd" | tr -d ' ') logins)"
