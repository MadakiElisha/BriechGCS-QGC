from coordinator.fusion import Fusion
from conftest import example


def test_detection_becomes_object():
    fusion = Fusion()
    obj = fusion.ingest(example("detection.valid"))
    assert obj["object_id"] == "o-tower-01-17"
    assert obj["pos"] == {"lat": 6.5251, "lon": 3.3801, "error_m": 6.0}
    assert obj["seen_by"] == ["tower-01"] and obj["snapshot_id"] == "snap-8f3a2c"


def test_same_track_updates_same_object_and_keeps_snapshot():
    fusion = Fusion()
    fusion.ingest(example("detection.valid"))
    later = example("detection.valid")
    later["data"]["geo"]["lat"] = 6.5252
    del later["data"]["snapshot_id"]
    obj = fusion.ingest(later)
    # The filter weights the track and the new sighting by their errors (6 m each
    # here, at the same instant), so the position moves halfway, not all the way.
    assert 6.5251 < obj["pos"]["lat"] < 6.5252 and obj["snapshot_id"] == "snap-8f3a2c"
    assert obj["pos"]["error_m"] < 6.0
    assert len(fusion.objects()) == 1


def test_no_geo_no_object():
    assert Fusion().ingest(example("detection.valid.no-geo")) is None


def test_cap_drops_oldest():
    fusion = Fusion(max_objects=3)
    for track in range(5):
        msg = example("detection.valid")
        msg["data"]["track_id"] = track
        fusion.ingest(msg)
    assert [o["object_id"] for o in fusion.objects()] == ["o-tower-01-2", "o-tower-01-3", "o-tower-01-4"]
    assert fusion.dropped == 2


# Row 4: tracks with a constant-velocity filter and gating

from datetime import datetime, timedelta, timezone

from conftest import detection
from coordinator.geo import distance_m, move

T0 = datetime(2026, 10, 26, 10, 30, 5, tzinfo=timezone.utc)


def ts(seconds: float) -> str:
    return (T0 + timedelta(seconds=seconds)).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def test_two_towers_seeing_one_person_make_one_object():
    fusion = Fusion()
    fusion.ingest(detection("tower-01", 17, 6.52510, 3.38010, 6.0, ts(0)))
    # tower-02 sees the same person 4 m away (well inside both errors)
    lat, lon = move(6.52510, 3.38010, 3.0, 2.6)
    obj = fusion.ingest(detection("tower-02", 4, lat, lon, 8.0, ts(0.2)))
    assert len(fusion.objects()) == 1
    assert obj["object_id"] == "o-tower-01-17"
    assert obj["seen_by"] == ["tower-01", "tower-02"]
    assert fusion.merged == 1
    # tower-02's next sighting of its track 4 goes straight to the same object
    obj = fusion.ingest(detection("tower-02", 4, lat, lon, 8.0, ts(0.7)))
    assert obj["object_id"] == "o-tower-01-17" and len(fusion.objects()) == 1


def test_far_apart_sightings_stay_separate():
    fusion = Fusion()
    fusion.ingest(detection("tower-01", 1, 6.52510, 3.38010, 6.0, ts(0)))
    lat, lon = move(6.52510, 3.38010, 80.0, 0.0)   # 80 m east: outside the gate
    fusion.ingest(detection("tower-02", 1, lat, lon, 6.0, ts(0)))
    assert len(fusion.objects()) == 2


def test_a_camera_never_merges_its_own_two_tracks():
    fusion = Fusion()
    fusion.ingest(detection("tower-01", 1, 6.52510, 3.38010, 6.0, ts(0)))
    fusion.ingest(detection("tower-01", 2, 6.52511, 3.38010, 6.0, ts(0)))  # 1 m away, but its tracker says two people
    assert len(fusion.objects()) == 2


def test_different_classes_never_merge():
    fusion = Fusion()
    fusion.ingest(detection("tower-01", 1, cls="person", ts=ts(0)))
    fusion.ingest(detection("tower-02", 1, cls="vehicle", ts=ts(0)))
    assert len(fusion.objects()) == 2


def test_velocity_follows_a_walking_person_and_the_gate_tracks_the_prediction():
    fusion = Fusion()
    lat, lon = 6.52510, 3.38010
    for i in range(20):     # 1.5 m/s east for 10 s, one sighting every 0.5 s
        p_lat, p_lon = move(lat, lon, 1.5 * i * 0.5, 0.0)
        obj = fusion.ingest(detection("tower-01", 7, p_lat, p_lon, 3.0, ts(i * 0.5)))
    assert 0.8 < obj["velocity"]["east_ms"] < 2.2
    assert abs(obj["velocity"]["north_ms"]) < 0.5
    # tower-02 picks the person up 3 s later where the prediction says they will be,
    # 4.5 m beyond the last sighting: it joins the walking track
    p_lat, p_lon = move(lat, lon, 1.5 * 12.5, 0.0)
    joined = fusion.ingest(detection("tower-02", 9, p_lat, p_lon, 5.0, ts(12.5)))
    assert joined["object_id"] == obj["object_id"] and len(fusion.objects()) == 1


def test_an_older_sighting_adds_a_camera_but_never_moves_the_track():
    fusion = Fusion()
    first = fusion.ingest(detection("tower-01", 1, 6.52510, 3.38010, 6.0, ts(5)))
    lat, lon = move(6.52510, 3.38010, 5.0, 0.0)
    obj = fusion.ingest(detection("tower-02", 1, lat, lon, 6.0, ts(1)))  # arrives late, from before
    assert obj["pos"] == first["pos"] and obj["seen_by"] == ["tower-01", "tower-02"]


def test_silent_tracks_go_lost_then_removed():
    fusion = Fusion()
    fusion.ingest(detection(ts=ts(0)))
    assert fusion.expire(T0 + timedelta(seconds=5)) == []
    (lost,) = fusion.expire(T0 + timedelta(seconds=11))
    assert lost["status"] == "lost"
    assert fusion.expire(T0 + timedelta(seconds=30)) == []     # reported once
    (removed,) = fusion.expire(T0 + timedelta(seconds=61))
    assert removed["status"] == "removed" and fusion.objects() == []
    # a new sighting with the old edge id starts a fresh object
    assert fusion.ingest(detection(ts=ts(62)))["status"] == "active"


def test_state_round_trip():
    fusion = Fusion()
    fusion.ingest(detection("tower-01", 1, ts=ts(0)))
    fusion.ingest(detection("tower-02", 3, ts=ts(0.1)))
    restored = Fusion()
    restored.load_state(fusion.to_state())
    assert restored.objects() == fusion.objects()
    # the link (tower-02, 3) survived, so its next sighting updates, not duplicates
    restored.ingest(detection("tower-02", 3, ts=ts(1)))
    assert len(restored.objects()) == 1


def test_objects_from_fusion_pass_the_schema(validator):
    fusion = Fusion()
    fusion.ingest(detection(ts=ts(0)))
    obj = fusion.ingest(detection("tower-02", 2, ts=ts(0.5)))
    msg = {"v": 1, "type": "object.update", "id": "t-1", "ts": ts(1), "src": "coordinator", "data": obj}
    assert validator.check(msg) is None
