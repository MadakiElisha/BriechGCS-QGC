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
    assert obj["pos"]["lat"] == 6.5252 and obj["snapshot_id"] == "snap-8f3a2c"
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
