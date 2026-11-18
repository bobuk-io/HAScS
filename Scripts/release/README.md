# bobuk.io release kit

One release scheme for every native `bobuk-io` app (Ting, Splash Finish, HAScS, lowkey).
The files in `Scripts/release/` and the four entry points in `Scripts/` are identical in every
repository. The canonical copy is `ting/Scripts/release`; copy changes from there with
`Scripts/release/sync_kit.sh ../<app>` and check the copies with `--check`. Do not edit a
copy in another repository.

## Commands

| Command | What it does |
| --- | --- |
| `Scripts/release_next.sh` | The whole next patch release, below. No arguments. |
| `Scripts/release.sh` | Test, build, sign, notarize, staple, archive, sign the appcast, install and restart. Publishes nothing. |
| `Scripts/publish.sh` | GitHub release (draft, assets, then published), the site feed, the Homebrew cask. |
| `Scripts/install.sh [App.app]` | Install an already notarized app in `INSTALL_DIR` and restart it. |
| `Scripts/release/landing.sh` | Deploy bobuk.io, commit and push the landing checkout, check the page and the live feed. |
| `Scripts/release/homebrew.sh [--publish]` | Print or publish the cask from `Scripts/homebrew_cask.rb`. |
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
- `Scripts/package_app.sh [debug|release]` that honours `ARCHES` (space separated),
  `APP_OUTPUT_DIR` (default `build/`), `SIGNING_MODE=adhoc|developer-id` and `APP_IDENTITY`,
  writes `$APP_OUTPUT_DIR/$APP_NAME.app`, builds each architecture with
  `--build-system native`, strips debug maps (`strip -S`) in release builds, and signs with the
  Hardened Runtime and a secure timestamp for Developer ID.
- `docs/releases/v<version>.md` for every published release.
- `Scripts/homebrew_cask.rb` with `@VERSION@` and `@SHA256@` when `HOMEBREW_CASK` is set.

## Rules

- Never modify a ZIP after the appcast signed it. Never edit a published `appcast.xml`.
- The Sparkle private key stays in the login Keychain; the kit only reads the public key.
- `check_privacy.swift` refuses home, build and temporary paths and key files in the bundle.
- The kit has no hosted CI. Run tests and releases locally.
