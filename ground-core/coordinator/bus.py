"""MQTT in: the broker connection and the checks every incoming message passes.

A message is used only when all of these hold, otherwise it is counted under
its reason and dropped:

* it is at most 4 KB (``size``) and is JSON (``json``);
* its topic is one of the three Briech topics (``topic``);
* it matches its schema (``schema``);
* its type is the one that topic carries (``type``);
* its ``src`` is the device id in the topic, and so is ``data.asset_id`` on
  an asset topic (``src``).

The broker's access list already stops a device publishing under another id;
the ``src`` check catches a device that lies inside its own topic.

Change this file only together with the lead: the guarantees in the handoff
(section 10) depend on it.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import ssl
from collections import Counter
from typing import Callable

import paho.mqtt.client as mqtt

from .config import Config
from .schemas import MessageValidator

log = logging.getLogger(__name__)

SUBSCRIPTION = "briech/v1/#"
MAX_PAYLOAD = 4096

_TOPIC_RE = re.compile(r"^briech/v1/(edge|asset)/([a-z0-9][a-z0-9-]{0,62})/(detection|status|state)$")
_TOPIC_TYPES = {
    ("edge", "detection"): "detection",
    ("edge", "status"): "edge.status",
    ("asset", "state"): "asset.state",
}


def topic_type(topic: str) -> tuple[str, str] | None:
    """(message type, device id) for a Briech topic, else None."""
    m = _TOPIC_RE.match(topic)
    if not m:
        return None
    msg_type = _TOPIC_TYPES.get((m.group(1), m.group(3)))
    return (msg_type, m.group(2)) if msg_type else None


def check_message(topic: str, payload: bytes, validator: MessageValidator) -> tuple[dict | None, str]:
    """(message, "ok") when the message may be used, else (None, drop reason)."""
    if len(payload) > MAX_PAYLOAD:
        return None, "size"
    expected = topic_type(topic)
    if expected is None:
        return None, "topic"
    try:
        msg = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None, "json"
    error = validator.check(msg)
    if error is not None:
        log.debug("schema drop on %s: %s", topic, error)
        return None, "schema"
    msg_type, device_id = expected
    if msg["type"] != msg_type:
        return None, "type"
    if msg["src"] != device_id:
        return None, "src"
    if msg_type == "asset.state" and msg["data"]["asset_id"] != device_id:
        return None, "src"
    return msg, "ok"


class MqttBus:
    """Subscribes to every Briech topic and hands checked messages to the event loop.

    paho runs its own network thread. Checking happens there; the accepted
    message is passed to ``on_message`` on the asyncio loop thread.
    """

    def __init__(
        self,
        config: Config,
        validator: MessageValidator,
        on_message: Callable[[dict], None],
        counters: Counter,
        loop: asyncio.AbstractEventLoop,
    ):
        self._config = config
        self._validator = validator
        self._on_message = on_message
        self._counters = counters
        self._loop = loop
        self.connected = False
        self._stopping = False

        client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id="briech-coordinator",
            protocol=mqtt.MQTTv311,
        )
        if config.mqtt_password is not None:
            client.username_pw_set(config.mqtt_username, config.mqtt_password)
        if config.mqtt_tls:
            client.tls_set(
                ca_certs=str(config.mqtt_ca) if config.mqtt_ca else None,
                cert_reqs=ssl.CERT_REQUIRED,
                tls_version=ssl.PROTOCOL_TLS_CLIENT,
            )
        client.reconnect_delay_set(min_delay=1, max_delay=30)
        client.on_connect = self._handle_connect
        client.on_disconnect = self._handle_disconnect
        client.on_message = self._handle_message
        self._client = client

    def start(self) -> None:
        log.info("MQTT: connecting to %s:%d as %s", self._config.mqtt_host, self._config.mqtt_port,
                 self._config.mqtt_username)
        self._client.connect_async(self._config.mqtt_host, self._config.mqtt_port, keepalive=30)
        self._client.loop_start()

    def stop(self) -> None:
        self._stopping = True
        self._client.disconnect()
        self._client.loop_stop()

    # paho thread

    def _handle_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            log.error("MQTT: connect refused: %s", reason_code)
            return
        self.connected = True
        client.subscribe(SUBSCRIPTION, qos=1)
        log.info("MQTT: connected, subscribed to %s", SUBSCRIPTION)

    def _handle_disconnect(self, client, userdata, flags, reason_code, properties):
        self.connected = False
        if not self._stopping:
            log.warning("MQTT: disconnected (%s), retrying", reason_code)

    def _handle_message(self, client, userdata, message):
        msg, reason = check_message(message.topic, message.payload, self._validator)
        self._loop.call_soon_threadsafe(self._deliver, msg, reason, message.topic)

    # event loop thread

    def _deliver(self, msg: dict | None, reason: str, topic: str) -> None:
        if msg is None:
            self._counters[f"drop_{reason}"] += 1
            log.info("MQTT: dropped message on %s (%s)", topic, reason)
            return
        self._counters["mqtt_in"] += 1
        self._on_message(msg)
