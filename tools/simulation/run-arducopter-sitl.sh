#!/usr/bin/env bash
# Backwards-compatible name for the PX4 Docker SITL launcher.

set -euo pipefail

for argument in "$@"; do
    if [[ "$argument" == "--with-latency" ]]; then
        echo "--with-latency is not supported by the PX4 SIH launcher." >&2
        exit 2
    fi
done

echo "This legacy launcher now starts PX4 SIH. Use run-px4-sitl-docker.sh directly." >&2
exec "$(dirname "$0")/run-px4-sitl-docker.sh" "$@"
