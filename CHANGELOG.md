# Changelog

All notable changes to this project will be documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.3.0] - 2026-07-09

### Fixed

- Restore automatic on quit now actually runs: the restore used to be
  scheduled while the process was already exiting, so fans stayed pinned at
  the last manual or curve target after quitting. Termination now waits
  (bounded to two seconds) for the helper to hand control back to macOS.
- Fan control no longer misses the moment the helper becomes ready: launching
  with a saved curve, or authorizing the helper in manual mode, could leave
  the control loop stopped until the temperature drifted enough. The app now
  acts on the committed helper state.
- Menu bar appearance changes (temperature unit, band colors, color styles,
  fan animation toggle) apply immediately instead of waiting for the next
  meaningful sensor change.
- The helper's own health check can no longer kill it mid-write: pings answer
  instantly even while a slow fan-mode unlock is running, and helper restarts
  now wait for in-flight commands to finish.
- Restoring automatic control is best-effort per fan everywhere (app, helper,
  CLI): one stuck fan no longer leaves the others pinned manual or skips the
  force-test reset, and failures are reported honestly.
- A failed target write rolls the fan back to automatic instead of leaving it
  pinned manual with a stale target.
- Fan writes report "contested" from the target readback instead of the
  instantaneous RPM, so a large legitimate speed change no longer flashes a
  false conflict warning.
- Network rates survive 4 GiB counter wraps: interface statistics now come
  from 64-bit counters, so sustained fast transfers no longer freeze the menu
  bar rate or lose session totals.
- The network popover's public IP refreshes after switching networks or VPN
  instead of staying stale; IPv6-only networks now show interface, router,
  and local address.
- Curve points must be finite numbers (a crafted curve string could silently
  drive fans to 100%), and CLI curve strings tolerate spaces around values.
- Fan RPM encoding clamps out-of-range values instead of crashing when
  dangerous ranges are unlocked.
- Fanless Macs read as zero fans again instead of an SMC error that also hid
  the temperature readout, and a corrupt fan count can no longer hang polling.
- The SwiftUI Settings scene now forwards to the real settings window, so it
  can never open an unpinned duplicate.
- Top-process sampling for the CPU and RAM popovers runs off the main thread.
- macOS Reduce Motion is honored: the fan spin, sliding charts, and settings
  animations go still while it is on, and the spin also pauses while the
  display sleeps.
- The Safety tab refreshes helper status when switching to it, not only when
  the settings window opens.
- CLI: unknown flags error out instead of being silently accepted, and Ctrl-C
  interrupts long curve intervals promptly.

### Changed

- Settings controls that used the system accent color now use the app accent,
  so the window no longer mixes two accents on Macs with a custom system
  accent.
- The fan popover's status banner can wrap to three lines so longer helper
  messages stay readable in Spanish.
- The manual slider is keyboard-operable (focusable, arrow keys), color
  swatches expose their selected state, and symbol-only buttons carry
  accessibility labels.
- Internal restructure with no visual changes: the Display settings pane
  split into focused section files, repeated UI extracted into shared
  components, views organized into Popover/Shared/Settings folders, and the
  pure fan-range and curve-editor math moved into MacFanCore under tests.
- `script/build_and_run.sh` moved to `scripts/` with the rest of the tooling.

### Security

- The privileged helper no longer writes logs to predictable /tmp paths,
  rejects oversized command payloads, and refuses queued commands older than
  30 seconds (for example commands stranded across a sleep).

## [1.2.0] - 2026-07-04

### Added

- Performance mode (Settings > General): Efficient (the default) steps the
  menu bar values and charts once per tick with no in-between animation
  frames and keeps the fan icon still, with its color still tracking
  temperature — the right choice for an app running in the background all
  day. Full keeps every continuous animation: sliding charts, rolling
  digits, and the 30 fps spinning fan icon.

- Spacing control for the menu bar modules (Settings > Display): Together,
  Tight, Normal, or Wide. Tight, Normal, and Wide keep one independent menu
  bar item per module (own click, popover, and drag position) and trim or
  grow the dead space around each; Together fuses the modules into a single
  block so even the system's own gap between items disappears, while clicks
  stay per-module — no whole-block highlight, and each click opens only that
  module's popover anchored to it.
- Per-module graph length for the CPU and memory charts: Compact, Medium, or
  Long, chosen independently for each.
