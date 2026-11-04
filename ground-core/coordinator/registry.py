"""What the coordinator knows about each asset and vehicle, and when it last heard from it.

Fixed assets come from ``config/assets.yaml``. Their state comes from
asset.state messages and their link from the edge computer's edge.status
(including the broker's last will). Vehicles come from QGC's vehicle.state.
"""

from __future__ import annotations

import copy
import logging
from pathlib import Path

import yaml

from .schemas import parse_ts

log = logging.getLogger(__name__)

# Fields a tower adapter may set. The coordinator owns kind, name, link and last_seen_ts.
_DEVICE_ASSET_FIELDS = ("pos", "health", "camera_heading_deg", "battery_pct", "mains_power", "temp_c", "note")


def _later(a: str | None, b: str) -> str:
    """The later of two schema timestamps (they may differ in fractional digits, so compare as times)."""
    if a is None:
        return b
    return b if parse_ts(b) > parse_ts(a) else a


def load_assets(path: Path) -> dict[str, dict]:
    doc = yaml.safe_load(Path(path).read_text()) or {}
    assets: dict[str, dict] = {}
    for item in doc.get("assets", []):
        asset_id = item["id"]
        if asset_id in assets:
            raise ValueError(f"{path}: asset {asset_id} listed twice")
        entry = {"asset_id": asset_id, "kind": item["kind"], "name": item.get("name", asset_id), "link": "unknown"}
        if "pos" in item:
            entry["pos"] = dict(item["pos"])
        assets[asset_id] = entry
    return assets


class Registry:
    def __init__(self, assets: dict[str, dict]):
        self._assets = assets
        self._vehicles: dict[int, dict] = {}
        self.source_last_seen: dict[str, str] = {}  # every MQTT source, listed in assets.yaml or not

    @classmethod
    def from_file(cls, path: Path) -> "Registry":
        assets = load_assets(path)
        log.info("registry: %d fixed assets from %s", len(assets), path)
        return cls(assets)

    def is_known_asset(self, asset_id: str) -> bool:
        return asset_id in self._assets

    def touch(self, source_id: str, ts: str) -> None:
        """Record that something was heard from ``source_id`` at ``ts``.

        Last-seen only moves forward: a last will carries the time the device
        connected, and an old retained message arrives when we resubscribe.
        """
        self.source_last_seen[source_id] = _later(self.source_last_seen.get(source_id), ts)
        asset = self._assets.get(source_id)
        if asset is not None:
            asset["last_seen_ts"] = _later(asset.get("last_seen_ts"), ts)

    def apply_asset_state(self, msg: dict) -> dict | None:
        """Merge an asset.state from a device. Returns the full asset entry, or None if unknown."""
        data = msg["data"]
        asset = self._assets.get(data["asset_id"])
        if asset is None:
            return None
        for key in _DEVICE_ASSET_FIELDS:
            if key in data:
                asset[key] = copy.deepcopy(data[key])
        self.touch(msg["src"], msg["ts"])
        return copy.deepcopy(asset)

    def apply_edge_status(self, msg: dict) -> dict | None:
        """Update the asset's link from an edge.status. Returns the asset entry when the link changed."""
        self.touch(msg["src"], msg["ts"])
        asset = self._assets.get(msg["src"])
        if asset is None:
            return None
        link = "offline" if msg["data"]["state"] == "offline" else "online"
        if asset.get("link") == link:
            return None
        asset["link"] = link
        return copy.deepcopy(asset)

    def apply_vehicle_state(self, msg: dict) -> None:
        for vehicle in msg["data"]["vehicles"]:
            entry = copy.deepcopy(vehicle)
            entry["last_seen_ts"] = msg["ts"]
            self._vehicles[vehicle["vehicle_id"]] = entry

    def assets(self) -> list[dict]:
        return [copy.deepcopy(a) for a in self._assets.values()]

    def vehicles(self) -> list[dict]:
        return [copy.deepcopy(v) for _, v in sorted(self._vehicles.items())]
