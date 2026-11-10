import sqlite3

import pytest

from coordinator.audit import GENESIS, AuditLog
from coordinator.store import StateStore


@pytest.fixture
def audit(tmp_path):
    log = AuditLog(tmp_path / "audit.sqlite")
    yield log
    log.close()


def fill(audit):
    audit.append("alert.new", {"alert_id": "a-1", "severity": "high"})
    audit.append("operator.action", {"action_id": "act-1", "phase": "decision", "decision": "approve"})
    audit.append("operator.action", {"action_id": "act-1", "phase": "outcome", "outcome": "confirmed"})


def test_chain_links_each_entry_to_the_last(audit):
    fill(audit)
    entries = audit.entries()
    assert [e["seq"] for e in entries] == [1, 2, 3]
    assert entries[0]["prev_hash"] == GENESIS
    assert entries[1]["prev_hash"] == entries[0]["hash"] and entries[2]["prev_hash"] == entries[1]["hash"]
    assert audit.verify() == {"ok": True, "entries": 3, "first_broken": None}


def test_empty_log_verifies(audit):
    assert audit.verify() == {"ok": True, "entries": 0, "first_broken": None}


@pytest.mark.parametrize("sql, broken", [
    ("UPDATE audit SET payload = '{\"decision\":\"reject\"}' WHERE seq = 2", 2),   # edit a payload
    ("UPDATE audit SET ts = '2020-01-01T00:00:00.000Z' WHERE seq = 1", 1),         # edit a time
    ("UPDATE audit SET kind = 'note' WHERE seq = 3", 3),                           # edit a kind
    ("DELETE FROM audit WHERE seq = 2", 3),                                        # delete a row
])
def test_editing_any_stored_row_makes_verify_fail(tmp_path, sql, broken):
    path = tmp_path / "audit.sqlite"
    log = AuditLog(path)
    fill(log)
    log.close()
    raw = sqlite3.connect(path)
    raw.execute(sql)
    raw.commit()
    raw.close()
    log = AuditLog(path)
    result = log.verify()
    log.close()
    assert result["ok"] is False and result["first_broken"] == broken


def test_entries_page_and_survive_reopening(tmp_path):
    path = tmp_path / "audit.sqlite"
    log = AuditLog(path)
    fill(log)
    log.close()
    log = AuditLog(path)
    assert [e["seq"] for e in log.entries(after=1, limit=1)] == [2]
    log.append("note", {"x": 1})                       # the chain continues across restarts
    assert log.verify()["ok"] and log.verify()["entries"] == 4
    log.close()


def test_state_store_round_trip(tmp_path):
    store = StateStore(tmp_path / "state.sqlite")
    assert store.load("fusion") is None
    store.save("fusion", {"tracks": [1]})
    store.save("fusion", {"tracks": [2]})
    store.close()
    store = StateStore(tmp_path / "state.sqlite")
    assert store.load("fusion") == {"tracks": [2]}
    store.close()
