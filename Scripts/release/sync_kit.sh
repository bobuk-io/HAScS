#!/usr/bin/env bash
# Copy the release kit from this repository into other app repositories, or check that their
# copies match. The kit is Scripts/release/ and the four entry points in Scripts/. App facts
# (release.env, version.env, Scripts/package_app.sh, Scripts/homebrew_cask.rb,
# Scripts/check_bundle.swift) are never touched.
#   Scripts/release/sync_kit.sh <repo>...          copy the kit
#   Scripts/release/sync_kit.sh --check <repo>...  exit 1 when a copy differs
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
CHECK=false
if [[ "${1:-}" == --check ]]; then CHECK=true; shift; fi
[[ $# -gt 0 ]] || { echo "Usage: Scripts/release/sync_kit.sh [--check] <repo>..." >&2; exit 2; }

FILES=(Scripts/release_next.sh Scripts/release.sh Scripts/publish.sh Scripts/install.sh)
while IFS= read -r file; do FILES+=("${file#"$SOURCE"/}"); done < <(find "$SOURCE/Scripts/release" -type f ! -name '.*' | sort)

status=0
for repo in "$@"; do
  repo=$(cd "$repo" && pwd)
  [[ "$repo" != "$SOURCE" ]] || continue
  [[ -f "$repo/release.env" ]] || { echo "$repo: no release.env; write it first (see Scripts/release/README.md)." >&2; status=1; continue; }
  if [[ "$CHECK" == true ]]; then
    for file in "${FILES[@]}"; do
      cmp -s "$SOURCE/$file" "$repo/$file" || { echo "$repo: $file differs from the kit." >&2; status=1; }
    done
    # Files that the kit no longer has.
    while IFS= read -r extra; do
      rel=${extra#"$repo"/}
      [[ -f "$SOURCE/$rel" ]] || { echo "$repo: $rel is not in the kit." >&2; status=1; }
    done < <(find "$repo/Scripts/release" -type f ! -name '.*' 2>/dev/null | sort)
  else
    rm -rf "$repo/Scripts/release"
    for file in "${FILES[@]}"; do
      mkdir -p "$repo/$(dirname "$file")"
      cp "$SOURCE/$file" "$repo/$file"
      if [[ "$file" == *.sh && "$file" != */common.sh ]]; then chmod +x "$repo/$file"; fi
    done
    echo "KIT_SYNCED: $repo"
  fi
done
[[ "$CHECK" == false || "$status" -ne 0 ]] || echo "KIT_MATCHES: $*"
exit "$status"
