import copy
import json
from pathlib import Path

import pytest

from coordinator.app import Coordinator
from coordinator.config import GROUND_CORE_DIR, REPO_DIR, Config
from coordinator.fusion import Fusion
from coordinator.registry import Registry
from coordinator.schemas import MessageValidator

SCHEMA_DIR = REPO_DIR / "schemas"
EXAMPLES_DIR = SCHEMA_DIR / "examples"
ASSETS_FILE = GROUND_CORE_DIR / "config" / "assets.yaml"

OPERATOR_TOKEN = "test-operator-token"
DEVICE_TOKEN = "test-device-token"
ADMIN_TOKEN = "test-admin-token"


def example(name: str) -> dict:
    """A fresh copy of schemas/examples/<name>.json."""
    return copy.deepcopy(json.loads((EXAMPLES_DIR / f"{name}.json").read_text()))


@pytest.fixture(scope="session")
def validator() -> MessageValidator:
    return MessageValidator(SCHEMA_DIR)


@pytest.fixture
def config(tmp_path: Path) -> Config:
    return Config(
        operator_tokens=frozenset({OPERATOR_TOKEN}),
        device_tokens={DEVICE_TOKEN: "tower-01"},
        admin_tokens=frozenset({ADMIN_TOKEN}),
        snapshot_dir=tmp_path / "snapshots",
        client_queue_size=5,
        heartbeat_s=0.05,
        hello_timeout_s=0.5,
        mqtt_tls=False,
    )


@pytest.fixture
def registry() -> Registry:
    return Registry.from_file(ASSETS_FILE)


@pytest.fixture
def coordinator(config, validator, registry) -> Coordinator:
    return Coordinator(config, validator, registry, Fusion())


def detection(src: str = "tower-01", track_id: int = 17, lat: float = 6.5251, lon: float = 3.3801,
              error_m: float = 6.0, ts: str = "2026-10-26T10:30:05.400Z", cls: str = "person",
              confidence: float = 0.9, late: bool = False) -> dict:
    """A valid detection message from ``src`` at ``ts``."""
    data = {"class": cls, "confidence": confidence, "track_id": track_id,
            "geo": {"lat": lat, "lon": lon, "error_m": error_m},
            "bbox": {"x": 0.4, "y": 0.5, "w": 0.05, "h": 0.14}}
    if late:
        data["late"] = True
    return {"v": 1, "type": "detection", "id": f"d-{src}-{track_id}-{ts}", "ts": ts, "src": src, "data": data}
