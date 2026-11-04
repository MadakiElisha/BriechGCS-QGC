"""Message checks against the JSON Schemas in ``schemas/``.

The schemas are the contract. Every message that arrives, and every message
the coordinator sends, goes through :meth:`MessageValidator.check`. A message
that fails is counted and dropped, never half-used.

Change this file only together with the lead: the guarantees in the handoff
(section 10) depend on it.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

# Schemas that describe parts of a message, not a message type.
_SHARED = ("envelope", "common")


def utc_now_iso() -> str:
    """UTC in ISO 8601 with milliseconds, ending in Z."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_ts(ts: str) -> datetime:
    """A schema timestamp as an aware UTC datetime. Accepts 0 to 6 fraction digits on any Python."""
    base, _, frac = ts.rstrip("Z").partition(".")
    micro = int(frac.ljust(6, "0")) if frac else 0
    return datetime.fromisoformat(base).replace(microsecond=micro, tzinfo=timezone.utc)


class MessageValidator:
    def __init__(self, schema_dir: Path):
        self.schema_dir = Path(schema_dir)
        resources = []
        by_type: dict[str, dict] = {}
        for path in sorted(self.schema_dir.glob("*.schema.json")):
            schema = json.loads(path.read_text())
            Draft202012Validator.check_schema(schema)
            resources.append((schema["$id"], Resource.from_contents(schema)))
            name = path.name[: -len(".schema.json")]
            if name not in _SHARED:
                by_type[name] = schema
        missing = [s for s in _SHARED if not (self.schema_dir / f"{s}.schema.json").is_file()]
        if missing or not by_type:
            raise FileNotFoundError(f"schemas missing in {self.schema_dir}: {missing or 'message types'}")
        registry = Registry().with_resources(resources)
        self._validators = {t: Draft202012Validator(s, registry=registry) for t, s in by_type.items()}

    @property
    def types(self) -> frozenset[str]:
        return frozenset(self._validators)

    def check(self, msg: Any) -> str | None:
        """None when ``msg`` is a valid message, else a short reason."""
        if not isinstance(msg, dict):
            return "not a JSON object"
        msg_type = msg.get("type")
        validator = self._validators.get(msg_type) if isinstance(msg_type, str) else None
        if validator is None:
            return f"unknown type {msg_type!r}"
        error = next(iter(validator.iter_errors(msg)), None)
        if error is None:
            return None
        where = "/".join(str(p) for p in error.absolute_path) or "(root)"
        return f"{msg_type}: {where}: {error.message[:160]}"
