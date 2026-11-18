#!/usr/bin/env bash
# Publish the landing site after a release: deploy bobuk.io (npm run deploy syncs the public
# repositories, builds, tests, copies the site and checks the main pages), commit and push the
# landing checkout, then check the app page and, with Sparkle, wait until the live feed has
# this build. Run again on its own to finish a release whose landing step failed.
source "$(dirname "$0")/common.sh"
read_version
[[ $# -eq 0 ]] || die "Usage: Scripts/release/landing.sh (it takes no arguments)"
[[ -n "$LANDING_SLUG" ]] || die "release.env has no LANDING_SLUG: this app has no landing page."
need npm git curl

[[ -d "$LANDING" ]] || die "No landing checkout at $LANDING; set LANDING to its checkout."
LANDING=$(cd "$LANDING" && pwd -P)
[[ "$(git -C "$LANDING" rev-parse --show-toplevel 2>/dev/null || true)" == "$LANDING" ]] || die "$LANDING is not a git checkout."
[[ "$(git -C "$LANDING" symbolic-ref --short -q HEAD || true)" == main ]] || die "Check out branch main in $LANDING."
# Only the files of a release may be uncommitted: the feed and the repository snapshot.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  path=${line:3}
  [[ "$path" == "$SITE_FEED_PATH" || "$path" == src/data/public-repos.json ]] && continue
  die "Commit or remove the change of $path in $LANDING first."
done < <(git -C "$LANDING" status --porcelain=v1 -uall)
if [[ -n "$FEED_URL" ]]; then
  grep -q "sparkle:version>${BUILD_NUMBER}<" "$LANDING/$SITE_FEED_PATH" 2>/dev/null \
    || die "$LANDING/$SITE_FEED_PATH has no build $BUILD_NUMBER; run Scripts/publish.sh first."
fi

stage "Landing site: deploy bobuk.io"
(cd "$LANDING" && npm run deploy)

stage "Landing site: commit and push"
(
  cd "$LANDING"
  git add -A
  if ! git diff --cached --quiet; then
    if [[ -n "$FEED_URL" ]]; then MESSAGE="$APP_NAME $MARKETING_VERSION: update feed"
    else MESSAGE="$APP_NAME $MARKETING_VERSION: sync release"; fi
    git commit --quiet -m "$MESSAGE"
  fi
  git push origin main
)

stage "Check the live site"
PAGE="$SITE_URL/apps/$LANDING_SLUG/"
curl -fsS --max-time 30 -o /dev/null "$PAGE?v=$(date +%s)" || die "$PAGE does not answer with HTTP 200."
if [[ -n "$FEED_URL" ]]; then
  WAIT=${RELEASE_FEED_WAIT:-120} INTERVAL=${RELEASE_FEED_INTERVAL:-10}
  DEADLINE=$((SECONDS + WAIT))
  until curl -fsSL --max-time 30 "$FEED_URL?v=$(date +%s)" 2>/dev/null | grep -q "sparkle:version>${BUILD_NUMBER}<"; do
    ((SECONDS < DEADLINE)) || die "The live feed $FEED_URL still has no build $BUILD_NUMBER after ${WAIT}s."
    sleep "$INTERVAL"
  done
fi
echo "LANDING_DONE: $PAGE"
