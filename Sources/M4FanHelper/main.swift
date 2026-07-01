import Darwin
import Foundation
import M4FanCore
import Security
import SystemConfiguration
import os

private let toolPath = "/Library/PrivilegedHelperTools/\(HelperPaths.label)"
private let plistPath = "/Library/LaunchDaemons/\(HelperPaths.launchDaemonPlistName)"
private let helperLog = Logger(subsystem: "com.stevenacz.M4FanControl", category: "helper")
private let helperVersion = "3.0"

@main
struct M4FanHelper {
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
                print("usage: M4FanHelper --install-daemon|--uninstall-daemon|--daemon")
            }
        } catch {
            fputs("M4FanHelper error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private enum LegacyInstaller {
    static func install() throws {
        guard geteuid() == 0 else {
            throw M4FanError("Helper installation requires root.")
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
              <key>StandardOutPath</key>
              <string>/tmp/\(HelperPaths.label).out.log</string>
              <key>StandardErrorPath</key>
              <string>/tmp/\(HelperPaths.label).err.log</string>
            </dict>
            </plist>
            """
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        chown(plistURL.path, 0, 0)
        chmod(plistURL.path, 0o644)

        _ = try? runLaunchctl(["bootout", "system/\(HelperPaths.label)"], allowFailure: true)
        try runLaunchctl(["bootstrap", "system", plistPath])
        try runLaunchctl(["kickstart", "-k", "system/\(HelperPaths.label)"])
        print("M4FanHelper installed")
    }

    static func uninstall() throws {
        guard geteuid() == 0 else {
            throw M4FanError("Helper uninstall requires root.")
        }
        _ = try? runLaunchctl(["bootout", "system/\(HelperPaths.label)"], allowFailure: true)
        try? FileManager.default.removeItem(atPath: plistPath)
        try? FileManager.default.removeItem(atPath: toolPath)
        print("M4FanHelper uninstalled")
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
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && !allowFailure {
            throw M4FanError((stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }
}

private struct ConsoleUser {
    let name: String
    let uid: uid_t
    let gid: gid_t
    let homeDirectory: URL
}

private final class Daemon: NSObject, NSXPCListenerDelegate, M4FanHelperXPCProtocol {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let listener = NSXPCListener(machServiceName: HelperPaths.machServiceName)
    private let commandQueue = DispatchQueue(label: "\(HelperPaths.label).commands")
    private let safety = HelperCommandSafety()

    func run() throws -> Never {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        listener.delegate = self
        listener.resume()
        RunLoop.current.run()
        throw M4FanError("Helper listener stopped unexpectedly.")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isAuthorizedClient(connection) else {
            return false
        }

        if let requirement = Self.clientCodeSigningRequirement {
            do {
                try connection.setCodeSigningRequirement(requirement)
            } catch {
                helperLog.error("rejected client: signing requirement setup failed")
                return false
            }
        }

        connection.exportedInterface = NSXPCInterface(with: M4FanHelperXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func runCommand(_ commandData: Data, withReply reply: @escaping (Data) -> Void) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            reply(self.responseData(for: commandData))
        }
    }

    private func responseData(for commandData: Data) -> Data {
        let response: HelperResponse
        do {
            let command = try decoder.decode(HelperCommand.self, from: commandData)
            response = try execute(command)
        } catch {
            helperLog.error("command failed: \(error.localizedDescription, privacy: .public)")
            response = HelperResponse(id: "unknown", ok: false, message: error.localizedDescription)
        }

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
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                exit(0)
            }
            return HelperResponse(id: command.id, ok: true, message: "Helper exiting for reload", helperVersion: helperVersion)
        case .setPercent:
            guard let percent = command.percent else {
                throw M4FanError("Missing percent.")
            }
            helperLog.info("setPercent requested fan=\(command.fanIndex, privacy: .public) percent=\(percent, privacy: .public)")
            try safety.validate(
                percent: percent,
                allowDangerous: command.allowDangerous,
                allowZero: command.allowZero
            )
            let smc = try SMCClient()
            let controller = FanController(smc: smc)
            let fan = try controller.fanInfo(index: command.fanIndex)
            let rpm = try controller.targetRPM(forPercent: percent, fan: fan)
            try safety.validate(rpm: rpm, fan: fan, percent: percent, allowDangerous: command.allowDangerous)
            let result = try controller.setTargetRPMVerified(index: command.fanIndex, rpm: rpm)
            helperLog.info(
                "setPercent applied fan=\(command.fanIndex, privacy: .public) targetRPM=\(rpm, privacy: .public) actualRPM=\(result.actualRPM ?? -1, privacy: .public) mode=\(result.mode ?? -1, privacy: .public) contested=\(result.contested, privacy: .public) strategy=\(result.strategy.rawValue, privacy: .public)"
            )
            return HelperResponse(
                id: command.id,
                ok: true,
                message: "Set fan \(command.fanIndex) to \(Int(rpm.rounded())) RPM (\(result.strategy.rawValue))",
                actualRPM: result.actualRPM,
                mode: result.mode,
                contested: result.contested
            )
        case .automatic:
            let smc = try SMCClient()
            let controller = FanController(smc: smc)
            let fans = try controller.allFans()
            for fan in fans {
                try controller.returnToAutomatic(index: fan.index)
            }
            try controller.resetForceTestIfAvailable()
            helperLog.info("automatic control restored")
            return HelperResponse(id: command.id, ok: true, message: "Automatic control restored")
        case .removeLegacyHelper:
            let message = removeLegacyHelper()
            helperLog.info("legacy helper cleanup: \(message, privacy: .public)")
            return HelperResponse(id: command.id, ok: true, message: message)
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
            !user.isEmpty,
            let home = FileManager.default.homeDirectory(forUser: user)
        else {
            return nil
        }
        return ConsoleUser(name: user, uid: uid, gid: gid, homeDirectory: home)
    }
}
