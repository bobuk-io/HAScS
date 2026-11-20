# HAScS project rules

- HAScS stands for **Home Assistant Scenes Selector**.
- The local checkout is `~/GitHub/bobuk.io/HAScS`.

- Use `io.bobuk.HAScS` for the app. Old `com.bobuk` identifiers are only for backward-compatible migration.
- The GitHub repository is `bobuk-io/HAScS` and is **public**. Do not change its visibility unless the user explicitly asks. Never publish credentials.
- Shared UI and infrastructure come from BobukKit (`Vendor/BobukKit`, read-only); read
  `../BobukKit/README.md` before adding windows, panels, controls, hotkeys, file stores,
  processes or update code here, and follow `../AGENTS.md`. The release kit in
  `Scripts/release/` is a managed copy of `../BobukKit/ReleaseKit`; never edit it here.
- Releases use the shared release kit (`Scripts/release/README.md`); app facts live in `release.env`.
- Every release must be signed with Developer ID, notarized and stapled, published to GitHub Releases, **installed at `/Applications/HAScS.app` and restarted**, and the landing site must be deployed. The user explicitly requests installation and restart as part of every release; do not stop after uploading artifacts.
- `Scripts/release_next.sh` (no arguments) does the whole next patch release. Prepare `docs/releases/v<version>.md`, commit the landing copy (clean `../landing` on main), set `APP_IDENTITY` and `NOTARY_PROFILE`, and check readiness with `Scripts/release/doctor.sh`. After a failure, run the same command again. `Scripts/release.sh` builds and installs without publishing; `Scripts/install.sh` installs an already notarized app without rebuilding. Verify that the running process is from `/Applications`, not `build/` or `dist/`.
- Never activate real Home Assistant scenes during validation. Use a local mock server. Do not open the real scene panel for unattended testing: it immediately accepts number keys.
- Keep HA credentials in Keychain (BobukKit's `KeychainItem`). Never commit or upload `.env`. Release artifacts must also pass `Scripts/check_bundle.swift`.
- After every release, update the HAScS pages on the landing site (`~/GitHub/bobuk.io/landing`) when the release needs it. See `../AGENTS.md`.
