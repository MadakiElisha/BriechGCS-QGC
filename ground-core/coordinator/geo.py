"""Small geometry helpers on WGS84 degrees.

Distances here are for a site a few kilometres across: an equirectangular
projection around the point of interest is accurate to well under a metre at
that size, which is far below every error_m the edge reports.
"""

from __future__ import annotations

import math

EARTH_RADIUS_M = 6_371_008.8


def offset_m(lat: float, lon: float, to_lat: float, to_lon: float) -> tuple[float, float]:
    """(east, north) in metres from (lat, lon) to (to_lat, to_lon)."""
    mean_lat = math.radians((lat + to_lat) / 2.0)
    east = math.radians(to_lon - lon) * math.cos(mean_lat) * EARTH_RADIUS_M
    north = math.radians(to_lat - lat) * EARTH_RADIUS_M
    return east, north


def distance_m(lat: float, lon: float, to_lat: float, to_lon: float) -> float:
    east, north = offset_m(lat, lon, to_lat, to_lon)
    return math.hypot(east, north)


def move(lat: float, lon: float, east_m: float, north_m: float) -> tuple[float, float]:
    """The point east_m and north_m metres away from (lat, lon)."""
    new_lat = lat + math.degrees(north_m / EARTH_RADIUS_M)
    new_lon = lon + math.degrees(east_m / (EARTH_RADIUS_M * math.cos(math.radians(lat))))
    return new_lat, new_lon


def inside_polygon(lat: float, lon: float, polygon: list[tuple[float, float]]) -> bool:
    """Whether (lat, lon) is inside polygon, a list of (lat, lon) corners (ray casting)."""
    inside = False
    n = len(polygon)
    for i in range(n):
        lat1, lon1 = polygon[i]
        lat2, lon2 = polygon[(i + 1) % n]
        if (lat1 > lat) != (lat2 > lat):
            cross_lon = lon1 + (lat - lat1) * (lon2 - lon1) / (lat2 - lat1)
            if lon < cross_lon:
                inside = not inside
    return inside
