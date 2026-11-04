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
