# MacFan Agent Guide

## Scope

This guide applies to `/Users/steven/Desktop/Proyectos/MacFan`.

## Communication

- Speak with Steven in Spanish.
- Keep code, durable technical docs, commit messages, and changelogs in English.
- This is a private/local project for Steven's own M4 Pro Mac. Do not create or push a public remote.

## Safety

- Fan control is hardware-sensitive. Default to read-only or dry-run behavior.
- Do not run automated 0 RPM or maximum RPM tests.
- Do not change persistent fan state without Steven's explicit live-test approval in the current thread.
- Do not request Accessibility permissions unless code actually uses Accessibility APIs.
- Do not store secrets, signing credentials, or Apple Developer account data in the repo.

## Architecture

- Prefer SwiftPM-first workflows unless an Xcode project is intentionally added.
- Keep SMC, fan, temperature, and curve logic in `MacFanCore`.
- Keep CLI behavior in `MacFanCLI`.
- Keep menu bar app code in `MacFanApp`.
- Share hardware logic through `MacFanCore`; do not duplicate SMC key handling in UI code.

## macOS App Patterns

- Follow local macOS app patterns: `NSStatusItem` + `NSPopover`, accessory app behavior, and explicit settings windows.
- Keep permissions honest and narrowly scoped.
- Use `SMAppService.mainApp` for start-at-login UX when feasible.
- Root SMC writes from the GUI must use a clearly separated helper/CLI path or a proper privileged helper. Never fake success.
- The local helper must expose only narrow fan-control actions. Never add generic shell execution.
- Never store administrator passwords or secrets; use system authorization/helper installation instead.

## Build And Verification

- Use the Makefile for the standard local gate:

```bash
make ci-check
```

- `make ci-check` runs lint, `swift build`, and `swift test`.
- Use `./script/build_and_run.sh stage` / `run` for the GUI app bundle.
- Use `make install-dev` for routine local app testing on Steven's Mac. It
  signs with Apple Development, installs to `~/Applications/MacFan.app`,
  and relaunches the app.
- Use `make format` / `make lint` before commits; optional Lefthook via
  `make hooks-install`.
- Preserve CLI verification with read-only and dry-run commands.
- Add or maintain focused tests for pure logic such as curve interpolation.

## Documentation

- Keep `CHANGELOG.md` updated for meaningful user-facing or safety-relevant
  changes under `Unreleased` until Steven approves a versioned release.
- Keep README safety notes aligned with the actual helper, mode, curve, and
  temperature behavior.
- Do not document raw SMC dumps, private local logs, or noisy one-off
  experiments; summarize durable findings only.

## Git

- Do not push, rebase, reset, delete branches, or create PRs unless Steven asks.
- Do not revert unrelated user changes.
- Use Conventional Commits if asked to commit.
