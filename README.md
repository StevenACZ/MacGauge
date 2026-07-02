# MacFan

Fan control and thermal monitoring for Apple Silicon Macs (M1 and later),
built as a Swift Package: a menu bar app, a CLI, and a narrow privileged
helper.

MacFan defaults to read-only monitoring. Live SMC writes always sit behind
explicit approval: a one-time helper authorization in the app, or deliberate
`sudo` flags in the CLI.

> **Warning**
> Fan control can interfere with macOS thermal management and, in the worst
> case, damage hardware. Keep an eye on temperatures during manual tests and
> return to automatic control when you are done. Use at your own risk.

## Features

- Menu bar app with live temperature and per-fan RPM.
- Manual mode: percentage slider applied to every fan, each converted to its
  own RPM range.
- Curve mode: editable temperature→percent curve applied continuously, with a
  live preview chart.
- Works on any Apple Silicon Mac: desktops and laptops with one or more fans
  are controlled together; fanless Macs (MacBook Air) are detected and shown
  as passively cooled.
- Contested-control detection: a warning appears when `thermalmonitord`
  overrides the requested target, and the app re-asserts it.
- Verified writes: the helper reads back fan mode and actual RPM after each
  write and retries when the system reverts it.
- English and Spanish UI, following the system language with an in-app
  override.
- No Accessibility permission, no analytics, no network access.

## Requirements

- Apple Silicon Mac (M1 or later).
- macOS 13 Ventura or later.

## Build the menu bar app

```sh
git clone https://github.com/StevenACZ/MacFan.git
cd MacFan
make stage            # builds dist/MacFan.app (ad-hoc signed)
./script/build_and_run.sh run
```

For a signed local install to `~/Applications` (requires an Apple Development
identity in your keychain):

```sh
make install-dev
```

Authorize the helper from Settings > Safety before using Manual or Curve
modes. macOS may ask for one approval in System Settings > Login Items. The
slider, curve, and restore-automatic actions never prompt again after that.

## Safety model

- Read-only commands run as the normal user.
- CLI write commands are dry-run by default; live writes require `sudo`,
  `--live`, and `--i-understand`.
- 0 RPM requires `--allow-zero --allow-dangerous`. Targets below the reported
  minimum, above the maximum, ≤10%, or ≥95% require `--allow-dangerous`.
- The app registers a narrow SMAppService LaunchDaemon helper only from
  Settings > Safety. It exposes only fan-control actions over XPC, verifies
  its clients' code signature, and never stores passwords.
- `curve` (CLI) restores automatic mode on exit unless `--no-restore-auto` is
  given; the app can restore automatic control on quit.

## CLI

Read-only:

```sh
.build/debug/macfan status    # model, chip, fans, representative temperature
.build/debug/macfan fans
.build/debug/macfan temps [--all]
.build/debug/macfan doctor
```

Dry-run writes (no SMC access):

```sh
.build/debug/macfan set --percent 45          # all fans
.build/debug/macfan set --fan 0 --rpm 3000    # one fan
.build/debug/macfan auto
.build/debug/macfan curve --points 40:40,60:50 --once
```

Live writes (controlled low-level testing only — the app is the normal flow):

```sh
sudo .build/debug/macfan set --percent 45 --live --i-understand
sudo .build/debug/macfan auto --live --i-understand
```

## How it works

Apple does not publish a fan-control API for macOS. MacFan talks to the
private `AppleSMC` IOKit service:

- Fan state lives in per-fan four-character keys (`F0Ac`, `F0Tg`, `F0Mn`,
  `F0Mx`, `F0Md`, …) discovered through `FNum`.
- On recent Apple Silicon (observed on M3/M4), `thermalmonitord` can hold
  fans in system mode and block manual writes until `Ftst = 1` lets the
  system yield control; it can also reclaim control under heavy thermal
  load. MacFan detects this, warns, and re-asserts the target, but cannot
  guarantee the firmware never wins.
- The representative temperature uses a trimmed mean over stable die-level
  thermal-mass sensors, with a broad plausible-key fallback for hardware
  where the preferred sensors are missing.

Useful references: [macos-smc-fan](https://github.com/agoodkind/macos-smc-fan),
[exelban/stats#2928](https://github.com/exelban/stats/issues/2928),
[Asahi Linux SMC docs](https://asahilinux.org/docs/hw/soc/smc/),
[SMCKit](https://github.com/beltex/SMCKit),
[iSMC](https://github.com/dkorunic/iSMC).

## Limitations

- Sensor names differ between chip generations and are not fully mapped;
  MacFan falls back to broad plausible thermal-mass keys when the preferred
  set is missing.
- Reported fan minimum/maximum values are guidelines, not guaranteed physical
  limits.
- `thermalmonitord` and firmware behavior vary by model and macOS release.
- A production-grade distribution needs a stable Developer ID identity and a
  notarized bundle; local script builds are ad-hoc signed.

## Helper management

Authorize once from Settings > Safety. After a dev update the app detects a
stale helper and repairs it automatically; the Safety tab shows live status
and a non-destructive Fix button. To remove the helper, toggle it off in
System Settings > Login Items > Allow in Background.

## Development

```sh
make ci-check   # lint + build + tests
make format
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE)
