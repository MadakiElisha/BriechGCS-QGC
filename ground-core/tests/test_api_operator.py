import asyncio
import json
from collections import Counter

import pytest
from aiohttp import WSMsgType

from coordinator.api_operator import (
    CLOSE_BAD_HELLO,
    CLOSE_HELLO_TIMEOUT,
    OPERATOR_PATH,
    SNAPSHOT_MAX,
    OperatorClient,
    create_app,
)
from conftest import DEVICE_TOKEN, OPERATOR_TOKEN, example

AUTH = {"Authorization": f"Bearer {OPERATOR_TOKEN}"}
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


@pytest.fixture
async def client(aiohttp_client, coordinator):
    return await aiohttp_client(create_app(coordinator))


async def _receive(ws, timeout=2.0):
    raw = await ws.receive(timeout=timeout)
    assert raw.type == WSMsgType.TEXT, raw
    return json.loads(raw.data)


async def _connect(client, operator_id="op-001"):
    ws = await client.ws_connect(OPERATOR_PATH, headers=AUTH)
    hello = example("hello.valid")
    hello["data"]["operator_id"] = operator_id
    await ws.send_str(json.dumps(hello))
    snap = await _receive(ws)
    assert snap["type"] == "snapshot"
    return ws, snap


async def test_healthz(client):
    resp = await client.get("/healthz")
    assert resp.status == 200 and await resp.text() == "ok\n"


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer wrong"}, {"Authorization": OPERATOR_TOKEN}])
async def test_token_checked_before_upgrade(client, headers):
    resp = await client.get(OPERATOR_PATH, headers=headers)
    assert resp.status == 401


async def test_hello_then_snapshot(client, validator):
    ws, snap = await _connect(client)
    assert validator.check(snap) is None
    assert snap["data"]["assets"][0]["asset_id"] == "tower-01"
    await ws.close()


async def test_first_message_must_be_hello(client):
    ws = await client.ws_connect(OPERATOR_PATH, headers=AUTH)
    await ws.send_str(json.dumps(example("vehicle.state.valid")))
    raw = await ws.receive(timeout=2)
    assert raw.type == WSMsgType.CLOSE and ws.close_code == CLOSE_BAD_HELLO


async def test_invalid_hello_rejected(client):
    ws = await client.ws_connect(OPERATOR_PATH, headers=AUTH)
    await ws.send_str(json.dumps(example("hello.invalid.no-operator")))
    await ws.receive(timeout=2)
    assert ws.close_code == CLOSE_BAD_HELLO


async def test_hello_timeout(client):
    ws = await client.ws_connect(OPERATOR_PATH, headers=AUTH)
    await ws.receive(timeout=2)
    assert ws.close_code == CLOSE_HELLO_TIMEOUT


async def test_changes_pushed_after_snapshot(client, coordinator, validator):
    ws, _ = await _connect(client)
    coordinator.on_bus_message(example("detection.valid"))
    msg = await _receive(ws)
    assert msg["type"] == "object.update" and msg["data"]["object_id"] == "o-tower-01-17"
    assert validator.check(msg) is None
    await ws.close()


async def test_heartbeat_arrives(client, coordinator):
    ws, _ = await _connect(client)
    task = asyncio.create_task(coordinator.run_heartbeat())
    try:
        msg = await _receive(ws)
        assert msg["type"] == "heartbeat" and msg["data"]["counters"]["clients"] == 1
    finally:
        task.cancel()
        await ws.close()


async def test_vehicle_reported_by_one_client_is_in_the_next_snapshot(client):
    """Miracle's FleetVehicleReporter check: a client that connects later sees the vehicle."""
    first, _ = await _connect(client, "op-001")
    await first.send_str(json.dumps(example("vehicle.state.valid")))
    await asyncio.sleep(0.05)
    second, snap = await _connect(client, "op-002")
    (vehicle,) = snap["data"]["vehicles"]
    assert vehicle["vehicle_id"] == 3 and vehicle["name"] == "BRCH-03" and "last_seen_ts" in vehicle
    await first.close()
    await second.close()


async def test_bad_and_wrong_direction_messages_dropped(client, coordinator):
    ws, _ = await _connect(client)
    await ws.send_str("{not json")
    await ws.send_str(json.dumps(example("vehicle.state.invalid.no-vehicle_id")))
    await ws.send_str(json.dumps(example("object.update.valid")))  # coordinator-to-QGC type
    await ws.send_str(json.dumps(example("operator.action.valid")))
    await asyncio.sleep(0.05)
    assert coordinator.counters["drop_ws_json"] == 1
    assert coordinator.counters["drop_ws_schema"] == 1
    assert coordinator.counters["drop_ws_type"] == 1
    assert len(coordinator.operator_actions) == 1
    await ws.close()


async def test_disconnect_unregisters_client(client, coordinator):
    ws, _ = await _connect(client)
    assert len(coordinator.clients) == 1
    await ws.close()
    await asyncio.sleep(0.05)
    assert coordinator.clients == set()


async def test_shutdown_closes_operator_sockets_with_going_away(client):
    ws, _ = await _connect(client)
    await client.server.app.shutdown()
    raw = await ws.receive(timeout=2)
    assert raw.type == WSMsgType.CLOSE and ws.close_code == 1001


def test_client_queue_is_bounded():
    class ClosedWs:
        closed = True

    counters = Counter()
    client = OperatorClient(ClosedWs(), "op-001", max_queue=3, counters=counters)
    for i in range(5):
        client.push(str(i))
    assert list(client._queue) == ["2", "3", "4"]
    assert client.dropped == 2 and counters["drop_queue"] == 2


async def test_snapshot_upload_and_fetch(client):
    resp = await client.post("/api/v1/snapshots", data=JPEG,
                             headers={"Authorization": f"Bearer {DEVICE_TOKEN}", "Content-Type": "image/jpeg"})
    assert resp.status == 201
    snapshot_id = (await resp.json())["snapshot_id"]
    assert snapshot_id.startswith("snap-")

    assert (await client.get(f"/api/v1/snapshots/{snapshot_id}")).status == 401
    resp = await client.get(f"/api/v1/snapshots/{snapshot_id}", headers=AUTH)
    assert resp.status == 200 and resp.content_type == "image/jpeg" and await resp.read() == JPEG


async def test_snapshot_upload_rules(client):
    jpeg_headers = {"Authorization": f"Bearer {DEVICE_TOKEN}", "Content-Type": "image/jpeg"}
    # operator token is not a device token
    resp = await client.post("/api/v1/snapshots", data=JPEG, headers={**AUTH, "Content-Type": "image/jpeg"})
    assert resp.status == 401
    resp = await client.post("/api/v1/snapshots", data=JPEG,
                             headers={"Authorization": f"Bearer {DEVICE_TOKEN}", "Content-Type": "image/png"})
    assert resp.status == 415
    resp = await client.post("/api/v1/snapshots", data=b"GIF89a", headers=jpeg_headers)
    assert resp.status == 415
    resp = await client.post("/api/v1/snapshots", data=JPEG + b"\x00" * SNAPSHOT_MAX, headers=jpeg_headers)
    assert resp.status == 413


@pytest.mark.parametrize("snapshot_id", ["snap-missing00", "..%2Fsecrets", "snap-ABC123"])
async def test_snapshot_not_found(client, snapshot_id):
    assert (await client.get(f"/api/v1/snapshots/{snapshot_id}", headers=AUTH)).status == 404
