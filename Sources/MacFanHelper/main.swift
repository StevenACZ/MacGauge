import Darwin
import Foundation
import MacFanCore
import Security
import SystemConfiguration
import os

private let toolPath = "/Library/PrivilegedHelperTools/\(HelperPaths.label)"
private let plistPath = "/Library/LaunchDaemons/\(HelperPaths.launchDaemonPlistName)"
private let helperLog = Logger(subsystem: "com.stevenacz.MacFan", category: "helper")
private let helperVersion = "5.0"

/// Awake-time seconds; unlike wall clock it never advances during sleep, so
/// watchdog staleness only counts time the machine was actually running.
private func uptimeNow() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
}

@main
struct MacFanHelper {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            switch arguments.first {
            case "--install-daemon":
                try LegacyInstaller.install()
            case "--uninstall-daemon":
                try LegacyInstaller.uninstall()
            case "--daemon", nil:
                let daemon = Daemon()
                try daemon.run()
            default:
                print("usage: MacFanHelper --install-daemon|--uninstall-daemon|--daemon")
            }
        } catch {
            fputs("MacFanHelper error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private enum LegacyInstaller {
    static func install() throws {
        guard geteuid() == 0 else {
            throw MacFanError("Helper installation requires root.")
        }

        let source = URL(fileURLWithPath: CommandLine.arguments[0])
        let destination = URL(fileURLWithPath: toolPath)
        let plistURL = URL(fileURLWithPath: plistPath)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        chown(destination.path, 0, 0)
        chmod(destination.path, 0o755)

        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key>
              <string>\(HelperPaths.label)</string>
              <key>ProgramArguments</key>
              <array>
                <string>\(toolPath)</string>
                <string>--daemon</string>
              </array>
              <key>MachServices</key>
              <dict>
                <key>\(HelperPaths.machServiceName)</key>
                <true/>
              </dict>
              <key>RunAtLoad</key>
              <true/>
              <key>KeepAlive</key>
              <true/>
            </dict>
            </plist>
            """
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        chown(plistURL.path, 0, 0)
        chmod(plistURL.path, 0o644)

        _ = try? runLaunchctl(["bootout", "system/\(HelperPaths.label)"], allowFailure: true)
        try runLaunchctl(["bootstrap", "system", plistPath])
        try runLaunchctl(["kickstart", "-k", "system/\(HelperPaths.label)"])
        print("MacFanHelper installed")
    }

    static func uninstall() throws {
        guard geteuid() == 0 else {
            throw MacFanError("Helper uninstall requires root.")
        }
        _ = try? runLaunchctl(["bootout", "system/\(HelperPaths.label)"], allowFailure: true)
        try? FileManager.default.removeItem(atPath: plistPath)
        try? FileManager.default.removeItem(atPath: toolPath)
        print("MacFanHelper uninstalled")
    }

    @discardableResult
    static func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()

        // Drain both pipes before waiting so output beyond the pipe buffer
        // cannot deadlock waitUntilExit.
        var errorData = Data()
        let errorDrained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errorData = error.fileHandleForReading.readDataToEndOfFile()
            errorDrained.signal()
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        errorDrained.wait()
        process.waitUntilExit()

        let stdout = String(data: outputData, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && !allowFailure {
            throw MacFanError((stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }
}

private struct ConsoleUser {
    let name: String
    let uid: uid_t
}

private final class Daemon: NSObject, NSXPCListenerDelegate, MacFanHelperXPCProtocol {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let listener = NSXPCListener(machServiceName: HelperPaths.machServiceName)
    private let commandQueue = DispatchQueue(label: "\(HelperPaths.label).commands")
    private let safety = HelperCommandSafety()
    // Guarded by commandQueue, like every SMC write.
    private var watchdog = HelperWatchdogState(nowUptime: uptimeNow())
    private var watchdogTimer: DispatchSourceTimer?

    func run() throws -> Never {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        listener.delegate = self
        listener.resume()
        startWatchdogTimer()
        RunLoop.current.run()
        throw MacFanError("Helper listener stopped unexpectedly.")
    }

    private func startWatchdogTimer() {
        let timer = DispatchSource.makeTimerSource(queue: commandQueue)
        timer.schedule(
            deadline: .now() + HelperWatchdogState.checkIntervalSeconds,
            repeating: HelperWatchdogState.checkIntervalSeconds,
            leeway: .seconds(5)
        )
        timer.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func watchdogTick() {
        guard watchdog.shouldRestoreAutomatic(nowUptime: uptimeNow()) else { return }
        helperLog.warning(
            "watchdog fired: manual control armed and no client activity for \(Int(HelperWatchdogState.silenceTimeoutSeconds), privacy: .public)s; restoring automatic"
        )
        let failures = restoreAllFansToAutomatic()
        if failures.isEmpty {
            watchdog.disarm()
            helperLog.info("watchdog restored automatic control")
        } else {
            // Back off a full silence window instead of hammering the SMC
            // every tick while a fan refuses to release.
            watchdog.recordClientActivity(nowUptime: uptimeNow())
            helperLog.error(
                "watchdog restore incomplete: \(failures.joined(separator: "; "), privacy: .public)")
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isAuthorizedClient(connection) else {
            return false
        }

        if let requirement = Self.clientCodeSigningRequirement {
            connection.setCodeSigningRequirement(requirement)
        }

        connection.exportedInterface = NSXPCInterface(with: MacFanHelperXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    private static let maxCommandBytes = 64 * 1024
    private static let maxCommandAge: TimeInterval = 30

    func runCommand(_ commandData: Data, withReply reply: @escaping (Data) -> Void) {
        guard commandData.count <= Self.maxCommandBytes else {
            helperLog.error("command rejected: payload of \(commandData.count, privacy: .public) bytes exceeds limit")
            reply(encode(HelperResponse(id: "unknown", ok: false, message: "Command payload too large.")))
            return
        }

        let command: HelperCommand
        do {
            command = try decoder.decode(HelperCommand.self, from: commandData)
        } catch {
            helperLog.error("command failed: \(error.localizedDescription, privacy: .public)")
            reply(encode(HelperResponse(id: "unknown", ok: false, message: error.localizedDescription)))
            return
        }

        // Any authenticated command counts as client activity for the
        // watchdog; the async hop keeps ping replies off the command queue.
        commandQueue.async { [weak self] in
            self?.watchdog.recordClientActivity(nowUptime: uptimeNow())
        }

        // Pings answer immediately so the app's health check cannot starve
        // behind a slow fan write on the serial command queue.
        if command.action == .ping {
            reply(encode(response(for: command)))
            return
        }

        commandQueue.async { [weak self] in
            guard let self else { return }
            reply(self.encode(self.response(for: command)))
        }
    }

    private func response(for command: HelperCommand) -> HelperResponse {
        do {
            let age = Date().timeIntervalSince(command.createdAt)
            if command.action != .ping, age > Self.maxCommandAge {
                throw MacFanError("Rejected command created \(Int(age))s ago; too old to run safely.")
            }
            return try execute(command)
        } catch {
            helperLog.error("command failed: \(error.localizedDescription, privacy: .public)")
            return HelperResponse(id: command.id, ok: false, message: error.localizedDescription)
        }
    }

    private func encode(_ response: HelperResponse) -> Data {
        do {
            return try encoder.encode(response)
        } catch {
            let fallback = #"{"id":"unknown","ok":false,"message":"Failed to encode helper response."}"#
            return Data(fallback.utf8)
        }
    }

    private func execute(_ command: HelperCommand) throws -> HelperResponse {
        switch command.action {
        case .ping:
            helperLog.debug("ping")
            return HelperResponse(id: command.id, ok: true, message: "helper ready", helperVersion: helperVersion)
        case .shutdown:
            helperLog.info("shutdown requested; exiting so launchd relaunches the current binary")
            // Exiting via the serial command queue lets in-flight commands
            // finish; the short delay lets this reply flush first.
            commandQueue.asyncAfter(deadline: .now() + 0.2) {
                exit(0)
            }
            return HelperResponse(id: command.id, ok: true, message: "Helper exiting for reload", helperVersion: helperVersion)
        case .setPercent:
            guard let percent = command.percent else {
                throw MacFanError("Missing percent.")
            }
            try safety.validate(
                percent: percent,
                allowDangerous: command.allowDangerous,
                allowZero: command.allowZero
            )
            let smc = try SMCClient()
            let controller = FanController(smc: smc)
            let fans: [FanInfo]
            if let indexes = command.fanIndexes {
                fans = try indexes.map { try controller.fanInfo(index: $0) }
            } else {
                fans = try controller.allFans()
            }
            guard !fans.isEmpty else {
                throw MacFanError("This Mac reports no controllable fans.")
            }
            // Arm before the first write: a partial failure can still leave a
            // fan pinned manual, and a stray arm over automatic fans is a
            // harmless no-op restore.
            watchdog.armForManualControl(nowUptime: uptimeNow())
            helperLog.info(
                "setPercent requested fans=\(fans.map(\.index), privacy: .public) percent=\(percent, privacy: .public)"
            )
            var results: [HelperFanResult] = []
            for fan in fans {
                let rpm = try controller.targetRPM(forPercent: percent, fan: fan)
                try safety.validate(rpm: rpm, fan: fan, percent: percent, allowDangerous: command.allowDangerous)
                let result = try controller.setTargetRPMVerified(index: fan.index, rpm: rpm)
                helperLog.info(
                    "setPercent applied fan=\(fan.index, privacy: .public) targetRPM=\(rpm, privacy: .public) actualRPM=\(result.actualRPM ?? -1, privacy: .public) mode=\(result.mode ?? -1, privacy: .public) contested=\(result.contested, privacy: .public) strategy=\(result.strategy.rawValue, privacy: .public)"
                )
                results.append(
                    HelperFanResult(
                        index: fan.index,
                        targetRPM: rpm,
                        actualRPM: result.actualRPM,
                        mode: result.mode,
                        contested: result.contested
                    )
                )
            }
            let summary =
                results
                .map { "fan \($0.index) → \(Int($0.targetRPM.rounded())) RPM" }
                .joined(separator: ", ")
            return HelperResponse(
                id: command.id,
                ok: true,
                message: "Set \(summary)",
                actualRPM: results.first?.actualRPM,
                mode: results.first?.mode,
                contested: results.contains { $0.contested },
                fans: results
            )
        case .automatic:
            let failures = restoreAllFansToAutomatic()
            guard failures.isEmpty else {
                let detail = failures.joined(separator: "; ")
                helperLog.error("automatic restore incomplete: \(detail, privacy: .public)")
                return HelperResponse(id: command.id, ok: false, message: "Automatic restore incomplete: \(detail)")
            }
            watchdog.disarm()
            helperLog.info("automatic control restored")
            return HelperResponse(id: command.id, ok: true, message: "Automatic control restored")
        case .disarmWatchdog:
            watchdog.disarm()
            helperLog.info("watchdog disarmed by client; manual control stays as-is")
            return HelperResponse(id: command.id, ok: true, message: "Watchdog disarmed", helperVersion: helperVersion)
        case .removeLegacyHelper:
            let message = removeLegacyHelper()
            helperLog.info("legacy helper cleanup: \(message, privacy: .public)")
            return HelperResponse(id: command.id, ok: true, message: message)
        }
    }

    // Best effort: one stuck fan must not leave the others pinned manual or
    // skip the Ftst reset.
    private func restoreAllFansToAutomatic() -> [String] {
        do {
            let smc = try SMCClient()
            let controller = FanController(smc: smc)
            let fans = try controller.allFans()
            var failures: [String] = []
            for fan in fans {
                do {
                    try controller.returnToAutomatic(index: fan.index)
                } catch {
                    failures.append("fan \(fan.index): \(error.localizedDescription)")
                }
            }
            do {
                try controller.resetForceTestIfAvailable()
            } catch {
                failures.append("Ftst reset: \(error.localizedDescription)")
            }
            return failures
        } catch {
            return [error.localizedDescription]
        }
    }

    private func removeLegacyHelper() -> String {
        let fileManager = FileManager.default
        let hadTool = fileManager.fileExists(atPath: LegacyHelperPaths.toolPath)
        let hadPlist = fileManager.fileExists(atPath: LegacyHelperPaths.plistPath)

        guard hadTool || hadPlist else {
            return "No legacy helper found."
        }

        _ = try? LegacyInstaller.runLaunchctl(
            ["bootout", "system/\(LegacyHelperPaths.label)"],
            allowFailure: true
        )
        try? fileManager.removeItem(atPath: LegacyHelperPaths.plistPath)
        try? fileManager.removeItem(atPath: LegacyHelperPaths.toolPath)

        let stillHasTool = fileManager.fileExists(atPath: LegacyHelperPaths.toolPath)
        let stillHasPlist = fileManager.fileExists(atPath: LegacyHelperPaths.plistPath)
        if stillHasTool || stillHasPlist {
            return "Legacy helper cleanup incomplete."
        }
        return "Legacy helper removed."
    }

    private func isAuthorizedClient(_ connection: NSXPCConnection) -> Bool {
        guard let user = currentConsoleUser() else {
            return false
        }
        return connection.effectiveUserIdentifier == user.uid
    }

    // Requires XPC clients to carry the same Team ID as this helper's own
    // signature; nil (no requirement) when the helper runs unsigned in dev.
    private static let clientCodeSigningRequirement: String? = {
        var codeRef: SecCode?
        guard SecCodeCopySelf([], &codeRef) == errSecSuccess, let code = codeRef else { return nil }
        var staticCodeRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCodeRef) == errSecSuccess,
            let staticCode = staticCodeRef
        else { return nil }
        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess,
            let info = infoRef as? [String: Any],
            let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
            !team.isEmpty
        else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }()

    private func currentConsoleUser() -> ConsoleUser? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let user = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
            user != "loginwindow",
            !user.isEmpty
        else {
            return nil
        }
        return ConsoleUser(name: user, uid: uid)
    }
}
