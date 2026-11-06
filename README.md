# HAScS — Home Assistant Scenes Selector

A native macOS menu-bar remote for Home Assistant scenes. Open a compact floating
panel, press a number, and get back to what you were doing.

Requires **macOS 14 or later**. Official releases support **Apple Silicon and Intel**.

## Install

1. Download the universal ZIP from [Releases](https://github.com/bobuk-io/HAScS/releases/latest).
2. Unzip it and move `HAScS.app` to `/Applications`.
3. Open the app. It starts in the menu bar without opening a window.
4. Right-click the house icon, choose **Settings**, and enter your Home Assistant
   URL and a long-lived access token.

Official release builds are signed with Developer ID, notarized by Apple, and
include a stapled notarization ticket. Each release includes a SHA-256 checksum.

## Use

- **Click the house icon:** show or hide the remote.
- **Right-click:** open Settings or quit HAScS.
- **1–9:** activate the corresponding scene, including numeric-keypad keys.
- **Arrow keys:** select a scene spatially: left/right within a row, up/down
  between rows. **Return:** activate it. **Escape:** hide the panel.
- **Command-comma** or the gear button: open Settings from the remote.
- **Deep link:** open the remote without activating a scene:

  ```sh
  open 'hascs://scenes'
  ```

The panel appears on the display containing the pointer and accepts number keys
immediately. After a successful response from Home Assistant, it briefly shows a
confirmation and hides. This confirms the request, not the final state of every
device. A Home Assistant scene is an action, not an on/off switch.

Scene numbers are saved by entity ID and remain stable when HA changes the order
of its response or adds scenes. Removing a scene can free its number for another
one. Up to **nine scenes** are available; additional rows scroll into view during
keyboard navigation. If HA has more than nine scenes, the panel displays a limit
notice. Global-hotkey registration and launch at login are not implemented yet.
An external shortcut tool can run the deep-link command above.

### Reorder scenes

Click **Reorder** and drag a tile onto the position it should occupy. The other
tiles shift; numbers, keyboard shortcuts, and tile positions stay in sync. Click
**Done** (or press Return) to save, or **Cancel** (Escape) to discard changes.
Closing the panel also discards unsaved changes. The order survives app restarts
and Home Assistant response-order changes.

Scenes cannot run while reordering. Click a tile to select it, then use
**Shift + arrow keys** to move it without dragging; plain arrows change selection.
Up/down moves between rows, preserving the intended column through the wide first
tile and incomplete rows; left/right stays within the current row. Movement stops
at the grid edges. Normal selection skips unavailable scenes; reordering includes
them. Each tile's context menu and VoiceOver actions also offer earlier/later moves.

## Languages

The interface supports **English, Ukrainian, and Russian**. By default it follows
macOS, with English as the fallback. Choose a language in Settings and relaunch
HAScS to apply it. Scene names remain exactly as configured in Home Assistant.

## Privacy and security

The HA URL and token are stored in **macOS Keychain**, not in UserDefaults or the
app bundle. The token is hidden in Settings; leave the field empty to keep the
saved value. Use HTTPS and a dedicated, non-administrator HA user where practical.
An HTTP connection sends the token without transport encryption.

Earlier local versions can migrate a legacy `.env` once. After successful
migration, connections use Keychain only. Old plaintext files and old Keychain
records are not automatically deleted. Remove redundant copies yourself when
safe. A local `.env` is excluded from git; protect it with `chmod 600 .env` if you
still need it. See [SECURITY.md](SECURITY.md) for the security model and private
vulnerability reporting.

The app identifier is `io.bobuk.HAScS`. Existing settings and scene-number
assignments are migrated from earlier local identifiers without changing them.

## Develop

Use Xcode or Command Line Tools with **Swift 6 or later** on macOS:

```sh
swift build
swift test
./Scripts/run.sh
```

`run.sh` builds a local app in `build/` and starts it. It refuses to overwrite a
running development copy. Local builds use ad-hoc signing by default and are not
notarized; macOS may ask for Keychain permission after rebuilding.

The SwiftUI interface and AppKit window/menu wiring live in `Sources/HAScS`.
Networking, configuration, Keychain storage, localization resources and scene
assignments live in `Sources/HAScSCore`. Tests use fake credentials and mock
transports; do not activate real scenes while validating changes.

## Release

Configure a Developer ID Application signing identity and a saved `notarytool`
Keychain profile, then run on a trusted maintainer workstation:

```sh
APP_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=HAScS \
./Scripts/release.sh
```

The script builds a universal app, removes debug-map paths, checks embedded
resources and local-path leakage, signs and notarizes it, and staples the ticket.
The ZIP and `SHA256SUMS.txt` are written to `dist/`.

It then **installs the release at `/Applications/HAScS.app` and restarts it**. The
previous installation is retained until the replacement starts successfully; an
app that refuses to quit is not force-killed. Existing credentials remain in
Keychain. Signing keys, `.env` and notarization credentials are never bundled.

Install an already prepared notarized build without rebuilding:

```sh
./Scripts/install.sh dist/HAScS.app
```

Validate the app without launching it or contacting HA:

```sh
swift Scripts/check_bundle.swift dist/HAScS.app
swift Scripts/check_release_privacy.swift dist/HAScS.app
```

Upload the verified ZIP and checksum to GitHub Releases with a matching version
tag. Release tasks are complete only after publication, installation and restart.

## License

Original HAScS code is licensed under [0BSD](LICENSE): use, modify and redistribute
it for any purpose, with no attribution requirement. Adapted build/release
scripts retain their upstream MIT license; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
