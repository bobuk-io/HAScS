#!/usr/bin/env bash
# Offline tests of the release kit: a temporary app tree and landing checkout with local bare
# origins, a stub build and mock gh, npm and curl. They never touch the real repository,
# GitHub, the tap, the landing site, Keychain or the installed apps.
#   Scripts/release/test_kit.sh
set -euo pipefail
KIT_SOURCE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL_GIT=$(command -v git)
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$HOME" "$TMP/bin"
printf '[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' > "$GIT_CONFIG_GLOBAL"
export STATE="$TMP/state" RELEASE_SITE_URL=https://site.invalid RELEASE_FEED_WAIT=0 RELEASE_FEED_INTERVAL=0
export REAL_GIT
unset $("$REAL_GIT" rev-parse --local-env-vars) GIT_CONFIG_SYSTEM RELEASE_T0 RELEASE_TIMING SPARKLE_BIN
# A sentinel landing checkout: an inherited LANDING must never be used.
SENTINEL="$TMP/sentinel"
"$REAL_GIT" init -q --bare "$SENTINEL.git"
(cd "$TMP" && "$REAL_GIT" clone -q "$SENTINEL.git" sentinel 2>/dev/null && cd sentinel \
  && "$REAL_GIT" commit -q --allow-empty -m sentinel && "$REAL_GIT" push -q origin main)
SENTINEL_HEAD=$("$REAL_GIT" -C "$SENTINEL" rev-parse HEAD)
export LANDING="$SENTINEL"
fail() { echo "FAIL: $*" >&2; for f in out err calls.log; do echo "--- $f" >&2; cat "$STATE/$f" >&2 2>/dev/null || true; done; exit 1; }

