"""EdgePublisher: messages match schemas/, the disk queue keeps order, late is flagged.

The broker is replaced by a stand-in for paho's client, so these run anywhere.
"""

import json
import time

import pytest

from pipeline import publisher as pub
from pipeline.publisher import DiskQueue, EdgePublisher, detection_data, envelope, status_data, topic

BBOX = {"x": 0.41, "y": 0.52, "w": 0.05, "h": 0.14}
GEO = {"lat": 6.5251, "lon": 3.3801, "error_m": 6.0}
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 100


class FakeInfo:
    def __init__(self, ok):
        self._ok = ok

    def wait_for_publish(self, timeout=None):
        return self._ok

    def is_published(self):
        return self._ok


class FakeClient:
    """What EdgePublisher uses of paho's client; records what was published."""

    def __init__(self):
        self.acks = True
        self.sent: list[tuple[str, dict, int, bool]] = []
        self.will = None

    def publish(self, topic_name, payload, qos=0, retain=False):
        if self.acks:
            self.sent.append((topic_name, json.loads(payload), qos, retain))
        return FakeInfo(self.acks)

    def will_set(self, topic_name, payload, qos=0, retain=False):
        self.will = (topic_name, json.loads(payload), qos, retain)

    def detections(self):
        return [m for t, m, _, _ in self.sent if t.endswith("/detection")]

    def statuses(self):
        return [m for t, m, _, _ in self.sent if t.endswith("/status")]

    def connect_async(self, *a, **k): pass
    def loop_start(self): pass
    def loop_stop(self): pass
    def disconnect(self): pass
    def username_pw_set(self, *a): pass
    def tls_set(self, **k): pass
    def reconnect_delay_set(self, **k): pass


class FakeUploader:
    def __init__(self):
        self.works = True
        self.uploads = 0

    def upload(self, jpeg):
        self.uploads += 1
        return f"snap-{self.uploads:06d}" if self.works else None


@pytest.fixture
def make(tmp_path, validator, monkeypatch):
    """make(**options) -> (publisher, fake client), not started: tests drive the sender by hand."""
    made = []

    def _make(**options):
        client = FakeClient()
        monkeypatch.setattr(pub.mqtt, "Client", lambda **k: client)
        options.setdefault("queue_path", tmp_path / "queue.sqlite")
        p = EdgePublisher("tower-01", "localhost", password="x", check=validator.check,
                          model_version="test-0.1", model_sha256="ab" * 32, **options)
        made.append(p)
        return p, client

    yield _make
    for p in made:
        p._queue.close()


def drain(p: EdgePublisher) -> None:
    while batch := p._queue.oldest(20):
        before = len(p._queue)
        p._send(batch)
        if len(p._queue) == before:
            return


# -- messages -----------------------------------------------------------------

def test_detection_and_status_match_the_schemas(validator):
    now = time.time()
    msgs = [
        envelope("detection", "d-tower-01-1", "tower-01", now, detection_data("person", 0.91, 17, BBOX, GEO)),
        envelope("detection", "d-tower-01-2", "tower-01", now, detection_data("vehicle", 1.0, 0, BBOX)),
        envelope("edge.status", "s-tower-01-1", "tower-01", now, status_data("offline")),
        envelope("edge.status", "s-tower-01-2", "tower-01", now, status_data(
            "degraded", model_version="m" * 80, model_sha256="0" * 64, uptime_s=3.21, fps=9.96,
            queue_len=4, cpu_temp_c=61.04)),
    ]
    for msg in msgs:
        assert validator.check(msg) is None, validator.check(msg)
    assert "geo" not in msgs[1]["data"]
    assert msgs[0]["ts"].endswith("Z") and len(msgs[0]["ts"]) == 24      # milliseconds, UTC


def test_topics_are_the_ones_the_bus_accepts():
    from coordinator.bus import topic_type
    assert topic_type(topic("tower-01", "detection")) == ("detection", "tower-01")
    assert topic_type(topic("tower-01", "status")) == ("edge.status", "tower-01")


