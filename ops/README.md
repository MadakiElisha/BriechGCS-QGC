# ops: broker and local services

`make -C ops <target>` from the repo root. See the top of `Makefile` for
every target.

## The MQTT broker

Mosquitto 2.0.20 in Docker (`docker-compose.yml`), TLS only on 8883, one
login per device, and an access list (`mosquitto/acl`) where each device can
publish only on its own three topics:

```
briech/v1/edge/<id>/detection
briech/v1/edge/<id>/status      retained, with an offline last will
briech/v1/asset/<id>/state      retained
```

The coordinator login reads `briech/v1/#` and publishes nothing. In the field
the broker is reached only over the VPN, never from the internet.

### First run

```sh
make -C ops setup                 # dev CA + certificate, logins for tower-01 and tower-02, tokens
make -C ops broker
make -C ops check-acl             # handoff check 1
```

`check-acl` publishes as `tower-01` on its own topic and on `tower-02`'s while
the coordinator login listens. The first arrives; the second is refused
silently (`mosquitto_pub` reports no error at QoS 0, nothing is delivered).
By hand, with the broker image's own clients:

```sh
docker run --rm --add-host=host.docker.internal:host-gateway \
  -v $PWD/ops/certs/ca.crt:/ca.crt:ro -v $PWD/ops/secrets/mqtt:/pw:ro eclipse-mosquitto:2.0.20 sh -c '
  mosquitto_pub -h host.docker.internal -p 8883 --cafile /ca.crt -u tower-01 -P "$(cat /pw/tower-01.password)" -t briech/v1/edge/tower-01/detection -m own;
  mosquitto_pub -h host.docker.internal -p 8883 --cafile /ca.crt -u tower-01 -P "$(cat /pw/tower-01.password)" -t briech/v1/edge/tower-02/detection -m other'
```

### Adding a device

```sh
make -C ops secrets DEVICES="tower-01 tower-02 tower-03"
docker restart briech-broker
```

Existing passwords are kept. A lost device is cut off alone: delete its file in
`ops/secrets/mqtt/`, re-run `make -C ops secrets`, and restart the broker.

### Certificates

`scripts/make-certs.sh` makes a small internal CA and one server certificate
used by both the broker and the coordinator. Name extra hosts or IPs (for
example the coordinator's VPN address, so QGC on another laptop can connect):

```sh
ops/scripts/make-certs.sh 10.8.0.1 ground.briech.lan
```

Give clients `ops/certs/ca.crt` only. The CA key never leaves this machine and
is not mounted into the broker.

## Secrets

`ops/certs/` and `ops/secrets/` are in `.gitignore` and made locally. Nothing
secret goes on a command line: the coordinator reads `*_FILE` variables
(see `ground-core/README.md`).

Known dev-only warning: Mosquitto says the password and ACL files are world
readable. On Docker Desktop the mounts cannot be given to the container's
user; on the field server use a systemd unit and `chmod 0600` owned by the
`mosquitto` user.

## Windows

Tried on 2026-11-09 (Windows 11, Docker Desktop 29.8, Python 3.13, Git Bash
or MSYS2 bash, Qt 6.10.1 MSVC). There is no `make`, so run what each target
runs, from the repo root in bash. Docker Desktop must be running.

```sh
# setup: virtualenv (Windows layout: Scripts/, not bin/)
python -m venv ground-core/.venv
ground-core/.venv/Scripts/python -m pip install -r ground-core/requirements-dev.txt -r sim/requirements.txt

# setup: certificates. MSYS bash turns "/O=Briech/..." into a Windows path unless told not to.
MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 bash ops/scripts/make-certs.sh

# setup: secrets. The temp folder must be a Windows path so Docker can mount it.
MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 TMPDIR="$(cygpath -m "$TEMP")" \
  bash ops/scripts/make-secrets.sh tower-01 tower-02

# broker
docker compose -f ops/docker-compose.yml up -d broker

# coordinator (terminal 1)
cd ground-core && R=../ops && \
BRIECH_MQTT_HOST=localhost BRIECH_MQTT_CA=$R/certs/ca.crt \
BRIECH_MQTT_PASSWORD_FILE=$R/secrets/mqtt/coordinator.password \
BRIECH_TLS_CERT=$R/certs/server.crt BRIECH_TLS_KEY=$R/certs/server.key \
BRIECH_OPERATOR_TOKENS_FILE=$R/secrets/operator.tokens \
BRIECH_DEVICE_TOKENS_FILE=$R/secrets/device.tokens \
.venv/Scripts/python -m coordinator

# publisher (terminal 2) and probe (terminal 3)
ground-core/.venv/Scripts/python sim/fake_fleet.py --scenario sim/scenarios/tower-walk.yaml
ground-core/.venv/Scripts/python sim/probe.py
```

Point QGC at it. Quit QGC first, because it rewrites the file on exit. The
script finds `%APPDATA%\Briech UAS\BriechUAS Daily.ini` on Windows:

```sh
ground-core/.venv/Scripts/python ops/scripts/qgc-fleet-settings.py
ground-core/.venv/Scripts/python ops/scripts/qgc-fleet-settings.py --show   # token hidden
```

QGC reads `[Fleet]` only when the link starts. After changing it, restart QGC
or turn Fleet off and on.

FleetLink tests and `fleetlink_probe` (in a VS x64 developer prompt, with
Ninja and `C:\Qt\6.10.1\msvc2022_64\bin` on `PATH`):

```bat
cmake -S custom/test/Fleet -B build/fleet-tests -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:/Qt/6.10.1/msvc2022_64
cmake --build build/fleet-tests && ctest --test-dir build/fleet-tests --output-on-failure
build\fleet-tests\fleetlink_probe --ca ops/certs/ca.crt --token-file ops/secrets/operator.tokens --vehicles 2 --seconds 10
```

Things that behave differently on Windows:

- Stop the coordinator with Ctrl+C. Asyncio has no signal handlers on Windows,
  so `__main__.py` falls back to cancelling and still shuts down cleanly.
- With the coordinator stopped, each reconnect attempt to `localhost` stays in
  CONNECTING for about 8 s before it fails, so RETRYING shows only briefly
  between attempts. Connecting to `localhost` while the coordinator is up takes
  about 2 s.
- `make-certs.sh` writes `DNS:host` for this machine's name, because
  `hostname -s` fails in MSYS. Pass the real name or IP as an argument if
  another computer must connect.
