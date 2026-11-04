import pytest

from coordinator.registry import load_assets
from conftest import example


def test_assets_yaml_loads(registry):
    (tower,) = registry.assets()
    assert tower["asset_id"] == "tower-01" and tower["kind"] == "tower" and tower["link"] == "unknown"


def test_duplicate_asset_rejected(tmp_path):
    path = tmp_path / "assets.yaml"
    path.write_text("assets:\n  - {id: t, kind: tower}\n  - {id: t, kind: tower}\n")
    with pytest.raises(ValueError):
        load_assets(path)


def test_asset_state_merges_device_fields_only(registry):
    msg = example("asset.state.valid")
    msg["data"]["kind"] = "drone"  # a device does not get to change what the asset is
    asset = registry.apply_asset_state(msg)
    assert asset["health"] == "ok" and asset["camera_heading_deg"] == 42.0
    assert asset["kind"] == "tower" and asset["last_seen_ts"] == msg["ts"]


def test_unknown_asset(registry):
    msg = example("asset.state.valid")
    msg["data"]["asset_id"] = msg["src"] = "tower-99"
    assert registry.apply_asset_state(msg) is None


def test_edge_status_reports_link_changes_once(registry):
    online = example("edge.status.valid")
    assert registry.apply_edge_status(online)["link"] == "online"
    assert registry.apply_edge_status(online) is None
    assert registry.apply_edge_status(example("edge.status.valid.offline"))["link"] == "offline"


def test_detection_source_last_seen(registry):
    registry.touch("edge-77", "2026-10-26T10:30:05.400Z")
    assert registry.source_last_seen["edge-77"] == "2026-10-26T10:30:05.400Z"


def test_vehicles_keep_latest_report(registry):
    msg = example("vehicle.state.valid")
    registry.apply_vehicle_state(msg)
    msg["data"]["vehicles"][0]["battery_pct"] = 70
    msg["ts"] = "2026-10-26T10:30:06.400Z"
    registry.apply_vehicle_state(msg)
    (vehicle,) = registry.vehicles()
    assert vehicle["battery_pct"] == 70 and vehicle["last_seen_ts"] == "2026-10-26T10:30:06.400Z"


def test_last_seen_never_goes_back(registry):
    registry.touch("tower-01", "2026-10-26T10:30:05.400Z")
    registry.touch("tower-01", "2026-10-26T10:29:00.000Z")  # e.g. a last will made at connect time
    registry.touch("tower-01", "2026-10-26T10:30:05.3Z")    # same second, one digit, still earlier
    assert registry.assets()[0]["last_seen_ts"] == "2026-10-26T10:30:05.400Z"
    assert registry.source_last_seen["tower-01"] == "2026-10-26T10:30:05.400Z"
