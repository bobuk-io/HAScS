#!/usr/bin/env bash
# Release the next patch version with one command and no arguments: raise the version,
# build and install the release (Scripts/release.sh), commit and push main, publish it
# (Scripts/publish.sh), then deploy the landing site and check it (Scripts/release/landing.sh).
# The mode comes from facts, never from a state file, so a failed run is started again with
# the same command:
#   new    - vV is published (and, with Sparkle, the live feed has build B): raise the version;
#   build  - there is no GitHub release vV: release V again from Scripts/release.sh;
#   tail   - vV is published but the live feed lacks build B: only the steps after the GitHub
#            release run (site feed, Homebrew cask, landing site).
# All checks that can fail run before the first change of any file.
source "$(dirname "$0")/common.sh"

if [[ $# -gt 0 ]]; then
  echo "Usage: Scripts/release_next.sh (it takes no arguments)" >&2
  exit 2
fi
[[ -n "${APP_IDENTITY:-}" ]] || die "Set APP_IDENTITY to a Developer ID Application signing identity."
[[ -n "${NOTARY_PROFILE:-}" ]] || die "Set NOTARY_PROFILE to a saved notarytool Keychain profile."
[[ -n "$GITHUB_REPO" ]] || die "release.env has no GITHUB_REPO: run Scripts/release.sh for a local signed build."
need gh git curl jq
[[ -z "$LANDING_SLUG" ]] || need npm

export RELEASE_TIMING=${RELEASE_TIMING:-$(mktemp "${TMPDIR:-/tmp}/release-timing.XXXXXX")}
trap 'timing_summary' EXIT
stage "Check the state of $APP_NAME"

read_version
CURRENT_VERSION=$MARKETING_VERSION CURRENT_BUILD=$BUILD_NUMBER
if [[ -n "$VERSION_SWIFT_FILE" ]]; then
  grep -qF "${VERSION_SWIFT_PREFIX}${CURRENT_VERSION}\"" "$VERSION_SWIFT_FILE" \
    || die "$VERSION_SWIFT_FILE does not hold version $CURRENT_VERSION of version.env."
fi

[[ "$(git symbolic-ref --short -q HEAD || true)" == main ]] || die "Check out branch main of $APP_NAME."
git fetch --quiet origin
git merge-base --is-ancestor origin/main HEAD || die "main is behind or diverged from origin/main; bring it up to date first."

if [[ -n "$LANDING_SLUG" ]]; then
  [[ -d "$LANDING" ]] || die "No landing checkout at $LANDING; set LANDING to its checkout."
  LANDING=$(cd "$LANDING" && pwd -P)
  [[ "$(cd "$LANDING" && git rev-parse --show-toplevel 2>/dev/null || true)" == "$LANDING" ]] || die "$LANDING is not a git checkout."
  [[ "$(cd "$LANDING" && git symbolic-ref --short -q HEAD || true)" == main ]] || die "Check out branch main in $LANDING."
  export LANDING
fi

# The GitHub release state of vV: empty (none), true (draft) or false (published). All pages
# are read (drafts are listed only here); a failed page fails the whole query.
TAG="v$CURRENT_VERSION"
RELEASE_STATE=$(gh api --paginate "repos/$GITHUB_REPO/releases?per_page=100" \
  --jq ".[] | select(.tag_name == \"$TAG\") | .draft") || die "Cannot read the GitHub releases of $GITHUB_REPO."
[[ "$RELEASE_STATE" != *$'\n'* ]] || die "More than one GitHub release has the tag $TAG."
FEED_HAS_BUILD=true
if [[ -n "$FEED_URL" ]]; then
  FEED=$(curl -fsSL --max-time 30 "$FEED_URL?v=$(date +%s)") || die "Cannot read the live feed $FEED_URL."
  grep -q 'sparkle:version>[0-9]*<' <<<"$FEED" || die "The live feed $FEED_URL has no build number."
  grep -q "sparkle:version>${CURRENT_BUILD}<" <<<"$FEED" || FEED_HAS_BUILD=false
fi
case "$RELEASE_STATE" in
  true) die "A draft release $TAG exists; publish or delete it first." ;;
  false) if [[ "$FEED_HAS_BUILD" == true ]]; then MODE=new; else MODE=tail; fi ;;
  '') MODE=build ;;
  *) die "Unexpected GitHub release state of $TAG: $RELEASE_STATE" ;;
esac
if [[ "$MODE" == new ]]; then
  IFS=. read -r MAJOR MINOR PATCH <<<"$CURRENT_VERSION"
  VERSION="$MAJOR.$MINOR.$((PATCH + 1))" BUILD=$((CURRENT_BUILD + 1))
else
  VERSION=$CURRENT_VERSION BUILD=$CURRENT_BUILD
