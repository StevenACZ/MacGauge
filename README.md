# M4FanControl

Personal SwiftPM fan-control app and CLI for Steven's Apple Silicon M4 Pro Mac.

This is private/local software, not a public universal app. It defaults to read-only monitoring and keeps live SMC writes behind explicit approval.

## Safety model

- Read-only commands run as the normal user.
- Write commands are dry-run by default.
- Live writes require `sudo`, `--live`, and `--i-understand`.
- 0 RPM requires `--allow-zero --allow-dangerous` and should only be used after explicit manual approval.
- Targets below reported minimum, above reported maximum, <=10%, or >=95% require `--allow-dangerous`.
- `curve` restores automatic mode on normal exit where possible unless `--no-restore-auto` is provided.
- No launch daemon, login item, or restart persistence is installed in this demo.
- The menu bar app installs a narrow local LaunchDaemon helper after one macOS administrator approval. It does not store passwords.

Fan control can damage hardware or interfere with macOS thermal management. Keep Activity Monitor or another temperature monitor visible during manual tests and return to automatic control after testing.

## Current Apple Silicon state

Apple does not publish a public fan-control API for macOS. This CLI talks to the private `AppleSMC` IOKit service.

References checked on June 24, 2026:

- [`agoodkind/macos-smc-fan`](https://github.com/agoodkind/macos-smc-fan): current Apple Silicon SMC fan-control research, including M4/M5 behavior, `Ftst`, and the need for a privileged helper for persistent writes.
- [`exelban/stats#2928`](https://github.com/exelban/stats/issues/2928): M3/M4+ manual fan control can appear to succeed while `thermalmonitord` immediately overrides writes unless `Ftst`/manual mode is handled.
- [Asahi Linux SMC docs](https://asahilinux.org/docs/hw/soc/smc/): Apple Silicon SMC exposes many four-character keys for fans, temperatures, power, and other hardware state.
- [`beltex/SMCKit`](https://github.com/beltex/SMCKit): older Swift SMC interface and key format reference, primarily Intel-era but still useful for IOKit structure and legacy formats.
- [`dkorunic/iSMC`](https://github.com/dkorunic/iSMC): current macOS SMC CLI reference for decoding sensors and fan data.

Practical implications:

- Reading fan RPM and many temperature-like SMC keys usually works without root.
- Apple Silicon fan keys use 4-byte little-endian floats for RPM/temperature on modern hardware, while Intel-era tools often use fixed-point formats.
- On tested M4 hardware, `thermalmonitord` can keep fans in system mode (`F0Md = 3`) and block manual writes until `Ftst = 1` lets the system yield control.
- A persistent, polished app should use a privileged helper daemon installed through Apple's ServiceManagement path. A production helper generally needs proper signing and a Developer ID certificate.
- This demo uses a root CLI for experimental manual writes instead of installing a helper.

## Build the CLI

```sh
cd /Users/steven/Desktop/Proyectos/M4FanControl
swift build
```

## Build and open the menu bar app

```sh
cd /Users/steven/Desktop/Proyectos/M4FanControl
./script/build_and_run.sh
```

This stages the app at:

```text
/Users/steven/Desktop/Proyectos/M4FanControl/dist/M4FanControl.app
```

Install a copy to `~/Applications` and open it:

```sh
./script/build_and_run.sh --install
```

The app bundle includes:

- `Contents/Resources/m4fan` for CLI compatibility.
- `Contents/Resources/M4FanHelper` for one-time local helper installation.

The first live control action may prompt for administrator approval to install the helper. After that, slider/curve changes use the helper and should not prompt repeatedly across app restarts.

## Read-only commands

```sh
.build/debug/m4fan status
.build/debug/m4fan fans
.build/debug/m4fan temps
.build/debug/m4fan temps --all
.build/debug/m4fan doctor
```

`status` prints the detected model, chip string, macOS version, process thermal state, fan count, representative SMC temperature, and fan RPM data when available.

## Dry-run write commands

These do not write to the SMC:

```sh
.build/debug/m4fan set --fan 0 --percent 45
.build/debug/m4fan set --fan 0 --rpm 3000
.build/debug/m4fan auto
.build/debug/m4fan curve --fan 0 --points 40:40,60:50 --once
```

## Manual live test

Use a moderate fan percentage first. Do not test 0 RPM or maximum in automation.

```sh
cd /Users/steven/Desktop/Proyectos/M4FanControl
sudo .build/debug/m4fan set --fan 0 --percent 45 --live --i-understand
```

Return to automatic control:

```sh
sudo .build/debug/m4fan auto --live --i-understand
```

If the live command reports `notPrivileged`, `badCommand`, or a firmware error, do not keep retrying aggressively. Capture the exact output and run:

```sh
.build/debug/m4fan doctor
```

## Curve demo

Dry-run once:

```sh
.build/debug/m4fan curve --fan 0 --points 40:40,60:50 --once
```

Live for 60 seconds with automatic restore on exit:

```sh
sudo .build/debug/m4fan curve --fan 0 --points 40:40,60:50 --duration 60 --live --i-understand
```

## Menu bar app features

- Compact status item showing representative temperature and current fan RPM.
- Compact status item showing representative temperature only, with colored fan icon/text.
- Popover with monitor, manual, and curve modes.
- Manual slider auto-applies after a short debounce; `Auto` remains explicit.
- Settings window with Celsius/Fahrenheit, start at login, restore on quit, manual target, editable curve points, run duration, color thresholds, icon animation, helper authorization, and safety toggle for edge ranges.
- Start at login uses `SMAppService.mainApp`; macOS may require approval in System Settings.
- No Accessibility permission is requested.

## Limitations

- Sensor names on Apple Silicon are not fully mapped. The CLI discovers plausible temperature keys and reports a representative average.
- The helper uses a private local command-file protocol in Steven's Application Support folder. A production app should migrate this to a signed XPC helper.
- Continuous curve control is driven by the app and sends time-limited helper commands.
- `thermalmonitord` and firmware behavior can vary by M4 Pro/Max/base model and macOS release.
- Reported `F0Mn`/`F0Mx` values are guidelines, not guaranteed physical limits.
- Live write paths are experimental and intentionally noisy about permission and safety failures.

## Helper management

Authorize/install helper from the app Settings > Safety tab, or let the first manual slider change prompt for approval.

Manual uninstall:

```sh
sudo /Users/steven/Applications/M4FanControl.app/Contents/Resources/M4FanHelper --uninstall-daemon
```
