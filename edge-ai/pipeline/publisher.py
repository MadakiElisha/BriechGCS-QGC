"""EdgePublisher: the last stage of the edge pipeline, from a detection to the broker.

    pub = EdgePublisher("tower-01", "broker.lan", password=..., ca_file="ca.crt",
                        queue_path="var/queue.sqlite", model_version="yolox-tiny-0.1.1rc0",
                        snapshot_url="https://ground.lan:8443/api/v1/snapshots", device_token=...)
    pub.start()
    pub.publish_detection("person", 0.91, track_id=17,
                          bbox={"x": 0.41, "y": 0.52, "w": 0.05, "h": 0.14},
                          geo={"lat": 6.5251, "lon": 3.3801, "error_m": 6.0}, jpeg=jpeg_bytes)
    pub.set_health(fps=12.5)
    pub.stop()

What it does (handoff section 9, "the edge publishers"):

* builds ``detection`` and ``edge.status`` to ``schemas/`` and sends them on
  ``briech/v1/edge/<id>/detection`` and ``.../status``;
* sends ``edge.status`` every 5 s, retained, with an offline one as the MQTT
  last will, so the broker announces a dead device at once;
* uploads a JPEG to ``POST /api/v1/snapshots`` and puts the returned
  ``snapshot_id`` in the detection. A failed upload never holds a detection
  back: it goes without a picture;
* keeps a disk queue. Every detection is written to it first and removed only
  when the broker has acknowledged it (QoS 1), so a link drop or a restart
  loses nothing. The queue is sent oldest first, and a detection sent more
  than 60 s after it was made carries ``late: true``.

Delivery is at least once: around a reconnect the same detection (same ``id``)
can arrive twice.

The caller's thread only writes to the queue; one sender thread owns the
network. Needs paho-mqtt and nothing else outside the standard library, so it
can be used without the rest of the pipeline.
"""

from __future__ import annotations

import json
import logging
import math
import re
import sqlite3
import ssl
import threading
import time
import urllib.error
import urllib.request
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

import paho.mqtt.client as mqtt

log = logging.getLogger(__name__)

LATE_AFTER_S = 60.0            # schemas/detection: "late" when sent this long after it was made
MAX_PER_SECOND = 10.0          # schemas/detection: up to 10 per second per source
STATUS_EVERY_S = 5.0           # schemas/edge.status
MAX_PAYLOAD = 4096             # the coordinator drops anything bigger
SNAPSHOT_MAX_BYTES = 300_000   # POST /api/v1/snapshots refuses more
SNAPSHOT_RETRY_S = 30.0        # after a failed upload, send without pictures for this long

_SOURCE_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
_CLASS_RE = re.compile(r"^[a-z_]{1,32}$")
_SNAPSHOT_ID_RE = re.compile(r"^snap-[a-z0-9]{6,32}$")
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


# ----------------------------------------------------------------------------
# Messages
# ----------------------------------------------------------------------------

def iso_utc(epoch_s: float) -> str:
    """UTC, ISO 8601 with milliseconds, ending in Z."""
    stamp = datetime.fromtimestamp(epoch_s, timezone.utc).isoformat(timespec="milliseconds")
    return stamp.replace("+00:00", "Z")


def topic(source_id: str, leaf: str) -> str:
    return f"briech/v1/edge/{source_id}/{leaf}"


def envelope(msg_type: str, msg_id: str, source_id: str, made_s: float, data: dict) -> dict:
    return {"v": 1, "type": msg_type, "id": msg_id, "ts": iso_utc(made_s), "src": source_id, "data": data}


def _unit(value: float, name: str) -> float:
    if not math.isfinite(value):
        raise ValueError(f"{name} is not a number")
    return min(1.0, max(0.0, float(value)))


