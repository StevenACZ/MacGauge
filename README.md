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
- The menu bar app registers a narrow SMAppService LaunchDaemon helper only from Settings > Safety. It does not store passwords.
- After the helper is approved, manual slider, curve, and automatic-restore commands use a privileged XPC Mach service, not Terminal, `sudo`, shell scripts, AppleScript, or command files.
- Manual slider and curve changes never trigger administrator approval or install the helper implicitly.

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
- The app's live manual and curve controls require the explicitly authorized local helper; CLI live writes remain experimental and require deliberate `sudo` flags.

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

Build the app bundle without opening it:

```sh
./script/build_and_run.sh stage
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
- `Contents/MacOS/M4FanHelper` for the privileged helper executable.
- `Contents/Library/LaunchDaemons/com.stevenacz.M4FanControl.XPCHelper.plist` for SMAppService registration.

Authorize the helper explicitly from Settings > Safety before using manual or curve controls. macOS may require one approval from that action. Slider, curve, restore automatic, launch, and status refresh never request administrator approval; if the helper is not ready, live controls stay locked until authorization is completed.

The helper warning's Settings button opens directly to the Safety tab. The current app helper identity is `com.stevenacz.M4FanControl.XPCHelper`. This intentionally avoids the older local helper label `com.stevenacz.M4FanControl.Helper`, which may still exist on Steven's Mac from pre-XPC builds. After `XPCHelper` is authorized, the app asks it to remove that legacy helper.

Local script builds are ad-hoc signed by default. For a stricter local signing test, set `SIGN_IDENTITY` before staging:

```sh
SIGN_IDENTITY="Developer ID Application: Example" ./script/build_and_run.sh stage
```

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

This CLI path is for controlled low-level testing only. It is not the normal app flow.

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
- Manual slider auto-applies after a short debounce only when the helper is already authorized; `Auto` remains explicit.
- Settings window with Celsius/Fahrenheit, start at login, restore on quit, manual target, editable curve points, run duration, color thresholds, icon animation, helper authorization, and safety toggle for edge ranges.
- Start at login uses `SMAppService.mainApp`; macOS may require approval in System Settings.
- Privileged fan writes from the app use the helper's XPC Mach service after the one-time Safety authorization.
- The locked-helper Settings button opens the Safety tab directly.
- No Accessibility permission is requested.

## Limitations

- Sensor names on Apple Silicon are not fully mapped. The CLI discovers plausible temperature keys and reports a representative average.
- The helper command path is XPC-based under `com.stevenacz.M4FanControl.XPCHelper`. The SwiftPM bundling script creates the right SMAppService layout, but a fully production-grade distribution should use a stable Apple signing identity and notarized bundle.
- Continuous curve control is driven by the app and sends time-limited helper commands.
- `thermalmonitord` and firmware behavior can vary by M4 Pro/Max/base model and macOS release.
- Reported `F0Mn`/`F0Mx` values are guidelines, not guaranteed physical limits.
- Live write paths are experimental and intentionally noisy about permission and safety failures.

## Helper management

Authorize/install helper from the app Settings > Safety tab. Manual slider and curve changes do not prompt for approval.

The normal app flow does not require terminal `sudo`. The command below is only a recovery path for removing the current `XPCHelper` helper:

Manual uninstall:

```sh
sudo /Users/steven/Applications/M4FanControl.app/Contents/MacOS/M4FanHelper --uninstall-daemon
```
