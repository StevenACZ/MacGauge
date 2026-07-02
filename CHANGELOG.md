# Changelog

All notable changes to this project will be documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-07-02

First public release, renamed from M4FanControl to MacFan.

### Added

- Interactive fan curve editor: drag points on the chart with a live value
  bubble, double-click to add a point, right-click to delete, gradient fill
  under the curve, and compact per-point chips with a popover for precise
  temperature/percent entry.
- Notarized DMG release packaging (`make notarized-dmg`).
- Universal Apple Silicon support: fans are enumerated dynamically, manual
  and curve targets apply to every fan (each converted to its own RPM range),
  and fanless Macs (MacBook Air) are shown as passively cooled instead of an
  error. Helper protocol v4 carries per-fan write results.
- English and Spanish localization following the system language, with an
  in-app override in Settings > General.
- Central UI theme (accent, layout metrics, animation springs), hover-filled
  footer action rows, per-fan RPM chips, a temperature-tinted identity
  header, a menu bar icon bounce on open, and animated settings tabs.
- MIT license and public-safe contributor docs.
- Standard Swift project workflow tooling: shared formatting config, Makefile
  checks, optional Lefthook hooks, and contributor/security docs.
- `make install-dev` / `scripts/install_dev.sh` for Apple Development signed
  local reinstalls to `~/Applications`.
- Contested-control detection in the popover: a warning banner appears when the
  system (`thermalmonitord`) is overriding the requested fan target.
- Verified helper write: `setPercent` now reads back `F0Md`/`F0Ac` after writing
  and re-asserts manual mode plus the target (bounded retry) when the system
  reverts it, returning the actual RPM, mode, and contested flag.
- App/helper diagnostic logging for fan writes, including requested percent,
  target RPM, actual RPM, SMC mode, helper state, and re-assert reasons.

### Changed

- Renamed the project from M4FanControl to MacFan: package, targets, bundle
  identifiers (`com.stevenacz.MacFan`), helper daemon label, CLI binary
  (`macfan`), scripts, and docs. Installing over an old M4FanControl build
  requires authorizing the renamed helper once from Settings > Safety and
  removing the old app from System Settings > Login Items.
- Temperature discovery now also covers the `Tp` die sensors used by M1/M2
  generations.
- CLI `set` and `curve` apply to all fans by default; `--fan` limits them to
  one.
- The update tick setting is no longer exposed in Settings and keeps its 1 s
  default.
- Simplified the menu bar popover footer to only Settings and Exit by removing
  the helper-readiness shield notice from Manual and Curve content.
- Curve mode popover header now shows the measured actual fan RPM (labeled
  "Actual") instead of the computed curve target; the curve target remains as a
  secondary "Curve target" row.
- Curve control re-applies the target when the fan mode reverts to system mode,
  not only when the temperature or percent changes.
- Fan monitor reuses a persistent SMC IOKit connection on a serial
  `.userInitiated` queue instead of opening a new connection on a low-priority
  detached task every tick, keeping temperature/RPM readings fresh under heavy
  CPU/RAM load.
- Removed terminal `sudo`/`launchctl` helper-management instructions from the
  README; dev install, helper authorization, and reload after a dev update are
  handled by `make install-dev` plus Settings > Safety and System Settings >
  Login Items, with no terminal command needed.
- The app now treats missing helper protocol fields as a stale helper instead of
  assuming the daemon is ready, and Settings > Safety offers a helper reload
  path through ServiceManagement.
- Manual/Curve popovers show a helper warning when fan targets are only previews
  because the privileged helper is not ready or needs reload.

### Fixed

- Fixed the Curve mode RPM display reporting the computed target (e.g. 1133 RPM)
  while the fan physically spun much faster: the popover now shows the real
  measured RPM and warns when the system is overriding the curve.
- Fixed persisted Curve mode showing a target after app launch without starting
  the curve-application loop once the helper becomes ready.
- Fixed curve re-assertion missing the case where actual RPM stays far below the
  requested target at the same curve percentage.

## [0.2.0] - 2026-06-26

### Added

- Added a configurable app update tick, defaulting to 1 second, for live temperature/RPM refresh and Curve target application.
- Added draggable Curve preview points with 0-100 C and 0-100% grid axes.
- Added a tested thermal-mass temperature estimator based on stable M4 Pro SMC sensors, with lightweight app-side smoothing.

### Changed

- Replaced the popover Manual target slider with a cleaner custom slider: a rounded track that fills with the accent color up to a circular thumb, removing the per-step tick marks from the native slider.
- Simplified the popover footer by hiding routine helper apply messages in Manual and Curve modes.
- Added the live Curve preview chart to the menu bar popover so current temperature and target track the curve without opening Settings.
- Stabilized the popover layout during live updates so footer controls no longer jump while Curve mode refreshes.
- Animated Manual/Curve popover height changes so mode switches grow and shrink smoothly.
- Fixed Curve preview x-axis labels clipping on the trailing edge by adding plot inset and label clamping.
- Changed Curve mode to run continuously until the user switches modes instead of ending after a timed run window.
- Simplified fan controls to Manual and Curve modes by removing the visible Monitor mode from the popover and Settings.
- Updated Curve control to sample a fresh temperature snapshot on each tick before applying the target.

### Fixed

- Centered the menu bar popover arrow over the fan icon and temperature text instead of anchoring it to the trailing edge of the status item.
- Tightened the menu bar status item width to fit the fan icon and temperature text so it no longer carries excess horizontal padding on either side.
- Fixed Curve target application lagging behind live temperature changes by applying targets immediately on snapshot updates and awaiting each helper write before the next tick.
- Fixed stale Curve targets that could lag behind live temperature/RPM changes.
- Fixed representative temperature spikes caused by unstable/cold/hot-spot SMC readings.
- Fixed ambiguous duplicate-temperature curve points by normalizing UI points and rejecting duplicate temperatures in core curve validation.
