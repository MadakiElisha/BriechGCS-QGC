# Briech ground services for local development. Run from the repo root as
#   make -C ops <target>
#
#   dev-up       broker, coordinator and fake publisher in the background
#                (logs and pids in ground-core/var/dev); dev-down stops them
#   sim-10       ten simulated PX4 drones (SIH, Docker) for QGC; sim-down stops them
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
# dev-up: where the background services write their logs and pids (git-ignored).
RUN       := $(REPO)/ground-core/var/dev
SIM_COUNT ?= 10

# Settings for the coordinator. Secrets are read from files, never put on the command line.
COORDINATOR_ENV := \
	BRIECH_MQTT_HOST=$(MQTT_HOST) \
	BRIECH_MQTT_CA=$(CERTS)/ca.crt \
	BRIECH_MQTT_PASSWORD_FILE=$(SECRETS)/mqtt/coordinator.password \
	BRIECH_TLS_CERT=$(CERTS)/server.crt \
	BRIECH_TLS_KEY=$(CERTS)/server.key \
	BRIECH_OPERATOR_TOKENS_FILE=$(SECRETS)/operator.tokens \
	BRIECH_DEVICE_TOKENS_FILE=$(SECRETS)/device.tokens

.PHONY: setup venv certs secrets broker broker-down broker-logs coordinator publisher probe test check-acl \
        dev-up dev-down sim-10 sim-down

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

# Everything QGC needs on the ground side, in one command. Each service runs in
# the background; its log is $(RUN)/<name>.log. Running dev-up twice does not
# start a second copy of a service that is still running.
dev-up: broker venv
	@mkdir -p $(RUN)
	@if [ -f $(RUN)/coordinator.pid ] && kill -0 $$(cat $(RUN)/coordinator.pid) 2>/dev/null; then \
	  echo "coordinator already running (pid $$(cat $(RUN)/coordinator.pid))"; \
	else \
	  cd $(REPO)/ground-core && $(COORDINATOR_ENV) nohup $(PY) -m coordinator > $(RUN)/coordinator.log 2>&1 & \
	  echo $$! > $(RUN)/coordinator.pid; echo "coordinator started, log $(RUN)/coordinator.log"; \
	fi
	@if [ -f $(RUN)/publisher.pid ] && kill -0 $$(cat $(RUN)/publisher.pid) 2>/dev/null; then \
	  echo "publisher already running (pid $$(cat $(RUN)/publisher.pid))"; \
	else \
	  nohup $(PY) $(REPO)/sim/fake_fleet.py --scenario $(REPO)/sim/scenarios/$(SCENARIO) --host $(MQTT_HOST) \
	    > $(RUN)/publisher.log 2>&1 & \
	  echo $$! > $(RUN)/publisher.pid; echo "publisher started ($(SCENARIO)), log $(RUN)/publisher.log"; \
	fi
	@echo "QGC: wss://localhost:8443/ws/v1/operator (python3 ops/scripts/qgc-fleet-settings.py sets it up)"

# Stops what dev-up started (by the pids it wrote), then the broker.
dev-down:
	@for name in publisher coordinator; do \
	  if [ -f $(RUN)/$$name.pid ]; then kill $$(cat $(RUN)/$$name.pid) 2>/dev/null && echo "$$name stopped"; rm -f $(RUN)/$$name.pid; fi; \
	done
	docker compose -f $(REPO)/ops/docker-compose.yml down

# Ten PX4 SIH drones in Docker, system ids 1..10, all on QGC's UDP 14550.
# SIM_COUNT=3 make -C ops sim-10 starts fewer.
sim-10:
	$(REPO)/sim/px4-sitl.sh up $(SIM_COUNT)

sim-down:
	$(REPO)/sim/px4-sitl.sh down

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