def detection_data(cls: str, confidence: float, track_id: int, bbox: dict, geo: dict | None = None) -> dict:
    """The ``data`` of a detection. Raises ValueError for what the schema would refuse.

    ``bbox`` is x, y, w, h as fractions of the frame from the top-left corner; a
    box that pokes just outside the frame is clipped. ``geo`` is lat, lon and
    error_m, or None when the target has no honest ground position. A position
    without an error greater than zero is refused, never repaired.
    """
    if not _CLASS_RE.match(cls):
        raise ValueError(f"class {cls!r}: lower case letters and underscores, at most 32")
    if not math.isfinite(confidence) or not 0.0 <= confidence <= 1.0:
        raise ValueError(f"confidence {confidence!r} is not within 0 to 1")
    if int(track_id) != track_id or track_id < 0:
        raise ValueError(f"track_id {track_id!r} is not a whole number from 0 up")
    data: dict = {
        "class": cls,
        "confidence": round(float(confidence), 3),
        "track_id": int(track_id),
        "bbox": {key: round(_unit(bbox[key], f"bbox.{key}"), 4) for key in ("x", "y", "w", "h")},
    }
    if geo is not None:
        lat, lon, error_m = float(geo["lat"]), float(geo["lon"]), float(geo["error_m"])
        if not (math.isfinite(lat) and -90.0 <= lat <= 90.0 and math.isfinite(lon) and -180.0 <= lon <= 180.0):
            raise ValueError(f"geo {lat!r}, {lon!r} is not a WGS84 position")
        if not math.isfinite(error_m) or error_m <= 0.0:
            raise ValueError("geo.error_m must be greater than zero: leave geo out rather than guess")
        data["geo"] = {"lat": round(lat, 7), "lon": round(lon, 7), "error_m": max(0.1, round(error_m, 1))}
    return data


def status_data(state: str, *, model_version: str | None = None, model_sha256: str | None = None,
                uptime_s: float | None = None, fps: float | None = None, queue_len: int | None = None,
                cpu_temp_c: float | None = None) -> dict:
    """The ``data`` of an edge.status. Fields that are None are left out."""
    if state not in ("online", "degraded", "offline"):
        raise ValueError(f"state {state!r}")
    data: dict = {"state": state}
    if model_version:
        data["model_version"] = model_version[:64]
    if model_sha256:
        data["model_sha256"] = model_sha256
    if uptime_s is not None:
        data["uptime_s"] = round(max(0.0, uptime_s), 1)
    if fps is not None and math.isfinite(fps):
        data["fps"] = round(max(0.0, fps), 1)
    if queue_len is not None:
        data["queue_len"] = max(0, int(queue_len))
    if cpu_temp_c is not None and math.isfinite(cpu_temp_c):
        data["cpu_temp_c"] = round(cpu_temp_c, 1)
    return data


def read_cpu_temp_c() -> float | None:
    """The board temperature on Linux (a Jetson, a Pi); None anywhere else."""
    try:
        return int(Path("/sys/class/thermal/thermal_zone0/temp").read_text().strip()) / 1000.0
    except (OSError, ValueError):
        return None


# ----------------------------------------------------------------------------
# Disk queue
# ----------------------------------------------------------------------------

@dataclass
class Queued:
    seq: int
    made_s: float               # when the detection was made, Unix seconds
    data: dict
    jpeg: bytes | None


