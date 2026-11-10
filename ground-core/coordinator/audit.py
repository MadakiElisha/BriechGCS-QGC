"""The audit log: every alert, decision and outcome, hash-chained in SQLite.

Each row stores its own hash and the previous row's hash:

    hash = sha256(seq | ts | kind | payload | prev_hash)

with payload as canonical JSON (sorted keys, no spaces). Changing, deleting or
reordering any stored row breaks the chain from that row on, and verify()
reports the first broken entry. The chain shows tampering; it does not
prevent it. Keep the database on the coordinator's own disk and back it up.
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
from pathlib import Path

from .schemas import utc_now_iso

GENESIS = "0" * 64


def canonical(payload: dict) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def entry_hash(seq: int, ts: str, kind: str, payload: str, prev_hash: str) -> str:
    return hashlib.sha256(f"{seq}|{ts}|{kind}|{payload}|{prev_hash}".encode()).hexdigest()


class AuditLog:
    def __init__(self, path: Path | str):
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(str(path), check_same_thread=False)
        self._lock = threading.Lock()
        self._db.execute(
            "CREATE TABLE IF NOT EXISTS audit ("
            " seq INTEGER PRIMARY KEY, ts TEXT NOT NULL, kind TEXT NOT NULL,"
            " payload TEXT NOT NULL, prev_hash TEXT NOT NULL, hash TEXT NOT NULL)")
        self._db.commit()

    def append(self, kind: str, payload: dict) -> dict:
        """Adds one entry and returns it."""
        with self._lock:
            last = self._db.execute("SELECT seq, hash FROM audit ORDER BY seq DESC LIMIT 1").fetchone()
            seq = last[0] + 1 if last else 1
            prev_hash = last[1] if last else GENESIS
            ts = utc_now_iso()
            text = canonical(payload)
            digest = entry_hash(seq, ts, kind, text, prev_hash)
            self._db.execute("INSERT INTO audit VALUES (?, ?, ?, ?, ?, ?)", (seq, ts, kind, text, prev_hash, digest))
            self._db.commit()
        return {"seq": seq, "ts": ts, "kind": kind, "payload": payload, "prev_hash": prev_hash, "hash": digest}

    def entries(self, after: int = 0, limit: int = 200) -> list[dict]:
        rows = self._db.execute(
            "SELECT seq, ts, kind, payload, prev_hash, hash FROM audit WHERE seq > ? ORDER BY seq LIMIT ?",
            (after, max(1, min(limit, 1000)))).fetchall()
        return [{"seq": s, "ts": t, "kind": k, "payload": json.loads(p), "prev_hash": ph, "hash": h}
                for s, t, k, p, ph, h in rows]

    def verify(self) -> dict:
        """Re-checks the whole chain. ok, the number of entries, and the first broken seq (or None)."""
        prev_hash, expected_seq, count = GENESIS, 1, 0
        for seq, ts, kind, payload, stored_prev, stored_hash in self._db.execute(
                "SELECT seq, ts, kind, payload, prev_hash, hash FROM audit ORDER BY seq"):
            count += 1
            if (seq != expected_seq or stored_prev != prev_hash
                    or entry_hash(seq, ts, kind, payload, stored_prev) != stored_hash):
                return {"ok": False, "entries": count, "first_broken": seq}
            prev_hash, expected_seq = stored_hash, seq + 1
        return {"ok": True, "entries": count, "first_broken": None}

    def close(self) -> None:
        self._db.close()
