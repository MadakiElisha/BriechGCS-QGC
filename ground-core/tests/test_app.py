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
