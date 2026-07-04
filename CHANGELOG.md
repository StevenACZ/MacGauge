# Changelog

All notable changes to this project will be documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Interactive temperature-colors editor in Settings > Display: a colored
  30-90 °C strip with draggable threshold handles, plus a live menu bar
  preview that mirrors the real icon, current color band, and spin speed.
- Guided helper flow in Settings > Safety: a status card with a per-state
  icon and color, an authorize → approve → ready step row while setup is
  pending, and plain-language explanations of the privileged helper, extreme
  ranges (showing the live manual range), and returning control to macOS.
- Explanatory subtitles on settings rows (start at login, restore on quit,
  fan icon animation, and each menu bar module).
- Optional menu bar modules (Settings > Display) for CPU, memory, and network,
  each with its own compact live menu bar item — percent plus a mini scrolling
  chart, or stacked download/upload rates — refreshed on the same tick as the
  fan monitor and universal across Apple Silicon.
- Module detail popovers: CPU shows usage history, chip, core layout
  (performance + efficiency), awake-since time, and the apps using the most
  CPU; memory shows used/available, a pressure badge, and the apps using the
  most memory; network shows live download/upload charts, interface, local and
  public IP (copyable), router, and session traffic totals.
- Real RPM context while editing the fan curve: the drag bubble and the point
  editor show the estimated RPM for each percent, a right-hand RPM axis maps
  the percent scale to the fan's real range, and the live marker carries a
  label with the fan's actual measured RPM as it moves.

### Changed

- Renamed the app and repository from MacFan to MacGauge, reflecting that it
  now covers system stats beyond fan control. Brand only: the bundle ID,
  helper label, and SwiftPM identifiers keep the MacFan prefix so existing
  installs, helper authorizations, and settings survive the rename.
- Menu bar modules now keep a constant width: values reserve their widest
  realistic size (three digits plus unit), so the network item no longer
  shifts left and right as rates change between two and three digits.
- The CPU popover shows the performance/efficiency split as one square per
  core with a compact "8P + 4E" label, and "Awake since" as a duration with
  the boot date on its own line — no more truncated text.
- The fan icon now spins continuously, accelerating and coasting down with
  the fan's real speed instead of stepping between four fixed rates.
- Module charts start as a flat line at the current level while their history
  builds up, instead of repeatedly climbing out of zero at the left edge.
- The memory pressure badge reads the kernel's actual pressure level
  (`kern.memorystatus_vm_pressure_level`) instead of inferring it from the
  used percentage, matching Activity Monitor; the percent thresholds remain
  as a fallback.
- The curve chart now extends flat to both chart edges beyond the outermost
  points, matching how targets are actually computed, so curves with few
  points no longer look cut off.
- Always-on performance pass: the fan status item skips redundant title and
  width updates on ticks where nothing visible changed, closing the settings
  window now releases its UI tree instead of leaving it observing live
  monitors, the fan icon image cache is bounded, and unused localization
  strings were removed.

### Fixed

- The menu bar fan icon no longer wobbles while spinning. Two causes: SF
  Symbol canvases carry baseline padding, so rotating around the canvas
  center made the blades orbit by about a pixel; and re-drawing the vector
  symbol at every angle let AppKit rasterize it against a slightly different
  pixel grid on some angles, which read as intermittent 1-2 px jumps. The
  glyph is now rasterized once into a fixed high-resolution bitmap, and each
  frame rotates that bitmap around its alpha-weighted centroid.
- The popover header now reads MacGauge — it was the last user-visible spot
  still showing the old MacFan brand.

## [1.0.1] - 2026-07-02

### Fixed

- Fixed the app crashing at launch on every Mac except the machine it was built
  on: the SwiftPM-generated `Bundle.module` accessor never looked inside the
  installed app's `Contents/Resources`, so resolving the localized strings
  bundle aborted before the menu bar icon could appear. The app now loads the
  resources bundle from the packaged app first and keeps the SwiftPM accessor
  only as a development fallback.

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
