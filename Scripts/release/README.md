# bobuk.io release kit

One release scheme for every native `bobuk-io` app (Ting, Splash Finish, HAScS, lowkey).
The files in `Scripts/release/` and the five entry points in `Scripts/` are identical in every
repository. The canonical copy is `BobukKit/ReleaseKit` (`release/` and `entry/`), next to the
shared Swift package. Change it there, run `ReleaseKit/release/test_kit.sh`, then
`BobukKit/Scripts/sync.sh` copies it into every app listed in `BobukKit/consumers.txt`, and
`BobukKit/Scripts/sync.sh --check <app>` finds drift. `.bobukkit-release` marks a managed copy.
Never edit the copy in an app repository.

## Commands

| Command | What it does |
| --- | --- |
| `Scripts/release_next.sh` | The whole next patch release, below. No arguments. |
| `Scripts/release.sh` | Test, build, sign, notarize, staple, archive, sign the appcast, install and restart. Publishes nothing. |
| `Scripts/publish.sh` | GitHub release (draft, assets, then published), the site feed, the Homebrew cask. |
| `Scripts/install.sh [App.app]` | Install an already notarized app in `INSTALL_DIR` and restart it. |
| `Scripts/release/landing.sh` | Deploy bobuk.io, commit and push the landing checkout, check the page and the live feed. |
| `Scripts/release/homebrew.sh [--publish]` | Print or publish the cask from `Scripts/homebrew_cask.rb`. |
| `Scripts/package_app.sh [debug|release]` | Build and sign the app bundle (see Packaging). |
| `Scripts/release/doctor.sh` | Read-only readiness check: configuration, tools, identity, notary profile, Sparkle key, GitHub, landing. |
| `Scripts/release/test_kit.sh` | Offline tests of the kit with mocks. Safe to run any time. |

`release_next.sh`, `release.sh` and `publish.sh` make a real release. Never run them to check
something; use `doctor.sh` and `test_kit.sh`.

## One release

Before the run:

1. Commit the change on `main`. Write `docs/releases/v<next version>.md` (leave it uncommitted
   or commit it).
2. Write and commit the landing copy for the release in `../landing` (all three locales) when
   the release needs it; leave `../landing` clean on `main`.
3. Set `APP_IDENTITY` (Developer ID Application) and `NOTARY_PROFILE` (notarytool profile).
4. Run `Scripts/release/doctor.sh`.

Then run `Scripts/release_next.sh`. It:

1. checks everything that can fail before it changes a file: arguments, credentials, branch
   and origin, clean trees, notes, the GitHub release and the live feed;
2. raises the last version number and `BUILD_NUMBER` (and `VERSION_SWIFT_FILE`);
3. runs `Scripts/release.sh`: the full test suite runs in the background in
   `.build/release-tests` while the universal app builds, is checked and notarized; nothing
   is installed or published unless the tests pass;
4. commits `Release <App> <version>`, pushes `main`, runs `Scripts/publish.sh`;
5. runs `Scripts/release/landing.sh`: `npm run deploy` (sync, build, test, upload, page
   checks), commit and push of the landing checkout, then the app page and the live feed;
6. prints `RELEASE_DONE` and the time of each stage.

A failed run is started again with the same command. The mode comes from facts: no GitHub
release of the current version means "build again", a published release with a stale feed
means "finish the tail", otherwise "next version".

## release.env

App facts live in `release.env` at the repository root, next to `version.env`. Only the first
two keys are required.

