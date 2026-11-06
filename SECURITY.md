# Security policy

## Reporting a vulnerability

Please report security issues privately using GitHub's **Report a vulnerability**
feature:

<https://github.com/bobuk-io/HAScS/security/advisories/new>

If that feature is unavailable, email **bobuk@rubedo.cloud** with the subject
`HAScS security report`.

Please do not disclose vulnerabilities in a public issue before we have had an
opportunity to investigate. Include the HAScS and macOS versions, reproduction
steps, expected impact, and a minimal proof of concept where possible. Never
include a real Home Assistant token, `.env`, private signing key, notarization
credentials, or an export of your full Home Assistant state.

This is a small community project. Reports are handled on a best-effort basis;
there is no guaranteed response or fix deadline. Supported fixes target the
latest published version.

## Security model

- Home Assistant's URL and long-lived access token are stored in macOS Keychain.
  They are not bundled with the app, logged by HAScS, or stored in UserDefaults.
- Legacy `.env` files and old Keychain entries are not automatically deleted
  after migration. Remove redundant plaintext copies yourself when safe.
- Use **HTTPS** and a dedicated, non-administrator Home Assistant user when
  practical. HTTP sends the bearer token without transport encryption. A token
  carries the permissions of its HA user; HAScS does not turn it into a
  scene-only token.
- HAScS reads `/api/states` to discover scenes and calls
  `/api/services/scene/turn_on` only when the user activates a scene.
- The `hascs://scenes` link opens the remote; it does not accept scene IDs or
  tokens and does not itself activate a scene. Once open, the remote accepts
  number keys immediately and can affect real devices.
- TLS certificate validation is handled by the system. Authenticated requests
  do not follow HTTP redirects, preventing accidental token forwarding.
- Official release apps are signed with Developer ID, notarized by Apple and
  include a stapled ticket. Notarization is not a guarantee that software is
  bug-free or safe for every use case.
- This is not a safety-critical controller. Do not rely on it for locks, alarms,
  medical equipment or any action where unintended activation could cause harm.

## Release and contributor safety

Download official builds only from this repository's Releases. Keep signing
keys and notarytool credentials outside git and CI jobs for untrusted code.
Contributions must be reviewed and tested with mock Home Assistant responses;
never run real scenes during automated validation.

`Scripts/release.sh` signs and notarizes an app and then installs and restarts it
at `/Applications/HAScS.app`. It is intended for a trusted maintainer workstation,
not for running directly against unreviewed pull requests. The resulting ZIP
must pass the local-path scan and signature, resource and notarization checks
before publication.
