#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Adapted from dimillian/skills; see THIRD_PARTY_NOTICES.md for license terms.
#
# Install only a verified release in INSTALL_DIR, then restart the app.
#   Scripts/install.sh [path/to/App.app]   (default: dist/<APP_NAME>.app)
# The previous copy is kept until the new one is copied, verified and running.
source "$(dirname "$0")/common.sh"

SOURCE=${1:-"$APP_BUNDLE"}
DEST="$INSTALL_DIR/$APP_NAME.app"

[[ -f "$SOURCE/Contents/Info.plist" ]] || die "$SOURCE is not an app bundle."
[[ ! -L "$DEST" ]] || die "$DEST is a symbolic link; no changes made."
SOURCE=$(cd "$SOURCE" && pwd -P)
mkdir -p "$INSTALL_DIR"
[[ "$SOURCE" != "$(cd "$INSTALL_DIR" && pwd -P)/$APP_NAME.app" ]] || die "Source and destination must differ."
[[ -w "$INSTALL_DIR" ]] || die "$INSTALL_DIR is not writable; no changes made."

ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")
[[ "$ID" == "$BUNDLE_ID" ]] || die "Refusing to install an unexpected bundle identifier: $ID"
if [[ -e "$DEST" ]]; then
  [[ -f "$DEST/Contents/Info.plist" ]] || die "$DEST is not a recognized app; no changes made."
  OLD_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
  [[ " $(known_bundle_ids) " == *" $OLD_ID "* ]] || die "$DEST belongs to a different app ($OLD_ID); no changes made."
fi
codesign --verify --deep --strict "$SOURCE"
xcrun stapler validate "$SOURCE"
spctl --assess --type execute "$SOURCE"
run_bundle_check "$SOURCE"
swift "$KIT/check_privacy.swift" "$SOURCE"

# Stage on the destination volume before the running app quits.
WORK=$(mktemp -d "$INSTALL_DIR/.${APP_NAME// /}-install.XXXXXX")
INSTALLED=0
cleanup() {
  local result=$?
  trap - EXIT
  if [[ "$result" -ne 0 ]]; then
    if [[ "$INSTALLED" == 1 && -d "$DEST" ]]; then mv "$DEST" "$WORK/failed.app" || true; fi
    if [[ -d "$WORK/previous.app" ]]; then
      mv "$WORK/previous.app" "$DEST"
      open -g "$DEST" || true
      echo "Restored the previous installation." >&2
    fi
  fi
  rm -rf "$WORK"
  exit "$result"
}
trap cleanup EXIT
ditto "$SOURCE" "$WORK/new.app"
codesign --verify --deep --strict "$WORK/new.app"

# Ask the app to quit normally; never force-kill it. Match bundle identifiers, not process names.
RELEASE_IDS="$(known_bundle_ids)" RELEASE_APP="$APP_NAME" swift -e '
import AppKit
let env = ProcessInfo.processInfo.environment
let ids = Set((env["RELEASE_IDS"] ?? "").split(separator: " ").map(String.init))
let apps = NSWorkspace.shared.runningApplications.filter { ids.contains($0.bundleIdentifier ?? "") }
for app in apps { _ = app.terminate() }
for _ in 0..<100 {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    if apps.allSatisfy({ $0.isTerminated }) { exit(0) }
}
fputs("\(env["RELEASE_APP"] ?? "The app") did not quit; installation stopped without forcing it.\n", stderr)
exit(1)
'
if [[ -d "$DEST" ]]; then mv "$DEST" "$WORK/previous.app"; fi
mv "$WORK/new.app" "$DEST"
INSTALLED=1
open -g "$DEST"

RELEASE_DEST="$DEST" swift -e '
import AppKit
let target = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RELEASE_DEST"]!).standardizedFileURL
for _ in 0..<100 {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    if NSWorkspace.shared.runningApplications.contains(where: {
        $0.bundleURL?.standardizedFileURL == target && !$0.isTerminated
    }) { exit(0) }
}
fputs("The installed app did not start.\n", stderr)
exit(1)
'
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")
echo "INSTALLED_AND_RUNNING: $DEST ($VERSION)"