fi
NOTES="docs/releases/v$VERSION.md"
echo "release_next: mode $MODE, $APP_NAME $VERSION (build $BUILD)."

# The app tree may hold only the files of this release.
case "$MODE" in
  new) ALLOWED=("$NOTES") ;;
  build) ALLOWED=(version.env "$NOTES") ; [[ -z "$VERSION_SWIFT_FILE" ]] || ALLOWED+=("$VERSION_SWIFT_FILE") ;;
  tail) ALLOWED=() ;;
esac
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  path=${line:3} ok=false
  for allowed in ${ALLOWED[@]+"${ALLOWED[@]}"}; do [[ "$path" == "$allowed" ]] && ok=true; done
  [[ "$ok" == true ]] || die "Commit or remove the change of $path in $APP_NAME first."
done < <(git status --porcelain=v1 -uall)
[[ -f "$NOTES" ]] || die "Write the release notes $NOTES first."
grep -q '[^[:space:]]' "$NOTES" || die "The release notes $NOTES are empty."

if [[ -n "$LANDING_SLUG" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path=${line:3}
    if [[ "$MODE" == tail && ( "$path" == "$SITE_FEED_PATH" || "$path" == src/data/public-repos.json ) ]]; then continue; fi
    die "Commit or remove the change of $path in $LANDING first."
  done < <(cd "$LANDING" && git status --porcelain=v1 -uall)
fi

if [[ "$MODE" == tail ]]; then
  read_version
  for file in "$ZIP" "$DIST/$CHECKSUMS_FILE" "$DIST/appcast.xml"; do
    [[ -f "$file" ]] || die "Missing $file of the published release $TAG."
  done
  grep -q "sparkle:version>${BUILD}<" "$DIST/appcast.xml" || die "dist/appcast.xml is not for build $BUILD."
  # The manifest must list this archive, and the archive must have that digest.
  EXPECTED=$(sed -n -E "s/^([0-9a-f]{64})  ${ARCHIVE//./\\.}$/\1/p" "$DIST/$CHECKSUMS_FILE")
  [[ -n "$EXPECTED" && "$EXPECTED" != *$'\n'* ]] || die "dist/$CHECKSUMS_FILE has no entry for $ARCHIVE."
  [[ "$(shasum -a 256 "$ZIP" | cut -d ' ' -f1)" == "$EXPECTED" ]] || die "dist/$CHECKSUMS_FILE does not match dist/$ARCHIVE."
fi

# The checks are done: from here on, files change.
if [[ "$MODE" == new ]]; then
  sed -i '' -E "s/^MARKETING_VERSION=.*/MARKETING_VERSION=${VERSION}/; s/^BUILD_NUMBER=.*/BUILD_NUMBER=${BUILD}/" version.env
  if [[ -n "$VERSION_SWIFT_FILE" ]]; then
    RELEASE_PREFIX="$VERSION_SWIFT_PREFIX" RELEASE_VERSION="$VERSION" \
      perl -pi -e 's/\Q$ENV{RELEASE_PREFIX}\E[0-9]+\.[0-9]+\.[0-9]+"/$ENV{RELEASE_PREFIX}$ENV{RELEASE_VERSION}"/' "$VERSION_SWIFT_FILE"
    grep -qF "${VERSION_SWIFT_PREFIX}${VERSION}\"" "$VERSION_SWIFT_FILE" || die "Could not raise the version in $VERSION_SWIFT_FILE."
  fi
  read_version
  [[ "$MARKETING_VERSION" == "$VERSION" && "$BUILD_NUMBER" == "$BUILD" ]] || die "Could not raise the version in version.env."
  echo "release_next: raised the version to $VERSION (build $BUILD)."
fi

if [[ "$MODE" == tail ]]; then
  if [[ -n "$FEED_URL" ]]; then
    mkdir -p "$LANDING/$(dirname "$SITE_FEED_PATH")"
    cp "$DIST/appcast.xml" "$LANDING/$SITE_FEED_PATH"
  fi
  if [[ -n "$HOMEBREW_CASK" ]]; then stage "Homebrew cask"; bash "$KIT/homebrew.sh" --publish; fi
else
  bash "$KIT/build.sh"
  stage "Commit and push $APP_NAME $VERSION"
  git add -- version.env "$NOTES"
  [[ -z "$VERSION_SWIFT_FILE" ]] || git add -- "$VERSION_SWIFT_FILE"
  if ! git diff --cached --quiet; then git commit --quiet -m "Release $APP_NAME $VERSION"; fi
  git push origin main
  bash "$KIT/publish.sh"
fi

if [[ -n "$LANDING_SLUG" ]]; then
  bash "$KIT/landing.sh" || die "The landing step failed. Fix it, then run Scripts/release/landing.sh or this command again."
fi
stage "Done"
echo "RELEASE_DONE: $APP_NAME $VERSION (build $BUILD)"
