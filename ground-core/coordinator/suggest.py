"""Rule-based suggestions: which drone to send to an alert. Decision support only.

Nothing is sent to a vehicle until a named operator approves in QGC.

A drone is a candidate only when everything needed to judge it is known and
current: a position, a whole battery percentage, a report from QGC no older
than STALE_S, and QGC not saying it cannot take a task. Its battery on landing
is estimated pessimistically as:

    battery now
      - drain per km * (there and back again, 2 x the straight-line distance)
      - drain per minute * the loiter time over the target

vehicle.state carries no home position, so "back again" is the outbound
distance. A drone whose estimate falls below the reserve (30 percent to
start) is never proposed. The rest are ranked by ETA; the first is the
proposal and up to five more are listed as alternatives.

The drain figures are placeholders until battery drain is measured per airframe
(spike S8). Change them in SuggestConfig, never by loosening the reserve check.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from .geo import distance_m
from .schemas import parse_ts


@dataclass(frozen=True)
class SuggestConfig:
    reserve_pct: float = 30.0
    cruise_ms: float = 8.0
    drain_pct_per_km: float = 2.5
    loiter_s: float = 120.0
    drain_pct_per_min: float = 1.5
    stale_s: float = 10.0
    action: str = "orbit"
    orbit_radius_m: float = 40.0
    orbit_alt_rel_m: float = 60.0
    max_alternatives: int = 5


def battery_after(battery_pct: float, distance_to_target_m: float, cfg: SuggestConfig) -> float:
    """Estimated battery percent on landing after flying out, loitering and flying back."""
    travel_km = 2.0 * distance_to_target_m / 1000.0
    return battery_pct - cfg.drain_pct_per_km * travel_km - cfg.drain_pct_per_min * cfg.loiter_s / 60.0


def candidates(target: dict, vehicles: list[dict], now: datetime, cfg: SuggestConfig) -> list[dict]:
    """Every vehicle that may be proposed, nearest ETA first."""
    out = []
    for v in vehicles:
        pos, battery, seen = v.get("pos"), v.get("battery_pct"), v.get("last_seen_ts")
        if not pos or battery is None or seen is None:
            continue
        if v.get("can_take_task") is False:
            continue
        if (now - parse_ts(seen)).total_seconds() > cfg.stale_s:
            continue
        distance = distance_m(pos["lat"], pos["lon"], target["lat"], target["lon"])
        after = battery_after(float(battery), distance, cfg)
        if after < cfg.reserve_pct:
            continue
        out.append({"vehicle_id": v["vehicle_id"], "eta_s": round(distance / cfg.cruise_ms, 1),
                    "battery_after_pct": max(0, min(100, int(after)))})
    out.sort(key=lambda c: (c["eta_s"], c["vehicle_id"]))
    return out


def suggest(alert: dict, vehicles: list[dict], now: datetime, cfg: SuggestConfig | None = None) -> dict | None:
    """The proposal for alert, or None when no drone may safely go."""
    cfg = cfg or SuggestConfig()
    ranked = candidates(alert["pos"], vehicles, now, cfg)
    if not ranked:
        return None
    best, rest = ranked[0], ranked[1:1 + cfg.max_alternatives]
    proposal = {"vehicle_id": best["vehicle_id"], "action": cfg.action, "eta_s": best["eta_s"],
                "battery_after_pct": best["battery_after_pct"]}
    if cfg.action == "orbit":
        proposal["radius_m"] = cfg.orbit_radius_m
        proposal["alt_rel_m"] = cfg.orbit_alt_rel_m
    if rest:
        proposal["alternatives"] = rest
    return proposal
