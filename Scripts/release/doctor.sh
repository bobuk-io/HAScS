#!/usr/bin/env bash
# Read-only check that this repository is ready for Scripts/release_next.sh: configuration,
# tools, signing identity, notarization profile, Sparkle key, GitHub access and the landing
# checkout. It builds, signs, uploads and changes nothing.
#   APP_IDENTITY=... NOTARY_PROFILE=... Scripts/release/doctor.sh
source "$(dirname "$0")/common.sh"
read_version
problems=0
ok() { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; problems=$((problems + 1)); }
check() { local label=$1; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi; }

echo "$APP_NAME $MARKETING_VERSION ($BUILD_NUMBER), bundle $BUNDLE_ID"
check "Scripts/package_app.sh is executable" test -x Scripts/package_app.sh
[[ -z "$BUNDLE_CHECK" ]] || check "$BUNDLE_CHECK exists" test -f "$BUNDLE_CHECK"
[[ -z "$HOMEBREW_CASK" ]] || check "Scripts/homebrew_cask.rb has @VERSION@ and @SHA256@" \
  bash -c 'grep -q @VERSION@ Scripts/homebrew_cask.rb && grep -q @SHA256@ Scripts/homebrew_cask.rb'
[[ -z "$VERSION_SWIFT_FILE" ]] || check "$VERSION_SWIFT_FILE holds $MARKETING_VERSION" \
  grep -qF "${VERSION_SWIFT_PREFIX}${MARKETING_VERSION}\"" "$VERSION_SWIFT_FILE"
for tool in swift xcrun codesign lipo ditto shasum jq; do check "tool $tool" command -v "$tool"; done

if [[ -n "${APP_IDENTITY:-}" ]]; then
  check "signing identity \"$APP_IDENTITY\" in Keychain" bash -c 'security find-identity -v -p codesigning | grep -qF "\"$0\""' "$APP_IDENTITY"
else
  bad "APP_IDENTITY is not set"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  check "notarytool profile $NOTARY_PROFILE" xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json
else
  bad "NOTARY_PROFILE is not set"
fi
[[ -z "$SPARKLE_ACCOUNT" ]] || check "Sparkle tools and Keychain key ($SPARKLE_ACCOUNT)" bash "$KIT/appcast.sh" --check

if [[ -n "$GITHUB_REPO" ]]; then
  check "git checkout on main" bash -c '[[ "$(git symbolic-ref --short -q HEAD)" == main ]]'
  check "GitHub access to $GITHUB_REPO" gh api "repos/$GITHUB_REPO" --jq .full_name
  check "docs/releases exists" test -d docs/releases
  [[ -z "$HOMEBREW_CASK" ]] || check "GitHub access to $HOMEBREW_TAP_REPO" gh api "repos/$HOMEBREW_TAP_REPO" --jq .full_name
else
  ok "no GITHUB_REPO: local signed builds only (Scripts/release.sh)"
fi
if [[ -n "$LANDING_SLUG" ]]; then
  check "landing checkout at $LANDING" git -C "$LANDING" rev-parse --show-toplevel
  check "landing page src/data/apps/$LANDING_SLUG.ts" test -f "$LANDING/src/data/apps/$LANDING_SLUG.ts"
  check "tool npm" command -v npm
fi
CANON="$ROOT/../ting"
if [[ -x "$CANON/Scripts/release/sync_kit.sh" && "$(cd "$CANON" && pwd)" != "$ROOT" ]]; then
  check "kit matches the canonical copy in ../ting" bash "$CANON/Scripts/release/sync_kit.sh" --check "$ROOT"
fi
if ((problems > 0)); then echo "DOCTOR: $problems problem(s)"; exit 1; fi
echo "DOCTOR: ready"
