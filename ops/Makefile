# Briech ground services for local development. Run from the repo root as
#   make -C ops <target>
#
#   setup        Python virtualenv, dev certificates, MQTT logins and tokens
#   broker       start Mosquitto (TLS on :8883) in Docker
#   coordinator  run the coordinator in the foreground (wss on :8443)
#   publisher    run the fake tower from sim/scenarios/$(SCENARIO)
#   probe        run the stand-in QGC client
#   test         schema checks and coordinator unit tests
#   check-acl    the two mosquitto_pub checks: own topic delivered, other topic refused
#   broker-down  stop the broker; broker-logs to follow its log

REPO      := $(abspath ..)
VENV      := $(REPO)/ground-core/.venv
PY        := $(VENV)/bin/python
CERTS     := $(REPO)/ops/certs
SECRETS   := $(REPO)/ops/secrets
SCENARIO  ?= tower-walk.yaml
DEVICES   ?= tower-01 tower-02
MQTT_HOST ?= localhost
IMAGE     := eclipse-mosquitto:2.0.20
# How a container reaches the broker port published on this machine.
DOCKER_HOST_NAME ?= host.docker.internal

# Settings for the coordinator. Secrets are read from files, never put on the command line.
COORDINATOR_ENV := \
	BRIECH_MQTT_HOST=$(MQTT_HOST) \
	BRIECH_MQTT_CA=$(CERTS)/ca.crt \
	BRIECH_MQTT_PASSWORD_FILE=$(SECRETS)/mqtt/coordinator.password \
	BRIECH_TLS_CERT=$(CERTS)/server.crt \
	BRIECH_TLS_KEY=$(CERTS)/server.key \
	BRIECH_OPERATOR_TOKENS_FILE=$(SECRETS)/operator.tokens \
	BRIECH_DEVICE_TOKENS_FILE=$(SECRETS)/device.tokens

.PHONY: setup venv certs secrets broker broker-down broker-logs coordinator publisher probe test check-acl

setup: venv certs secrets

venv: $(VENV)/.installed
$(VENV)/.installed: $(REPO)/ground-core/requirements.txt $(REPO)/ground-core/requirements-dev.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r $(REPO)/ground-core/requirements-dev.txt
	touch $@

certs:
	@test -f $(CERTS)/server.crt || $(REPO)/ops/scripts/make-certs.sh

secrets:
	$(REPO)/ops/scripts/make-secrets.sh $(DEVICES)

broker:
	@test -f $(CERTS)/server.crt && test -f $(SECRETS)/mosquitto.passwd || { echo "run: make -C ops setup"; exit 1; }
	docker compose -f $(REPO)/ops/docker-compose.yml up -d broker
	@echo "broker on mqtts://$(MQTT_HOST):8883"

broker-down:
	docker compose -f $(REPO)/ops/docker-compose.yml down

broker-logs:
	docker logs -f briech-broker

coordinator: venv
	cd $(REPO)/ground-core && $(COORDINATOR_ENV) $(PY) -m coordinator

publisher: venv
	$(PY) $(REPO)/sim/fake_fleet.py --scenario $(REPO)/sim/scenarios/$(SCENARIO) --host $(MQTT_HOST)

probe: venv
	$(PY) $(REPO)/sim/probe.py $(PROBE_ARGS)

test: venv
	cd $(REPO)/ground-core && $(PY) -m pytest -q

# Step 1 check. The coordinator login watches; tower-01 publishes on its own
# topic (arrives) and on tower-02's (silently refused: mosquitto_pub reports
# success, nothing arrives). Uses the broker image's mosquitto clients, so
# nothing needs installing.
check-acl:
	@docker run --rm --add-host=host.docker.internal:host-gateway -v $(CERTS):/certs:ro -v $(SECRETS):/secrets:ro $(IMAGE) sh -c '\
	  set -e; \
	  sub() { mosquitto_sub -h $(DOCKER_HOST_NAME) -p 8883 --cafile /certs/ca.crt -u coordinator -P "$$(cat /secrets/mqtt/coordinator.password)" -t "briech/v1/edge/+/detection" -v -W 3 "$$@"; }; \
	  pub() { mosquitto_pub -h $(DOCKER_HOST_NAME) -p 8883 --cafile /certs/ca.crt -u tower-01 -P "$$(cat /secrets/mqtt/tower-01.password)" "$$@"; }; \
	  sub > /tmp/got 2>/dev/null & sleep 1; \
	  pub -t briech/v1/edge/tower-01/detection -m own-topic && echo "pub on own topic:   accepted by client"; \
	  pub -t briech/v1/edge/tower-02/detection -m other-topic && echo "pub on other topic: accepted by client (QoS 0 refusals are silent)"; \
	  wait; echo "--- what the coordinator login received:"; cat /tmp/got; \
	  grep -q tower-01/detection /tmp/got && ! grep -q tower-02 /tmp/got && echo "PASS: own topic delivered, other device topic refused" || { echo FAIL; exit 1; }'
