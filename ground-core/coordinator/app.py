"""The coordinator core: routes checked messages to the registry, fusion and
alerts, and fans the changes out to every connected QGC.

Everything here runs on the asyncio event loop thread.

Guarantees kept here (handoff section 10):
- every outgoing message is checked against its schema before it is sent;
- object.update goes out at most twice a second per object: a newer update
  waiting for its turn replaces an older one, which is counted as dropped,
  so QGC always ends up with the newest state;
- silent towers are marked offline, silent tracks lost and then removed;
- alerts, decisions and outcomes go to the hash-chained audit log;
- tracks and alerts are saved, so a restart keeps them.
"""

from __future__ import annotations

import asyncio
import json
import logging
import secrets
import time
from collections import Counter, deque
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Callable

from .alerts import Alerts
from .config import Config
from .fusion import Fusion
from .registry import Registry
from .schemas import MessageValidator, utc_now_iso
from .suggest import SuggestConfig, suggest
from .zones import Zone

if TYPE_CHECKING:
    from .api_operator import OperatorClient
    from .audit import AuditLog
    from .store import StateStore

log = logging.getLogger(__name__)

SRC = "coordinator"
MAX_OPERATOR_ACTIONS = 1000
EXPIRY_EVERY_S = 1.0
SAVE_EVERY_S = 2.0


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Coordinator:
    def __init__(self, config: Config, validator: MessageValidator, registry: Registry, fusion: Fusion | None = None,
                 zones: list[Zone] | None = None, audit: "AuditLog | None" = None, store: "StateStore | None" = None,
                 suggest_config: SuggestConfig | None = None,
                 clock: Callable[[], float] = time.monotonic, wall_clock: Callable[[], datetime] = utc_now):
        self.config = config
        self.validator = validator
        self.registry = registry
        self.fusion = fusion or Fusion()
        self.audit = audit
        self.store = store
        self.suggest_config = suggest_config or SuggestConfig()
        self.clock = clock
        self.wall_clock = wall_clock
        self.alerts = Alerts(zones or [], suggest=self._suggest)
        self.counters: Counter = Counter()
        self.clients: set["OperatorClient"] = set()
        self.operator_actions: deque = deque(maxlen=MAX_OPERATOR_ACTIONS)
        self._started = clock()
        self._heartbeat_seq = 0
        self._object_sent: dict[str, float] = {}     # object id -> clock() of the last object.update
        self._object_held: dict[str, dict] = {}      # object id -> newest update waiting for its turn
        self._last_expiry = clock()
        self._last_save = clock()
        self._dirty = False
        self._load()

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
            "alerts": self.alerts.alerts(),
        })

    def heartbeat_data(self) -> dict:
        self._heartbeat_seq += 1
        counters = dict(self.counters)
        counters["drop_fusion_cap"] = self.fusion.dropped
        counters["drop_alert_cap"] = self.alerts.dropped
        counters["fusion_merged"] = self.fusion.merged
        counters["clients"] = len(self.clients)
        return {
            "seq": self._heartbeat_seq,
            "uptime_s": round(self.clock() - self._started, 1),
            "counters": counters,
        }

    async def run_heartbeat(self) -> None:
        while True:
            await asyncio.sleep(self.config.heartbeat_s)
            self.broadcast("heartbeat", self.heartbeat_data())

    async def run_ticker(self) -> None:
        while True:
            await asyncio.sleep(self.config.tick_s)
            self.tick()

    def tick(self) -> None:
        """Sends held object updates whose turn has come; once a second, expiries and silence; saves."""
        self.flush_objects()
        now = self.clock()
        if now - self._last_expiry >= EXPIRY_EVERY_S:
            self._last_expiry = now
            wall = self.wall_clock()
            for obj in self.fusion.expire(wall):
                self._send_object(obj, force=True)
                self._emit(self.alerts.on_object(obj, wall))     # lost or removed: approved alerts resolve
                self._dirty = True
            self._emit(self.alerts.expire(wall))
            for asset in self.registry.check_silent(wall, self.config.asset_silent_s):
                log.info("asset %s is silent: offline", asset["asset_id"])
                self.broadcast("asset.state", asset)
        if self._dirty and now - self._last_save >= SAVE_EVERY_S:
            self.save()

    # object.update rate limit

    def _send_object(self, obj: dict, force: bool = False) -> None:
        object_id = obj["object_id"]
        now = self.clock()
        last = self._object_sent.get(object_id)
        if force or last is None or now - last >= self.config.object_min_interval_s:
            self._object_held.pop(object_id, None)
            self._object_sent[object_id] = now
            if obj.get("status") == "removed":
                self._object_sent.pop(object_id, None)
            self.broadcast("object.update", obj)
            return
        if object_id in self._object_held:
            self.counters["drop_rate_object"] += 1   # replaced before its turn came
        self._object_held[object_id] = obj

    def flush_objects(self) -> None:
        now = self.clock()
        for object_id, obj in list(self._object_held.items()):
            if now - self._object_sent.get(object_id, 0.0) >= self.config.object_min_interval_s:
                self._send_object(obj)

    # Alerts and the audit log

    def _suggest(self, alert: dict) -> dict | None:
        return suggest(alert, self.registry.vehicles(), self.wall_clock(), self.suggest_config)

    def _emit(self, events: list[tuple[str, dict]]) -> None:
        for msg_type, data in events:
            if msg_type.startswith("alert."):
                log.info("%s %s %s%s", msg_type, data["alert_id"], data.get("status", ""),
                         f" ({data['reason']})" if "reason" in data else "")
            self.broadcast(msg_type, data)
            self._audit(msg_type, data)
            self._dirty = True

    def _audit(self, kind: str, payload: dict) -> None:
        if self.audit is not None:
            self.audit.append(kind, payload)

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
            back = self.registry.touch(msg["src"], msg["ts"])
            if back is not None:
                self.broadcast("asset.state", back)
            obj = self.fusion.ingest(msg)
            if obj is None:
                self.counters["detection_no_geo"] += 1
                return
            self._dirty = True
            self._send_object(obj)
            late = bool(msg["data"].get("late"))
            if late:
                self.counters["detection_late"] += 1
            self._emit(self.alerts.on_object(obj, self.wall_clock(), late=late))

    # Incoming from QGC (already checked by api_operator)

    def on_operator_message(self, client: "OperatorClient", msg: dict) -> None:
        msg_type = msg["type"]
        if msg_type == "vehicle.state":
            self.registry.apply_vehicle_state(msg)
        elif msg_type == "operator.action":
            data = msg["data"]
            self.operator_actions.append(msg)
            self._audit("operator.action", dict(data, src=msg["src"], sent_ts=msg["ts"]))
            log.info("operator.action %s %s by %s: %s", data["action_id"], data["phase"], data["operator_id"],
                     {k: data[k] for k in ("alert_id", "decision", "vehicle_id", "command", "outcome") if k in data})
            if data["phase"] == "decision":
                self._emit(self.alerts.on_decision(data))

    # Persistence

    def save(self) -> None:
        self._last_save = self.clock()
        self._dirty = False
        if self.store is not None:
            self.store.save("fusion", self.fusion.to_state())
            self.store.save("alerts", self.alerts.to_state())

    def _load(self) -> None:
        if self.store is None:
            return
        fusion, alerts = self.store.load("fusion"), self.store.load("alerts")
        if fusion:
            self.fusion.load_state(fusion)
        if alerts:
            self.alerts.load_state(alerts)
        log.info("restored %d objects and %d alerts", len(self.fusion.objects()), len(self.alerts.alerts()))
        self._emit(self.alerts.resolve_missing({o["object_id"] for o in self.fusion.objects()}))
