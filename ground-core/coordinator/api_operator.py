"""HTTP and WebSocket endpoints: QGC on /ws/v1/operator, and snapshot images.

WebSocket order on every connection: the operator token is checked before the
upgrade (401 without it), then the first message must be a valid hello
(close 4400, or 4408 if none arrives in time), then the client gets a
snapshot followed only by changes.

Each client has a bounded queue. When a slow client's queue is full the
oldest message is dropped and counted, so one stuck QGC cannot grow memory.
"""

from __future__ import annotations

import asyncio
import hmac
import json
import logging
import re
import secrets
from collections import Counter, deque
from pathlib import Path

from aiohttp import WSCloseCode, WSMsgType, web

from .app import Coordinator

log = logging.getLogger(__name__)

OPERATOR_PATH = "/ws/v1/operator"
FROM_QGC = frozenset({"vehicle.state", "operator.action"})
WS_MAX_MESSAGE = 64 * 1024
SNAPSHOT_MAX = 300 * 1024

CLOSE_BAD_HELLO = 4400
CLOSE_HELLO_TIMEOUT = 4408
CLOSE_SERVER_ERROR = 1011

_SNAPSHOT_ID_RE = re.compile(r"^snap-[a-z0-9]{6,32}$")

COORDINATOR = web.AppKey("coordinator", Coordinator)


class OperatorClient:
    def __init__(self, ws: web.WebSocketResponse, operator_id: str, max_queue: int, counters: Counter):
        self.ws = ws
        self.operator_id = operator_id
        self.dropped = 0
        self._max = max_queue
        self._queue: deque[str] = deque()
        self._wake = asyncio.Event()
        self._counters = counters

    def push(self, text: str) -> None:
        if len(self._queue) >= self._max:
            self._queue.popleft()
            self.dropped += 1
            self._counters["drop_queue"] += 1
        self._queue.append(text)
        self._wake.set()

    async def run_writer(self) -> None:
        try:
            while not self.ws.closed:
                await self._wake.wait()
                self._wake.clear()
                while self._queue and not self.ws.closed:
                    await self.ws.send_str(self._queue.popleft())
        except (ConnectionResetError, RuntimeError):
            pass


def _bearer(request: web.Request) -> str | None:
    scheme, _, token = request.headers.get("Authorization", "").partition(" ")
    return token.strip() if scheme.lower() == "bearer" and token.strip() else None


def _match_token(token: str | None, tokens) -> str | None:
    """The matching token from ``tokens``, compared in constant time against every entry."""
    if token is None:
        return None
    match = None
    for candidate in tokens:  # no early exit, so timing does not hint which token matched
        if hmac.compare_digest(token.encode(), candidate.encode()):
            match = candidate
    return match


def _require_operator(request: web.Request) -> None:
    config = request.app[COORDINATOR].config
    if _match_token(_bearer(request), config.operator_tokens) is None:
        request.app[COORDINATOR].counters["http_unauthorized"] += 1
        raise web.HTTPUnauthorized(headers={"WWW-Authenticate": "Bearer"})


def _parse(raw) -> dict | None:
    if raw.type != WSMsgType.TEXT:
        return None
    try:
        msg = json.loads(raw.data)
    except json.JSONDecodeError:
        return None
    return msg if isinstance(msg, dict) else None


async def healthz(request: web.Request) -> web.Response:
    return web.Response(text="ok\n")


