#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Adapted from dimillian/skills; see THIRD_PARTY_NOTICES.md for license terms.
#
# Builds <APP_NAME>.app for every bobuk-io app. Each app's Scripts/package_app.sh only calls this;
# its facts live in release.env and two optional files (see README.md, "Packaging"):
#   Scripts/Info.extra.plist   more Info.plist entries: <key>/<value> lines inside <dict>
#   Scripts/App.entitlements   entitlements of the app (default: none)
# Usage: Scripts/package_app.sh [debug|release]. Honours ARCHES, APP_OUTPUT_DIR, SIGNING_MODE and
# APP_IDENTITY as the release kit contract says.
set -euo pipefail

CONF=${1:-release}
[[ "$CONF" == release || "$CONF" == debug ]] || { echo "Usage: Scripts/package_app.sh [debug|release]" >&2; exit 2; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KIT="$ROOT/Scripts/release"
cd "$ROOT"
# shellcheck source=/dev/null
source ./release.env
# shellcheck source=/dev/null
source ./version.env
: "${APP_NAME:?Set APP_NAME in release.env}"
: "${BUNDLE_ID:?Set BUNDLE_ID in release.env}"
APP_EXECUTABLE=${APP_EXECUTABLE:-$APP_NAME}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-14.0}
PACKAGE_MENU_BAR=${PACKAGE_MENU_BAR:-1}
PACKAGE_CATEGORY=${PACKAGE_CATEGORY:-public.app-category.utilities}
PACKAGE_HELPERS=${PACKAGE_HELPERS:-}
PACKAGE_RESOURCES=${PACKAGE_RESOURCES-LICENSE THIRD_PARTY_NOTICES.md}
PACKAGE_ICON=${PACKAGE_ICON:-}
PACKAGE_REFUSE_RUNNING=${PACKAGE_REFUSE_RUNNING:-0}
PACKAGE_SPARKLE_IN_DEBUG=${PACKAGE_SPARKLE_IN_DEBUG:-0}
SIGNING_MODE=${SIGNING_MODE:-}
APP_IDENTITY=${APP_IDENTITY:-}

read -r -a ARCH_LIST <<<"${ARCHES:-${PACKAGE_ARCHES:-$(uname -m)}}"
OUTPUT_DIR=${APP_OUTPUT_DIR:-"$ROOT/build"}
APP="$OUTPUT_DIR/$APP_NAME.app"

if [[ "$PACKAGE_REFUSE_RUNNING" == 1 ]] && pgrep -f -x "$APP/Contents/MacOS/$APP_EXECUTABLE" >/dev/null; then
  echo "ERROR: $APP is running; quit it before rebuilding." >&2
  exit 1
fi

# Every standard and Retina representation from the committed icon master.
ICON_TARGET="$ROOT/.build/Icon.icns"
mkdir -p "$ROOT/.build"
if [[ -z "$PACKAGE_ICON" ]]; then
  bash "$KIT/icon.sh" "$ROOT/Assets/AppIcon.png" "$ICON_TARGET"
elif [[ "$PACKAGE_ICON" == *.swift ]]; then
  # A Swift renderer writes Icon.icns into the folder it is given.
  swift "$ROOT/$PACKAGE_ICON" "$(dirname "$ICON_TARGET")"
else
  "$ROOT/$PACKAGE_ICON" "$ICON_TARGET"
fi
[[ -f "$ICON_TARGET" ]] || { echo "ERROR: $PACKAGE_ICON did not write $ICON_TARGET" >&2; exit 1; }

# The native build system writes each architecture to .build/<arch>-apple-macosx/<conf>.
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$ARCH" --build-system native
done
product() { echo ".build/$2-apple-macosx/$CONF/$1"; }

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# One binary of every architecture, verified.
install_binary() {
  local name=$1 dest=$2 binaries=() arch
  for arch in "${ARCH_LIST[@]}"; do
    [[ -f "$(product "$name" "$arch")" ]] || { echo "ERROR: Missing $name build for $arch" >&2; exit 1; }
    binaries+=("$(product "$name" "$arch")")
  done
  mkdir -p "$(dirname "$dest")"
  lipo -create "${binaries[@]}" -output "$dest"
  chmod +x "$dest"
  for arch in "${ARCH_LIST[@]}"; do lipo "$dest" -verify_arch "$arch"; done
  [[ "$(lipo -archs "$dest" | wc -w | tr -d ' ')" == "${#ARCH_LIST[@]}" ]] || { echo "ERROR: $dest has extra architectures" >&2; exit 1; }
  # Release builds drop debug-map paths (local home and build paths) before signing.
  if [[ "$CONF" == release ]]; then xcrun strip -S "$dest"; fi
}