# Mocks record their calls in $STATE/calls.log.
cat > "$TMP/bin/git" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in commit|push) echo "git[$(basename "$PWD")] $*" >> "$STATE/calls.log" ;; esac
exec "$REAL_GIT" "$@"
MOCK
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "gh $*" >> "$STATE/calls.log"
[[ ! -e "$STATE/gh_fail" ]] || { echo 'gh: network error' >&2; exit 1; }
if [[ $# -eq 5 && "$1 $2 $3 $4" == 'api --paginate repos/test-org/demo/releases?per_page=100 --jq' ]]; then
  # releases.json holds the pages of the API; --paginate applies the filter to each page.
  jq -c '.[]' "$STATE/releases.json" | while IFS= read -r page; do jq -r "$5" <<<"$page"; done
  exit 0
fi
echo "Unexpected gh call: $*" >&2; exit 1
MOCK
cat > "$TMP/bin/npm" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "npm $*" >> "$STATE/calls.log"
# The deploy makes the site feed live.
if [[ "$*" == 'run deploy' && ! -e "$STATE/deploy_broken" ]]; then cp public/apps/demo/appcast.xml "$STATE/live.xml"; fi
MOCK
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
echo "curl ${*: -1}" >> "$STATE/calls.log"
[[ ! -e "$STATE/curl_fail" ]] || exit 22
cat "$STATE/live.xml"
MOCK
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

feed() { printf '<rss><item><sparkle:version>%s</sparkle:version></item></rss>\n' "$1"; }

# A fresh world: Demo 0.7.4 (build 19), release v0.7.4 draft state $1 (empty: none), live feed build $2.
setup() {
  rm -rf "$TMP/w" "$STATE"
  mkdir -p "$TMP/w" "$STATE"
  : > "$STATE/calls.log"
  if [[ -n "$1" ]]; then
    jq -n --argjson draft "$1" '[[{tag_name:"v0.7.4",draft:$draft}]]' > "$STATE/releases.json"
  else
    echo '[[]]' > "$STATE/releases.json"
  fi
  feed "$2" > "$STATE/live.xml"
  APP="$TMP/w/demo" LAND="$TMP/w/landing"
  export LANDING="$LAND"
  mkdir -p "$APP/Scripts/release" "$APP/Sources/DemoCore" "$APP/docs/releases"
  cp "$KIT_SOURCE"/* "$APP/Scripts/release/"
  cat > "$APP/release.env" <<'ENV'
APP_NAME="Demo App"
APP_EXECUTABLE=Demo
BUNDLE_ID=io.bobuk.demo
ARCHIVE_PREFIX=Demo
CHECKSUMS_FILE=SHA256SUMS.txt
GITHUB_REPO=test-org/demo
LANDING_SLUG=demo
SPARKLE_ACCOUNT=io.bobuk.demo
SPARKLE_PUBLIC_KEY=test-key
GITHUB_APPCAST=1
HOMEBREW_CASK=demo
VERSION_SWIFT_FILE=Sources/DemoCore/DemoVersion.swift
VERSION_SWIFT_PREFIX='marketing = "'
ENV
  cat > "$APP/Scripts/release/build.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "build.sh $*" >> "$STATE/calls.log"
[[ ! -e "$STATE/build_fail" ]] || { echo 'Notarization was not accepted (Invalid).' >&2; exit 1; }
source version.env
mkdir -p dist
echo "archive $MARKETING_VERSION" > "dist/Demo-${MARKETING_VERSION}-universal.zip"
(cd dist && shasum -a 256 "Demo-${MARKETING_VERSION}-universal.zip" > SHA256SUMS.txt)
printf '<rss><item><sparkle:version>%s</sparkle:version></item></rss>\n' "$BUILD_NUMBER" > dist/appcast.xml
STUB
  cat > "$APP/Scripts/release/publish.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
echo "publish.sh $*" >> "$STATE/calls.log"
[[ "$(git rev-parse HEAD)" == "$(git ls-remote origin refs/heads/main | cut -f1)" ]] || { echo 'not pushed' >&2; exit 1; }
cp dist/appcast.xml "$LANDING/public/apps/demo/appcast.xml"
source version.env
jq --arg tag "v$MARKETING_VERSION" '[[{tag_name:$tag,draft:false}]] + .' "$STATE/releases.json" > "$STATE/releases.new"
mv "$STATE/releases.new" "$STATE/releases.json"
STUB
  cat > "$APP/Scripts/release/homebrew.sh" <<'STUB'
#!/usr/bin/env bash
echo "homebrew.sh $*" >> "$STATE/calls.log"
STUB
  printf '# Version.\nMARKETING_VERSION=0.7.4\nBUILD_NUMBER=19\n' > "$APP/version.env"
  printf 'public enum DemoVersion {\n    public static let marketing = "0.7.4"\n}\n' > "$APP/Sources/DemoCore/DemoVersion.swift"
  echo 'Notes of 0.7.4.' > "$APP/docs/releases/v0.7.4.md"
  printf 'dist/\n' > "$APP/.gitignore"
  mkdir -p "$LAND/public/apps/demo" "$LAND/src/data"
  feed "$2" > "$LAND/public/apps/demo/appcast.xml"
  echo '{}' > "$LAND/src/data/public-repos.json"
  local repo
  for repo in "$APP" "$LAND"; do
    "$REAL_GIT" init -q --bare "$repo.git"
    (cd "$repo" && "$REAL_GIT" init -q && "$REAL_GIT" add -A && "$REAL_GIT" commit -qm init \
      && "$REAL_GIT" remote add origin "$repo.git" && "$REAL_GIT" push -q origin main)
  done
  # A change merged locally, not pushed yet: main is ahead of origin.
  (cd "$APP" && echo change > feature.txt && "$REAL_GIT" add feature.txt && "$REAL_GIT" commit -qm feature)
}
notes() { echo "Notes of $1." > "$APP/docs/releases/v$1.md"; }
run() { (cd "$APP" && LANDING="$LAND" APP_IDENTITY="${APP_IDENTITY-Developer ID Application: Test}" \
  NOTARY_PROFILE="${NOTARY_PROFILE-test}" bash Scripts/release/next.sh "$@" >"$STATE/out" 2>"$STATE/err"); }
version_is() { grep -qx "MARKETING_VERSION=$1" "$APP/version.env" && grep -qx "BUILD_NUMBER=$2" "$APP/version.env" \
  && grep -q "marketing = \"$1\"" "$APP/Sources/DemoCore/DemoVersion.swift"; }
snapshot() {
  SNAP_APP=$(cd "$APP" && "$REAL_GIT" rev-parse HEAD) SNAP_APP_ORIGIN=$("$REAL_GIT" -C "$APP.git" rev-parse main)
  SNAP_LAND=$(cd "$LAND" 2>/dev/null && "$REAL_GIT" rev-parse HEAD || true)
  SNAP_FILES=$(cat "$APP/version.env" "$APP/Sources/DemoCore/DemoVersion.swift")
}
# The run stopped with a message matching $1 and changed nothing.
stopped() {
  if run "${@:2}"; then fail "accepted: $1"; fi
  grep -q -- "$1" "$STATE/err" || fail "no message '$1'"
  [[ "$(cat "$APP/version.env" "$APP/Sources/DemoCore/DemoVersion.swift")" == "$SNAP_FILES" ]] || fail "version changed: $1"
  [[ "$(cd "$APP" && "$REAL_GIT" rev-parse HEAD)" == "$SNAP_APP" ]] || fail "app commit: $1"
  [[ "$("$REAL_GIT" -C "$APP.git" rev-parse main)" == "$SNAP_APP_ORIGIN" ]] || fail "app push: $1"
  [[ "$(cd "$LAND" 2>/dev/null && "$REAL_GIT" rev-parse HEAD || true)" == "$SNAP_LAND" ]] || fail "landing commit: $1"
  if [[ -d "$LAND" && -z "${LANDING_DIRTY:-}" ]]; then
    [[ -z "$(cd "$LAND" && "$REAL_GIT" status --porcelain)" ]] || fail "landing changed: $1"
  fi
  ! grep -Eq '^(build\.sh|publish\.sh|homebrew|npm|git)' "$STATE/calls.log" || fail "a step ran: $1"
}
# The recorded calls hold these lines in this order.
in_order() {
  local pattern line=0 found
  for pattern in "$@"; do
    found=$(tail -n "+$((line + 1))" "$STATE/calls.log" | grep -n -m1 -E -- "$pattern" | cut -d: -f1) \
      || fail "missing in order: $pattern"
    line=$((line + found))
  done
}

# Arguments, credentials and missing notes stop before any change.
setup false 19; notes 0.7.5; snapshot
stopped 'Usage: Scripts/release_next.sh' --dry-run
[[ ! -s "$STATE/calls.log" ]] || fail 'argument run called a command'
APP_IDENTITY='' stopped 'Set APP_IDENTITY'
NOTARY_PROFILE='' stopped 'Set NOTARY_PROFILE'
rm "$APP/docs/releases/v0.7.5.md"
stopped 'docs/releases/v0.7.5.md first'
: > "$APP/docs/releases/v0.7.5.md"
stopped 'docs/releases/v0.7.5.md are empty'

# Other stops before any change.
notes 0.7.5; echo x > "$APP/other.txt"
stopped 'change of other.txt'
rm "$APP/other.txt"
echo y >> "$APP/version.env"; snapshot
stopped 'change of version.env'
setup false 19; notes 0.7.5
(cd "$APP" && "$REAL_GIT" push -q origin main && "$REAL_GIT" reset -q --hard HEAD~1); snapshot
stopped 'behind or diverged'
setup false 19; notes 0.7.5; rm -rf "$LAND"; snapshot
stopped 'No landing checkout'
setup false 19; notes 0.7.5; echo draft > "$LAND/draft.txt"; snapshot
LANDING_DIRTY=1 stopped 'change of draft.txt in'
setup true 19; notes 0.7.5; snapshot
stopped 'draft release v0.7.4'
setup false 19; notes 0.7.5; touch "$STATE/gh_fail"; snapshot
stopped 'Cannot read the GitHub releases'
setup false 19; notes 0.7.5; touch "$STATE/curl_fail"; snapshot
stopped 'Cannot read the live feed'
setup false 19; notes 0.7.5; sed -i '' 's/0.7.4/0.7.3/' "$APP/Sources/DemoCore/DemoVersion.swift"
(cd "$APP" && "$REAL_GIT" commit -qam drift); snapshot
stopped 'does not hold version 0.7.4'

# A published current release beyond the first page of the API is found; two are refused.
others() { jq -n '[range(100) | {tag_name: "v0.0.\(.)", draft: false}]'; }
setup false 19; notes 0.7.5
jq --argjson others "$(others)" '[$others] + .' "$STATE/releases.json" > "$STATE/r" && mv "$STATE/r" "$STATE/releases.json"
run || fail 'run with the release on page 2 failed'
grep -q 'mode new' "$STATE/out" || fail 'release on page 2 not found'
setup false 19; notes 0.7.5
jq '. + .' "$STATE/releases.json" > "$STATE/r" && mv "$STATE/r" "$STATE/releases.json"; snapshot
stopped 'More than one GitHub release has the tag v0.7.4'

# A full new release, in order, with stage times.
setup false 19; notes 0.7.5
run || fail 'good run failed'
version_is 0.7.5 20 || fail 'version not raised to 0.7.5 (build 20)'
in_order '^build\.sh' '^git\[demo\] commit --quiet -m Release Demo App 0\.7\.5$' '^git\[demo\] push origin main$' \
  '^publish\.sh' '^npm run deploy$' '^git\[landing\] commit --quiet -m Demo App 0\.7\.5: update feed$' \
  '^git\[landing\] push origin main$' '^curl https://site\.invalid/apps/demo/\?v=' '^curl https://site\.invalid/apps/demo/appcast\.xml'
grep -q '^RELEASE_DONE: Demo App 0.7.5 (build 20)$' "$STATE/out" || fail 'done line'
grep -q 'Stage times:' "$STATE/out" && grep -q ' total$' "$STATE/out" || fail 'no stage times'
[[ "$(grep -c '^npm ' "$STATE/calls.log")" == 1 ]] || fail 'the landing site was built more than once'
[[ "$(cd "$APP" && "$REAL_GIT" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' ')" == \
  'Sources/DemoCore/DemoVersion.swift docs/releases/v0.7.5.md version.env ' ]] || fail 'release commit files'
[[ "$(cd "$APP" && "$REAL_GIT" rev-parse HEAD)" == "$("$REAL_GIT" -C "$APP.git" rev-parse main)" ]] || fail 'app not pushed'
[[ "$(cd "$LAND" && "$REAL_GIT" rev-parse HEAD)" == "$("$REAL_GIT" -C "$LAND.git" rev-parse main)" ]] || fail 'landing not pushed'
grep -q 'sparkle:version>20<' "$STATE/live.xml" || fail 'feed not deployed'

# A failing build: no commit, no push, no publish; the raised version stays, the next run goes on.
setup false 19; notes 0.7.5; snapshot; touch "$STATE/build_fail"
if run; then fail 'accepted a failing build'; fi
grep -q 'Notarization was not accepted' "$STATE/err" || fail 'message of the build'
version_is 0.7.5 20 || fail 'raised version lost'
[[ "$(cd "$APP" && "$REAL_GIT" rev-parse HEAD)" == "$SNAP_APP" ]] || fail 'commit after failure'
! grep -Eq '^(publish\.sh|npm|git)' "$STATE/calls.log" || fail 'a step ran after failure'
rm "$STATE/build_fail"; : > "$STATE/calls.log"
run || fail 'second run failed'
version_is 0.7.5 20 || fail 'second run raised the version again'
grep -q 'mode build' "$STATE/out" || fail 'second run mode'
in_order '^build\.sh' '^git\[demo\] commit --quiet -m Release Demo App 0\.7\.5$' '^publish\.sh' '^npm run deploy$'

# The tail: published, the live feed lacks the build.
setup false 18
(cd "$APP" && bash Scripts/release/build.sh) && : > "$STATE/calls.log"
cp "$APP/dist/appcast.xml" "$LAND/public/apps/demo/appcast.xml"
echo '{"x":1}' > "$LAND/src/data/public-repos.json"
run || fail 'tail run failed'
version_is 0.7.4 19 || fail 'tail raised the version'
! grep -Eq '^(build|publish)\.sh' "$STATE/calls.log" || fail 'tail built or published'
cmp -s "$APP/dist/appcast.xml" "$STATE/live.xml" || fail 'tail did not deploy the appcast'
in_order '^homebrew\.sh --publish$' '^npm run deploy$' '^git\[landing\] commit --quiet -m Demo App 0\.7\.4: update feed$' \
  '^git\[landing\] push origin main$'
grep -q '^RELEASE_DONE: Demo App 0.7.4 (build 19)$' "$STATE/out" || fail 'tail done line'

# The tail stops when the manifest does not list this archive or its digest differs.
setup false 18; (cd "$APP" && bash Scripts/release/build.sh) && : > "$STATE/calls.log"
echo other > "$APP/dist/other.txt"
(cd "$APP/dist" && shasum -a 256 other.txt > SHA256SUMS.txt); snapshot
stopped 'has no entry for Demo-0.7.4-universal.zip'
(cd "$APP/dist" && shasum -a 256 Demo-0.7.4-universal.zip other.txt > SHA256SUMS.txt)
echo corrupted >> "$APP/dist/Demo-0.7.4-universal.zip"
stopped 'does not match dist/Demo-0.7.4-universal.zip'

# A feed that never goes live fails the run and names the way to finish.
setup false 19; notes 0.7.5; touch "$STATE/deploy_broken"
if run; then fail 'accepted a feed that never went live'; fi
grep -q 'still has no build 20' "$STATE/err" || fail 'feed timeout message'
grep -q 'Scripts/release/landing.sh' "$STATE/err" || fail 'no way to finish named'

# An app without Sparkle, Homebrew or landing page: published means "new".
setup false 19; notes 0.7.5
sed -i '' -E '/^(SPARKLE_|GITHUB_APPCAST|HOMEBREW_|LANDING_SLUG|VERSION_SWIFT)/d' "$APP/release.env"
(cd "$APP" && "$REAL_GIT" commit -qam plain)
touch "$STATE/curl_fail"
run || fail 'plain app run failed'
grep -q 'mode new' "$STATE/out" || fail 'plain app mode'
! grep -Eq '^(npm|curl|homebrew)' "$STATE/calls.log" || fail 'plain app used the site or the tap'
grep -qx 'MARKETING_VERSION=0.7.5' "$APP/version.env" || fail 'plain app version'

[[ "$("$REAL_GIT" -C "$SENTINEL" rev-parse HEAD)" == "$SENTINEL_HEAD" \
  && "$("$REAL_GIT" -C "$SENTINEL.git" rev-parse main)" == "$SENTINEL_HEAD" \
  && -z "$("$REAL_GIT" -C "$SENTINEL" status --porcelain)" ]] || fail 'the inherited LANDING checkout was touched'
echo 'release_next tests passed.'

bash "$KIT_SOURCE/test_publish.sh"
bash "$KIT_SOURCE/test_install.sh"
echo 'KIT_TESTS_PASSED'
