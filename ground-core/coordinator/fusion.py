"""Detections to objects: sightings become tracks.

Each track holds a position, a velocity and an error (metres, one sigma). A
detection is matched to a track in three steps:

1. The same camera and the same edge track id as before: that track.
2. Otherwise, every track of the same class is predicted forward to the
   detection's time with its velocity (constant-velocity model), and the
   nearest one inside the gate is taken. The gate is
   max(GATE_MIN_M, GATE_SIGMAS * sqrt(track_error^2 + detection_error^2)),
   so two cameras that disagree by less than their stated errors merge.
   A camera never merges two of its own track ids: its tracker already says
   they are different objects.
3. Otherwise a new track starts.

The update weights prediction and measurement by their errors (a scalar
Kalman gain), so a precise sighting moves a track more than a vague one, and
the velocity follows the corrected motion. Tracks nobody has seen for
LOST_AFTER_S become "lost", and after REMOVE_AFTER_S "removed" and dropped.
"""

from __future__ import annotations

import copy
import math
from collections import OrderedDict
from dataclasses import dataclass, field
from datetime import datetime

from .geo import move, offset_m, distance_m
from .schemas import parse_ts

MAX_OBJECTS = 500
GATE_MIN_M = 10.0
GATE_SIGMAS = 3.0
PROCESS_NOISE_MS = 1.0      # how far a walking person may stray from a straight line, per second
VELOCITY_GAIN = 0.5         # share of the position correction fed into the velocity
MAX_SPEED_MS = 60.0         # a track faster than this is a mismatch, not a vehicle on site
LOST_AFTER_S = 10.0
REMOVE_AFTER_S = 60.0
MIN_ERROR_M = 0.5


@dataclass
class Track:
    object_id: str
    cls: str
    confidence: float
    lat: float
    lon: float
    error_m: float
    seen: datetime              # time of the last sighting
    seen_ts: str                # the same, as the sender wrote it
    east_ms: float = 0.0
    north_ms: float = 0.0
    seen_by: dict[str, str] = field(default_factory=dict)   # source id -> last sighting ts
    snapshot_id: str | None = None
    status: str = "active"

    def predict(self, at: datetime) -> tuple[float, float, float]:
        """(lat, lon, error_m) moved forward to ``at``."""
        dt = max(0.0, (at - self.seen).total_seconds())
        lat, lon = move(self.lat, self.lon, self.east_ms * dt, self.north_ms * dt)
        return lat, lon, math.hypot(self.error_m, PROCESS_NOISE_MS * dt)

    def to_object(self) -> dict:
        obj = {
            "object_id": self.object_id,
            "class": self.cls,
            "confidence": round(self.confidence, 3),
            "pos": {"lat": round(self.lat, 7), "lon": round(self.lon, 7),
                    "error_m": round(max(self.error_m, MIN_ERROR_M), 1)},
            "velocity": {"east_ms": round(self.east_ms, 2), "north_ms": round(self.north_ms, 2)},
            "seen_by": sorted(self.seen_by),
            "last_seen_ts": self.seen_ts,
            "status": self.status,
        }
        if self.snapshot_id:
            obj["snapshot_id"] = self.snapshot_id
        return obj

    def to_state(self) -> dict:
        state = copy.deepcopy(self.__dict__)
        state["seen"] = self.seen_ts
        return state

    @classmethod
    def from_state(cls, state: dict) -> "Track":
        state = dict(state)
        state["seen"] = parse_ts(state["seen_ts"])
        return cls(**state)


