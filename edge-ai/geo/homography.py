"""Tower camera geolocation: a pixel on the ground to latitude and longitude, with its error.

A fixed camera looking at flat ground maps pixels to the map with one 3x3
matrix (a homography), fitted from control points: places whose pixel and
whose latitude and longitude are both known. Four is the minimum; more
points also tell us how well the flat-ground model fits.

The error is one sigma in metres and has three parts, added in quadrature:

* ``control_error_m``: how well the control points themselves are known.
  This is the floor; no position is better than the survey behind it.
* the fit residual: how far the fitted matrix leaves the control points
  (zero with exactly four points, so it cannot vouch for itself then).
* the pixel part: how uncertain the foot point is in the picture, times how
  many metres one pixel covers there, in the worst direction. Far from the
  camera a pixel covers many metres, so the error grows towards the horizon.

A pixel at or above the horizon has no ground position, and neither has one
whose error is over ``max_error_m``: both return None. Nothing is made up.

Spike S4 measures the real accuracy; until then the numbers here are a model.
"""

from __future__ import annotations

import math

import numpy as np

METRES_PER_DEG_LAT = 111_320.0


def _normalise(points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Points moved to zero mean and unit spread, and the 3x3 matrix that does it (keeps the fit stable)."""
    mean = points.mean(axis=0)
    spread = np.sqrt(((points - mean) ** 2).sum(axis=1)).mean() or 1.0
    s = math.sqrt(2.0) / spread
    t = np.array([[s, 0.0, -s * mean[0]], [0.0, s, -s * mean[1]], [0.0, 0.0, 1.0]])
    return (points - mean) * s, t


class GroundHomography:
    """Fit once from control points, then ``locate`` each foot point.

    ``points`` are (u, v, lat, lon): pixel column and row, WGS84 degrees.
    """

    def __init__(self, points: list[tuple[float, float, float, float]], control_error_m: float,
                 max_error_m: float = 30.0):
        if len(points) < 4:
            raise ValueError("a homography needs at least 4 control points")
        if not control_error_m > 0:
            raise ValueError("control_error_m must be greater than zero: say how well the points are known")
        self.control_error_m = float(control_error_m)
        self.max_error_m = float(max_error_m)
        arr = np.asarray(points, dtype=float)
        self._lat0, self._lon0 = arr[:, 2].mean(), arr[:, 3].mean()
        self._m_per_deg_lon = METRES_PER_DEG_LAT * math.cos(math.radians(self._lat0))
        pixels = arr[:, :2]
        ground = np.column_stack(((arr[:, 3] - self._lon0) * self._m_per_deg_lon,       # east, metres
                                  (arr[:, 2] - self._lat0) * METRES_PER_DEG_LAT))       # north, metres

        # Direct linear transform on normalised points.
        p, tp = _normalise(pixels)
        g, tg = _normalise(ground)
        rows = []
        for (u, v), (x, y) in zip(p, g):
            rows.append([-u, -v, -1, 0, 0, 0, x * u, x * v, x])
            rows.append([0, 0, 0, -u, -v, -1, y * u, y * v, y])
        _, singular, vt = np.linalg.svd(np.asarray(rows))
        if singular[-2] < 1e-9 * singular[0]:
            raise ValueError("control points are in a line (or repeated): the homography is not defined")
        h = np.linalg.inv(tg) @ vt[-1].reshape(3, 3) @ tp
        w = np.column_stack((pixels, np.ones(len(pixels)))) @ h[2]
        if not (np.all(w > 0) or np.all(w < 0)):
            raise ValueError("control points lie on both sides of the horizon: check them")
        self._h = h / w.mean()          # every control point now has w > 0, about 1

        fitted = np.array([self._ground(u, v)[:2] for u, v in pixels])
        self.fit_rms_m = float(np.sqrt(((fitted - ground) ** 2).sum(axis=1).mean()))

    def _ground(self, u: float, v: float) -> tuple[float, float, float]:
        x, y, w = self._h @ (u, v, 1.0)
        return (x / w, y / w, w) if w != 0 else (math.inf, math.inf, 0.0)

    def locate(self, u: float, v: float, sigma_px: float) -> dict | None:
        """{"lat", "lon", "error_m"} for the ground under pixel (u, v), or None when there is no honest answer.

        ``sigma_px`` is how uncertain the pixel is (one sigma): for a
        detection, how well the box's bottom edge marks where the feet are.
        """
        east, north, w = self._ground(u, v)
        if w <= 1e-6:                   # at or above the horizon
            return None
        h = self._h
        jacobian = np.array([[h[0, 0] - east * h[2, 0], h[0, 1] - east * h[2, 1]],
                             [h[1, 0] - north * h[2, 0], h[1, 1] - north * h[2, 1]]]) / w
        metres_per_px = float(np.linalg.svd(jacobian, compute_uv=False)[0])     # worst direction
        error_m = math.sqrt(self.control_error_m ** 2 + self.fit_rms_m ** 2 + (metres_per_px * sigma_px) ** 2)
        if not math.isfinite(error_m) or error_m > self.max_error_m:
            return None
        return {"lat": self._lat0 + north / METRES_PER_DEG_LAT,
                "lon": self._lon0 + east / self._m_per_deg_lon,
                "error_m": error_m}
