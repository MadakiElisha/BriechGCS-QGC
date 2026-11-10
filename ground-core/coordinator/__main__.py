"""Run the coordinator: ``python -m coordinator`` from ground-core/. Settings come from the environment (config.py)."""

from __future__ import annotations

import asyncio
import logging
import signal
import ssl

from aiohttp import web

from .api_operator import OPERATOR_PATH, create_app
from .app import Coordinator
from .audit import AuditLog
from .bus import MqttBus
from .config import Config
from .fusion import Fusion
from .registry import Registry
from .schemas import MessageValidator
from .store import StateStore
from .zones import load_zones

log = logging.getLogger("coordinator")


async def run(config: Config) -> None:
    validator = MessageValidator(config.schema_dir)
    log.info("schemas: %s", ", ".join(sorted(validator.types)))
    registry = Registry.from_file(config.assets_file)
    zones = load_zones(config.zones_file)
    log.info("zones: %d from %s", len(zones), config.zones_file)
    if config.data_dir is not None:
        audit = AuditLog(config.data_dir / "audit.sqlite")
        store = StateStore(config.data_dir / "state.sqlite")
        log.info("audit log and saved state in %s", config.data_dir)
    else:
        audit = store = None
        log.warning("BRIECH_DATA_DIR=memory: no audit log on disk, nothing survives a restart")
    coordinator = Coordinator(config, validator, registry, Fusion(), zones=zones, audit=audit, store=store)
    if not config.operator_tokens:
        log.warning("no operator tokens set (BRIECH_OPERATOR_TOKENS): QGC cannot connect")

    loop = asyncio.get_running_loop()
    bus = MqttBus(config, validator, coordinator.on_bus_message, coordinator.counters, loop)
    bus.start()

    ssl_context = None
    if config.tls_enabled:
        ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ssl_context.load_cert_chain(config.tls_cert, config.tls_key)
    else:
        log.warning("BRIECH_TLS_CERT not set: serving plain HTTP and ws://, for local development only")

    runner = web.AppRunner(create_app(coordinator), access_log=None)
    await runner.setup()
    await web.TCPSite(runner, config.http_host, config.http_port, ssl_context=ssl_context).start()
    scheme = "wss" if ssl_context else "ws"
    log.info("operator WebSocket on %s://%s:%d%s", scheme, config.http_host, config.http_port, OPERATOR_PATH)

    heartbeat = asyncio.create_task(coordinator.run_heartbeat())
    ticker = asyncio.create_task(coordinator.run_ticker())
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            # Windows has no loop signal handlers: Ctrl+C cancels this task instead,
            # and the finally below still shuts down cleanly.
            pass
    try:
        await stop.wait()
    finally:
        log.info("stopping")
        heartbeat.cancel()
        ticker.cancel()
        bus.stop()
        await runner.cleanup()
        coordinator.save()
        if audit is not None:
            audit.close()
            store.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(run(Config.from_env()))
    except KeyboardInterrupt:
        pass    # Windows: Ctrl+C arrives here after run() has cleaned up


if __name__ == "__main__":
    main()
