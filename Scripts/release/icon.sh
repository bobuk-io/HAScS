#!/usr/bin/env bash
# Builds an .icns from a 1024×1024 PNG master with tools included in macOS.
#   Scripts/release/icon.sh Assets/AppIcon.png .build/Icon.icns
set -euo pipefail
MASTER=${1:?Usage: icon.sh <master.png> <output.icns>}
OUTPUT=${2:?Usage: icon.sh <master.png> <output.icns>}

[[ -f "$MASTER" ]] || { echo "ERROR: App icon master is missing: $MASTER" >&2; exit 1; }
SIZE=$(sips -g pixelWidth -g pixelHeight "$MASTER" | awk '/pixelWidth:/ { w = $2 } /pixelHeight:/ { h = $2 } END { print w "x" h }')
[[ "$SIZE" == 1024x1024 ]] || { echo "ERROR: $MASTER must be 1024x1024 (found $SIZE)." >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/bobuk-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/Icon.iconset"
mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=$([[ "$scale" == 2 ]] && echo @2x || true)
    target="$ICONSET/icon_${size}x${size}${suffix}.png"
    if [[ "$pixels" == 1024 ]]; then cp "$MASTER" "$target"; else sips -z "$pixels" "$pixels" "$MASTER" --out "$target" >/dev/null; fi
  done
done
iconutil --convert icns "$ICONSET" --output "$WORK/Icon.icns"
mv "$WORK/Icon.icns" "$OUTPUT"
echo "ICON_READY: $OUTPUT"
