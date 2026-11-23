#!/usr/bin/env bash
# Make the WireGuard VPN the field devices use to reach the ground server
# (handoff, section 9: the broker is never open to the internet).
#
#   ops/scripts/make-wireguard.sh <endpoint> [device-id ...]     default device: tower-01
#
# <endpoint> is how the devices reach the ground server from the field:
# host or host:port (port 51820 when not given). Run it on the ground server.
# Writes ops/secrets/wireguard/ (not in git):
#
#   wg0.conf          the ground server's: copy to /etc/wireguard/wg0.conf there
#   <device>.conf     each device's: copy to /etc/wireguard/wg0.conf on that device
#   *.key, peers.txt  the private keys and the addresses given out
#
# The ground server is 10.77.0.1; devices get 10.77.0.11, .12, ... in the order
# they are first made. Each device can reach the ground server and nothing
# else. Existing keys and addresses are kept, so re-running only adds devices.
# Needs the wg command (sudo apt install wireguard-tools).
set -euo pipefail

if [[ $# -lt 1 || "$1" == -* ]]; then
  echo "usage: $0 <endpoint host[:port]> [device-id ...]" >&2
  exit 2
fi
endpoint=$1; shift
[[ "$endpoint" == *:* ]] || endpoint="$endpoint:51820"
devices=("$@")
[[ ${#devices[@]} -eq 0 ]] && devices=(tower-01)
command -v wg >/dev/null || { echo "the wg command is missing: sudo apt install wireguard-tools" >&2; exit 1; }

repo=$(cd "$(dirname "$0")/../.." && pwd)
dir="$repo/ops/secrets/wireguard"
mkdir -p "$dir"
chmod 700 "$dir"
umask 077

key() {   # the private key in $1, made once
  [[ -s "$dir/$1.key" ]] || wg genkey > "$dir/$1.key"
}

key server
touch "$dir/peers.txt"
for device in "${devices[@]}"; do
  if [[ ! "$device" =~ ^[a-z0-9][a-z0-9-]{0,62}$ || "$device" == server ]]; then
    echo "bad device id '$device': lower case letters, digits and hyphens only" >&2
    exit 1
  fi
  if ! grep -q "^$device " "$dir/peers.txt"; then
    last=$(awk '{ split($2, a, "."); if (a[4] > n) n = a[4] } END { print n + 0 }' "$dir/peers.txt")
    next=$(( last < 11 ? 11 : last + 1 ))
    (( next <= 254 )) || { echo "no addresses left in 10.77.0.0/24" >&2; exit 1; }
    echo "$device 10.77.0.$next" >> "$dir/peers.txt"
    echo "gave $device 10.77.0.$next"
  fi
  key "$device"
done

server_pub=$(wg pubkey < "$dir/server.key")
{
  echo "# The ground server's end of the field VPN. Made by ops/scripts/make-wireguard.sh."
  echo "[Interface]"
  echo "Address = 10.77.0.1/24"
  echo "ListenPort = ${endpoint##*:}"
  echo "PrivateKey = $(cat "$dir/server.key")"
  while read -r device address; do
    [[ -n "$device" && -s "$dir/$device.key" ]] || continue
    echo
    echo "[Peer]"
    echo "# $device"
    echo "PublicKey = $(wg pubkey < "$dir/$device.key")"
    echo "AllowedIPs = $address/32"
  done < "$dir/peers.txt"
} > "$dir/wg0.conf"

while read -r device address; do
  [[ -n "$device" && -s "$dir/$device.key" ]] || continue
  {
    echo "# $device's end of the field VPN. Made by ops/scripts/make-wireguard.sh."
    echo "[Interface]"
    echo "Address = $address/32"
    echo "PrivateKey = $(cat "$dir/$device.key")"
    echo
    echo "[Peer]"
    echo "# the ground server"
    echo "PublicKey = $server_pub"
    echo "Endpoint = $endpoint"
    echo "# Only the ground server goes through the tunnel."
    echo "AllowedIPs = 10.77.0.1/32"
    echo "PersistentKeepalive = 25"
  } > "$dir/$device.conf"
done < "$dir/peers.txt"

echo "wrote $dir/wg0.conf and one .conf per device ($(wc -l < "$dir/peers.txt") devices)"
echo "on each device, map ground.lan to 10.77.0.1 in /etc/hosts; the server certificate must name ground.lan"
