# Contributing

Thanks for helping improve M4FanControl.

## Setup

```bash
make tools
make ci-check
```

For the menu bar app bundle:

```bash
make stage
./script/build_and_run.sh run
```

## Workflow

```bash
make format
make lint
make build
make test
```

- Keep changes focused and small.
- Fan control is hardware-sensitive: default to read-only or dry-run behavior.
- Do not commit credentials, signing files, local logs, or SMC dump artifacts.
- Use `make ci-check` before opening a PR or merging substantial changes.

## Pull Requests

Before opening a PR:

```bash
make ci-check
git diff --check
```

Include:

- What changed.
- How it was verified.
- Any safety, permission, or helper/XPC impact.

## Signing

This is a private/local project. Contributor builds use ad-hoc or local signing.
Maintainers configure Apple Development, helper installation, and release
packaging outside any public distribution path.
