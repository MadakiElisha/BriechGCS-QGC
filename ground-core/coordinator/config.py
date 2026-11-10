"""Coordinator settings, read from environment variables.

Secrets never live in git or on the command line. Each secret can be given
directly (``BRIECH_MQTT_PASSWORD``) or as a file holding it
(``BRIECH_MQTT_PASSWORD_FILE``), which suits systemd credentials and the files
``ops/scripts/make-secrets.sh`` writes.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping

GROUND_CORE_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = GROUND_CORE_DIR.parent


class ConfigError(ValueError):
    pass


def _secret(env: Mapping[str, str], name: str) -> str | None:
    """NAME, or the contents of the file named by NAME_FILE."""
    if env.get(name):
        return env[name]
    path = env.get(f"{name}_FILE")
    if path:
        try:
            return Path(path).read_text().strip()
        except OSError as exc:
            raise ConfigError(f"{name}_FILE: cannot read {path}: {exc.strerror}") from exc
    return None


def _token_list(text: str | None) -> frozenset[str]:
    """Tokens separated by commas or newlines."""
    if not text:
        return frozenset()
    return frozenset(t.strip() for t in text.replace("\n", ",").split(",") if t.strip())


def _device_tokens(text: str | None) -> dict[str, str]:
    """``device-id=token`` pairs separated by commas or newlines. Returns token -> device id."""
    out: dict[str, str] = {}
    if not text:
        return out
    for item in text.replace("\n", ",").split(","):
        item = item.strip()
        if not item or item.startswith("#"):
            continue
        device, sep, token = item.partition("=")
        if not sep or not device.strip() or not token.strip():
            raise ConfigError("BRIECH_DEVICE_TOKENS: expected device-id=token pairs")
        out[token.strip()] = device.strip()
    return out


def _bool(env: Mapping[str, str], name: str, default: bool) -> bool:
    value = env.get(name)
    if value is None or value == "":
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def _path(env: Mapping[str, str], name: str, default: Path | None) -> Path | None:
    value = env.get(name)
    return Path(value) if value else default


@dataclass(frozen=True)
class Config:
    # MQTT broker
    mqtt_host: str = "localhost"
    mqtt_port: int = 8883
    mqtt_tls: bool = True
    mqtt_ca: Path | None = None
    mqtt_username: str = "coordinator"
    mqtt_password: str | None = None

    # HTTP and WebSocket server for QGC and the edge snapshot uploads
    http_host: str = "0.0.0.0"
    http_port: int = 8443
    tls_cert: Path | None = None
    tls_key: Path | None = None

    operator_tokens: frozenset[str] = frozenset()
    device_tokens: dict[str, str] = field(default_factory=dict)  # token -> device id
    admin_tokens: frozenset[str] = frozenset()                   # GET /api/v1/audit and /audit/verify

    assets_file: Path = GROUND_CORE_DIR / "config" / "assets.yaml"
    zones_file: Path = GROUND_CORE_DIR / "config" / "zones.yaml"
    # The audit log and the saved tracks and alerts. None keeps both in memory only.
    data_dir: Path | None = GROUND_CORE_DIR / "var"
    schema_dir: Path = REPO_DIR / "schemas"
    snapshot_dir: Path = GROUND_CORE_DIR / "var" / "snapshots"

    client_queue_size: int = 500
    heartbeat_s: float = 2.0
    hello_timeout_s: float = 5.0
    asset_silent_s: float = 15.0        # a tower heard from before but silent this long goes offline
    object_min_interval_s: float = 0.5  # at most 2 object.update per second per object
    tick_s: float = 0.1                 # how often held object updates and expiries are checked

    @property
    def tls_enabled(self) -> bool:
        return self.tls_cert is not None

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Config":
        env = os.environ if env is None else env
        defaults = cls()
        cfg = cls(
            mqtt_host=env.get("BRIECH_MQTT_HOST", defaults.mqtt_host),
            mqtt_port=int(env.get("BRIECH_MQTT_PORT", defaults.mqtt_port)),
            mqtt_tls=_bool(env, "BRIECH_MQTT_TLS", defaults.mqtt_tls),
            mqtt_ca=_path(env, "BRIECH_MQTT_CA", None),
            mqtt_username=env.get("BRIECH_MQTT_USERNAME", defaults.mqtt_username),
            mqtt_password=_secret(env, "BRIECH_MQTT_PASSWORD"),
            http_host=env.get("BRIECH_HTTP_HOST", defaults.http_host),
            http_port=int(env.get("BRIECH_HTTP_PORT", defaults.http_port)),
            tls_cert=_path(env, "BRIECH_TLS_CERT", None),
            tls_key=_path(env, "BRIECH_TLS_KEY", None),
            operator_tokens=_token_list(_secret(env, "BRIECH_OPERATOR_TOKENS")),
            device_tokens=_device_tokens(_secret(env, "BRIECH_DEVICE_TOKENS")),
            admin_tokens=_token_list(_secret(env, "BRIECH_ADMIN_TOKENS")),
            assets_file=_path(env, "BRIECH_ASSETS_FILE", defaults.assets_file),
            zones_file=_path(env, "BRIECH_ZONES_FILE", defaults.zones_file),
            data_dir=None if env.get("BRIECH_DATA_DIR") == "memory" else _path(env, "BRIECH_DATA_DIR", defaults.data_dir),
            schema_dir=_path(env, "BRIECH_SCHEMA_DIR", defaults.schema_dir),
            snapshot_dir=_path(env, "BRIECH_SNAPSHOT_DIR", defaults.snapshot_dir),
            client_queue_size=int(env.get("BRIECH_CLIENT_QUEUE_SIZE", defaults.client_queue_size)),
            heartbeat_s=float(env.get("BRIECH_HEARTBEAT_S", defaults.heartbeat_s)),
            asset_silent_s=float(env.get("BRIECH_ASSET_SILENT_S", defaults.asset_silent_s)),
        )
        if (cfg.tls_cert is None) != (cfg.tls_key is None):
            raise ConfigError("set both BRIECH_TLS_CERT and BRIECH_TLS_KEY, or neither")
        if cfg.client_queue_size < 1:
            raise ConfigError("BRIECH_CLIENT_QUEUE_SIZE must be at least 1")
        return cfg
