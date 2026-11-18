#!/usr/bin/env bash
# Starts the real app, waits for the Briech Modern view to finish loading, and
# fails on QML errors that break a whole screen: a missing module, a missing
# type, a component that cannot load.
#
#   custom/test/ui-smoke.sh <app> [expect] [seconds]
#
#   app      the executable or AppImage
#   expect   "3D" or "2D fallback": the attitude view the build must report
#            (optional; checks that a build without Qt Quick 3D really falls back)
#   seconds  how long to wait for the Modern view (default 90)
#
# --simple-boot-test exits before any QML loads, so it cannot catch these.
# Needs a display: CI runs this under xvfb-run. The log is kept in
# ui-smoke.log next to where it runs.
set -uo pipefail

app="${1:?usage: ui-smoke.sh <app> [expect] [seconds]}"
expect="${2:-}"
seconds="${3:-90}"
log="$PWD/ui-smoke.log"
marker="Briech Modern view loaded; attitude view: "
# Errors that mean a screen did not load at all.
fatal='module "[^"]+" is not installed|is not a type|failed to load component|Type [A-Za-z0-9_.]+ unavailable'

export QT_FORCE_STDERR_LOGGING=1
export QT_LOGGING_RULES="qml.debug=true;js.debug=true;default.info=true"

"$app" > "$log" 2>&1 &
pid=$!

status=0
for _ in $(seq 1 "$seconds"); do
  grep -q "$marker" "$log" && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
sleep 5    # let late-loading parts (Fleet layer, panels) report their errors too
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

if ! grep -q "$marker" "$log"; then
  echo "FAIL: the Modern view did not report loading within ${seconds} s"
  status=1
else
  echo "PASS: $(grep -o "$marker.*" "$log" | head -1)"
  if [[ -n "$expect" ]] && ! grep -q "$marker$expect" "$log"; then
    echo "FAIL: expected attitude view \"$expect\""
    status=1
  fi
fi

if grep -E -q "$fatal" "$log"; then
  echo "FAIL: QML errors that stop a screen loading:"
  grep -E "$fatal" "$log" | sort | uniq -c | head -20
  status=1
else
  echo "PASS: no missing QML modules, types or components"
fi

if [[ $status -ne 0 ]]; then
  echo "--- last 40 lines of $log"
  tail -n 40 "$log"
fi
exit $status
