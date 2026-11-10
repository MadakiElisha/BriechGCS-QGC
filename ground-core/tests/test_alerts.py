from datetime import datetime, timedelta, timezone

from coordinator.alerts import Alerts
from coordinator.zones import Zone

T0 = datetime(2026, 10, 26, 10, 30, 5, tzinfo=timezone.utc)
ZONE = Zone("north-fence", "north-fence", "high", ((6.5250, 3.3800), (6.5250, 3.3810), (6.5260, 3.3810), (6.5260, 3.3800)))


def obj(object_id="o-tower-01-17", lat=6.5255, lon=3.3805, status="active", cls="person"):
    return {"object_id": object_id, "class": cls, "confidence": 0.9,
            "pos": {"lat": lat, "lon": lon, "error_m": 6.0}, "seen_by": ["tower-01"],
            "last_seen_ts": "2026-10-26T10:30:05.400Z", "status": status}


def test_track_inside_zone_raises_one_alert_not_one_per_sighting():
    alerts = Alerts([ZONE])
    (event,) = alerts.on_object(obj(), T0)
    assert event[0] == "alert.new"
    alert = event[1]
    assert alert["severity"] == "high" and alert["zone_id"] == "north-fence" and alert["status"] == "open"
    assert alert["reason"] == "Person inside zone north-fence"
    for i in range(20):
        assert alerts.on_object(obj(lat=6.5255 + i * 1e-6), T0 + timedelta(seconds=i)) == []
    assert len(alerts.alerts()) == 1


def test_outside_lost_and_late_raise_nothing():
    alerts = Alerts([ZONE])
    assert alerts.on_object(obj(lat=6.5270), T0) == []
    assert alerts.on_object(obj(status="lost"), T0) == []
    assert alerts.on_object(obj(), T0, late=True) == []


def test_decision_updates_status_once():
    alerts = Alerts([ZONE])
    (_, alert) = alerts.on_object(obj(), T0)[0]
    action = {"alert_id": alert["alert_id"], "decision": "approve", "operator_id": "op-001", "phase": "decision"}
    (event,) = alerts.on_decision(action)
    assert event == ("alert.update", {"alert_id": alert["alert_id"], "status": "approved", "operator_id": "op-001"})
    assert alerts.on_decision(action) == []            # already decided
    assert alerts.on_decision(dict(action, alert_id="a-unknown")) == []


def test_unanswered_alert_expires_and_a_new_entry_alerts_again():
    alerts = Alerts([ZONE], expire_after_s=120)
    (_, alert) = alerts.on_object(obj(), T0)[0]
    assert alerts.expire(T0 + timedelta(seconds=60)) == []
    (event,) = alerts.expire(T0 + timedelta(seconds=121))
    assert event == ("alert.update", {"alert_id": alert["alert_id"], "status": "expired"})
    # the same track still in the zone after its alert expired raises a new one
    (again,) = alerts.on_object(obj(), T0 + timedelta(seconds=130))
    assert again[1]["alert_id"] != alert["alert_id"]


def test_rejected_alert_does_not_expire():
    alerts = Alerts([ZONE], expire_after_s=1)
    (_, alert) = alerts.on_object(obj(), T0)[0]
    alerts.on_decision({"alert_id": alert["alert_id"], "decision": "reject", "operator_id": "op-001"})
    assert alerts.expire(T0 + timedelta(seconds=5)) == []
    assert alerts.get(alert["alert_id"])["status"] == "rejected"


def test_proposal_attached_from_suggest():
    alerts = Alerts([ZONE], suggest=lambda a: {"vehicle_id": 3, "action": "orbit"})
    (_, alert) = alerts.on_object(obj(), T0)[0]
    assert alert["proposal"] == {"vehicle_id": 3, "action": "orbit"}


def test_cap_drops_closed_alerts_first():
    alerts = Alerts([ZONE], max_alerts=3)
    first = alerts.on_object(obj("o-1"), T0)[0][1]
    alerts.on_decision({"alert_id": first["alert_id"], "decision": "reject", "operator_id": "op-001"})
    for i in range(2, 5):
        alerts.on_object(obj(f"o-{i}"), T0)
    ids = [a["object_id"] for a in alerts.alerts()]
    assert "o-1" not in ids and len(ids) == 3 and alerts.dropped == 1


