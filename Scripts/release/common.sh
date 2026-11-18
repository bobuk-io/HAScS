# Shared helpers of the bobuk.io release kit. Sourced by the other kit scripts, never run.
# The kit is identical in every app repository; app facts live in release.env and version.env.
# Canonical copy: ting/Scripts/release. Copy changes with Scripts/release/sync_kit.sh.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
KIT="$ROOT/Scripts/release"

die() { echo "release: $*" >&2; exit 1; }
note() { echo "release: $*"; }

[[ -f release.env ]] || die "No release.env in $ROOT."
[[ -f version.env ]] || die "No version.env in $ROOT."
# shellcheck source=/dev/null
source ./release.env

: "${APP_NAME:?Set APP_NAME in release.env}"
: "${BUNDLE_ID:?Set BUNDLE_ID in release.env}"
APP_EXECUTABLE=${APP_EXECUTABLE:-$APP_NAME}
LEGACY_BUNDLE_IDS=${LEGACY_BUNDLE_IDS:-}
ARCHIVE_PREFIX=${ARCHIVE_PREFIX:-${APP_NAME// /}}
CHECKSUMS_FILE=${CHECKSUMS_FILE:-SHA256SUMS.txt}
INSTALL_DIR=${INSTALL_DIR:-/Applications}
GITHUB_REPO=${GITHUB_REPO:-}
LANDING_SLUG=${LANDING_SLUG:-}
SPARKLE_ACCOUNT=${SPARKLE_ACCOUNT:-}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-}
GITHUB_APPCAST=${GITHUB_APPCAST:-0}
HOMEBREW_CASK=${HOMEBREW_CASK:-}
HOMEBREW_TAP_REPO=${HOMEBREW_TAP_REPO:-bobuk-io/homebrew-tap}
TEST_ARGS=${TEST_ARGS:-}
EXTRA_TESTS=${EXTRA_TESTS:-}
VERSION_SWIFT_FILE=${VERSION_SWIFT_FILE:-}
VERSION_SWIFT_PREFIX=${VERSION_SWIFT_PREFIX:-}
BUNDLE_CHECK=${BUNDLE_CHECK:-}
ARCHES=${RELEASE_ARCHES:-arm64 x86_64}

SITE_URL=${RELEASE_SITE_URL:-https://bobuk.io}
LANDING=${LANDING:-"$ROOT/../landing"}
DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
SPARKLE_BIN=${SPARKLE_BIN:-"$ROOT/.build/sparkle-tools/bin"}
FEED_URL=""
if [[ -n "$SPARKLE_ACCOUNT" && -n "$LANDING_SLUG" ]]; then
  FEED_URL=${RELEASE_FEED_URL:-"$SITE_URL/apps/$LANDING_SLUG/appcast.xml"}
fi
SITE_FEED_PATH="public/apps/$LANDING_SLUG/appcast.xml"

# MARKETING_VERSION and BUILD_NUMBER, read without sourcing anything else from version.env.
read_version() {
  MARKETING_VERSION=$(sed -n -E 's/^MARKETING_VERSION=([^[:space:]]*)$/\1/p' version.env)
  BUILD_NUMBER=$(sed -n -E 's/^BUILD_NUMBER=([^[:space:]]*)$/\1/p' version.env)
  [[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION in version.env is not X.Y.Z."
  [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "BUILD_NUMBER in version.env is not a number."
  TAG="v$MARKETING_VERSION"
  NOTES="docs/releases/$TAG.md"
  ARCHIVE="$ARCHIVE_PREFIX-$MARKETING_VERSION-universal.zip"
  ZIP="$DIST/$ARCHIVE"
}

# The app-specific check of a built bundle: a Swift or Python script, or an executable.
run_bundle_check() {
  [[ -n "$BUNDLE_CHECK" ]] || return 0
  case "$BUNDLE_CHECK" in
    *.swift) swift "$ROOT/$BUNDLE_CHECK" "$1" ;;
    *.py) python3 -I "$ROOT/$BUNDLE_CHECK" "$1" ;;
    *) "$ROOT/$BUNDLE_CHECK" "$1" ;;
  esac
}

# The bundle identifiers that an installed copy may have: this one and older ones.
known_bundle_ids() { echo "$BUNDLE_ID $LEGACY_BUNDLE_IDS"; }

# Stage lines with the time since the start of the whole release; release_next prints the totals.
stage() {
  local now
  now=$(date +%s)
  export RELEASE_T0=${RELEASE_T0:-$now}
  local elapsed=$((now - RELEASE_T0))
  printf '==> [%02d:%02d] %s\n' $((elapsed / 60)) $((elapsed % 60)) "$*"
  if [[ -n "${RELEASE_TIMING:-}" ]]; then printf '%s\t%s\n' "$now" "$*" >> "$RELEASE_TIMING"; fi
}

timing_summary() {
  [[ -s "${RELEASE_TIMING:-}" ]] || return 0
  echo "Stage times:"
  awk -F '\t' -v end="$(date +%s)" '
    { t[NR] = $1; name[NR] = $2 }
    END {
      for (i = 1; i <= NR; i++) {
        stop = (i < NR) ? t[i + 1] : end
        printf "  %4ds  %s\n", stop - t[i], name[i]
      }
      printf "  %4ds  total\n", end - t[1]
    }' "$RELEASE_TIMING"
}

need() {
  local tool
  for tool in "$@"; do command -v "$tool" >/dev/null || die "The command $tool is required."; done
}
