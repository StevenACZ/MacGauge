# Security

## Secret Handling

Do not commit:

- Administrator passwords or authorization artifacts
- Signing certificates, provisioning profiles, or local Xcode user data
- `.env*` files, credentials, or private SMC dump logs
- Local crash reports, DMGs, or staged app bundles from release runs
- The Sparkle EdDSA private key (it lives only in the maintainer's Keychain;
  the repo carries just the public key in the generated Info.plist)

Root SMC writes from the GUI must use the narrow helper/CLI path. Never add
generic shell execution or store secrets in the repo.

## Reporting

For security-sensitive issues, do not post secrets or private hardware logs in
public channels. Open a minimal report that describes the affected area and
share sensitive details only through a private maintainer-approved channel.

## Repo Boundary

The repo should contain source code, tests, build scripts, formatting config,
contributor docs, and changelog.

## Update Channel

In-app updates are served from GitHub Releases through a Sparkle appcast
(`appcast.xml` uploaded with each release). Updates install only if their
EdDSA signature matches the public key embedded in the app, so only the
maintainer holding the private key can publish an installable update. Local maintainer notes and release artifacts
stay ignored unless they are scrubbed and intentionally published.
