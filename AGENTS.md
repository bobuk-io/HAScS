# HAScS project rules

- HAScS stands for **Home Assistant Scenes Selector**.
- The local checkout is `~/GitHub/bobuk.io/HAScS`.

- Use `io.bobuk.HAScS` for the app and `io.bobuk` for new identifiers. Old `com.bobuk` identifiers are only for backward-compatible migration.
- The GitHub repository is `bobuk-io/HAScS` and must remain **private** until the user explicitly requests a visibility change. The source is prepared for possible public release, but preparation is not permission to change visibility. Never publish credentials.
- Keep README, release notes, security policy and other documentation in English. Keep the repository focused on the shipping application, without discarded design experiments or their history.
- Original code is 0BSD; preserve the MIT attribution for the adapted scripts identified in `THIRD_PARTY_NOTICES.md`.
- Every release must be signed with Developer ID, notarized and stapled, published to GitHub Releases, **installed at `/Applications/HAScS.app` and restarted**. The user explicitly requests installation and restart as part of every release; do not stop after uploading artifacts.
- `Scripts/release.sh` prepares and installs the release. `Scripts/install.sh` can install an already notarized app without rebuilding. Verify that the running process is from `/Applications`, not `build/` or `dist/`.
- Never activate real Home Assistant scenes during validation. Use a local mock server. Do not open the real scene panel for unattended testing: it immediately accepts number keys.
- Keep HA credentials in Keychain. Never commit or upload `.env`, credentials, signing keys or notarization credentials. Release artifacts must pass `Scripts/check_release_privacy.swift`; do not ship local home/build paths.
- After every release, update the HAScS pages on the landing site (`~/GitHub/bobuk.io/landing`) when the release needs it. See `../AGENTS.md`.
