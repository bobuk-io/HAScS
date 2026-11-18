#!/usr/bin/env bash
# Offline tests of Scripts/release/publish.sh and homebrew.sh with mock git, gh and curl.
# Run by test_kit.sh; never touches GitHub, the tap or the landing site.
set -euo pipefail
KIT_SOURCE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/app"
mkdir -p "$APP/Scripts/release" "$APP/dist" "$APP/docs/releases" "$TMP/bin" "$TMP/landing/public"
cp "$KIT_SOURCE"/*.sh "$KIT_SOURCE"/*.swift "$APP/Scripts/release/"
cat > "$APP/release.env" <<'ENV'
APP_NAME="Demo App"
BUNDLE_ID=io.bobuk.demo
ARCHIVE_PREFIX=Demo
CHECKSUMS_FILE=SHA256SUMS
GITHUB_REPO=test-org/demo
LANDING_SLUG=demo
SPARKLE_ACCOUNT=io.bobuk.demo
SPARKLE_PUBLIC_KEY=test-key
GITHUB_APPCAST=1
HOMEBREW_CASK=demo
ENV
cat > "$APP/Scripts/homebrew_cask.rb" <<'CASK'
cask "demo" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/test-org/demo/releases/download/v#{version}/Demo-#{version}-universal.zip"
  app "Demo App.app"
end
CASK
printf 'MARKETING_VERSION=1.2.3\nBUILD_NUMBER=19\n' > "$APP/version.env"
printf 'archive\n' > "$APP/dist/Demo-1.2.3-universal.zip"
(cd "$APP/dist" && shasum -a 256 Demo-1.2.3-universal.zip > SHA256SUMS)
printf '<sparkle:version>19</sparkle:version>\n' > "$APP/dist/appcast.xml"
printf 'Release notes\n' > "$APP/docs/releases/v1.2.3.md"
export EVENTS="$TMP/events" LANDING="$TMP/landing" TEST_TMP="$TMP" RELEASE_SITE_URL=https://site.invalid
export TEST_SHA=$(shasum -a 256 "$APP/dist/Demo-1.2.3-universal.zip" | cut -d ' ' -f1)
unset RELEASE_T0 RELEASE_TIMING
cat > "$TMP/bin/git" <<'MOCK'
#!/bin/sh
case "$1" in
  status) exit 0 ;;
  rev-parse) echo test-head ;;
  ls-remote) printf 'test-head\trefs/heads/main\n' ;;
  *) exit 1 ;;
esac
MOCK
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'release view v1.2.3 --repo test-org/demo') exit 1 ;;
  'api repos/test-org/demo/releases/latest')
    if [[ -n "${LATEST:-v1.2.2}" && "${LATEST:-v1.2.2}" != none ]]; then jq -n --arg t "${LATEST:-v1.2.2}" '{tag_name:$t}'
    else echo '{"status":"404"}'; exit 1; fi ;;
  release\ create*) echo draft >> "$EVENTS" ;;
  release\ edit*) echo publish >> "$EVENTS"; exit "${FAIL_EDIT:-0}" ;;
  'api repos/test-org/demo/releases/tags/v1.2.3')
    jq -n --arg digest "sha256:${TEST_DIGEST:-$TEST_SHA}" --argjson draft "${TEST_DRAFT:-false}" \
      '{draft:$draft,prerelease:false,assets:[{name:"Demo-1.2.3-universal.zip",digest:$digest}]}' ;;
  'api repos/bobuk-io/homebrew-tap/contents/Casks/demo.rb')
    if [[ -n "${TEST_STATUS:-}" ]]; then printf '{"status":"%s"}\n' "$TEST_STATUS"; exit 1; fi
    jq -n --arg content "${TEST_CONTENT:-}" '{sha:"test-sha",content:$content}' ;;
  'api --method PUT repos/bobuk-io/homebrew-tap/contents/Casks/demo.rb --input -')
    tee "$TEST_TMP/request.json" >/dev/null; echo cask >> "$EVENTS" ;;
  *) echo "Unexpected gh call: $*" >&2; exit 1 ;;
esac
MOCK
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
while [[ "$1" != -o ]]; do shift; done
case "${*: -1}" in
  https://site.invalid/*) printf '<sparkle:version>%s</sparkle:version>\n' "${SITE_BUILD:-18}" > "$2"; printf '%s' "${SITE_STATUS:-200}" ;;
  *) printf '<sparkle:version>18</sparkle:version>\n' > "$2"; printf '%s' "${GITHUB_STATUS:-200}" ;;
esac
MOCK
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
FEED="$LANDING/public/apps/demo/appcast.xml"
publish() { (cd "$APP" && bash Scripts/release/publish.sh) >"$TMP/out" 2>&1; }
fail() { echo "FAIL: $*" >&2; cat "$TMP/out" >&2; exit 1; }

# Good runs: draft, publish, site feed, cask, in this order. A missing site feed (404) is allowed.
publish || fail 'good publish'
cmp -s "$APP/dist/appcast.xml" "$FEED" || fail 'site feed not copied'
[[ "$(cat "$EVENTS")" == $'draft\npublish\ncask' ]] || fail "order: $(cat "$EVENTS")"
rm -f "$FEED" "$EVENTS" "$TMP/request.json"
SITE_STATUS=404 LATEST=none publish || fail 'first release with no site feed'
rm -f "$FEED" "$EVENTS" "$TMP/request.json"

# Refusals publish nothing and never update the cask.
for scenario in 'SITE_BUILD=20' 'SITE_STATUS=503' 'GITHUB_STATUS=500' 'FAIL_EDIT=1' 'LATEST=v1.2.3' 'LATEST=v1.10.0'; do
  if env "$scenario" bash -c "cd '$APP' && bash Scripts/release/publish.sh" >"$TMP/out" 2>&1; then fail "accepted $scenario"; fi
  [[ ! -f "$FEED" ]] || fail "feed copied: $scenario"
  if [[ -f "$EVENTS" ]]; then ! grep -q cask "$EVENTS" || fail "cask updated: $scenario"; rm "$EVENTS"; fi
done

# The cask: rendered from the template, published only for a matching, published archive.
HB() { (cd "$APP" && bash Scripts/release/homebrew.sh "$@"); }
HB > "$TMP/cask.rb"
grep -q 'version "1.2.3"' "$TMP/cask.rb" && grep -q "sha256 \"$TEST_SHA\"" "$TMP/cask.rb" || fail 'cask render'
HB --publish >/dev/null
jq -e '.sha == "test-sha" and .message == "chore(demo): update cask to 1.2.3"' "$TMP/request.json" >/dev/null || fail 'cask request'
jq -r '.content' "$TMP/request.json" | base64 --decode | cmp -s - "$TMP/cask.rb" || fail 'cask content'
rm "$TMP/request.json"
TEST_CONTENT=$(base64 < "$TMP/cask.rb" | tr -d '\n') HB --publish >/dev/null
[[ ! -e "$TMP/request.json" ]] || fail 'unchanged cask uploaded'
TEST_STATUS=404 HB --publish >/dev/null
jq -e 'has("sha") == false and has("content")' "$TMP/request.json" >/dev/null || fail 'new cask request'
rm "$TMP/request.json"
for scenario in TEST_STATUS=500 TEST_DIGEST=wrong TEST_DRAFT=true; do
  if env "$scenario" bash -c "cd '$APP' && bash Scripts/release/homebrew.sh --publish" >/dev/null 2>&1; then fail "cask accepted $scenario"; fi
done
if HB --invalid >/dev/null 2>&1; then fail 'cask accepted an invalid argument'; fi
[[ ! -e "$TMP/request.json" ]] || fail 'a refused cask was uploaded'
echo 'publish and Homebrew tests passed.'
