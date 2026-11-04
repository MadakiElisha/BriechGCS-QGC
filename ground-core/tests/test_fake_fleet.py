"""The fake publisher is held to the same schemas as a real device."""

from conftest import REPO_DIR

import fake_fleet

SCENARIO = fake_fleet.load_scenario(REPO_DIR / "sim" / "scenarios" / "tower-walk.yaml")


def test_every_message_kind_is_valid(validator):
    src = SCENARIO["source"]
    msgs = [
        fake_fleet.edge_status(src, 1, "online", SCENARIO, 12.0),
        fake_fleet.edge_status(src, 2, "offline", SCENARIO, 0),
        fake_fleet.asset_state(src, 3, SCENARIO),
    ] + [fake_fleet.detection(src, 4 + i, obj, t) for i, obj in enumerate(SCENARIO["objects"]) for t in (0, 30, 600)]
    for msg in msgs:
        assert validator.check(msg) is None, validator.check(msg)


def test_object_moves_at_its_velocity():
    obj = {"track_id": 1, "start": {"lat": 6.5, "lon": 3.3}, "velocity": {"north_ms": 10.0, "east_ms": 0.0}}
    lat, lon = fake_fleet.object_position(obj, 11.132)
    assert abs(lat - (6.5 + 0.001)) < 1e-6 and lon == 3.3


def test_topics_match_what_the_bus_accepts():
    from coordinator.bus import topic_type
    src = SCENARIO["source"]
    assert topic_type(fake_fleet.topic("edge", src, "detection")) == ("detection", src)
    assert topic_type(fake_fleet.topic("edge", src, "status")) == ("edge.status", src)
    assert topic_type(fake_fleet.topic("asset", src, "state")) == ("asset.state", src)
