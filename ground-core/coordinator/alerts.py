"""Alerts: an active track inside a watch zone.

One alert per (object, zone) while the alert is still open, acknowledged or
approved, so a person standing in a zone raises one alert, not one per
sighting. A late detection (sent from the edge's disk queue after a link
outage) never raises a live alert.

An alert ends when an operator rejects it, or when it expires unanswered.
Approval does not end it at once: the outcome of the command comes later as
operator.action and goes to the audit log. An approved alert is resolved when
its object has been outside the zone for RESOLVE_OUTSIDE_S, or its track is
lost or removed, so the same person coming back later raises a new alert.
The wait keeps someone standing on the zone's edge from raising a stream of
alerts.

Every change is returned as an event, (message type, data), for the
coordinator to broadcast and audit.
"""

from __future__ import annotations

import copy
import itertools
import time
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from typing import Callable

from .schemas import parse_ts
from .zones import Zone, zones_containing

ACTIVE = frozenset({"open", "acknowledged", "approved"})
MAX_ALERTS = 100            # the snapshot's maxItems
EXPIRE_AFTER_S = 120.0      # an unanswered alert lapses after this
RESOLVE_OUTSIDE_S = 30.0    # an approved alert's object outside its zone this long: resolved

Event = tuple[str, dict]


def iso(at: datetime) -> str:
    return at.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class Alerts:
    def __init__(self, zones: list[Zone], suggest: Callable[[dict], dict | None] | None = None,
                 expire_after_s: float = EXPIRE_AFTER_S, max_alerts: int = MAX_ALERTS,
                 resolve_outside_s: float = RESOLVE_OUTSIDE_S):
        self.zones = zones
        self._suggest = suggest
        self._expire_after = timedelta(seconds=expire_after_s)
        self._max = max_alerts
        self._resolve_outside = timedelta(seconds=resolve_outside_s)
        self._outside_since: dict[str, datetime] = {}           # approved alert_id -> first seen outside
        self._alerts: "OrderedDict[str, dict]" = OrderedDict()   # oldest first
        self._open: dict[tuple[str, str], str] = {}             # (object_id, zone_id) -> alert_id
        # Ids stay unique across restarts: a time prefix plus a counter.
        self._prefix = format(int(time.time()), "x")
        self._counter = itertools.count(1)
        self.dropped = 0

    def on_object(self, obj: dict, now: datetime, late: bool = False) -> list[Event]:
        """Alerts raised, or approved alerts resolved, by an object update."""
        if late:
            return []
        if obj.get("status", "active") != "active":         # lost or removed
            return [self._resolve(alert) for alert in self._approved_for(obj["object_id"])]
        events: list[Event] = []
        pos = obj["pos"]
        for alert in self._approved_for(obj["object_id"]):
            zone = next((z for z in self.zones if z.zone_id == alert.get("zone_id")), None)
            if zone is not None and zone.contains(pos["lat"], pos["lon"]):
                self._outside_since.pop(alert["alert_id"], None)
                continue
            since = self._outside_since.setdefault(alert["alert_id"], now)
            if zone is None or now - since >= self._resolve_outside:
                events.append(self._resolve(alert))
        for zone in zones_containing(self.zones, pos["lat"], pos["lon"], obj["class"]):
            key = (obj["object_id"], zone.zone_id)
            current = self._alerts.get(self._open.get(key, ""))
            if current is not None and current["status"] in ACTIVE:
                continue
            events.append(("alert.new", self._raise(obj, zone, now)))
        return events

    def _approved_for(self, object_id: str) -> list[dict]:
        return [a for a in self._alerts.values() if a["object_id"] == object_id and a["status"] == "approved"]

    def _resolve(self, alert: dict) -> Event:
        alert["status"] = "resolved"
        self._outside_since.pop(alert["alert_id"], None)
        return ("alert.update", {"alert_id": alert["alert_id"], "status": "resolved"})

    def _raise(self, obj: dict, zone: Zone, now: datetime) -> dict:
        alert_id = f"a-{self._prefix}-{next(self._counter)}"
        alert = {
            "alert_id": alert_id,
            "object_id": obj["object_id"],
            "severity": zone.severity,
            "reason": f"{obj['class'].replace('_', ' ').capitalize()} inside zone {zone.name}"[:200],
            "zone_id": zone.zone_id,
            "class": obj["class"],
            "confidence": obj["confidence"],
            "pos": copy.deepcopy(obj["pos"]),
            "seen_by": list(obj["seen_by"]),
            "expires_ts": iso(now + self._expire_after),
            "status": "open",
        }
        if obj.get("snapshot_id"):
            alert["snapshot_id"] = obj["snapshot_id"]
        if self._suggest is not None:
            proposal = self._suggest(alert)
            if proposal is not None:
                alert["proposal"] = proposal
        self._alerts[alert_id] = alert
        self._open[(obj["object_id"], zone.zone_id)] = alert_id
        self._cap()
        return copy.deepcopy(alert)

    def _cap(self) -> None:
        while len(self._alerts) > self._max:
            closed = next((aid for aid, a in self._alerts.items() if a["status"] not in ACTIVE), None)
            victim = closed if closed is not None else next(iter(self._alerts))
            del self._alerts[victim]
            self.dropped += 1

    def on_decision(self, action: dict) -> list[Event]:
        """An operator's approve or reject on an alert (operator.action, phase decision)."""
        alert = self._alerts.get(action.get("alert_id", ""))
        if alert is None or alert["status"] not in ("open", "acknowledged"):
            return []
        alert["status"] = "approved" if action["decision"] == "approve" else "rejected"
        alert["operator_id"] = action["operator_id"]
        return [("alert.update", {"alert_id": alert["alert_id"], "status": alert["status"],
                                  "operator_id": alert["operator_id"]})]

    def expire(self, now: datetime) -> list[Event]:
        events: list[Event] = []
        for alert in self._alerts.values():
            if alert["status"] in ("open", "acknowledged") and parse_ts(alert["expires_ts"]) <= now:
                alert["status"] = "expired"
                events.append(("alert.update", {"alert_id": alert["alert_id"], "status": "expired"}))
        return events

    def resolve_missing(self, object_ids: set[str]) -> list[Event]:
        """Approved alerts whose object no longer exists (after a restart): resolved."""
        return [self._resolve(a) for a in list(self._alerts.values())
                if a["status"] == "approved" and a["object_id"] not in object_ids]

    def get(self, alert_id: str) -> dict | None:
        alert = self._alerts.get(alert_id)
        return copy.deepcopy(alert) if alert else None

    def alerts(self) -> list[dict]:
        return [copy.deepcopy(a) for a in self._alerts.values()]

    # Persistence (store.py)

    def to_state(self) -> dict:
        return {"alerts": self.alerts(),
                "open": [[oid, zid, aid] for (oid, zid), aid in self._open.items()]}

    def load_state(self, state: dict) -> None:
        self._alerts = OrderedDict((a["alert_id"], a) for a in state.get("alerts", []))
        self._open = {(oid, zid): aid for oid, zid, aid in state.get("open", []) if aid in self._alerts}
