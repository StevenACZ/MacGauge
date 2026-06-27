# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Added a configurable app update tick, defaulting to 1 second, for live temperature/RPM refresh and Curve target application.
- Added draggable Curve preview points with 0-100 C and 0-100% grid axes.
- Added a tested thermal-mass temperature estimator based on stable M4 Pro SMC sensors, with lightweight app-side smoothing.

### Changed

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
- Fixed Curve target application lagging behind live temperature changes by applying targets immediately on snapshot updates and awaiting each helper write before the next tick.
- Fixed stale Curve targets that could lag behind live temperature/RPM changes.
- Fixed representative temperature spikes caused by unstable/cold/hot-spot SMC readings.
- Fixed ambiguous duplicate-temperature curve points by normalizing UI points and rejecting duplicate temperatures in core curve validation.