class DiskQueue:
    """Detections waiting to be sent, in one SQLite file, oldest first.

    Holds at most ``max_items``; when full the oldest is dropped and counted
    in ``dropped``. Pictures are kept only while they total under
    ``max_jpeg_bytes``: beyond that a detection is queued without its picture.
    Safe to use from two threads.
    """

    def __init__(self, path: str | Path, max_items: int = 20_000, max_jpeg_bytes: int = 20_000_000):
        self.max_items = max_items
        self.max_jpeg_bytes = max_jpeg_bytes
        self.dropped = 0
        self._lock = threading.Lock()
        if str(path) != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("PRAGMA synchronous=NORMAL")
        # AUTOINCREMENT: a sequence number is never used twice, even after its row is gone.
        self._db.execute("CREATE TABLE IF NOT EXISTS detections ("
                         "seq INTEGER PRIMARY KEY AUTOINCREMENT, made_s REAL NOT NULL, "
                         "data TEXT NOT NULL, jpeg BLOB)")
        self._db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        self._db.execute("INSERT OR IGNORE INTO meta VALUES ('created', ?)", (format(int(time.time()), "x"),))
        #: Made once per queue file and put in every message id, so ids stay unique if the file is replaced.
        self.created: str = self._db.execute("SELECT value FROM meta WHERE key = 'created'").fetchone()[0]
        self._len, self._jpeg_bytes = self._db.execute(
            "SELECT COUNT(*), COALESCE(SUM(LENGTH(jpeg)), 0) FROM detections").fetchone()

    def __len__(self) -> int:
        return self._len

    def put(self, made_s: float, data: dict, jpeg: bytes | None = None) -> int:
        with self._lock:
            if jpeg is not None and self._jpeg_bytes + len(jpeg) > self.max_jpeg_bytes:
                jpeg = None
            while self._len >= self.max_items:
                seq, size = self._db.execute(
                    "SELECT seq, COALESCE(LENGTH(jpeg), 0) FROM detections ORDER BY seq LIMIT 1").fetchone()
                self._forget(seq, size)
                self.dropped += 1
            cur = self._db.execute("INSERT INTO detections (made_s, data, jpeg) VALUES (?, ?, ?)",
                                   (made_s, json.dumps(data, separators=(",", ":")), jpeg))
            self._len += 1
            self._jpeg_bytes += len(jpeg) if jpeg else 0
            return cur.lastrowid

    def oldest(self, limit: int) -> list[Queued]:
        with self._lock:
            rows = self._db.execute(
                "SELECT seq, made_s, data, jpeg FROM detections ORDER BY seq LIMIT ?", (limit,)).fetchall()
        return [Queued(seq, made_s, json.loads(data), jpeg) for seq, made_s, data, jpeg in rows]

    def oldest_made_s(self) -> float | None:
        with self._lock:
            row = self._db.execute("SELECT made_s FROM detections ORDER BY seq LIMIT 1").fetchone()
        return row[0] if row else None

    def replace_picture(self, seq: int, data: dict) -> None:
        """Store ``data`` (now holding a snapshot_id) and drop the uploaded picture."""
        with self._lock:
            row = self._db.execute("SELECT COALESCE(LENGTH(jpeg), 0) FROM detections WHERE seq = ?", (seq,)).fetchone()
            if row is None:
                return
            self._db.execute("UPDATE detections SET data = ?, jpeg = NULL WHERE seq = ?",
                             (json.dumps(data, separators=(",", ":")), seq))
            self._jpeg_bytes -= row[0]

    def remove(self, seq: int) -> None:
        with self._lock:
            row = self._db.execute("SELECT COALESCE(LENGTH(jpeg), 0) FROM detections WHERE seq = ?", (seq,)).fetchone()
            if row is not None:
                self._forget(seq, row[0])

    def _forget(self, seq: int, jpeg_size: int) -> None:
        self._db.execute("DELETE FROM detections WHERE seq = ?", (seq,))
        self._len -= 1
        self._jpeg_bytes -= jpeg_size

    def close(self) -> None:
        with self._lock:
            self._db.close()


# ----------------------------------------------------------------------------
# Snapshot upload
# ----------------------------------------------------------------------------

