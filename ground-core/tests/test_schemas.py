"""Every example in schemas/examples/ is valid or invalid exactly as its name says."""

import json

import pytest
from jsonschema import Draft202012Validator

from coordinator.schemas import parse_ts, utc_now_iso
from conftest import EXAMPLES_DIR, SCHEMA_DIR

EXAMPLES = sorted(EXAMPLES_DIR.glob("*.json"))


def _expected(path):
    """(type, should_be_valid) from a name like detection.valid.json or detection.invalid.no-geo.json."""
    stem = path.name[: -len(".json")]
    for marker, valid in ((".valid", True), (".invalid", False)):
        type_, sep, _ = stem.partition(marker)
        if sep:
            return type_, valid
    raise AssertionError(f"{path.name}: name must contain .valid or .invalid")


@pytest.mark.parametrize("path", sorted(SCHEMA_DIR.glob("*.schema.json")), ids=lambda p: p.name)
def test_schema_is_valid_draft_2020_12(path):
    Draft202012Validator.check_schema(json.loads(path.read_text()))


@pytest.mark.parametrize("path", EXAMPLES, ids=lambda p: p.name)
def test_example_matches_its_name(path, validator):
    msg_type, should_be_valid = _expected(path)
    msg = json.loads(path.read_text())
    assert msg["type"] == msg_type, "the file name and the message type must agree"
    error = validator.check(msg)
    if should_be_valid:
        assert error is None, error
    else:
        assert error is not None, "expected this example to fail its schema"


def test_every_type_has_valid_and_invalid_examples(validator):
    seen = {(t, v) for t, v in map(_expected, EXAMPLES)}
    for msg_type in validator.types:
        assert (msg_type, True) in seen, f"no valid example for {msg_type}"
        assert (msg_type, False) in seen, f"no invalid example for {msg_type}"


def test_unknown_fields_are_ignored(validator):
    msg = json.loads((EXAMPLES_DIR / "detection.valid.json").read_text())
    msg["future_field"] = 1
    msg["data"]["another_future_field"] = {"x": 1}
    assert validator.check(msg) is None


def test_unknown_type_is_rejected(validator):
    msg = json.loads((EXAMPLES_DIR / "detection.valid.json").read_text())
    msg["type"] = "detection.v2"
    assert "unknown type" in validator.check(msg)


def test_examples_stay_under_4_kb():
    for path in EXAMPLES:
        if not path.name.startswith("snapshot."):
            assert len(json.dumps(json.loads(path.read_text()))) < 4096, path.name


@pytest.mark.parametrize("ts,micro", [("2026-10-26T10:30:05Z", 0), ("2026-10-26T10:30:05.4Z", 400000),
                                      ("2026-10-26T10:30:05.400Z", 400000), ("2026-10-26T10:30:05.123456Z", 123456)])
def test_parse_ts(ts, micro):
    t = parse_ts(ts)
    assert (t.second, t.microsecond, t.utcoffset().total_seconds()) == (5, micro, 0)


def test_utc_now_iso_matches_the_schema(validator):
    msg = json.loads((EXAMPLES_DIR / "heartbeat.valid.json").read_text())
    msg["ts"] = utc_now_iso()
    assert validator.check(msg) is None and len(msg["ts"]) == 24
