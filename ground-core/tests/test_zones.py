import pytest

from coordinator.config import GROUND_CORE_DIR
from coordinator.zones import Zone, load_zones, zones_containing

SQUARE = ((6.5250, 3.3800), (6.5250, 3.3810), (6.5260, 3.3810), (6.5260, 3.3800))


def test_point_in_polygon():
    zone = Zone("north-fence", "North fence", "high", SQUARE)
    assert zone.contains(6.5255, 3.3805)
    assert not zone.contains(6.5265, 3.3805)
    assert not zone.contains(6.5255, 3.3795)


def test_classes_filter():
    zone = Zone("gate", "Gate", "medium", SQUARE, frozenset({"vehicle"}))
    assert zones_containing([zone], 6.5255, 3.3805, "vehicle") == [zone]
    assert zones_containing([zone], 6.5255, 3.3805, "person") == []


def test_shipped_zones_file_loads():
    zones = load_zones(GROUND_CORE_DIR / "config" / "zones.yaml")
    assert zones and all(z.severity in ("low", "medium", "high") for z in zones)


def test_missing_file_means_no_zones(tmp_path):
    assert load_zones(tmp_path / "none.yaml") == []


@pytest.mark.parametrize("body", [
    "zones:\n  - id: Bad Id\n    polygon: [[0,0],[0,1],[1,1]]\n",
    "zones:\n  - id: a\n    polygon: [[0,0],[0,1]]\n",
    "zones:\n  - id: a\n    severity: extreme\n    polygon: [[0,0],[0,1],[1,1]]\n",
    "zones:\n  - id: a\n    polygon: [[0,0],[0,1],[1,1]]\n  - id: a\n    polygon: [[0,0],[0,1],[1,1]]\n",
])
def test_bad_zone_files_are_refused(tmp_path, body):
    path = tmp_path / "zones.yaml"
    path.write_text(body)
    with pytest.raises(ValueError):
        load_zones(path)