class SnapshotUploader:
    """POST /api/v1/snapshots: one JPEG in, a snapshot id out."""

    def __init__(self, url: str, device_token: str, ca_file: str | None = None, timeout_s: float = 3.0):
        self.url = url
        self._token = device_token
        self._timeout_s = timeout_s
        self._context = ssl.create_default_context(cafile=ca_file) if url.startswith("https") else None

    def upload(self, jpeg: bytes) -> str | None:
        """The snapshot id, or None when the upload did not work (logged, never raised)."""
        request = urllib.request.Request(self.url, data=jpeg, method="POST", headers={
            "Authorization": f"Bearer {self._token}", "Content-Type": "image/jpeg"})
        try:
            with urllib.request.urlopen(request, timeout=self._timeout_s, context=self._context) as response:
                snapshot_id = json.loads(response.read(4096)).get("snapshot_id")
        except (OSError, ValueError, urllib.error.URLError) as error:   # the token is never in these
            log.warning("snapshot upload failed: %s", error)
            return None
        if not isinstance(snapshot_id, str) or not _SNAPSHOT_ID_RE.match(snapshot_id):
            log.warning("snapshot upload: unusable answer")
            return None
        return snapshot_id


# ----------------------------------------------------------------------------
# The publisher
# ----------------------------------------------------------------------------

class _Bucket:
    """At most ``rate`` per second, with bursts up to one second's worth."""

    def __init__(self, rate: float):
        self.rate = rate
        self._tokens = rate
        self._at = time.monotonic()

    def available(self) -> int:
        now = time.monotonic()
        self._tokens = min(self.rate, self._tokens + (now - self._at) * self.rate)
        self._at = now
        return int(self._tokens)

    def take(self, n: int = 1) -> bool:
        if self.available() < n:
            return False
        self._tokens -= n
        return True


