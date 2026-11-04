"""Detections to objects.

This is the skeleton's pass-through: one object per (source, edge track id),
moved to the latest detection. Row 4 of the coordinator plan replaces it with
real tracks (a constant-velocity filter with gating, so two towers seeing one
person give one object listing both in ``seen_by``) behind the same
``ingest`` call.
"""

from __future__ import annotations

import copy
from collections import OrderedDict

MAX_OBJECTS = 500


class Fusion:
    def __init__(self, max_objects: int = MAX_OBJECTS):
        self._max = max_objects
        self._objects: "OrderedDict[str, dict]" = OrderedDict()
        self.dropped = 0  # objects pushed out by the cap

    def ingest(self, msg: dict) -> dict | None:
        """The changed object for a detection message, or None if it has no ground position."""
        data = msg["data"]
        geo = data.get("geo")
        if geo is None:
            return None
        object_id = f"o-{msg['src']}-{data['track_id']}"
        obj = {
            "object_id": object_id,
            "class": data["class"],
            "confidence": data["confidence"],
            "pos": dict(geo),
            "seen_by": [msg["src"]],
            "last_seen_ts": msg["ts"],
            "status": "active",
        }
        if "snapshot_id" in data:
            obj["snapshot_id"] = data["snapshot_id"]
        elif object_id in self._objects and "snapshot_id" in self._objects[object_id]:
            obj["snapshot_id"] = self._objects[object_id]["snapshot_id"]
        self._objects[object_id] = obj
        self._objects.move_to_end(object_id)
        while len(self._objects) > self._max:
            self._objects.popitem(last=False)
            self.dropped += 1
        return copy.deepcopy(obj)

    def objects(self) -> list[dict]:
        return [copy.deepcopy(o) for o in self._objects.values()]
