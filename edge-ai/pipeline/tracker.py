"""Tracker: keeps the same id on the same object between frames.

Each track remembers its box and how fast the box is moving across the
picture. For a new frame every track's box is first moved to where it should
be by now, then tracks and boxes of the same class are paired greedily by
overlap (IoU). Moving the box first matters when frames are dropped: at 3
frames a second a walking person's old and new boxes barely overlap.

A track gets its id, and is reported, only after ``min_hits`` frames in a
row, so a one-frame false detection never reaches the operator. It is
forgotten after ``max_gap_s`` without a match. Ids are never reused within a
run.

This is deliberately small: no appearance model, so two people who cross
can swap ids, and an occlusion longer than ``max_gap_s`` gives a new id.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from .detector import Box


@dataclass
class Track:
    box: Box
    seen_s: float               # when it was last matched
    track_id: int | None = None  # set when the track is confirmed
    hits: int = 1               # frames matched in a row
    vx: float = 0.0             # pixels per second, box centre
    vy: float = 0.0

    def predicted(self, now_s: float) -> Box:
        dt = now_s - self.seen_s
        return replace(self.box, x=self.box.x + self.vx * dt, y=self.box.y + self.vy * dt)


def iou(a: Box, b: Box) -> float:
    w = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
    h = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
    if w <= 0 or h <= 0:
        return 0.0
    inter = w * h
    return inter / (a.w * a.h + b.w * b.h - inter)


class IouTracker:
    def __init__(self, first_id: int = 1, min_iou: float = 0.2, min_hits: int = 3, max_gap_s: float = 1.0):
        self.min_iou = min_iou
        self.min_hits = min_hits
        self.max_gap_s = max_gap_s
        self._next_id = first_id
        self._tracks: list[Track] = []

    def update(self, boxes: list[Box], now_s: float) -> list[Track]:
        """Feed one frame's boxes and its time in seconds; returns the confirmed tracks seen in this frame."""
        self._tracks = [t for t in self._tracks if now_s - t.seen_s <= self.max_gap_s]
        pairs = sorted(((iou(t.predicted(now_s), b), ti, bi) for ti, t in enumerate(self._tracks)
                        for bi, b in enumerate(boxes) if t.box.cls == b.cls), reverse=True)
        matched: set[int] = set()
        used_boxes: set[int] = set()
        for overlap, ti, bi in pairs:
            if overlap < self.min_iou:
                break
            if ti in matched or bi in used_boxes:
                continue
            matched.add(ti)
            used_boxes.add(bi)
            track, box = self._tracks[ti], boxes[bi]
            dt = now_s - track.seen_s
            if dt > 0:
                # Half old, half new: a jittery box does not send the prediction flying.
                track.vx = 0.5 * track.vx + 0.5 * ((box.x + box.w / 2) - (track.box.x + track.box.w / 2)) / dt
                track.vy = 0.5 * track.vy + 0.5 * ((box.y + box.h / 2) - (track.box.y + track.box.h / 2)) / dt
            track.box, track.seen_s, track.hits = box, now_s, track.hits + 1
        for ti, track in enumerate(self._tracks):
            if ti not in matched:
                track.hits = 0
        self._tracks += [Track(box, now_s) for bi, box in enumerate(boxes) if bi not in used_boxes]
        seen = [t for t in self._tracks if t.seen_s == now_s]
        for track in seen:
            if track.track_id is None and track.hits >= self.min_hits:
                track.track_id = self._next_id
                self._next_id += 1
        return [t for t in seen if t.track_id is not None]

    def reset(self) -> None:
        """Forget every track (a cut in the video). Ids carry on, so none is reused."""
        self._tracks = []
