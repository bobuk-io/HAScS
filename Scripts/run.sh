#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Do not overwrite or kill a running instance: an HA request may be in flight.
if pgrep -f -x "$ROOT/build/HAScS.app/Contents/MacOS/HAScS" >/dev/null; then
  echo "HAScS is already running; quit it from the menu bar before rebuilding."
  exit 1
fi
"$ROOT/Scripts/package_app.sh" "${1:-debug}"
open "$ROOT/build/HAScS.app"
echo "HAScS started in the menu bar. Open it via the house icon or: open 'hascs://scenes'"