| Key | Meaning | Default |
| --- | --- | --- |
| `APP_NAME` | Bundle name without `.app`, also used in titles | required |
| `BUNDLE_ID` | `CFBundleIdentifier` | required |
| `APP_EXECUTABLE` | `Contents/MacOS` executable | `APP_NAME` |
| `LEGACY_BUNDLE_IDS` | Older identifiers that an installed copy may have | none |
| `ARCHIVE_PREFIX` | `dist/<prefix>-<version>-universal.zip` | `APP_NAME` without spaces |
| `CHECKSUMS_FILE` | Checksum manifest in `dist/` and on GitHub | `SHA256SUMS.txt` |
| `INSTALL_DIR` | Where releases are installed | `/Applications` |
| `GITHUB_REPO` | `owner/name`; empty means local signed builds only | none |
| `LANDING_SLUG` | Page `bobuk.io/apps/<slug>/`; empty skips the landing step | none |
| `SPARKLE_ACCOUNT`, `SPARKLE_PUBLIC_KEY` | Keychain account and public EdDSA key; empty means no Sparkle | none |
| `GITHUB_APPCAST` | `1` uploads `appcast.xml` to the GitHub release for old copies | `0` |
| `HOMEBREW_CASK` | Cask name in `bobuk-io/homebrew-tap`; needs `Scripts/homebrew_cask.rb` | none |
| `TEST_ARGS` | Extra `swift test` arguments | none |
| `EXTRA_TESTS` | Other suites after `swift test`, run with `bash -c` | none |
| `VERSION_SWIFT_FILE`, `VERSION_SWIFT_PREFIX` | A source file that repeats the version after the prefix | none |
| `BUNDLE_CHECK` | App-specific check of the built bundle (`.swift`, `.py` or an executable), given the app path | none |

## What every app provides

- `version.env` with `MARKETING_VERSION=X.Y.Z` and `BUILD_NUMBER=N`.
- `docs/releases/v<version>.md` for every published release.
- `Scripts/homebrew_cask.rb` with `@VERSION@` and `@SHA256@` when `HOMEBREW_CASK` is set.
- `Assets/AppIcon.png` (1024×1024), or its own renderer in `PACKAGE_ICON`.
- Optional `Scripts/Info.extra.plist` (more Info.plist entries; `@BUNDLE_ID@` is replaced) and
  `Scripts/App.entitlements`.

## Packaging

`Scripts/package_app.sh [debug|release]` is a kit entry point that runs `package.sh`. It honours
`ARCHES` (space separated), `APP_OUTPUT_DIR` (default `build/`), `SIGNING_MODE=adhoc|developer-id`
and `APP_IDENTITY`, writes `$APP_OUTPUT_DIR/$APP_NAME.app`, builds each architecture with
`--build-system native`, strips debug maps (`strip -S`) in release builds, embeds SwiftPM
frameworks (Sparkle) and resource bundles, and signs inside out with the Hardened Runtime and a
secure timestamp for Developer ID. Release builds of apps with `SPARKLE_PUBLIC_KEY` and
`LANDING_SLUG` get `SUFeedURL` (`https://bobuk.io/apps/<slug>/appcast.xml`) and `SUPublicEDKey`.

| release.env key | Meaning | Default |
| --- | --- | --- |
| `PACKAGE_ARCHES` | Architectures when `ARCHES` is unset | this Mac's |
| `PACKAGE_MENU_BAR` | `1` sets `LSUIElement` (menu-bar app without a Dock icon) | `1` |
| `PACKAGE_CATEGORY` | `LSApplicationCategoryType` | `public.app-category.utilities` |
| `PACKAGE_HELPERS` | More executables: `product:folder[:codesign-identifier]`, space separated; folder under `Contents` | none |
| `PACKAGE_RESOURCES` | Files copied into `Contents/Resources`; empty for none | `LICENSE THIRD_PARTY_NOTICES.md` |
| `PACKAGE_ICON` | Own icon renderer: a `.swift` script gets the output folder, another executable the output file | `Scripts/release/icon.sh Assets/AppIcon.png` |
| `PACKAGE_REFUSE_RUNNING` | `1` refuses to replace a running build | `0` |
| `PACKAGE_SPARKLE_IN_DEBUG` | `1` also gives debug builds the update feed | `0` |
| `MACOS_MIN_VERSION` | `LSMinimumSystemVersion` | `14.0` |

## Rules

- Never modify a ZIP after the appcast signed it. Never edit a published `appcast.xml`.
- The Sparkle private key stays in the login Keychain; the kit only reads the public key.
- `check_privacy.swift` refuses home, build and temporary paths and key files in the bundle.
- The kit has no hosted CI. Run tests and releases locally.
