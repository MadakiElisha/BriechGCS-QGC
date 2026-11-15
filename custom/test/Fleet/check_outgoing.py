"""Checks every message QGC sends against schemas/, with the coordinator's own validator.

fleet_outgoing_samples (built from custom/test/Fleet) writes hello, vehicle.state
and operator.action messages made by the same C++ the app uses, over normal and
edge-case inputs. Each one goes through ground-core's MessageValidator, the check
the coordinator applies to every message it receives: a message that fails here
is one the coordinator would count and drop.

    python check_outgoing.py --emitter build/fleet-tests/fleet_outgoing_samples
    python check_outgoing.py --input samples.jsonl

Needs jsonschema and referencing (pip install -r ground-core/requirements.txt).
Exit 0 when every message is valid and every kind of message was produced.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_DIR / "ground-core"))

from coordinator.schemas import MessageValidator  # noqa: E402

# What QGC sends (FleetProtocol::outgoingTypes plus hello) and what each must cover.
EXPECTED_TYPES = {"hello", "vehicle.state", "operator.action"}
EXPECTED_ACTION_VALUES = {
    "phase": {"decision", "command", "outcome"},
    "command": {"goto", "orbit", "hold", "return"},
    "outcome": {"confirmed", "refused", "no_response"},
    "decision": {"approve", "reject"},
}
MIN_MESSAGES = 1000


def load(args: argparse.Namespace) -> list[dict]:
    if args.input:
        text = Path(args.input).read_text(encoding="utf-8")
    else:
        result = subprocess.run([args.emitter], capture_output=True, check=True)
        sys.stderr.write(result.stderr.decode(errors="replace"))
        text = result.stdout.decode("utf-8")
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--emitter", help="path to the fleet_outgoing_samples program")
    source.add_argument("--input", help="a JSON-lines file it wrote")
    parser.add_argument("--show", type=int, default=3, help="failing cases to list per reason")
    args = parser.parse_args()

    validator = MessageValidator(REPO_DIR / "schemas")
    lines = load(args)

    failures: dict[str, list[str]] = defaultdict(list)
    types_seen: dict[str, int] = defaultdict(int)
    action_values: dict[str, set] = defaultdict(set)
    for line in lines:
        message = line["message"]
        types_seen[message.get("type")] += 1
        if message.get("type") == "operator.action":
            for key in EXPECTED_ACTION_VALUES:
                if key in message.get("data", {}):
                    action_values[key].add(message["data"][key])
        reason = validator.check(message)
        if reason is not None:
            failures[reason].append(line["case"])

    problems = []
    if len(lines) < MIN_MESSAGES:
        problems.append(f"only {len(lines)} messages, expected at least {MIN_MESSAGES}")
    if set(types_seen) != EXPECTED_TYPES:
        problems.append(f"message types {sorted(types_seen)}, expected {sorted(EXPECTED_TYPES)}")
    for key, expected in EXPECTED_ACTION_VALUES.items():
        if missing := expected - action_values[key]:
            problems.append(f"operator.action never had {key} {sorted(missing)}")

    print(f"{len(lines)} messages: " + ", ".join(f"{t} {n}" for t, n in sorted(types_seen.items())))
    failed = sum(len(c) for c in failures.values())
    for reason, cases in sorted(failures.items(), key=lambda kv: -len(kv[1])):
        print(f"\nFAIL x{len(cases)}: {reason}")
        for case in cases[: args.show]:
            print(f"    {case}")
    for problem in problems:
        print(f"\nFAIL: {problem}")

    if failed or problems:
        print(f"\n{failed} of {len(lines)} messages fail the schemas")
        return 1
    print("all valid against schemas/ (the coordinator's MessageValidator)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
