#!/usr/bin/env bash
# Run from a synchronized app snapshot; no upstream checkout/network is required.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ -f "$ROOT/.bobukkit-vendor" && -f "$ROOT/MANIFEST.sha256" ]] || {
    echo 'This check needs a vendored snapshot. In the canonical kit, run swift test.' >&2; exit 1;
}
(cd "$ROOT" && shasum -a 256 -c MANIFEST.sha256)
exec swift test --package-path "$ROOT" --scratch-path "${BOBUKKIT_SCRATCH_PATH:-$ROOT/.build}"
