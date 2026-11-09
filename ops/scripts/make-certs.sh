#!/usr/bin/env bash
# Make a small internal certificate authority and one server certificate
# for the broker (mqtts :8883) and the coordinator (wss :8443).
#
#   ops/scripts/make-certs.sh [extra-host-or-ip ...]
#
# Writes ops/certs/ (not in git). The certificate covers localhost,
# 127.0.0.1, this machine's name and any extra names or IPs given, e.g. the
# coordinator's VPN address so QGC on another laptop can connect. Copy only
# ca.crt to clients. Re-run with FORCE=1 to replace an existing CA.
set -euo pipefail

dir="$(cd "$(dirname "$0")/.." && pwd)/certs"
mkdir -p "$dir"
chmod 700 "$dir"
cd "$dir"

if [[ -f ca.key && "${FORCE:-0}" != "1" ]]; then
  echo "CA already exists in $dir (FORCE=1 to replace). Reissuing the server certificate only."
else
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 1825 \
    -subj "/O=Briech/CN=Briech Fleet dev CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout ca.key -out ca.crt 2>/dev/null
  echo "made CA: $dir/ca.crt"
fi

san="DNS:localhost,IP:127.0.0.1,DNS:$(hostname -s 2>/dev/null || echo host),DNS:briech-broker,DNS:host.docker.internal"
for extra in "$@"; do
  if [[ "$extra" =~ ^[0-9.]+$ || "$extra" == *:* ]]; then san+=",IP:$extra"; else san+=",DNS:$extra"; fi
done

openssl req -newkey rsa:2048 -sha256 -nodes -subj "/O=Briech/CN=briech-ground" \
  -keyout server.key -out server.csr 2>/dev/null
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 825 -sha256 \
  -extfile <(printf "subjectAltName=%s\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n" "$san") \
  -out server.crt 2>/dev/null
rm -f server.csr
# The broker container reads the key as its own user, so it cannot be 0600 to us alone.
chmod 600 ca.key
chmod 644 ca.crt server.crt server.key
echo "made server certificate for: $san"
