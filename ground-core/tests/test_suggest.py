from datetime import datetime, timezone

import pytest

from coordinator.geo import move
from coordinator.suggest import SuggestConfig, battery_after, suggest

NOW = datetime(2026, 10, 26, 10, 30, 5, tzinfo=timezone.utc)
SEEN = "2026-10-26T10:30:04.000Z"
TARGET = {"lat": 6.5251, "lon": 3.3801, "error_m": 6.0}
CFG = SuggestConfig()


def vehicle(vid, battery, east_m=500.0, seen=SEEN, can_take_task=True, pos=True):
    lat, lon = move(TARGET["lat"], TARGET["lon"], east_m, 0.0)
    v = {"vehicle_id": vid, "name": f"BRCH-{vid}", "mode": "Hold", "armed": True, "flying": True,
         "battery_pct": battery, "last_seen_ts": seen}
    if pos:
        v["pos"] = {"lat": lat, "lon": lon, "alt_rel_m": 40.0}
    if can_take_task is not None:
        v["can_take_task"] = can_take_task
    return v


def alert():
    return {"alert_id": "a-1", "pos": TARGET}


def test_nearest_capable_drone_is_proposed_with_alternatives():
    proposal = suggest(alert(), [vehicle(1, 90, 2000), vehicle(2, 90, 400), vehicle(3, 90, 900)], NOW)
    assert proposal["vehicle_id"] == 2 and proposal["action"] == "orbit"
    assert proposal["radius_m"] == CFG.orbit_radius_m and proposal["alt_rel_m"] == CFG.orbit_alt_rel_m
    assert [a["vehicle_id"] for a in proposal["alternatives"]] == [3, 1]
    assert proposal["eta_s"] == pytest.approx(400 / CFG.cruise_ms, abs=1)


@pytest.mark.parametrize("battery, distance", [(32, 100), (40, 1500), (31, 0), (60, 7000)])
def test_a_drone_that_would_land_below_the_reserve_is_never_proposed(battery, distance):
    assert battery_after(battery, distance, CFG) < CFG.reserve_pct
    assert suggest(alert(), [vehicle(1, battery, distance)], NOW) is None


def test_reserve_holds_for_every_alternative_too():
    low = vehicle(7, 32, 50)       # close, but would land below the reserve (28.75 %)
    ok = vehicle(8, 95, 3000)
    proposal = suggest(alert(), [low, ok], NOW)
    assert proposal["vehicle_id"] == 8 and "alternatives" not in proposal
    assert proposal["battery_after_pct"] >= CFG.reserve_pct


@pytest.mark.parametrize("v", [
    vehicle(1, None),                                   # battery unknown
    vehicle(1, 90, pos=False),                          # position unknown
    vehicle(1, 90, can_take_task=False),                # QGC says it cannot take a task
    vehicle(1, 90, seen="2026-10-26T10:29:40.000Z"),    # report 25 s old
])
def test_unknown_or_stale_drones_are_never_proposed(v):
    assert suggest(alert(), [v], NOW) is None


def test_can_take_task_left_out_is_not_a_refusal():
    # QGC leaves can_take_task out when the firmware does not report arming checks
    assert suggest(alert(), [vehicle(1, 90, can_take_task=None)], NOW)["vehicle_id"] == 1


def test_proposal_battery_is_a_whole_percent():
    proposal = suggest(alert(), [vehicle(1, 87, 333)], NOW)
    assert isinstance(proposal["battery_after_pct"], int)