class Fusion:
    def __init__(self, max_objects: int = MAX_OBJECTS):
        self._max = max_objects
        self._tracks: "OrderedDict[str, Track]" = OrderedDict()   # least recently seen first
        self._links: dict[tuple[str, int], str] = {}              # (source, edge track id) -> object id
        self.dropped = 0    # objects pushed out by the cap
        self.merged = 0     # sightings joined to another camera's track

    # Matching

    def _match(self, source: str, cls: str, lat: float, lon: float, error_m: float, at: datetime) -> Track | None:
        own = {oid for (src, _), oid in self._links.items() if src == source}
        best, best_d = None, None
        for track in self._tracks.values():
            if track.cls != cls or track.status == "removed" or track.object_id in own:
                continue
            p_lat, p_lon, p_err = track.predict(at)
            d = distance_m(p_lat, p_lon, lat, lon)
            gate = max(GATE_MIN_M, GATE_SIGMAS * math.hypot(p_err, error_m))
            if d <= gate and (best_d is None or d < best_d):
                best, best_d = track, d
        return best

    def _new_track(self, source: str, track_id: int, data: dict, at: datetime, ts: str) -> Track:
        object_id = f"o-{source}-{track_id}"
        n = 2
        while object_id in self._tracks:
            object_id = f"o-{source}-{track_id}-{n}"
            n += 1
        geo = data["geo"]
        return Track(object_id=object_id, cls=data["class"], confidence=data["confidence"],
                     lat=geo["lat"], lon=geo["lon"], error_m=geo["error_m"], seen=at, seen_ts=ts)

    @staticmethod
    def _update(track: Track, data: dict, at: datetime, ts: str) -> None:
        geo = data["geo"]
        dt = (at - track.seen).total_seconds()
        if dt < 0:
            return  # an older sighting than the track already has: it may add a camera, never move it
        p_lat, p_lon, p_err = track.predict(at)
        gain = p_err ** 2 / (p_err ** 2 + geo["error_m"] ** 2)
        res_e, res_n = offset_m(p_lat, p_lon, geo["lat"], geo["lon"])
        track.lat, track.lon = move(p_lat, p_lon, gain * res_e, gain * res_n)
        track.error_m = math.sqrt((p_err ** 2 * geo["error_m"] ** 2) / (p_err ** 2 + geo["error_m"] ** 2))
        if dt > 0:
            track.east_ms += VELOCITY_GAIN * gain * res_e / dt
            track.north_ms += VELOCITY_GAIN * gain * res_n / dt
            speed = math.hypot(track.east_ms, track.north_ms)
            if speed > MAX_SPEED_MS:
                track.east_ms *= MAX_SPEED_MS / speed
                track.north_ms *= MAX_SPEED_MS / speed
        track.seen, track.seen_ts = at, ts
        track.confidence = data["confidence"]

    # Public

    def ingest(self, msg: dict) -> dict | None:
        """The changed object for a detection message, or None if it has no ground position."""
        data = msg["data"]
        if data.get("geo") is None:
            return None
        source, ts = msg["src"], msg["ts"]
        at = parse_ts(ts)
        key = (source, data["track_id"])

        track = self._tracks.get(self._links.get(key, ""))
        if track is None:
            geo = data["geo"]
            track = self._match(source, data["class"], geo["lat"], geo["lon"], geo["error_m"], at)
            if track is None:
                track = self._new_track(source, data["track_id"], data, at, ts)
                self._tracks[track.object_id] = track
            else:
                if source not in track.seen_by:
                    self.merged += 1
                self._update(track, data, at, ts)
            self._links[key] = track.object_id
        else:
            self._update(track, data, at, ts)
        if track.seen_by.get(source) is None or parse_ts(track.seen_by[source]) <= at:
            track.seen_by[source] = ts
        if data.get("snapshot_id"):
            track.snapshot_id = data["snapshot_id"]
        track.status = "active"

        self._tracks.move_to_end(track.object_id)
        while len(self._tracks) > self._max:
            oldest, _ = self._tracks.popitem(last=False)
            self._forget(oldest)
            self.dropped += 1
        return track.to_object()

    def expire(self, now: datetime) -> list[dict]:
        """Marks silent tracks lost, then removed. Returns every object that changed."""
        changed = []
        for track in list(self._tracks.values()):
            silent = (now - track.seen).total_seconds()
            if silent > REMOVE_AFTER_S:
                track.status = "removed"
                changed.append(track.to_object())
                del self._tracks[track.object_id]
                self._forget(track.object_id)
            elif silent > LOST_AFTER_S and track.status == "active":
                track.status = "lost"
                changed.append(track.to_object())
        return changed

    def get(self, object_id: str) -> dict | None:
        track = self._tracks.get(object_id)
        return track.to_object() if track else None

    def objects(self) -> list[dict]:
        return [t.to_object() for t in self._tracks.values()]

    def _forget(self, object_id: str) -> None:
        for key in [k for k, v in self._links.items() if v == object_id]:
            del self._links[key]

    # Persistence (store.py)

    def to_state(self) -> dict:
        return {"tracks": [t.to_state() for t in self._tracks.values()],
                "links": [[src, tid, oid] for (src, tid), oid in self._links.items()]}

    def load_state(self, state: dict) -> None:
        self._tracks.clear()
        self._links.clear()
        for item in state.get("tracks", []):
            track = Track.from_state(item)
            self._tracks[track.object_id] = track
        for src, tid, oid in state.get("links", []):
            if oid in self._tracks:
                self._links[(src, tid)] = oid
