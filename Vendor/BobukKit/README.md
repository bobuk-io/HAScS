# BobukKit

The name is a Ukrainian pun: **Бобук Кіт** — “Bobuk the Cat”. Bobuk is the
author's name, and Ukrainian **кіт** means “cat”. A toolkit with a cat in its name. :)

Shared macOS components for bobuk-io apps. Canonical checkout:
`~/GitHub/bobuk.io/BobukKit`. Requires macOS 14 and Swift 6.2.

## BobukUI

- `PickerRow`: identical row height, insets, hover and selected backgrounds.
  It does not own a button, search, focus or actions; retain native app controls.
- `PickerSearchField`: native live search input with standard editing/cancel behavior,
  palette-owned text colors and shared height. It writes a binding; apps own filtering
  and results. It saves no recent searches, never takes focus automatically and does not
  intercept keyboard commands such as Cmd-W.
- `PickerBadge`: centered monospaced text in a fixed column. Compute
  `PickerMetrics.badgeWidth(for:)` **once for the complete list**, not per row.
  Extremely long aliases truncate with a full-text tooltip. History uses the same column.
- `PickerSurfaceView` / `.pickerPanel(palette:)`: one AppKit surface renderer for
  borderless panels and SwiftUI cards, with a clipped rounded frame and accent rule.
  Native titled browser windows, OS resizing and shadows remain application-owned.
- `ShortcutFooter`: semantic shortcut/action groups that wrap together, not a long
  pre-spaced string. Hints do not register keyboard handlers. All commands remain
  in the application's responder chain. Group identity is the unique key/action pair.
- `PickerSelection`: non-wrapping, clamped movement. Optional selection lets the
  first Up return to typed input, as in lowkey; Ting keeps the first result selected.

Applications provide `PickerPalette` at the current window's theme boundary.
Palette roles are surface, text, secondary text, accent, frame border and badge ink.
The kit owns shared geometry, not app branding, WebKit profiles or appearance storage.
Use native Buttons and accessibility labels/hints on each action. Decorative icons
should be hidden from accessibility. Selection traits belong to the action, not
its surrounding layout. No automatic focus/activation, keyboard synthesis or animation.

## Local copies, not remote dependencies

Consumers use `.package(path: "Vendor/BobukKit")`. Builds need neither this checkout
nor GitHub. Commit the vendored snapshot with each app. Do not edit copies.

```sh
Scripts/sync.sh                 # sync all consumers in consumers.txt
Scripts/sync.sh --check         # fail on missing/drifted copies; never write
Scripts/sync.sh /path/to/app    # explicit consumer, including a fresh checkout
swift test
swift run BobukUIGallery /tmp/bobukkit-gallery
Scripts/test_sync.sh            # offline sync safety tests
```

`consumers.txt` paths are relative to this checkout. Consumers are Ting
(launcha, selecta, Clipbawd and Settings), lowkey (address/alias picker), Splash Finish
(panel frame and shortcut footer) and HAScS (localized shortcut footer).
Splash Finish retains its variable-height notification cards and separate link/dismiss
actions; HAScS retains its scene tiles and grid navigation. Ahti is not a consumer.
Snapshot files are
listed in `MANIFEST.sha256`; `.bobukkit-vendor` marks ownership. Sync refuses an
unmarked nonempty directory or a symlink rather than deleting app-owned files.
Only the marked `Vendor/BobukKit` subtree is managed. Cached `.build`/`.swiftpm`
folders are preserved and excluded from drift comparison. The gallery and tests
travel with the snapshot, but synchronization scripts remain canonical.
`Vendor/BobukKit/Scripts/check-vendor.sh` verifies snapshot hashes and runs its
unit tests without an upstream checkout. All consumer apps run it as a release EXTRA_TESTS
suite; its independent scratch directory avoids app build/test contention.

Before changing a component: edit here, run the relevant kit tests and gallery,
sync **all** registered consumers, run their focused tests, inspect their actual
layouts, and commit copies alongside app changes. Run `--check` before committing.
No hosted CI or remote package resolution is required.

## State/QA contract

The offline gallery renders a real native search input, light/dark palettes at 340 and 560 points, selected
and unselected rows, history, long aliases, and a wrapping footer. It uses only
invisible windows and demo data; it does not activate an app or read settings.
Tests cover selection boundaries, optional selection, equal badge geometry and
whole-group footer wrapping. App tests retain ownership of search results, row
actions, profile identity and window lifecycle.

Not included yet: shared release kit, keyboard-layout search, history or Sparkle.
Those remain in their current projects; this extraction is deliberately UI-only.

## License

0BSD, see LICENSE. No external runtime dependencies.
