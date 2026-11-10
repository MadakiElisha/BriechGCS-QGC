"""Scenario replays: the fake publisher's own messages, driven through the
coordinator in simulated time, with no broker. These are the row checks from
the handoff, run on every push."""

from datetime import datetime, timedelta, timezone

import fake_fleet
from conftest import REPO_DIR
from coordinator.app import Coordinator
from coordinator.config import GROUND_CORE_DIR
from coordinator.fusion import Fusion
from coordinator.zones import load_zones

SCENARIOS = REPO_DIR / "sim" / "scenarios"
T0 = datetime(2026, 10, 26, 10, 30, 0, tzinfo=timezone.utc)


class Clock:
    def __init__(self):
        self.t = 0.0

    def mono(self):
        return self.t

    def wall(self):
        return T0 + timedelta(seconds=self.t)


class FakeClient:
    def __init__(self):
        self.sent = []

    def push(self, text):
        import json
        self.sent.append(json.loads(text))


def at(msg, clock):
    msg["ts"] = clock.wall().isoformat(timespec="milliseconds").replace("+00:00", "Z")
    return msg


def make(config, validator, registry, clock):
    coord = Coordinator(config, validator, registry, Fusion(), zones=load_zones(GROUND_CORE_DIR / "config" / "zones.yaml"),
                        clock=clock.mono, wall_clock=clock.wall)
    client = FakeClient()
    coord.clients.add(client)
    return coord, client


def replay(coord, clock, scenarios, seconds, step=0.5):
    """Each scenario's objects, one sighting every step seconds, ticking the coordinator in between."""
    seq = 0
    t = 0.0
    while t <= seconds:
        clock.t = t
        for scenario in scenarios:
            for obj in scenario["objects"]:
                if obj.get("start_s", 0) <= t <= obj.get("stop_s", 1e9):
                    seq += 1
                    msg = at(fake_fleet.detection(scenario["source"], seq, obj, t - obj.get("start_s", 0)), clock)
                    assert coord.validator.check(msg) is None
                    coord.on_bus_message(msg)
        coord.tick()
        t += step


def test_walk_into_zone_raises_one_alert_within_a_second(config, validator, registry):
    clock = Clock()
    coord, client = make(config, validator, registry, clock)
    scenario = fake_fleet.load_scenario(SCENARIOS / "tower-walk.yaml")
    person = next(o for o in scenario["objects"] if o["track_id"] == 17)
    zone = coord.alerts.zones[0]

    # When does track 17 first stand inside the zone?
    entered = next(t / 10 for t in range(0, 1200) if zone.contains(*fake_fleet.object_position(person, t / 10)))
    raised_at = []
    pushed = client.push
    client.push = lambda text: (raised_at.append(clock.t) if '"alert.new"' in text else None, pushed(text))
    replay(coord, clock, [scenario], seconds=entered + 30)

    news = [m for m in client.sent if m["type"] == "alert.new"]
    assert len(news) == 1, "one alert, not one per sighting"
    assert raised_at[0] - entered <= 1.0, (entered, raised_at[0])     # simulated seconds
    assert news[0]["data"]["zone_id"] == "north-fence"
    assert all(validator.check(m) is None for m in client.sent)


def test_two_towers_one_person_one_object(config, validator, registry):
    clock = Clock()
    coord, client = make(config, validator, registry, clock)
    walk = fake_fleet.load_scenario(SCENARIOS / "tower-walk.yaml")
    walk["objects"] = [o for o in walk["objects"] if o["track_id"] == 17]
    second = fake_fleet.load_scenario(SCENARIOS / "two-towers.yaml")
    replay(coord, clock, [walk, second], seconds=10)

    objects = coord.fusion.objects()
    assert len(objects) == 1
    assert objects[0]["seen_by"] == ["tower-01", "tower-02"]


def test_object_updates_never_exceed_two_per_second(config, validator, registry):
    clock = Clock()
    coord, client = make(config, validator, registry, clock)
    walk = fake_fleet.load_scenario(SCENARIOS / "tower-walk.yaml")
    walk["objects"] = [o for o in walk["objects"] if o["track_id"] == 17]
    sent_at = []
    client.push = lambda text: sent_at.append(clock.t) if '"object.update"' in text else None
    replay(coord, clock, [walk], seconds=20, step=0.1)     # 10 sightings a second

    assert len(sent_at) >= 35, "updates kept flowing at about 2 per second"
    for i in range(2, len(sent_at)):    # never three updates inside one second
        assert sent_at[i] - sent_at[i - 2] >= 1.0 - 1e-9, sent_at[i - 2:i + 1]
    assert coord.counters["drop_rate_object"] > 100     # the replaced ones are counted


def test_restart_keeps_tracks_and_alerts(config, validator, registry, tmp_path):
    from coordinator.registry import Registry
    from coordinator.store import StateStore
    clock = Clock()
    store = StateStore(tmp_path / "state.sqlite")
    coord = Coordinator(config, validator, registry, Fusion(), zones=load_zones(GROUND_CORE_DIR / "config" / "zones.yaml"),
                        store=store, clock=clock.mono, wall_clock=clock.wall)
    walk = fake_fleet.load_scenario(SCENARIOS / "tower-walk.yaml")
    replay(coord, clock, [walk], seconds=40)
    coord.save()
    before_objects, before_alerts = coord.fusion.objects(), coord.alerts.alerts()
    assert before_objects and before_alerts
    store.close()

    store = StateStore(tmp_path / "state.sqlite")
    restarted = Coordinator(config, validator, Registry.from_file(registry_path()), Fusion(),
                            zones=load_zones(GROUND_CORE_DIR / "config" / "zones.yaml"), store=store,
                            clock=clock.mono, wall_clock=clock.wall)
    assert restarted.fusion.objects() == before_objects
    assert restarted.alerts.alerts() == before_alerts
    assert validator.check(restarted.snapshot()) is None
    store.close()


def registry_path():
    return GROUND_CORE_DIR / "config" / "assets.yaml"
