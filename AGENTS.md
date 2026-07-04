# MacGauge Agent Guide

## Scope

This guide applies to the MacGauge repository: a SwiftPM macOS project with a
menu bar app, a CLI, and a privileged XPC helper for Apple Silicon fan
control and live system stats (CPU, memory, network).

## Naming

- MacGauge is the brand: the .app bundle, display name, docs, and releases.
- Internal identifiers keep the MacFan prefix on purpose: the SwiftPM package
  and products (`MacFanCore`, `MacFanApp`, `MacFanCLI`, `MacFanHelper`), the
  `com.stevenacz.MacFan` bundle ID, the helper label, defaults keys, and
  status item autosave names. Changing them breaks installed helpers,
  authorizations, and user settings — do not rename them for cosmetics.

## Safety

- Fan control is hardware-sensitive. Default to read-only or dry-run behavior.
- Do not run automated 0 RPM or maximum RPM tests.
- Do not change persistent fan state without the maintainer's explicit
  live-test approval in the current thread.
- Do not request macOS permissions the code does not actually use.
- Do not store secrets, signing credentials, or Apple Developer account data
  in the repo.

## Architecture

- Prefer SwiftPM-first workflows unless an Xcode project is intentionally
  added.
- Keep SMC, fan, temperature, and curve logic in `MacFanCore`.
- Keep CLI behavior in `MacFanCLI`.
- Keep menu bar app code in `MacFanApp`.
- Share hardware logic through `MacFanCore`; do not duplicate SMC key handling
  in UI code.
- Never assume a specific chip generation or fan count: enumerate fans via
  `FNum`, convert percentages per fan, and treat fanless Macs as a valid
  state.

## macOS App Patterns

- Follow local macOS app patterns: `NSStatusItem` + `NSPopover`, accessory app
  behavior, and explicit settings windows.
- Design tokens and animation springs live in `MacFanApp/Support/Theme.swift`;
  use them instead of inline constants.
- UI strings are localized (en/es) through `LocalizationManager` and
  `"key".localized`; add new strings to both
  `Sources/MacFanApp/Resources/{en,es}.lproj/Localizable.strings`.
- Keep permissions honest and narrowly scoped.
- Use `SMAppService.mainApp` for start-at-login UX when feasible.
- Root SMC writes from the GUI must use the privileged XPC helper. Never fake
  success.
- The helper must expose only narrow fan-control actions. Never add generic
  shell execution.
- Never store administrator passwords; use system authorization/helper
  installation instead.

## Menu Bar Performance (learned 2026-07-04)

The app runs in the background all day; every animation frame inside an
`NSStatusItem` forces AppKit to re-layout and re-snapshot the item, which once
held the app at ~80% of one core. Keep these rules:

- No continuous or implicit SwiftUI animations in menu bar label views; gate
  any motion behind `settings.performanceMode == .full` (Efficient is the
  default and must stay dry: one step per tick).
- Popover content must be lazy: build the `NSHostingController` on show and
  release it in `popoverDidClose`. A hosting controller that merely exists
  keeps its whole SwiftUI graph rendering while the popover is closed.
- After touching menu bar UI, verify idle cost with `sample <pid>` — seeing
  `NSStatusItem _updateReplicants` high in the profile means the item redraws
  too often. Idle target: a few percent of one core.

## Build And Verification

- Standard local gate:

```bash
make ci-check
```

- `make ci-check` runs lint, `swift build`, and `swift test`.
- Use `./script/build_and_run.sh stage` / `run` for the GUI app bundle.
- Use `make install-dev` for a signed local install to `~/Applications`.
- Use `make format` / `make lint` before commits; optional Lefthook via
  `make hooks-install`.
- Preserve CLI verification with read-only and dry-run commands.
- Add or maintain focused tests for pure logic such as curve interpolation.

## Documentation

- Keep `CHANGELOG.md` updated for meaningful user-facing or safety-relevant
  changes under `Unreleased` until a versioned release is approved.
- Keep README safety notes aligned with the actual helper, mode, curve, and
  temperature behavior.
- Do not document raw SMC dumps, private local logs, or noisy one-off
  experiments; summarize durable findings only.

## Git

- Do not push, rebase, reset, delete branches, or create PRs unless the
  maintainer asks.
- Do not revert unrelated user changes.
- Use Conventional Commits.
