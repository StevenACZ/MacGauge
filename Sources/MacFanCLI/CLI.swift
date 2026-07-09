import Foundation
import MacFanCore

struct CLIError: LocalizedError {
    let message: String
    let exitCode: Int

    init(_ message: String, exitCode: Int = 1) {
        self.message = message
        self.exitCode = exitCode
    }

    var errorDescription: String? { message }
}

struct ParsedArguments {
    let command: String
    let options: [String: String]
    let flags: Set<String>

    func value(_ name: String) -> String? {
        options[name]
    }

    func has(_ name: String) -> Bool {
        flags.contains(name)
    }

    func double(_ name: String) throws -> Double? {
        guard let raw = value(name) else { return nil }
        guard let parsed = Double(raw) else {
            throw CLIError("Invalid number for --\(name): \(raw)")
        }
        return parsed
    }
}

struct CLI {
    let parsed: ParsedArguments

    init(arguments: [String]) throws {
        parsed = try CLI.parse(arguments)
    }

    func run() throws {
        if parsed.has("help") {
            printHelp()
            return
        }
        switch parsed.command {
        case "help", "--help", "-h":
            printHelp()
        case "status":
            try status()
        case "fans":
            try fans()
        case "temps":
            try temperatures()
        case "set":
            try setFan()
        case "auto":
            try automatic()
        case "curve":
            try curve()
        case "doctor":
            try doctor()
        default:
            throw CLIError("Unknown command '\(parsed.command)'. Run macfan help.", exitCode: 2)
        }
    }

    private static let allowedOptionNames: [String: Set<String>] = [
        "help": [], "--help": [], "-h": [],
        "status": [],
        "fans": [],
        "temps": ["all"],
        "set": ["fan", "rpm", "percent", "live", "i-understand", "allow-dangerous", "allow-zero"],
        "auto": ["fan", "live", "i-understand", "keep-ftst"],
        "curve": [
            "points", "interval", "duration", "fan", "once", "live", "i-understand",
            "allow-dangerous", "allow-zero", "no-restore-auto",
        ],
        "doctor": [],
    ]

    private static func parse(_ arguments: [String]) throws -> ParsedArguments {
        var command = "status"
        var startIndex = 0
        if let first = arguments.first, !first.hasPrefix("-") {
            command = first
            startIndex = 1
        }

        var options: [String: String] = [:]
        var flags = Set<String>()
        var index = startIndex

        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--") else {
                throw CLIError("Unexpected argument '\(token)'. Options must use --name value or --flag.", exitCode: 2)
            }