def test_alerts_pass_the_schema(validator):
    alerts = Alerts([ZONE], suggest=lambda a: {"vehicle_id": 3, "action": "orbit", "radius_m": 40.0})
    (_, alert) = alerts.on_object(obj(), T0)[0]
    msg = {"v": 1, "type": "alert.new", "id": "t-1", "ts": "2026-10-26T10:30:06.000Z", "src": "coordinator",
           "data": alert}
    assert validator.check(msg) is None


def test_state_round_trip():
    alerts = Alerts([ZONE])
    alerts.on_object(obj(), T0)
    restored = Alerts([ZONE])
    restored.load_state(alerts.to_state())
    assert restored.alerts() == alerts.alerts()
    assert restored.on_object(obj(), T0) == []         # still one alert for that track


# Approved alerts end once the person has gone, so a return raises a new alert

OUTSIDE = 6.5270


def approved(alerts):
    (_, alert) = alerts.on_object(obj(), T0)[0]
    alerts.on_decision({"alert_id": alert["alert_id"], "decision": "approve", "operator_id": "op-001",
                        "phase": "decision"})
    return alert["alert_id"]


def test_approved_alert_resolves_after_thirty_seconds_outside_then_a_return_alerts_again():
    alerts = Alerts([ZONE])
    alert_id = approved(alerts)
    assert alerts.on_object(obj(lat=OUTSIDE), T0 + timedelta(seconds=10)) == []      # just left
    assert alerts.on_object(obj(lat=OUTSIDE), T0 + timedelta(seconds=39)) == []      # 29 s outside
    (event,) = alerts.on_object(obj(lat=OUTSIDE), T0 + timedelta(seconds=40))         # 30 s outside
    assert event == ("alert.update", {"alert_id": alert_id, "status": "resolved"})
    (event,) = alerts.on_object(obj(), T0 + timedelta(seconds=60))                    # back inside
    assert event[0] == "alert.new" and event[1]["alert_id"] != alert_id


def test_stepping_back_inside_restarts_the_wait():
    alerts = Alerts([ZONE])
    approved(alerts)
    alerts.on_object(obj(lat=OUTSIDE), T0 + timedelta(seconds=1))
    assert alerts.on_object(obj(), T0 + timedelta(seconds=20)) == []                  # inside: no new alert
    assert alerts.on_object(obj(lat=OUTSIDE), T0 + timedelta(seconds=21)) == []
    assert alerts.on_object(obj(lat=OUTSIDE), T0 + timedelta(seconds=50)) == []       # 29 s since it left again
    assert alerts.on_object(obj(lat=OUTSIDE), T0 + timedelta(seconds=51))[0][1]["status"] == "resolved"


def test_lost_track_resolves_its_approved_alert_but_not_an_open_one():
    alerts = Alerts([ZONE])
    alert_id = approved(alerts)
    alerts.on_object(obj(object_id="o-2"), T0)                                        # open, unanswered
    events = alerts.on_object(obj(status="lost"), T0 + timedelta(seconds=11))
    assert events == [("alert.update", {"alert_id": alert_id, "status": "resolved"})]
    assert alerts.on_object(obj(object_id="o-2", status="lost"), T0) == []            # open ones expire instead


def test_restart_resolves_approved_alerts_whose_object_is_gone():
    alerts = Alerts([ZONE])
    alert_id = approved(alerts)
    restored = Alerts([ZONE])
    restored.load_state(alerts.to_state())
    assert restored.resolve_missing({"o-tower-01-17"}) == []
    assert restored.resolve_missing(set()) == [("alert.update", {"alert_id": alert_id, "status": "resolved"})]


def test_resolved_update_passes_the_schema(validator):
    alerts = Alerts([ZONE])
    approved(alerts)
    (_, data) = alerts.on_object(obj(status="removed"), T0)[0]
    msg = {"v": 1, "type": "alert.update", "id": "m-1", "ts": "2026-10-26T10:30:05.400Z", "src": "coordinator",
           "data": data}
    assert validator.check(msg) is None
