"""Watch zones from config/zones.yaml (read-only in the first release).

A watch zone raises an alert in the coordinator. It is not a geofence: a
geofence is set on the autopilot and enforced by the vehicle, coordinator or not.

    zones:
      - id: north-fence
        name: North fence
        severity: high                 # low, medium or high
        classes: [person, vehicle]     # optional; every class when left out
        polygon:                       # [lat, lon] corners, WGS84 degrees, at least 3
          - [6.5250, 3.3800]
          - ...
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import yaml

from .geo import inside_polygon

_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
SEVERITIES = ("low", "medium", "high")


@dataclass(frozen=True)
class Zone:
    zone_id: str
    name: str
    severity: str
    polygon: tuple[tuple[float, float], ...]
    classes: frozenset[str] | None = None

    def watches(self, cls: str) -> bool:
        return self.classes is None or cls in self.classes

    def contains(self, lat: float, lon: float) -> bool:
        return inside_polygon(lat, lon, list(self.polygon))

    def to_json(self) -> dict:
        out = {
            "zone_id": self.zone_id,
            "name": self.name,
            "severity": self.severity,
            "polygon": [{"lat": lat, "lon": lon} for lat, lon in self.polygon],
        }
        if self.classes is not None:
            out["classes"] = sorted(self.classes)
        return out


def load_zones(path: Path) -> list[Zone]:
    """The zones in ``path``, or none if the file does not exist."""
    path = Path(path)
    if not path.is_file():
        return []
    doc = yaml.safe_load(path.read_text()) or {}
    zones: list[Zone] = []
    seen: set[str] = set()
    for item in doc.get("zones", []):
        zone_id = str(item["id"])
        if not _ID_RE.match(zone_id):
            raise ValueError(f"{path}: zone id {zone_id!r}: lower case letters, digits and hyphens only")
        if zone_id in seen:
            raise ValueError(f"{path}: zone {zone_id} listed twice")
        seen.add(zone_id)
        severity = item.get("severity", "medium")
        if severity not in SEVERITIES:
            raise ValueError(f"{path}: zone {zone_id}: severity must be one of {SEVERITIES}")
        polygon = tuple((float(lat), float(lon)) for lat, lon in item["polygon"])
        if len(polygon) < 3:
            raise ValueError(f"{path}: zone {zone_id}: a polygon needs at least 3 corners")
        classes = item.get("classes")
        zones.append(Zone(zone_id, str(item.get("name", zone_id)), severity, polygon,
                          frozenset(classes) if classes else None))
    return zones


def zones_containing(zones: list[Zone], lat: float, lon: float, cls: str) -> list[Zone]:
    return [z for z in zones if z.watches(cls) and z.contains(lat, lon)]