            let name = String(token.dropFirst(2))
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                options[name] = arguments[index + 1]
                index += 2
            } else {
                flags.insert(name)
                index += 1
            }
        }

        if let allowed = allowedOptionNames[command] {
            // --help is always accepted and handled in run().
            let unknown = Set(options.keys).union(flags).subtracting(allowed).subtracting(["help"]).sorted()
            guard unknown.isEmpty else {
                let listed = unknown.map { "--\($0)" }.joined(separator: ", ")
                throw CLIError("Unknown option(s) for '\(command)': \(listed). Run macfan help.", exitCode: 2)
            }
        }

        return ParsedArguments(command: command, options: options, flags: flags)
    }

    private func status() throws {
        stdoutLine("Model: \(SystemInfo.hardwareModel)")
        stdoutLine("Chip: \(SystemInfo.chipName)")
        stdoutLine("macOS: \(SystemInfo.osVersion)")
        stdoutLine("Process thermal state: \(SystemInfo.thermalState)")
        stdoutLine("Privilege: \(SystemInfo.isRoot ? "root" : "user")")

        do {
            let smc = try SMCClient()
            let fans = try FanController(smc: smc).allFans()
            let tempReader = TemperatureReader(smc: smc)
            stdoutLine("SMC: available")
            stdoutLine("Fan count: \(fans.count)")
            if let representative = try tempReader.representativeTemperature() {
                stdoutLine("Representative SMC temperature: \(formatCelsius(representative))")
            } else {
                stdoutLine("Representative SMC temperature: unavailable")
            }
            printFans(fans)
        } catch {
            stdoutLine("SMC: unavailable (\(error.localizedDescription))")
        }
    }

    private func fans() throws {
        let smc = try SMCClient()
        let controller = FanController(smc: smc)
        let fans = try controller.allFans()
        stdoutLine("Fan count: \(fans.count)")
        stdoutLine("Ftst available: \(controller.forceTestAvailable() ? "yes" : "no")")
        if let ftst = controller.forceTestValue() {
            stdoutLine("Ftst value: \(ftst)")
        }
        printFans(fans)
    }

    private func temperatures() throws {
        let smc = try SMCClient()
        let reader = TemperatureReader(smc: smc)
        let includeAll = parsed.has("all")
        let readings = try reader.readings(includeAll: includeAll)
        if let representative = try reader.representativeTemperature() {
            stdoutLine("Representative: \(formatCelsius(representative))")
        }
        stdoutLine("Temperature sensors: \(readings.count)")
        for reading in readings {
            stdoutLine("  \(reading.key) [\(reading.type)]: \(formatCelsius(reading.celsius))")
        }
    }

    private func setFan() throws {
        let smc = try SMCClient()
        let controller = FanController(smc: smc)
        let fans: [FanInfo]
        if let fanValue = parsed.value("fan") {
            guard let index = Int(fanValue) else {
                throw CLIError("Invalid fan index: \(fanValue)")
            }
            fans = [try controller.fanInfo(index: index)]
        } else {
            fans = try controller.allFans()
        }
        guard !fans.isEmpty else {
            throw CLIError("This Mac reports no controllable fans.")
        }

        var plans: [(fan: FanInfo, target: Double)] = []
        for fan in fans {
            let target = try targetRPM(controller: controller, fan: fan)
            try validateTarget(target, fan: fan)
            plans.append((fan, target))
        }

        if !parsed.has("live") {
            for plan in plans {
                stdoutLine("[dry-run] Would set fan \(plan.fan.index) to \(Int(plan.target.rounded())) RPM.")
            }
            stdoutLine("[dry-run] Add --live --i-understand and run with sudo to write to SMC.")
            return
        }

        try requireLivePermission()
        for plan in plans {
            let strategy = try controller.setTargetRPM(index: plan.fan.index, rpm: plan.target)
            stdoutLine("Set fan \(plan.fan.index) target to \(Int(plan.target.rounded())) RPM using \(strategy.rawValue).")
        }
        stdoutLine("Use 'sudo .build/debug/macfan auto --live --i-understand' to return to automatic control.")
    }

    private func automatic() throws {
        let smc = try SMCClient()
        let controller = FanController(smc: smc)
        let allFans = try controller.allFans()
        let fanIndexes: [Int]
        if let fan = parsed.value("fan") {
            guard let index = Int(fan) else {
                throw CLIError("Invalid fan index: \(fan)")
            }
            fanIndexes = [index]
        } else {
            fanIndexes = allFans.map(\.index)
        }

        if !parsed.has("live") {
            stdoutLine("[dry-run] Would return fan(s) \(fanIndexes.map(String.init).joined(separator: ", ")) to automatic mode.")
            stdoutLine("[dry-run] Would reset Ftst to 0 if present, unless --keep-ftst is used.")
            return
        }

        try requireLivePermission()
        // Best effort: one stuck fan must not leave the others pinned manual
        // or skip the Ftst reset.
        var failures: [String] = []
        for fan in fanIndexes {
            do {
                try controller.returnToAutomatic(index: fan)
            } catch {
                failures.append("fan \(fan): \(error.localizedDescription)")
            }
        }
        if !parsed.has("keep-ftst") {
            do {
                try controller.resetForceTestIfAvailable()
            } catch {
                failures.append("Ftst reset: \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw CLIError("Automatic restore incomplete: \(failures.joined(separator: "; "))")
        }
        stdoutLine("Returned fan(s) \(fanIndexes.map(String.init).joined(separator: ", ")) to automatic control.")
    }

    private func curve() throws {
        let smc = try SMCClient()
        let controller = FanController(smc: smc)
        let reader = TemperatureReader(smc: smc)
        let curve = try FanCurve.parse(parsed.value("points"))
        let interval = try parsed.double("interval") ?? 5.0
        let duration = try parsed.double("duration")
        let once = parsed.has("once")
        let fans: [FanInfo]
        if let fanValue = parsed.value("fan") {
            guard let index = Int(fanValue) else {
                throw CLIError("Invalid fan index: \(fanValue)")
            }
            fans = [try controller.fanInfo(index: index)]
        } else {
            fans = try controller.allFans()
        }
        guard !fans.isEmpty else {
            throw CLIError("This Mac reports no controllable fans.")
        }
        let live = parsed.has("live")

        if live {
            try requireLivePermission()
        } else {
            stdoutLine("[dry-run] Curve writes are disabled. Add --live --i-understand and run with sudo to write.")
        }

        StopFlag.installSignalHandlers()
        let start = Date()
        var wroteLive = false
        defer {
            if live, wroteLive, !parsed.has("no-restore-auto") {
                var failures: [String] = []
                for fan in fans {
                    do {
                        try controller.returnToAutomatic(index: fan.index)
                    } catch {
                        failures.append("fan \(fan.index)")
                    }
                }
                do {
                    try controller.resetForceTestIfAvailable()
                } catch {
                    failures.append("Ftst reset")
                }
                if failures.isEmpty {
                    stderrLine("restored fan(s) \(fans.map { String($0.index) }.joined(separator: ", ")) to automatic control")
                } else {
                    stderrLine(
                        "WARNING: automatic restore failed for \(failures.joined(separator: ", ")); run 'sudo macfan auto --live --i-understand'"
                    )
                }
            }
        }

        repeat {
            guard let temp = try reader.representativeTemperature() else {
                throw CLIError("No representative SMC temperature available for curve control.")
            }
            let percent = curve.percent(for: temp)
            for fan in fans {
                let rpm = try controller.targetRPM(forPercent: percent, fan: fan)
                try validateTarget(rpm, fan: fan, percent: percent, fromCurve: true)

                if live {
                    let strategy = try controller.setTargetRPM(index: fan.index, rpm: rpm)
                    wroteLive = true
                    stdoutLine(
                        "fan=\(fan.index) temp=\(formatCelsius(temp)) target=\(formatPercent(percent)) rpm=\(Int(rpm.rounded())) strategy=\(strategy.rawValue)"
                    )
                } else {
                    stdoutLine(
                        "[dry-run] fan=\(fan.index) temp=\(formatCelsius(temp)) target=\(formatPercent(percent)) rpm=\(Int(rpm.rounded()))")
                }
            }

            if once { break }
            if let duration, Date().timeIntervalSince(start) >= duration { break }
            sleepUnlessStopped(seconds: max(1, interval))
        } while !StopFlag.shouldStop
    }

    // Sleeps in short chunks so Ctrl-C interrupts long curve intervals fast.
    private func sleepUnlessStopped(seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while !StopFlag.shouldStop {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            Thread.sleep(forTimeInterval: min(0.25, remaining))
        }
    }

    private func doctor() throws {
        stdoutLine("Model: \(SystemInfo.hardwareModel)")
        stdoutLine("Chip: \(SystemInfo.chipName)")
        stdoutLine("macOS: \(SystemInfo.osVersion)")
        stdoutLine("Privilege: \(SystemInfo.isRoot ? "root" : "user")")

        let smc = try SMCClient()
        let controller = FanController(smc: smc)
        let fans = try controller.allFans()
        stdoutLine("SMC: available")
        stdoutLine("SMC struct stride: \(MemoryLayout<SMCParamStruct>.stride)")
        stdoutLine("Fan count: \(fans.count)")
        stdoutLine("Ftst available: \(controller.forceTestAvailable() ? "yes" : "no")")

        for fan in fans {
            stdoutLine(
                "Fan \(fan.index): modeKey=\(fan.modeKey ?? "unavailable") mode=\(fan.mode.map(String.init) ?? "unavailable") current=\(formatRPM(fan.currentRPM))"
            )
        }

        stdoutLine(
            "Write readiness: \(SystemInfo.isRoot ? "root process; live writes may be attempted with explicit flags" : "not root; live writes should fail")"
        )
    }

    private func printFans(_ fans: [FanInfo]) {
        for fan in fans {
            let label = fan.name.map { " \($0)" } ?? ""
            stdoutLine("Fan \(fan.index)\(label):")
            stdoutLine("  current: \(formatRPM(fan.currentRPM))")
            stdoutLine("  min:     \(formatRPM(fan.minRPM))")
            stdoutLine("  max:     \(formatRPM(fan.maxRPM))")
            stdoutLine("  target:  \(formatRPM(fan.targetRPM))")
            stdoutLine("  mode:    \(fan.mode.map(String.init) ?? "unavailable")\(fan.modeKey.map { " (\($0))" } ?? "")")
        }
    }

    private func targetRPM(controller: FanController, fan: FanInfo) throws -> Double {
        if let rpm = try parsed.double("rpm") {
            return rpm
        }

        if let percent = try parsed.double("percent") {
            guard percent >= 0, percent <= 100 else {
                throw CLIError("--percent must be between 0 and 100.")
            }
            return try controller.targetRPM(forPercent: percent, fan: fan)
        }

        throw CLIError("Provide --rpm N or --percent N.")
    }

    // Maps the shared HelperCommandSafety policy onto CLI flags and richer
    // error text; curve targets get no extra leniency over direct ones.
    private func validateTarget(_ rpm: Double, fan: FanInfo, percent: Double? = nil, fromCurve: Bool = false) throws {
        guard rpm.isFinite, rpm >= 0 else {
            throw CLIError("Target RPM must be a finite value >= 0.")
        }

        if rpm == 0 && !parsed.has("allow-zero") {
            throw CLIError(
                "0 RPM is dangerous. Add --allow-zero --allow-dangerous only for deliberate, supervised zero-RPM testing.")
        }

        let safety = HelperCommandSafety()
        let allowDangerous = parsed.has("allow-dangerous")
        do {
            if let percent {
                try safety.validate(percent: percent, allowDangerous: allowDangerous, allowZero: parsed.has("allow-zero"))
            }
            try safety.validate(rpm: rpm, fan: fan, percent: percent ?? 0, allowDangerous: allowDangerous)
        } catch {
            let minText = formatRPM(fan.minRPM)
            let maxText = formatRPM(fan.maxRPM)
            throw CLIError(
                "Target \(Int(rpm.rounded())) RPM is outside the conservative safe band (min \(minText), max \(maxText), percent \(percent.map(formatPercent) ?? "n/a")). Add --allow-dangerous only for approved manual testing."
            )
        }
    }

    private func requireLivePermission() throws {
        guard parsed.has("i-understand") else {
            throw CLIError("Live SMC writes require --i-understand.")
        }

        guard SystemInfo.isRoot else {
            throw CLIError("Live SMC writes require root. Re-run with sudo after reviewing README.md.")
        }
    }

    private func printHelp() {
        stdoutLine(
            """
            macfan - Apple Silicon fan-control CLI

            Read-only commands:
              macfan status
              macfan fans
              macfan temps [--all]
              macfan doctor

            Dry-run write commands (all fans unless --fan is given):
              macfan set --percent 45
              macfan set --fan 0 --rpm 3000
              macfan auto
              macfan curve --points 40:40,60:50 --once

            Live write commands require sudo plus explicit flags:
              sudo .build/debug/macfan set --fan 0 --percent 45 --live --i-understand
              sudo .build/debug/macfan auto --live --i-understand

            Dangerous values:
              --allow-dangerous permits values outside reported min/max or <=10% / >=95%
              --allow-zero permits 0 RPM, and should not be used without explicit approval
            """
        )
    }
}