def test_a_box_poking_outside_the_frame_is_clipped(validator):
    data = detection_data("person", 0.5, 1, {"x": -0.01, "y": 0.9, "w": 0.2, "h": 1.2})
    assert data["bbox"] == {"x": 0.0, "y": 0.9, "w": 0.2, "h": 1.0}
    assert validator.check(envelope("detection", "d-1", "tower-01", time.time(), data)) is None


@pytest.mark.parametrize("geo", [
    {"lat": 6.5, "lon": 3.3, "error_m": 0.0},
    {"lat": 6.5, "lon": 3.3, "error_m": float("nan")},
    {"lat": 96.5, "lon": 3.3, "error_m": 5.0},
])
def test_a_position_without_an_honest_error_is_refused(geo):
    with pytest.raises(ValueError):
        detection_data("person", 0.9, 1, BBOX, geo)
    with pytest.raises(KeyError):
        detection_data("person", 0.9, 1, BBOX, {"lat": 6.5, "lon": 3.3})


@pytest.mark.parametrize("cls, confidence, track_id", [("Person", 0.9, 1), ("person", 1.4, 1), ("person", 0.9, -1)])
def test_values_the_schema_refuses_are_refused_at_the_door(cls, confidence, track_id):
    with pytest.raises(ValueError):
        detection_data(cls, confidence, track_id, BBOX)


# -- disk queue ---------------------------------------------------------------

def test_queue_is_oldest_first_and_survives_a_restart(tmp_path):
    q = DiskQueue(tmp_path / "q.sqlite")
    for i in range(3):
        q.put(100.0 + i, {"n": i})
    created = q.created
    q.close()

    q = DiskQueue(tmp_path / "q.sqlite")
    assert len(q) == 3 and q.created == created
    assert [item.data["n"] for item in q.oldest(10)] == [0, 1, 2]
    last = q.oldest(10)[-1].seq
    for item in q.oldest(10):
        q.remove(item.seq)
    assert len(q) == 0
    assert q.put(200.0, {"n": 3}) > last        # a sequence number is never used twice
    q.close()


def test_a_full_queue_drops_the_oldest_and_counts_it(tmp_path):
    q = DiskQueue(tmp_path / "q.sqlite", max_items=3)
    for i in range(5):
        q.put(float(i), {"n": i})
    assert [item.data["n"] for item in q.oldest(10)] == [2, 3, 4]
    assert q.dropped == 2 and len(q) == 3
    q.close()


def test_pictures_are_kept_only_within_their_budget(tmp_path):
    q = DiskQueue(tmp_path / "q.sqlite", max_jpeg_bytes=250)
    for _ in range(3):
        q.put(1.0, {}, JPEG)
    assert [item.jpeg is not None for item in q.oldest(10)] == [True, True, False]
    q.remove(q.oldest(1)[0].seq)                # room again
    q.put(1.0, {}, JPEG)
    assert q.oldest(10)[-1].jpeg is not None
    q.close()


# -- the publisher ------------------------------------------------------------

def test_detections_go_out_in_order_with_qos_1_and_leave_the_queue(make, validator):
    p, client = make()
    for track in (1, 2, 3):
        assert p.publish_detection("person", 0.9, track, BBOX, GEO)
    drain(p)
    sent = client.detections()
    assert [m["data"]["track_id"] for m in sent] == [1, 2, 3]
    assert all(validator.check(m) is None for m in sent)
    assert all(qos == 1 and not retain for t, _, qos, retain in client.sent if t.endswith("/detection"))
    assert len({m["id"] for m in sent}) == 3 and all(m["src"] == "tower-01" for m in sent)
    assert "late" not in sent[0]["data"]
    assert p.queue_len == 0 and p.stats["sent"] == 3


def test_link_down_keeps_detections_then_sends_them_oldest_first(make):
    p, client = make()
    client.acks = False
    for track in (1, 2):
        p.publish_detection("person", 0.9, track, BBOX, GEO)
    drain(p)
    assert p.queue_len == 2 and client.detections() == []

    client.acks = True
    p.publish_detection("person", 0.9, 3, BBOX, GEO)
    drain(p)
    assert [m["data"]["track_id"] for m in client.detections()] == [1, 2, 3]
    assert p.queue_len == 0