async def operator_ws(request: web.Request) -> web.WebSocketResponse:
    coord = request.app[COORDINATOR]
    _require_operator(request)

    ws = web.WebSocketResponse(heartbeat=10.0, max_msg_size=WS_MAX_MESSAGE)
    await ws.prepare(request)

    try:
        first = await ws.receive(timeout=coord.config.hello_timeout_s)
    except asyncio.TimeoutError:
        await ws.close(code=CLOSE_HELLO_TIMEOUT, message=b"hello timeout")
        return ws
    hello = _parse(first)
    if hello is None or hello.get("type") != "hello" or coord.validator.check(hello) is not None:
        coord.counters["drop_ws_hello"] += 1
        await ws.close(code=CLOSE_BAD_HELLO, message=b"first message must be a valid hello")
        return ws

    snapshot = coord.snapshot()
    if snapshot is None:
        await ws.close(code=CLOSE_SERVER_ERROR, message=b"snapshot failed")
        return ws
    client = OperatorClient(ws, hello["data"]["operator_id"], coord.config.client_queue_size, coord.counters)
    # The snapshot is queued and the client registered in one step, so no change can slip between them.
    client.push(json.dumps(snapshot, separators=(",", ":")))
    coord.clients.add(client)
    writer = asyncio.create_task(client.run_writer())
    log.info("operator %s connected (%s), %d clients", client.operator_id, hello["data"]["client"],
             len(coord.clients))

    try:
        async for raw in ws:
            if raw.type == WSMsgType.ERROR:
                break
            msg = _parse(raw)
            if msg is None:
                coord.counters["drop_ws_json"] += 1
                continue
            error = coord.validator.check(msg)
            if error is not None:
                coord.counters["drop_ws_schema"] += 1
                log.info("operator %s: dropped message: %s", client.operator_id, error)
                continue
            if msg["type"] not in FROM_QGC:
                coord.counters["drop_ws_type"] += 1
                continue
            coord.on_operator_message(client, msg)
    finally:
        coord.clients.discard(client)
        writer.cancel()
        log.info("operator %s disconnected, %d clients, %d dropped from its queue",
                 client.operator_id, len(coord.clients), client.dropped)
    return ws


def _write_file(path: Path, body: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".part")
    tmp.write_bytes(body)
    tmp.replace(path)


async def upload_snapshot(request: web.Request) -> web.Response:
    coord = request.app[COORDINATOR]
    token = _match_token(_bearer(request), coord.config.device_tokens)
    device = coord.config.device_tokens[token] if token else None
    if device is None:
        coord.counters["http_unauthorized"] += 1
        raise web.HTTPUnauthorized(headers={"WWW-Authenticate": "Bearer"})
    if request.content_type != "image/jpeg":
        raise web.HTTPUnsupportedMediaType(text="send one JPEG as image/jpeg\n")
    body = await request.read()  # the app's client_max_size answers 413 above SNAPSHOT_MAX
    if not body.startswith(b"\xff\xd8\xff"):
        raise web.HTTPUnsupportedMediaType(text="not a JPEG\n")
    snapshot_id = f"snap-{secrets.token_hex(8)}"
    await asyncio.to_thread(_write_file, coord.config.snapshot_dir / f"{snapshot_id}.jpg", body)
    coord.counters["snapshots_in"] += 1
    log.info("snapshot %s from %s, %d bytes", snapshot_id, device, len(body))
    return web.json_response({"snapshot_id": snapshot_id}, status=201)


async def get_snapshot(request: web.Request) -> web.StreamResponse:
    _require_operator(request)
    snapshot_id = request.match_info["snapshot_id"]
    if not _SNAPSHOT_ID_RE.match(snapshot_id):
        raise web.HTTPNotFound()
    path = request.app[COORDINATOR].config.snapshot_dir / f"{snapshot_id}.jpg"
    if not path.is_file():
        raise web.HTTPNotFound()
    return web.FileResponse(path, headers={"Content-Type": "image/jpeg", "Cache-Control": "private, max-age=3600"})


async def close_operator_sockets(app: web.Application) -> None:
    """On shutdown, tell every QGC we are going (1001) so it reconnects at once
    rather than waiting for its silence timeout. aiohttp does not do this itself."""
    for client in list(app[COORDINATOR].clients):
        await client.ws.close(code=WSCloseCode.GOING_AWAY, message=b"coordinator shutting down")


def create_app(coordinator: Coordinator) -> web.Application:
    app = web.Application(client_max_size=SNAPSHOT_MAX)
    app[COORDINATOR] = coordinator
    app.on_shutdown.append(close_operator_sockets)
    app.add_routes([
        web.get("/healthz", healthz),
        web.get(OPERATOR_PATH, operator_ws),
        web.post("/api/v1/snapshots", upload_snapshot),
        web.get("/api/v1/snapshots/{snapshot_id}", get_snapshot),
    ])
    return app
