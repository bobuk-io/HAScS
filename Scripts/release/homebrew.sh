#!/usr/bin/env bash
# Render the Homebrew cask from Scripts/homebrew_cask.rb and the release archive;
# --publish writes it to the tap. Safe to run again on its own if the tap update failed.
#   Scripts/release/homebrew.sh            print the cask
#   Scripts/release/homebrew.sh --publish  update Casks/<HOMEBREW_CASK>.rb in the tap
source "$(dirname "$0")/common.sh"
read_version

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --publish ) ]]; then
  die "Usage: Scripts/release/homebrew.sh [--publish]"
fi
[[ -n "$HOMEBREW_CASK" ]] || die "release.env has no HOMEBREW_CASK."
TEMPLATE="$ROOT/Scripts/homebrew_cask.rb"
[[ -f "$TEMPLATE" ]] || die "Missing the cask template $TEMPLATE."
[[ -f "$ZIP" ]] || die "Missing $ZIP."
SHA256=$(shasum -a 256 "$ZIP" | cut -d ' ' -f1)
CASK=$(sed -e "s/@VERSION@/$MARKETING_VERSION/g" -e "s/@SHA256@/$SHA256/g" "$TEMPLATE")
! grep -q '@[A-Z0-9_]*@' <<<"$CASK" || die "The cask template has an unknown placeholder."
if [[ "${1:-}" != --publish ]]; then
  printf '%s\n' "$CASK"
  exit 0
fi
need gh jq

# Do not point Homebrew at a draft, prerelease, missing or mismatched archive.
RELEASE=$(gh api "repos/$GITHUB_REPO/releases/tags/$TAG")
printf '%s' "$RELEASE" | jq -e --arg name "$ARCHIVE" --arg digest "sha256:$SHA256" \
  '.draft == false and .prerelease == false and any(.assets[]; .name == $name and .digest == $digest)' >/dev/null \
  || die "The published release does not match $ZIP."
ENDPOINT="repos/$HOMEBREW_TAP_REPO/contents/Casks/$HOMEBREW_CASK.rb"
if ! EXISTING=$(gh api "$ENDPOINT"); then
  # A new cask has no file yet. Only an explicit 404 allows creating it; authentication,
  # network and server errors stop here instead of looking like a missing file.
  printf '%s' "$EXISTING" | jq -e '.status == "404"' >/dev/null 2>&1 || die "Cannot read the Homebrew cask."
  EXISTING='{}'
fi
CONTENT=$(printf '%s\n' "$CASK" | base64 | tr -d '\n')
if [[ "$(printf '%s' "$EXISTING" | jq -r '.content // ""' | tr -d '\n')" == "$CONTENT" ]]; then
  echo "Homebrew cask is already up to date."
  exit 0
fi
printf '%s' "$EXISTING" | jq --arg content "$CONTENT" --arg version "$MARKETING_VERSION" --arg cask "$HOMEBREW_CASK" \
  '{message: ("chore(" + $cask + "): update cask to " + $version), content: $content} + (if .sha then {sha: .sha} else {} end)' |
  gh api --method PUT "$ENDPOINT" --input - >/dev/null
echo "HOMEBREW_UPDATED: ${HOMEBREW_TAP_REPO/homebrew-/}/$HOMEBREW_CASK $MARKETING_VERSION"