install_binary "$APP_EXECUTABLE" "$APP/Contents/MacOS/$APP_EXECUTABLE"
HELPER_PATHS=()
HELPER_IDS=()
for helper in $PACKAGE_HELPERS; do
  IFS=: read -r name folder identifier <<<"$helper"
  install_binary "$name" "$APP/Contents/${folder:-MacOS}/$name"
  HELPER_PATHS+=("$APP/Contents/${folder:-MacOS}/$name")
  HELPER_IDS+=("${identifier:-}")
done

for resource in $PACKAGE_RESOURCES; do cp "$ROOT/$resource" "$APP/Contents/Resources/$(basename "$resource")"; done
# Plain app resources, then SwiftPM resource bundles next to the built binary.
if [[ -d "$ROOT/Sources/$APP_EXECUTABLE/Resources" ]]; then
  cp -R "$ROOT/Sources/$APP_EXECUTABLE/Resources/." "$APP/Contents/Resources/"
fi
shopt -s nullglob
for bundle in "$(dirname "$(product "$APP_EXECUTABLE" "${ARCH_LIST[0]}")")/"*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
FRAMEWORKS=("$(dirname "$(product "$APP_EXECUTABLE" "${ARCH_LIST[0]}")")/"*.framework)
shopt -u nullglob
if [[ ${#FRAMEWORKS[@]} -gt 0 ]]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "${FRAMEWORKS[@]}" "$APP/Contents/Frameworks/"
  chmod -R a+rX "$APP/Contents/Frameworks"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_EXECUTABLE"
fi
cp "$ICON_TARGET" "$APP/Contents/Resources/Icon.icns"

# Only release builds read the update feed unless the app asks otherwise; development copies
# never replace themselves. The feed lives on bobuk.io; the archives stay on GitHub Releases.
SPARKLE_KEYS=""
if [[ -n "${SPARKLE_PUBLIC_KEY:-}" && -n "${LANDING_SLUG:-}" && ( "$CONF" == release || "$PACKAGE_SPARKLE_IN_DEBUG" == 1 ) ]]; then
  SPARKLE_KEYS="    <key>SUFeedURL</key><string>https://bobuk.io/apps/$LANDING_SLUG/appcast.xml</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
"
fi
EXTRA_PLIST=""
[[ -f "$ROOT/Scripts/Info.extra.plist" ]] && EXTRA_PLIST=$(sed -e "s/@BUNDLE_ID@/$BUNDLE_ID/g" "$ROOT/Scripts/Info.extra.plist")
LSUI_VALUE=$([[ "$PACKAGE_MENU_BAR" == 1 ]] && echo true || echo false)
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
[[ -z "$(git status --porcelain 2>/dev/null || true)" ]] || GIT_COMMIT="$GIT_COMMIT-dirty"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_EXECUTABLE}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><${LSUI_VALUE}/>
    <key>LSApplicationCategoryType</key><string>${PACKAGE_CATEGORY}</string>
    <key>NSHighResolutionCapable</key><true/>
${EXTRA_PLIST:+$EXTRA_PLIST
}${SPARKLE_KEYS}    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

ENTITLEMENTS="$ROOT/.build/$APP_EXECUTABLE.entitlements"
if [[ -f "$ROOT/Scripts/App.entitlements" ]]; then
  cp "$ROOT/Scripts/App.entitlements" "$ENTITLEMENTS"
else
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict/>\n</plist>\n' > "$ENTITLEMENTS"
fi

# Writable, without extended attributes or AppleDouble files that break code sealing.
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

if [[ "$SIGNING_MODE" == adhoc || -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --sign -)
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi
# Inside out: framework binaries, frameworks, helpers, then the app.
shopt -s nullglob
for framework in "$APP/Contents/Frameworks/"*.framework; do
  while IFS= read -r -d '' binary; do codesign "${CODESIGN_ARGS[@]}" "$binary"; done \
    < <(find "$framework" -type f -perm -111 -print0)
  codesign "${CODESIGN_ARGS[@]}" "$framework"
done
shopt -u nullglob
for index in "${!HELPER_PATHS[@]}"; do
  if [[ -n "${HELPER_IDS[$index]}" ]]; then
    codesign "${CODESIGN_ARGS[@]}" --identifier "${HELPER_IDS[$index]}" "${HELPER_PATHS[$index]}"
  else
    codesign "${CODESIGN_ARGS[@]}" "${HELPER_PATHS[$index]}"
  fi
done
codesign "${CODESIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP"
echo "Created $APP"
