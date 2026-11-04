"""The coordinator core: routes checked messages to the registry and fusion,
and fans the changes out to every connected QGC.

Everything here runs on the asyncio event loop thread.
"""

from __future__ import annotations

import asyncio
import json
import logging
import secrets
import time
from collections import Counter, deque
from typing import TYPE_CHECKING

from .config import Config
from .fusion import Fusion
from .registry import Registry
from .schemas import MessageValidator, utc_now_iso

if TYPE_CHECKING:
    from .api_operator import OperatorClient

log = logging.getLogger(__name__)

SRC = "coordinator"
MAX_OPERATOR_ACTIONS = 1000


class Coordinator:
    def __init__(self, config: Config, validator: MessageValidator, registry: Registry, fusion: Fusion | None = None):
        self.config = config
        self.validator = validator
        self.registry = registry
        self.fusion = fusion or Fusion()
        self.counters: Counter = Counter()
        self.clients: set["OperatorClient"] = set()
        # Until audit.py exists (row 7), operator actions are logged and kept here.
        self.operator_actions: deque = deque(maxlen=MAX_OPERATOR_ACTIONS)
        self._started = time.monotonic()
        self._heartbeat_seq = 0

    # Outgoing

    def make_message(self, msg_type: str, data: dict) -> dict | None:
        """A complete message from the coordinator, or None if it would break its schema."""
        msg = {
            "v": 1,
            "type": msg_type,
            "id": f"{msg_type}-{secrets.token_hex(6)}",
            "ts": utc_now_iso(),
            "src": SRC,
            "data": data,
        }
        error = self.validator.check(msg)
        if error is not None:
            self.counters["drop_outgoing"] += 1
            log.error("not sending invalid %s: %s", msg_type, error)
            return None
        return msg

    def broadcast(self, msg_type: str, data: dict) -> None:
        msg = self.make_message(msg_type, data)
        if msg is None:
            return
        text = json.dumps(msg, separators=(",", ":"))
        for client in list(self.clients):
            client.push(text)
        self.counters[f"out_{msg_type}"] += 1

    def snapshot(self) -> dict | None:
        return self.make_message("snapshot", {
            "assets": self.registry.assets(),
            "vehicles": self.registry.vehicles(),
            "objects": self.fusion.objects(),
            "alerts": [],  # alerts.py (row 5)
        })

    def heartbeat_data(self) -> dict:
        self._heartbeat_seq += 1
        counters = dict(self.counters)
        counters["drop_fusion_cap"] = self.fusion.dropped
        counters["clients"] = len(self.clients)
        return {
            "seq": self._heartbeat_seq,
            "uptime_s": round(time.monotonic() - self._started, 1),
            "counters": counters,
        }

    async def run_heartbeat(self) -> None:
        while True:
            await asyncio.sleep(self.config.heartbeat_s)
            self.broadcast("heartbeat", self.heartbeat_data())

    # Incoming from MQTT (already checked by bus.check_message)

    def on_bus_message(self, msg: dict) -> None:
        msg_type = msg["type"]
        if msg_type == "asset.state":
            asset = self.registry.apply_asset_state(msg)
            if asset is None:
                self.counters["drop_unknown_asset"] += 1
                return
            self.broadcast("asset.state", asset)
        elif msg_type == "edge.status":
            changed = self.registry.apply_edge_status(msg)
            if changed is not None:
                log.info("asset %s is %s", changed["asset_id"], changed["link"])
                self.broadcast("asset.state", changed)
        elif msg_type == "detection":
            self.registry.touch(msg["src"], msg["ts"])
            obj = self.fusion.ingest(msg)
            if obj is None:
                self.counters["detection_no_geo"] += 1
                return
            self.broadcast("object.update", obj)

    # Incoming from QGC (already checked by api_operator)

    def on_operator_message(self, client: "OperatorClient", msg: dict) -> None:
        msg_type = msg["type"]
        if msg_type == "vehicle.state":
            self.registry.apply_vehicle_state(msg)
        elif msg_type == "operator.action":
            data = msg["data"]
            self.operator_actions.append(msg)
            log.info("operator.action %s %s by %s: %s", data["action_id"], data["phase"], data["operator_id"],
                     {k: data[k] for k in ("alert_id", "decision", "vehicle_id", "command", "outcome") if k in data})
