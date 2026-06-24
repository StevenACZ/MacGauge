# M4FanControl Agent Guide

## Scope

This guide applies to `/Users/steven/Desktop/Proyectos/M4FanControl`.

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
- Keep SMC, fan, temperature, and curve logic in `M4FanCore`.
- Keep CLI behavior in `M4FanCLI`.
- Keep menu bar app code in `M4FanControlApp`.
- Share hardware logic through `M4FanCore`; do not duplicate SMC key handling in UI code.

## macOS App Patterns

- Follow local macOS app patterns: `NSStatusItem` + `NSPopover`, accessory app behavior, and explicit settings windows.
- Keep permissions honest and narrowly scoped.
- Use `SMAppService.mainApp` for start-at-login UX when feasible.
- Root SMC writes from the GUI must use a clearly separated helper/CLI path or a proper privileged helper. Never fake success.

## Build And Verification

- Use `swift build` for package checks.
- Use `./script/build_and_run.sh` for the GUI app once present.
- Preserve CLI verification with read-only and dry-run commands.
- Add or maintain focused tests for pure logic such as curve interpolation.

## Git

- Do not push, rebase, reset, delete branches, or create PRs unless Steven asks.
- Do not revert unrelated user changes.
- Use Conventional Commits if asked to commit.
