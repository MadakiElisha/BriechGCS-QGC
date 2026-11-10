import json

from conftest import example


class FakeClient:
    def __init__(self):
        self.sent = []

    def push(self, text):
        self.sent.append(json.loads(text))


def _connect(coordinator):
    client = FakeClient()
    coordinator.clients.add(client)
    return client


def test_detection_broadcasts_valid_object_update(coordinator, validator):
    client = _connect(coordinator)
    coordinator.on_bus_message(example("detection.valid"))
    (msg,) = client.sent
    assert msg["type"] == "object.update" and msg["src"] == "coordinator"
    assert validator.check(msg) is None


def test_detection_without_geo_counted(coordinator):
    client = _connect(coordinator)
    coordinator.on_bus_message(example("detection.valid.no-geo"))
    assert client.sent == [] and coordinator.counters["detection_no_geo"] == 1


def test_asset_state_forwarded_with_coordinator_fields(coordinator, validator):
    client = _connect(coordinator)
    coordinator.on_bus_message(example("asset.state.valid"))
    (msg,) = client.sent
    assert msg["type"] == "asset.state" and msg["data"]["name"] == "Tower 01 (pilot)"
    assert validator.check(msg) is None


def test_unknown_asset_dropped(coordinator):
    msg = example("asset.state.valid")
    msg["src"] = msg["data"]["asset_id"] = "tower-99"
    coordinator.on_bus_message(msg)
    assert coordinator.counters["drop_unknown_asset"] == 1


def test_last_will_marks_asset_offline(coordinator):
    client = _connect(coordinator)
    coordinator.on_bus_message(example("edge.status.valid"))
    coordinator.on_bus_message(example("edge.status.valid"))  # no change, no message
    coordinator.on_bus_message(example("edge.status.valid.offline"))
    assert [m["data"]["link"] for m in client.sent] == ["online", "offline"]


def test_snapshot_is_valid_and_complete(coordinator, validator):
    coordinator.on_bus_message(example("detection.valid"))
    coordinator.on_operator_message(None, example("vehicle.state.valid"))
    snap = coordinator.snapshot()
    assert validator.check(snap) is None
    assert [len(snap["data"][k]) for k in ("assets", "vehicles", "objects", "alerts")] == [1, 1, 1, 0]


def test_heartbeat_is_valid_and_carries_counters(coordinator, validator):
    coordinator.counters["drop_schema"] = 3
    msg = coordinator.make_message("heartbeat", coordinator.heartbeat_data())
    assert validator.check(msg) is None
    assert msg["data"]["seq"] == 1 and msg["data"]["counters"]["drop_schema"] == 3


def test_invalid_outgoing_message_is_not_sent(coordinator):
    client = _connect(coordinator)
    coordinator.broadcast("object.update", {"object_id": "o-1"})
    assert client.sent == [] and coordinator.counters["drop_outgoing"] == 1


def test_operator_actions_kept(coordinator):
    coordinator.on_operator_message(None, example("operator.action.valid"))
    assert coordinator.operator_actions[-1]["data"]["decision"] == "approve"


# Rows 2, 5 and 7: silence, alerts and the audit log, through the coordinator

from datetime import datetime, timedelta, timezone

from conftest import detection
from coordinator.app import Coordinator
from coordinator.audit import AuditLog
from coordinator.fusion import Fusion
from coordinator.zones import Zone

T0 = datetime(2026, 10, 26, 10, 30, 5, 400000, tzinfo=timezone.utc)
ZONE = Zone("north-fence", "north-fence", "high",
            ((6.5250, 3.3800), (6.5250, 3.3810), (6.5260, 3.3810), (6.5260, 3.3800)))


class Clock:
    def __init__(self):
        self.t = 0.0

    def mono(self):
        return self.t

    def wall(self):
        return T0 + timedelta(seconds=self.t)


def _coordinator(config, validator, registry, **kw):
    clock = Clock()
    coord = Coordinator(config, validator, registry, Fusion(), clock=clock.mono, wall_clock=clock.wall, **kw)
    return coord, clock, _connect(coord)


def test_silent_tower_goes_offline_and_comes_back(config, validator, registry):
    coord, clock, client = _coordinator(config, validator, registry)
    coord.on_bus_message(example("asset.state.valid"))          # heard at 10:30:05.400
    client.sent.clear()
    clock.t = 10.0
    coord.tick()
    assert client.sent == []                                    # 10 s of silence: still fine
    clock.t = 16.0
    coord.tick()
    (msg,) = client.sent
    assert msg["type"] == "asset.state" and msg["data"]["link"] == "offline"
    assert validator.check(msg) is None
    client.sent.clear()
    later = example("asset.state.valid")
    later["ts"] = "2026-10-26T10:30:22.000Z"
    coord.on_bus_message(later)
    assert client.sent[-1]["data"]["link"] == "online"


def test_detection_in_zone_raises_alert_and_decision_updates_it(config, validator, registry, tmp_path):
    audit = AuditLog(tmp_path / "audit.sqlite")
    coord, clock, client = _coordinator(config, validator, registry, zones=[ZONE], audit=audit)
    coord.on_bus_message(detection(lat=6.5255, lon=3.3805))
    types = [m["type"] for m in client.sent]
    assert types == ["object.update", "alert.new"]
    alert = client.sent[1]["data"]
    assert all(validator.check(m) is None for m in client.sent)

    action = example("operator.action.valid")
    action["data"]["alert_id"] = alert["alert_id"]
    coord.on_operator_message(None, action)
    update = client.sent[-1]
    assert update["type"] == "alert.update" and update["data"]["status"] == "approved"
    assert coord.snapshot()["data"]["alerts"][0]["status"] == "approved"

    kinds = [e["kind"] for e in audit.entries()]
    assert kinds == ["alert.new", "operator.action", "alert.update"]
    assert audit.verify()["ok"]
    audit.close()


def test_late_detection_raises_no_alert(config, validator, registry):
    coord, clock, client = _coordinator(config, validator, registry, zones=[ZONE])
    coord.on_bus_message(detection(lat=6.5255, lon=3.3805, late=True))
    assert [m["type"] for m in client.sent] == ["object.update"]
    assert coord.counters["detection_late"] == 1


def test_alert_carries_a_safe_proposal(config, validator, registry):
    coord, clock, client = _coordinator(config, validator, registry, zones=[ZONE])
    report = example("vehicle.state.valid")
    v = report["data"]["vehicles"][0]
    v["pos"]["lat"], v["pos"]["lon"] = 6.5240, 3.3790       # about 200 m away
    report["ts"] = "2026-10-26T10:30:05.000Z"
    coord.on_operator_message(None, report)
    coord.on_bus_message(detection(lat=6.5255, lon=3.3805))
    alert = client.sent[-1]["data"]
    assert alert["proposal"]["vehicle_id"] == v["vehicle_id"]
    assert alert["proposal"]["battery_after_pct"] >= coord.suggest_config.reserve_pct
    assert validator.check(client.sent[-1]) is None


def test_silent_track_reported_lost_then_removed(config, validator, registry):
    coord, clock, client = _coordinator(config, validator, registry)
    coord.on_bus_message(detection())
    clock.t = 11.0
    coord.tick()
    assert client.sent[-1]["data"]["status"] == "lost"
    clock.t = 62.0
    coord.tick()
    updates = [m for m in client.sent if m["type"] == "object.update"]
    assert updates[-1]["data"]["status"] == "removed"
    assert coord.fusion.objects() == []
    # the tower that sent it has been silent too, and says so
    assert client.sent[-1]["type"] == "asset.state" and client.sent[-1]["data"]["link"] == "offline"