class EdgePublisher:
    """Sends one edge computer's detections and status. See the module text.

    ``source_id`` is the device id: the MQTT login, the id in the topics and
    ``src`` in every message. ``check``, when given, is called with each
    finished message and returns None or a reason; a message with a reason is
    dropped and counted (``invalid``), never sent. Pass the coordinator's
    ``MessageValidator.check`` in tests and on a development machine.

    ``stats`` counts: ``queued``, ``sent``, ``late``, ``status``,
    ``snapshots``, ``snapshot_failed``, ``rate_limited``, ``invalid``,
    ``queue_dropped``, ``picture_too_big``.
    """

    def __init__(self, source_id: str, host: str, port: int = 8883, *, password: str | None = None,
                 ca_file: str | None = None, tls: bool = True, queue_path: str | Path = "var/queue.sqlite",
                 model_version: str | None = None, model_sha256: str | None = None,
                 snapshot_url: str | None = None, device_token: str | None = None,
                 check: Callable[[dict], str | None] | None = None,
                 status_every_s: float = STATUS_EVERY_S, max_per_second: float = MAX_PER_SECOND,
                 late_after_s: float = LATE_AFTER_S, queue_max_items: int = 20_000):
        if not _SOURCE_RE.match(source_id):
            raise ValueError(f"source id {source_id!r}: lower case letters, digits and hyphens")
        if model_sha256 is not None and not _SHA256_RE.match(model_sha256):
            raise ValueError("model_sha256 is 64 lower case hex digits")
        self.source_id = source_id
        self.stats: Counter = Counter()
        self.last_error: str | None = None
        self._host, self._port = host, port
        self._model_version, self._model_sha256 = model_version, model_sha256
        self._check = check
        self._status_every_s = status_every_s
        self._late_after_s = late_after_s
        self._queue = DiskQueue(queue_path, max_items=queue_max_items)
        self._uploader = SnapshotUploader(snapshot_url, device_token, ca_file) if snapshot_url and device_token else None
        self._upload_after = 0.0
        self._accept = _Bucket(max_per_second)      # what the pipeline may hand over
        self._wire = _Bucket(max_per_second)        # what goes to the broker, backlog included
        self._fps: float | None = None
        self._degraded: str | None = None
        self._status_seq = 0
        self._status_due = 0.0
        self._started = time.monotonic()
        self._connected = threading.Event()
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

        client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                             client_id=f"edge-{source_id}", protocol=mqtt.MQTTv311)
        if password is not None:
            client.username_pw_set(source_id, password)
        if tls:
            client.tls_set(ca_certs=ca_file, cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
        will = envelope("edge.status", f"s-{source_id}-will", source_id, time.time(), status_data("offline"))
        client.will_set(topic(source_id, "status"), json.dumps(will, separators=(",", ":")), qos=1, retain=True)
        client.reconnect_delay_set(min_delay=1, max_delay=30)
        client.on_connect = self._on_connect
        client.on_disconnect = self._on_disconnect
        self._client = client

    # -- the pipeline's side --------------------------------------------------

    def start(self) -> None:
        """Connect in the background and start sending. Returns at once: the queue covers a late link."""
        log.info("MQTT: connecting to %s:%d as %s, %d detections waiting in the queue",
                 self._host, self._port, self.source_id, len(self._queue))
        self._client.connect_async(self._host, self._port, keepalive=10)
        self._client.loop_start()
        self._thread = threading.Thread(target=self._run, name="edge-publisher", daemon=True)
        self._thread.start()

    def wait_connected(self, timeout_s: float) -> bool:
        return self._connected.wait(timeout_s)

    @property
    def connected(self) -> bool:
        return self._connected.is_set()

    @property
    def queue_len(self) -> int:
        return len(self._queue)

    def publish_detection(self, cls: str, confidence: float, track_id: int, bbox: dict,
                          geo: dict | None = None, jpeg: bytes | None = None, made_s: float | None = None) -> bool:
        """Queue one detection. False when it was over the rate limit and not taken.

        ``made_s`` is when the frame was taken (Unix seconds, default now).
        ``jpeg`` is a picture of it, at most 300 KB. Raises ValueError for
        values the schema would refuse.
        """
        data = detection_data(cls, confidence, track_id, bbox, geo)
        if not self._accept.take():
            self.stats["rate_limited"] += 1
            return False
        if jpeg is not None and (len(jpeg) > SNAPSHOT_MAX_BYTES or not jpeg.startswith(b"\xff\xd8\xff")):
            self.stats["picture_too_big"] += 1
            jpeg = None
        self._queue.put(time.time() if made_s is None else made_s, data, jpeg if self._uploader else None)
        self.stats["queued"] += 1
        self._wake.set()
        return True

    def set_health(self, fps: float | None = None, degraded: str | None = None) -> None:
        """What the next edge.status reports. ``degraded`` is a short reason, or None when all is well."""
        self._fps = fps
        if degraded != self._degraded:
            self._degraded = degraded
            self._status_due = 0.0
            self._wake.set()

    def stop(self, flush_s: float = 2.0) -> None:
        """Send what can be sent in ``flush_s``, say offline, disconnect. The rest stays on disk."""
        deadline = time.monotonic() + flush_s
        while self.connected and len(self._queue) and time.monotonic() < deadline:
            time.sleep(0.05)
        self._stop.set()
        self._wake.set()
        if self._thread is not None:
            self._thread.join(timeout=10)
        if self.connected:   # a clean stop says offline itself; only a crash leaves it to the last will
            self._send_status("offline")
        self._client.disconnect()
        self._client.loop_stop()
        self._queue.close()
        log.info("stopped: %s", dict(self.stats))

    # -- paho's thread --------------------------------------------------------

    def _on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            self.last_error = f"broker refused {self.source_id}: {reason_code}"
            log.error("MQTT: %s", self.last_error)
            return
        log.info("MQTT: connected")
        self.last_error = None
        self._status_due = 0.0      # replace the retained offline will straight away
        self._connected.set()
        self._wake.set()

    def _on_disconnect(self, client, userdata, flags, reason_code, properties):
        if self._connected.is_set() and not self._stop.is_set():
            log.warning("MQTT: disconnected (%s), detections go to the disk queue", reason_code)
        self._connected.clear()

    # -- the sender thread ----------------------------------------------------

    def _run(self) -> None:
        while not self._stop.is_set():
            self._wake.clear()
            if not self._connected.is_set():
                self._wake.wait(0.5)
                continue
            if time.monotonic() >= self._status_due:
                self._send_status(self._state())
                self._status_due = time.monotonic() + self._status_every_s
            budget = min(self._wire.available(), 20)
            batch = self._queue.oldest(budget) if budget else []
            if batch:
                self._wire.take(len(batch))
                self._send(batch)
            elif len(self._queue):
                time.sleep(0.02)    # a backlog, waiting on the rate limit
            else:
                self._wake.wait(0.2)

    def _state(self) -> str:
        oldest = self._queue.oldest_made_s()
        behind = oldest is not None and time.time() - oldest > self._late_after_s
        return "degraded" if self._degraded or behind else "online"

    def _send_status(self, state: str) -> None:
        self._status_seq += 1
        if state == "offline":
            data = status_data("offline")
        else:
            data = status_data(state, model_version=self._model_version, model_sha256=self._model_sha256,
                               uptime_s=time.monotonic() - self._started, fps=self._fps,
                               queue_len=len(self._queue), cpu_temp_c=read_cpu_temp_c())
        msg = envelope("edge.status", f"s-{self.source_id}-{self._queue.created}-{self._status_seq:06d}",
                       self.source_id, time.time(), data)
        payload = self._payload(msg)
        if payload is None:
            return
        info = self._client.publish(topic(self.source_id, "status"), payload, qos=1, retain=True)
        if state == "offline":
            try:
                info.wait_for_publish(2.0)
            except (RuntimeError, ValueError):
                pass
        self.stats["status"] += 1

    def _payload(self, msg: dict) -> str | None:
        """The message as compact JSON, or None (counted) when it must not be sent."""
        payload = json.dumps(msg, separators=(",", ":"))
        reason = self._check(msg) if self._check else None
        if reason is None and len(payload.encode()) > MAX_PAYLOAD:
            reason = "over 4 KB"
        if reason is not None:
            self.stats["invalid"] += 1
            log.error("not sent, %s: %s", reason, payload[:300])
            return None
        return payload

    def _attach_picture(self, item: Queued) -> None:
        if item.jpeg is None or self._uploader is None or time.monotonic() < self._upload_after:
            return
        snapshot_id = self._uploader.upload(item.jpeg)
        if snapshot_id is None:
            self.stats["snapshot_failed"] += 1
            self._upload_after = time.monotonic() + SNAPSHOT_RETRY_S
            return
        item.data["snapshot_id"] = snapshot_id
        self._queue.replace_picture(item.seq, item.data)   # a resend must not upload it again
        self.stats["snapshots"] += 1

    def _send(self, batch: list[Queued]) -> None:
        waiting = []
        for item in batch:
            self._attach_picture(item)
            data = dict(item.data)
            late = time.time() - item.made_s > self._late_after_s
            if late:
                data["late"] = True
            msg = envelope("detection", f"d-{self.source_id}-{self._queue.created}-{item.seq:06d}",
                           self.source_id, item.made_s, data)
            payload = self._payload(msg)
            if payload is None:
                self._queue.remove(item.seq)    # it will never be valid: do not block the queue behind it
                continue
            waiting.append((item, late, self._client.publish(topic(self.source_id, "detection"), payload, qos=1)))
        deadline = time.monotonic() + 5.0
        for item, late, info in waiting:
            try:
                info.wait_for_publish(max(0.0, deadline - time.monotonic()))
                acknowledged = info.is_published()
            except (RuntimeError, ValueError):
                acknowledged = False
            if not acknowledged:
                break               # the link went: this one and the rest stay queued, in order
            self._queue.remove(item.seq)
            self.stats["sent"] += 1
            self.stats["late"] += late
        self.stats["queue_dropped"] = self._queue.dropped
