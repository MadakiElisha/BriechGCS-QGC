"""Persistence: tracks and alerts survive a coordinator restart.

A small SQLite table of named JSON documents. The coordinator saves the
fusion and alert state every few seconds when something changed, and loads it
on start, so a restart keeps what the operators were looking at. Vehicles and
asset states are not stored: they are re-reported within seconds.
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from .schemas import utc_now_iso


class StateStore:
    def __init__(self, path: Path | str):
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(str(path), check_same_thread=False)
        self._db.execute("CREATE TABLE IF NOT EXISTS state (name TEXT PRIMARY KEY, doc TEXT NOT NULL, saved_ts TEXT NOT NULL)")
        self._db.commit()

    def save(self, name: str, doc: dict) -> None:
        self._db.execute("INSERT INTO state VALUES (?, ?, ?) ON CONFLICT(name) DO UPDATE SET doc = excluded.doc,"
                         " saved_ts = excluded.saved_ts", (name, json.dumps(doc, separators=(",", ":")), utc_now_iso()))
        self._db.commit()

    def load(self, name: str) -> dict | None:
        row = self._db.execute("SELECT doc FROM state WHERE name = ?", (name,)).fetchone()
        return json.loads(row[0]) if row else None

    def close(self) -> None:
        self._db.close()
