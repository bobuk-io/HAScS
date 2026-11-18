# HAScS project rules

- HAScS stands for **Home Assistant Scenes Selector**.
- The local checkout is `~/GitHub/bobuk.io/HAScS`.

- Use `io.bobuk.HAScS` for the app and `io.bobuk` for new identifiers. Old `com.bobuk` identifiers are only for backward-compatible migration.
- The GitHub repository is `bobuk-io/HAScS` and is **public**. Do not change its visibility unless the user explicitly asks. Never publish credentials.
- Keep README, release notes, security policy and other documentation in English. Keep the repository focused on the shipping application, without discarded design experiments or their history.
- Original code is 0BSD; preserve the MIT attribution for the adapted scripts identified in `THIRD_PARTY_NOTICES.md`.
- Releases use the shared bobuk.io release kit in `Scripts/release/` (see its `README.md`); app facts live in `release.env`. The canonical kit is in `../ting/Scripts/release`: change it there and copy it with `Scripts/release/sync_kit.sh`; never edit the copy here.
- Every release must be signed with Developer ID, notarized and stapled, published to GitHub Releases, **installed at `/Applications/HAScS.app` and restarted**, and the landing site must be deployed. The user explicitly requests installation and restart as part of every release; do not stop after uploading artifacts.
- `Scripts/release_next.sh` (no arguments) does the whole next patch release. Prepare `docs/releases/v<version>.md`, commit the landing copy (clean `../landing` on main), set `APP_IDENTITY` and `NOTARY_PROFILE`, and check readiness with `Scripts/release/doctor.sh`. After a failure, run the same command again. `Scripts/release.sh` builds and installs without publishing; `Scripts/install.sh` installs an already notarized app without rebuilding. Verify that the running process is from `/Applications`, not `build/` or `dist/`.
- Test the kit only with the offline `Scripts/release/test_kit.sh`; never run `release_next.sh`, `release.sh` or `publish.sh` for a check.
- Never activate real Home Assistant scenes during validation. Use a local mock server. Do not open the real scene panel for unattended testing: it immediately accepts number keys.
- Keep HA credentials in Keychain. Never commit or upload `.env`, credentials, signing keys or notarization credentials. Release artifacts must pass `Scripts/check_bundle.swift` and `Scripts/release/check_privacy.swift`; do not ship local home/build paths.
- After every release, update the HAScS pages on the landing site (`~/GitHub/bobuk.io/landing`) when the release needs it. See `../AGENTS.md`.
