#!/usr/bin/env bash
# Generate a signed Sparkle appcast for one already notarized release archive.
# The EdDSA private key stays in the login Keychain under SPARKLE_ACCOUNT. Never export,
# commit or upload it.
#   Scripts/release/appcast.sh          sign dist/<ARCHIVE_PREFIX>-<version>-universal.zip
#   Scripts/release/appcast.sh --check  only check the tools, the Keychain key and the notes
source "$(dirname "$0")/common.sh"
read_version

[[ -n "$SPARKLE_ACCOUNT" && -n "$SPARKLE_PUBLIC_KEY" ]] || die "release.env has no Sparkle account or public key."
[[ -n "$GITHUB_REPO" && -n "$LANDING_SLUG" ]] || die "Sparkle needs GITHUB_REPO and LANDING_SLUG in release.env."
[[ -x "$SPARKLE_BIN/generate_appcast" && -x "$SPARKLE_BIN/generate_keys" ]] || \
  die "Sparkle tools missing: set SPARKLE_BIN to the bin directory of the verified Sparkle 2.10.1 release."
ACTUAL=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
[[ "$ACTUAL" == "$SPARKLE_PUBLIC_KEY" ]] || die "Sparkle Keychain public key mismatch; refusing to create an unusable appcast."
[[ -f "$NOTES" ]] || die "Missing release notes $NOTES."
if [[ "${1:-}" == --check ]]; then
  echo "APPCAST_TOOLS_READY"
  exit 0
fi
[[ $# -eq 0 ]] || die "Usage: Scripts/release/appcast.sh [--check]"
[[ -f "$ZIP" ]] || die "Missing $ZIP."

TMP=$(mktemp -d "${TMPDIR:-/tmp}/release-appcast.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cp "$ZIP" "$TMP/"
# Sparkle shows Markdown notes that share the archive's base name.
cp "$NOTES" "$TMP/${ARCHIVE%.zip}.md"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/$TAG/" \
  --link "$SITE_URL/apps/$LANDING_SLUG/" "$TMP"
[[ -f "$TMP/appcast.xml" ]] || die "No appcast was generated."
grep -q "sparkle:version>${BUILD_NUMBER}<" "$TMP/appcast.xml" || die "The appcast does not contain build $BUILD_NUMBER."
cp "$TMP/appcast.xml" "$DIST/appcast.xml"
echo "APPCAST_READY: $DIST/appcast.xml"
