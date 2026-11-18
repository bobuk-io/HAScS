#!/usr/bin/env bash
# Publish an already built, notarized and installed release: the GitHub release, then (with
# Sparkle) the appcast in the landing checkout, then (with Homebrew) the cask.
# Run Scripts/release.sh first. The GitHub release is created as a draft, all assets are
# uploaded, and only then is it published, so no feed ever points at a missing archive.
source "$(dirname "$0")/common.sh"
read_version
[[ $# -eq 0 ]] || die "Usage: Scripts/publish.sh (it takes no arguments)"
[[ -n "$GITHUB_REPO" ]] || die "release.env has no GITHUB_REPO: this app is not published."
need gh git curl jq

ASSETS=("$ZIP" "$DIST/$CHECKSUMS_FILE")
[[ -n "$SPARKLE_ACCOUNT" ]] && ASSETS+=("$DIST/appcast.xml")
for file in "${ASSETS[@]}" "$NOTES"; do
  [[ -f "$file" ]] || die "Missing $file. Run Scripts/release.sh first."
done
if [[ -n "$SPARKLE_ACCOUNT" ]]; then
  [[ -d "$LANDING/public" ]] || die "No landing site at $LANDING; set LANDING to its checkout."
  grep -q "sparkle:version>${BUILD_NUMBER}<" "$DIST/appcast.xml" || die "The appcast is not for build $BUILD_NUMBER."
fi
[[ -z "$(git status --porcelain)" ]] || die "Commit changes before publishing."
COMMIT=$(git rev-parse HEAD)
[[ "$COMMIT" == "$(git ls-remote origin refs/heads/main | cut -f1)" ]] || die "Push the release commit to main before publishing."
(cd "$DIST" && shasum -a 256 -c "$CHECKSUMS_FILE")

stage "Check published versions"
gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1 && die "Release $TAG already exists."
# The latest published release; only an explicit 404 means that there is none yet.
if LATEST_JSON=$(gh api "repos/$GITHUB_REPO/releases/latest" 2>/dev/null); then
  LATEST=$(jq -r '.tag_name' <<<"$LATEST_JSON")
else
  jq -e '.status == "404"' >/dev/null 2>&1 <<<"$LATEST_JSON" || die "Cannot read the latest release of $GITHUB_REPO."
  LATEST=""
fi
if [[ -n "$LATEST" ]]; then
  HIGHEST=$(printf '%s\n%s\n' "${LATEST#v}" "$MARKETING_VERSION" | sort -V | tail -1)
  [[ "$HIGHEST" == "$MARKETING_VERSION" && "${LATEST#v}" != "$MARKETING_VERSION" ]] \
    || die "Version $MARKETING_VERSION must be greater than the latest release $LATEST."
fi
if [[ -n "$SPARKLE_ACCOUNT" ]]; then
  # The build number must grow past every published feed. A 404 means no feed yet;
  # any other failure stops, instead of hiding a newer published build.
  PUBLISHED=0
  FEEDS=("$FEED_URL")
  [[ "$GITHUB_APPCAST" == 1 ]] && FEEDS+=("https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml")
  FEED_TMP=$(mktemp)
  trap 'rm -f "$FEED_TMP"' EXIT
  for url in "${FEEDS[@]}"; do
    CODE=$(curl -sS -L --max-time 30 -o "$FEED_TMP" -w '%{http_code}' "$url?v=$(date +%s)") || CODE=000
    case "$CODE" in
      200)
        BUILD=$(grep -o 'sparkle:version>[0-9]*<' "$FEED_TMP" | tr -dc '0-9\n' | sort -n | tail -1)
        [[ -n "$BUILD" ]] || die "Cannot read the build number of $url."
        ((BUILD > PUBLISHED)) && PUBLISHED=$BUILD ;;
      404) ;;
      *) die "Cannot check the feed $url: HTTP $CODE." ;;
    esac
  done
  ((BUILD_NUMBER > PUBLISHED)) || die "BUILD_NUMBER=$BUILD_NUMBER must be greater than the published $PUBLISHED."
fi

stage "GitHub release $TAG"
GH_ASSETS=("$ZIP" "$DIST/$CHECKSUMS_FILE")
[[ -n "$SPARKLE_ACCOUNT" && "$GITHUB_APPCAST" == 1 ]] && GH_ASSETS+=("$DIST/appcast.xml")
gh release create "$TAG" --repo "$GITHUB_REPO" --target "$COMMIT" --draft \
  --title "$APP_NAME $MARKETING_VERSION" --notes-file "$NOTES" "${GH_ASSETS[@]}"
gh release edit "$TAG" --repo "$GITHUB_REPO" --draft=false --latest
echo "PUBLISHED: $TAG on GitHub Releases."

if [[ -n "$SPARKLE_ACCOUNT" ]]; then
  # The archive is public now: the site feed may point at it.
  mkdir -p "$LANDING/$(dirname "$SITE_FEED_PATH")"
  cp "$DIST/appcast.xml" "$LANDING/$SITE_FEED_PATH"
  echo "FEED_READY: $LANDING/$SITE_FEED_PATH"
fi
if [[ -n "$HOMEBREW_CASK" ]]; then
  stage "Homebrew cask"
  # The cask refers only to an already published, checksum-verified archive.
  # Retry on its own with Scripts/release/homebrew.sh --publish if this fails.
  bash "$KIT/homebrew.sh" --publish
fi
