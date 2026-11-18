#!/usr/bin/env bash
# Offline tests of Scripts/release/install.sh: a temporary INSTALL_DIR and mock codesign, xcrun,
# spctl, swift and open. Run by test_kit.sh; never touches installed apps.
set -euo pipefail
KIT_SOURCE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/app" APPS="$TMP/My Apps"
mkdir -p "$APP/Scripts/release" "$TMP/bin"
cp "$KIT_SOURCE"/*.sh "$KIT_SOURCE"/*.swift "$APP/Scripts/release/"
cat > "$APP/release.env" <<ENV
APP_NAME="Demo App"
BUNDLE_ID=io.bobuk.demo
LEGACY_BUNDLE_IDS=com.bobuk.demo
INSTALL_DIR="$APPS"
ENV
printf 'MARKETING_VERSION=1.2.3\nBUILD_NUMBER=19\n' > "$APP/version.env"
bundle() { # bundle <path> <id> <version>
  mkdir -p "$1/Contents"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" -c "Add :CFBundleShortVersionString string $3" \
    "$1/Contents/Info.plist" >/dev/null
}
for tool in codesign xcrun spctl; do printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$tool"; done
# swift: the privacy check passes; the "did it start" script fails when asked to.
cat > "$TMP/bin/swift" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == -e && -n "${RELEASE_DEST:-}" && -e "$STATE_DIR/no_start" ]]; then exit 1; fi
exit 0
MOCK
printf '#!/bin/sh\necho "open $*" >> "$STATE_DIR/opened"\n' > "$TMP/bin/open"
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" STATE_DIR="$TMP"
install_app() { (cd "$APP" && bash Scripts/release/install.sh "$@") >"$TMP/out" 2>&1; }
fail() { echo "FAIL: $*" >&2; cat "$TMP/out" >&2; exit 1; }
version_of() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APPS/Demo App.app/Contents/Info.plist"; }

bundle "$TMP/new/Demo App.app" io.bobuk.demo 1.2.3
install_app "$TMP/new/Demo App.app" || fail 'fresh install into a missing folder with a space'
[[ "$(version_of)" == 1.2.3 ]] || fail 'fresh install version'
grep -q 'INSTALLED_AND_RUNNING' "$TMP/out" || fail 'no installed line'

# An older copy with the legacy identifier is replaced.
rm -rf "$APPS/Demo App.app"; bundle "$APPS/Demo App.app" com.bobuk.demo 1.0.0
install_app "$TMP/new/Demo App.app" || fail 'legacy identifier not replaced'
[[ "$(version_of)" == 1.2.3 ]] || fail 'legacy replacement version'

# A copy that does not start: the previous one comes back.
rm -rf "$APPS/Demo App.app"; bundle "$APPS/Demo App.app" io.bobuk.demo 1.0.0
touch "$TMP/no_start"
if install_app "$TMP/new/Demo App.app"; then fail 'accepted an app that did not start'; fi
[[ "$(version_of)" == 1.0.0 ]] || fail 'previous copy not restored'
grep -q 'Restored the previous installation' "$TMP/out" || fail 'no restore message'
rm "$TMP/no_start"
[[ -z "$(find "$APPS" -name '.DemoApp-install.*' -maxdepth 1)" ]] || fail 'staging folder left behind'

# Refusals change nothing.
bundle "$TMP/other/Demo App.app" io.bobuk.other 9.9.9
if install_app "$TMP/other/Demo App.app"; then fail 'installed an unexpected identifier'; fi
rm -rf "$APPS/Demo App.app"; bundle "$APPS/Demo App.app" io.bobuk.other 1.0.0
if install_app "$TMP/new/Demo App.app"; then fail 'replaced a different app'; fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPS/Demo App.app/Contents/Info.plist")" == io.bobuk.other ]] \
  || fail 'a different app was changed'
rm -rf "$APPS/Demo App.app"; ln -s "$TMP/new/Demo App.app" "$APPS/Demo App.app"
if install_app "$TMP/new/Demo App.app"; then fail 'followed a symbolic link'; fi
echo 'install tests passed.'