def test_the_queue_outlives_the_process(make, tmp_path):
    p, client = make()
    client.acks = False
    p.publish_detection("person", 0.9, 7, BBOX, GEO)
    drain(p)
    p._queue.close()

    p2, client2 = make()                        # same queue file, as after a crash
    drain(p2)
    assert [m["data"]["track_id"] for m in client2.detections()] == [7]


def test_older_than_60_s_is_sent_late_with_its_own_time(make, validator):
    p, client = make()
    made = time.time() - 61
    p.publish_detection("person", 0.9, 1, BBOX, GEO, made_s=made)
    p.publish_detection("person", 0.9, 2, BBOX, GEO)
    drain(p)
    old, fresh = client.detections()
    assert old["data"]["late"] is True and "late" not in fresh["data"]
    assert old["ts"] == pub.iso_utc(made)       # when it was made, not when it was sent
    assert validator.check(old) is None
    assert p.stats["late"] == 1


def test_no_more_than_ten_a_second_are_taken(make):
    p, _ = make()
    taken = [p.publish_detection("person", 0.9, i, BBOX) for i in range(25)]
    assert sum(taken) == 10 and p.stats["rate_limited"] == 15


def test_a_picture_becomes_a_snapshot_id_and_is_uploaded_once(make, validator):
    p, client = make()
    p._uploader = uploader = FakeUploader()
    client.acks = False
    p.publish_detection("person", 0.9, 1, BBOX, GEO, jpeg=JPEG)
    drain(p)                                    # uploaded, but the broker did not take the detection
    client.acks = True
    drain(p)
    (msg,) = client.detections()
    assert msg["data"]["snapshot_id"] == "snap-000001" and uploader.uploads == 1
    assert validator.check(msg) is None


def test_a_failed_upload_never_holds_a_detection_back(make):
    p, client = make()
    p._uploader = uploader = FakeUploader()
    uploader.works = False
    p.publish_detection("person", 0.9, 1, BBOX, GEO, jpeg=JPEG)
    p.publish_detection("person", 0.9, 2, BBOX, GEO, jpeg=JPEG)
    drain(p)
    assert [("snapshot_id" in m["data"]) for m in client.detections()] == [False, False]
    assert uploader.uploads == 1                # the second did not wait on a dead server
    assert p.stats["snapshot_failed"] == 1


def test_a_message_that_fails_the_check_is_dropped_not_stuck(make):
    p, client = make()
    p._queue.put(time.time(), {"class": "person"})          # not a whole detection
    p.publish_detection("person", 0.9, 2, BBOX, GEO)
    drain(p)
    assert [m["data"]["track_id"] for m in client.detections()] == [2]
    assert p.stats["invalid"] == 1 and p.queue_len == 0


def test_status_and_last_will(make, validator):
    p, client = make()
    will_topic, will, qos, retain = client.will
    assert will_topic == "briech/v1/edge/tower-01/status" and qos == 1 and retain
    assert will["data"] == {"state": "offline"} and validator.check(will) is None

    p.set_health(fps=9.8)
    p._send_status(p._state())
    p._queue.put(time.time() - 120, detection_data("person", 0.9, 1, BBOX))    # a backlog from an outage
    p._send_status(p._state())
    p._send_status("offline")
    online, behind, offline = client.statuses()
    assert all(validator.check(m) is None for m in (online, behind, offline))
    assert all(qos == 1 and retain for t, _, qos, retain in client.sent if t.endswith("/status"))
    assert online["data"]["state"] == "online" and online["data"]["fps"] == 9.8
    assert online["data"]["model_version"] == "test-0.1" and online["data"]["model_sha256"] == "ab" * 32
    assert behind["data"]["state"] == "degraded" and behind["data"]["queue_len"] == 1
    assert offline["data"] == {"state": "offline"}
