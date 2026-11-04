import json

import pytest

from coordinator.bus import MAX_PAYLOAD, check_message, topic_type
from conftest import example


def _payload(msg) -> bytes:
    return json.dumps(msg).encode()


@pytest.mark.parametrize("topic,expected", [
    ("briech/v1/edge/tower-01/detection", ("detection", "tower-01")),
    ("briech/v1/edge/tower-01/status", ("edge.status", "tower-01")),
    ("briech/v1/asset/tower-01/state", ("asset.state", "tower-01")),
    ("briech/v1/asset/tower-01/detection", None),
    ("briech/v1/edge/tower-01/state", None),
    ("briech/v2/edge/tower-01/detection", None),
    ("briech/v1/edge/Tower-01/detection", None),
    ("briech/v1/edge/tower-01/detection/extra", None),
    ("briech/v1/edge/+/detection", None),
])
def test_topic_type(topic, expected):
    assert topic_type(topic) == expected


def test_good_messages_pass(validator):
    for topic, name in [
        ("briech/v1/edge/tower-01/detection", "detection.valid"),
        ("briech/v1/edge/tower-01/status", "edge.status.valid"),
        ("briech/v1/asset/tower-01/state", "asset.state.valid"),
    ]:
        msg, reason = check_message(topic, _payload(example(name)), validator)
        assert reason == "ok" and msg["src"] == "tower-01"


def test_wrong_topic_for_type(validator):
    _, reason = check_message("briech/v1/edge/tower-01/status", _payload(example("detection.valid")), validator)
    assert reason == "type"


def test_src_must_match_topic(validator):
    _, reason = check_message("briech/v1/edge/tower-02/detection", _payload(example("detection.valid")), validator)
    assert reason == "src"


def test_asset_id_must_match_topic(validator):
    msg = example("asset.state.valid")
    msg["data"]["asset_id"] = "tower-02"
    _, reason = check_message("briech/v1/asset/tower-01/state", _payload(msg), validator)
    assert reason == "src"


def test_schema_failure(validator):
    _, reason = check_message("briech/v1/edge/tower-01/detection",
                              _payload(example("detection.invalid.no-error_m")), validator)
    assert reason == "schema"


@pytest.mark.parametrize("payload,reason", [
    (b"{not json", "json"),
    (b"\xff\xfe", "json"),
    (b"[]", "schema"),
    (b"x" * (MAX_PAYLOAD + 1), "size"),
])
def test_bad_payloads(payload, reason, validator):
    assert check_message("briech/v1/edge/tower-01/detection", payload, validator) == (None, reason)


def test_unknown_topic(validator):
    assert check_message("briech/v1/other", _payload(example("detection.valid")), validator) == (None, "topic")
