#!/usr/bin/env python3
"""Point a local QGC build at the local coordinator by writing its [Fleet] settings.

    python3 ops/scripts/qgc-fleet-settings.py                # the Debug build ("BriechUAS Daily.ini")
    python3 ops/scripts/qgc-fleet-settings.py --ini PATH     # any other QGC settings file
    python3 ops/scripts/qgc-fleet-settings.py --show

Sets Fleet/enabled, Fleet/url, Fleet/token (from ops/secrets/operator.tokens),
Fleet/operatorId and Fleet/caFile (ops/certs/ca.crt). Only the [Fleet]
section is touched. Quit QGC first: it rewrites the file when it exits.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
if sys.platform == "win32":
    DEFAULT_INI = Path(os.environ["APPDATA"]) / "Briech UAS" / "BriechUAS Daily.ini"
else:
    DEFAULT_INI = Path.home() / ".config" / "briechuas.com" / "BriechUAS Daily.ini"


def fleet_section(values: dict[str, str]) -> str:
    return "[Fleet]\n" + "".join(f"{k}={v}\n" for k, v in values.items()) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--ini", type=Path, default=DEFAULT_INI)
    ap.add_argument("--url", default="wss://localhost:8443/ws/v1/operator")
    ap.add_argument("--operator", default="op-001")
    ap.add_argument("--token-file", type=Path, default=REPO / "ops" / "secrets" / "operator.tokens")
    ap.add_argument("--ca", type=Path, default=REPO / "ops" / "certs" / "ca.crt")
    ap.add_argument("--disable", action="store_true", help="set Fleet/enabled=false and leave the rest")
    ap.add_argument("--show", action="store_true", help="print the current [Fleet] section, token hidden")
    args = ap.parse_args()

    text = args.ini.read_text() if args.ini.exists() else ""
    section = re.search(r"^\[Fleet\]\n(?:(?!\[).*\n?)*", text, flags=re.MULTILINE)

    if args.show:
        body = section.group(0) if section else "(no [Fleet] section)\n"
        print(re.sub(r"^(token=).*$", r"\1<hidden>", body, flags=re.MULTILINE), end="")
        return 0

    if args.disable:
        values = dict(re.findall(r"^([^=\n]+)=(.*)$", section.group(0), flags=re.MULTILINE)) if section else {}
        values["enabled"] = "false"
    else:
        token = args.token_file.read_text().split()[0]
        values = {
            "enabled": "true",
            "url": args.url,
            "token": token,
            "operatorId": args.operator,
            # Forward slashes: QSettings reads a backslash in an .ini file as an escape.
            "caFile": args.ca.resolve().as_posix(),
        }

    new = fleet_section(values)
    text = text[: section.start()] + new + text[section.end():] if section else text.rstrip("\n") + "\n\n" + new
    args.ini.parent.mkdir(parents=True, exist_ok=True)
    args.ini.write_text(text)
    print(f"wrote [Fleet] in {args.ini}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
