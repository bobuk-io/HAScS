#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Adapted from dimillian/skills; see THIRD_PARTY_NOTICES.md for license terms.
#
# Build, sign, notarize, staple and check a universal release, write the ZIP, the checksums
# and (with Sparkle) the signed appcast to dist/, then install the release in INSTALL_DIR and
# restart it. Publishing is a separate step: Scripts/release/publish.sh.
#
# The full test suite runs in the background, in its own scratch path, while the app builds
# and Apple notarizes it. Nothing is installed or published unless the tests pass.
# Set RELEASE_SERIAL_TESTS=1 to run the tests first instead.
source "$(dirname "$0")/common.sh"
read_version

: "${APP_IDENTITY:?Set APP_IDENTITY to a Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a saved notarytool Keychain profile}"
[[ $# -eq 0 ]] || die "Usage: Scripts/release.sh (it takes no arguments)"
mkdir -p "$DIST"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/release-notary.XXXXXX")
TESTS_PID=""
cleanup() {
  if [[ -n "$TESTS_PID" ]] && kill -0 "$TESTS_PID" 2>/dev/null; then kill "$TESTS_PID" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

stage "Preflight: $APP_NAME $MARKETING_VERSION ($BUILD_NUMBER)"
# Credentials stay inside Keychain; check them before an expensive build.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null \
  || die "notarytool cannot use the Keychain profile $NOTARY_PROFILE."
if [[ -n "$GITHUB_REPO" || -n "$SPARKLE_ACCOUNT" ]]; then
  [[ -f "$NOTES" ]] || die "Write the release notes $NOTES first."
fi
if [[ -n "$SPARKLE_ACCOUNT" ]]; then bash "$KIT/appcast.sh" --check; fi

TEST_LOG="$DIST/tests.log"
TEST_COMMAND=(swift test --scratch-path "$ROOT/.build/release-tests")
# shellcheck disable=SC2206
if [[ -n "$TEST_ARGS" ]]; then TEST_COMMAND+=($TEST_ARGS); fi
# swift test, then the app's other suites (EXTRA_TESTS, run with bash -c).
run_tests() {
  "${TEST_COMMAND[@]}" || return 1
  if [[ -n "$EXTRA_TESTS" ]]; then bash -c "$EXTRA_TESTS" || return 1; fi
}
if [[ "${RELEASE_SERIAL_TESTS:-0}" == 1 ]]; then
  stage "Tests"
  run_tests </dev/null >"$TEST_LOG" 2>&1 || { tail -40 "$TEST_LOG" >&2; die "Tests failed; see $TEST_LOG."; }
else
  stage "Tests started in the background (log: dist/tests.log)"
  # No terminal for the tests: a test that starts an interactive shell must not stop on SIGTTOU.
  run_tests </dev/null >"$TEST_LOG" 2>&1 &
  TESTS_PID=$!
fi

stage "Build universal app ($ARCHES)"
ARCHES="$ARCHES" SIGNING_MODE=developer-id APP_IDENTITY="$APP_IDENTITY" APP_OUTPUT_DIR="$DIST" \
  "$ROOT/Scripts/package_app.sh" release
[[ -d "$APP_BUNDLE" ]] || die "Scripts/package_app.sh did not create $APP_BUNDLE."

stage "Check the signed bundle"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
# One architecture per call: newer lipo refuses several after -verify_arch.
for ARCH in $ARCHES; do lipo "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE" -verify_arch "$ARCH"; done
ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")
SHORT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")
[[ "$ID" == "$BUNDLE_ID" ]] || die "The bundle identifier is $ID, not $BUNDLE_ID."
[[ "$SHORT" == "$MARKETING_VERSION" && "$BUILD" == "$BUILD_NUMBER" ]] \
  || die "The bundle is $SHORT ($BUILD), version.env says $MARKETING_VERSION ($BUILD_NUMBER)."
run_bundle_check "$APP_BUNDLE"
swift "$KIT/check_privacy.swift" "$APP_BUNDLE"

stage "Notarize (Apple)"
/usr/bin/ditto --norsrc -c -k --keepParent "$APP_BUNDLE" "$WORK/Notarize.zip"
xcrun notarytool submit "$WORK/Notarize.zip" --keychain-profile "$NOTARY_PROFILE" \
  --wait --output-format json >"$DIST/notarization.json"
STATUS=$(/usr/bin/plutil -extract status raw -o - "$DIST/notarization.json")
if [[ "$STATUS" != "Accepted" ]]; then
  SUBMISSION=$(/usr/bin/plutil -extract id raw -o - "$DIST/notarization.json")
  xcrun notarytool log "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" >"$DIST/notarization-log.json" || true
  die "Notarization was not accepted ($STATUS). See dist/notarization-log.json."
fi

stage "Staple and check Gatekeeper"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
swift "$KIT/check_privacy.swift" "$APP_BUNDLE"

stage "Archive"
rm -f "$ZIP"
/usr/bin/ditto --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP"
(cd "$DIST" && shasum -a 256 "$ARCHIVE" >"$CHECKSUMS_FILE")
if [[ -n "$SPARKLE_ACCOUNT" ]]; then
  stage "Sign the appcast (Sparkle)"
  # Sign the final archive. Do not modify the ZIP after this point.
  bash "$KIT/appcast.sh"
fi

if [[ -n "$TESTS_PID" ]]; then
  stage "Wait for the tests"
  if ! wait "$TESTS_PID"; then
    TESTS_PID=""
    tail -40 "$TEST_LOG" >&2
    die "Tests failed; see $TEST_LOG. Nothing was installed or published."
  fi
  TESTS_PID=""
fi
if grep -q 'warning:' "$TEST_LOG"; then note "The tests printed compiler warnings; see $TEST_LOG."; fi

stage "Install in $INSTALL_DIR and restart"
bash "$KIT/install.sh" "$APP_BUNDLE"
echo "RELEASE_READY: $ZIP"
