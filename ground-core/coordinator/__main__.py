"""Run the coordinator: ``python -m coordinator`` from ground-core/. Settings come from the environment (config.py)."""

from __future__ import annotations

import asyncio
import logging
import signal
import ssl

from aiohttp import web

from .api_operator import OPERATOR_PATH, create_app
from .app import Coordinator
from .bus import MqttBus
from .config import Config
from .fusion import Fusion
from .registry import Registry
from .schemas import MessageValidator

log = logging.getLogger("coordinator")


async def run(config: Config) -> None:
    validator = MessageValidator(config.schema_dir)
    log.info("schemas: %s", ", ".join(sorted(validator.types)))
    registry = Registry.from_file(config.assets_file)
    coordinator = Coordinator(config, validator, registry, Fusion())
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
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()

    log.info("stopping")
    heartbeat.cancel()
    bus.stop()
    await runner.cleanup()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    asyncio.run(run(Config.from_env()))


if __name__ == "__main__":
    main()
