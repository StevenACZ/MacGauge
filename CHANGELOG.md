# Changelog

All notable changes to this project will be documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Standard Swift project workflow tooling: shared formatting config, Makefile
  checks, optional Lefthook hooks, and contributor/security docs.
- `make install-dev` / `scripts/install_dev.sh` for Apple Development signed
  local reinstalls to `~/Applications`.
- Contested-control detection in the popover: a warning banner appears when the
  system (`thermalmonitord`) is overriding the requested fan target.
- Verified helper write: `setPercent` now reads back `F0Md`/`F0Ac` after writing
  and re-asserts manual mode plus the target (bounded retry) when the system
  reverts it, returning the actual RPM, mode, and contested flag.

### Changed

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

### Fixed

- Fixed the Curve mode RPM display reporting the computed target (e.g. 1133 RPM)
  while the fan physically spun much faster: the popover now shows the real
  measured RPM and warns when the system is overriding the curve.

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