- Per-module color style: Multicolor (the module's own tint), Mono (menu bar
  label color), Gray, or By load — the chart takes the same normal/medium/hot
  colors as the fan temperature bands as usage climbs (CPU by sustained
  usage, memory by real memory pressure). The network arrows follow their own
  selected style, and the fan item gets its own Temperature/Mono/Gray choice.

- Show more / Show less in the CPU and RAM popovers: the top-processes list
  expands from 5 to 15 rows and the popover grows with it, collapsing back
  on reopen.
- Customizable By-load colors per module: CPU and RAM get their own
  0-100 % band editor (draggable thresholds plus a color per band, like the
  temperature editor) so each user decides when the chart turns from calm
  to warning to hot; the network module gets its own upload/download arrow
  colors, and the color presets gain Orange and Blue. The CPU/RAM/network
  detail popovers now follow the exact same configured colors instead of
  their old fixed tints.
- Simulated activity in the Settings > Display previews: CPU and memory
  sweep from idle to ~95 % and back, and the network preview climbs from a
  few KB/s into the MB/s range, so color styles and thresholds visibly trip
  in real time while being adjusted — no need to load the Mac to test them.
  The Modules section gets a preview of the whole enabled set, reacting
  live to the spacing choice.

### Changed

- The CPU and RAM popovers now rank every process the user can read —
  compilers, helpers, and daemons included, like Activity Monitor — instead
  of only regular applications, so a heavy build no longer leaves MacGauge
  looking like the top consumer by omission. Detail popover charts also
  follow the performance mode, keeping MacGauge's own footprint honest while
  the panel is open.
- Settings > Display redesigned as a visual-configuration screen with a
  section sidebar (fan & temperature, modules, CPU, RAM, network): one card
  at a time instead of a long scroll, each with a live preview that reflects
  the current style choices in real time, with the previews running while
  the tab is open even if a module is hidden. The fan icon and the
  temperature colors share one section, and each metric card is ordered for
  live color testing — preview first, color style and band editor right
  under it, graph length last.
- The performance mode picker (Settings > General) became two selectable
  cards with an icon and a one-line promise each — Efficient (light all
  day) and Full (every animation) — and every General row gained an icon.
- The CPU/RAM By-load bands now read Low / Medium / High — "hot" stays
  exclusive to temperature, where it belongs.
- The Modules section uses the pane's full width: toggle rows no longer
  reserve a wide control column, so descriptions run in one or two lines
  instead of wrapping next to a dead column.
- Menu bar module animations polished: percent values and network rates roll
  with a numeric transition, chart colors cross-fade when the style or load
  band changes, and the network arrows dim while their direction is idle.

### Fixed

- Idle CPU usage: the menu bar modules kept a continuous animation pipeline
  alive (sliding sparklines, rolling digits, and the 30 fps fan icon each
  forced macOS to re-layout and re-snapshot the status items up to the
  display refresh rate), holding the app at most of one CPU core around the
  clock. In the Efficient performance mode the app now idles at a few
  percent.
- Closed popovers kept rendering: every popover's SwiftUI content (fan panel,
  CPU/RAM/network details) was created at startup and stayed live while
  closed, re-rendering charts and animations on every tick and keeping the
  per-app process sampler polling. Popover content is now built when the
  popover opens and released when it closes.
- The CPU popover could stay on "Measuring..." forever: switching between the
  CPU and RAM popovers let the closing view's teardown land after the opening
  view's start and kill the shared process sampler. Start/stop is now
  reference-counted, and the first real reading lands in half a second.
- Settings > Display > Fan now says why the fan icon is not spinning in the
  Efficient performance mode (notice + disabled toggle, and the preview stays
  still), instead of showing an animation the menu bar would not play.
- The settings window could drift away from its designed size — macOS can
  resize even a user-non-resizable window programmatically (edge tiling,
  toolbar reshapes), leaving the fixed-size content floating in dead space
  with a clipped scroll bar. The window now pins its content size and snaps
  back if anything resizes it.
- Settings cards could lose their window margins on every tab: a wide
  always-mounted row (the temperature band editor next to the sidebar)
  pushed the shared tab stack past the window paddings. The rigid rows are
  slimmer and every tab is pinned to the designed content width.

## [1.1.0] - 2026-07-03

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
