# Security

## Secret Handling

Do not commit:

- Administrator passwords or authorization artifacts
- Signing certificates, provisioning profiles, or local Xcode user data
- `.env*` files, credentials, or private SMC dump logs
- Local crash reports, DMGs, or staged app bundles from release runs

Root SMC writes from the GUI must use the narrow helper/CLI path. Never add
generic shell execution or store secrets in the repo.

## Reporting

For security-sensitive issues, do not post secrets or private hardware logs in
public channels. Open a minimal report that describes the affected area and
share sensitive details only through a private maintainer-approved channel.

## Repo Boundary

The repo should contain source code, tests, build scripts, formatting config,
contributor docs, and changelog. Local maintainer notes and release artifacts
stay ignored unless they are scrubbed and intentionally published.
