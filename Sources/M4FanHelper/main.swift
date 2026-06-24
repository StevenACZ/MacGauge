import Darwin
import Foundation
import M4FanCore
import SystemConfiguration

private let toolPath = "/Library/PrivilegedHelperTools/\(HelperPaths.label)"
private let plistPath = "/Library/LaunchDaemons/\(HelperPaths.label).plist"

@main
struct M4FanHelper {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            switch arguments.first {
            case "--install-daemon":
                try Installer.install()
            case "--uninstall-daemon":
                try Installer.uninstall()
            case "--daemon":
                try Daemon().run()
            default:
                print("usage: M4FanHelper --install-daemon|--uninstall-daemon|--daemon")
            }
        } catch {
            fputs("M4FanHelper error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private enum Installer {
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
    private static func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
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

private final class Daemon {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var lastCommandID: String?

    func run() throws -> Never {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        while true {
            autoreleasepool {
                do {
                    try processNextCommandIfNeeded()
                } catch {
                    writeFallbackError(error)
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func processNextCommandIfNeeded() throws {
        guard let user = currentConsoleUser() else { return }
        let directory = HelperPaths.appSupportDirectory(homeDirectory: user.homeDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chown(directory.path, user.uid, user.gid)
        chmod(directory.path, 0o700)

        let commandURL = HelperPaths.commandFile(homeDirectory: user.homeDirectory)
        guard FileManager.default.fileExists(atPath: commandURL.path) else { return }

        let data = try Data(contentsOf: commandURL)
        let command = try decoder.decode(HelperCommand.self, from: data)
        guard command.id != lastCommandID else { return }
        lastCommandID = command.id

        let response: HelperResponse
        do {
            response = try execute(command)
        } catch {
            response = HelperResponse(id: command.id, ok: false, message: error.localizedDescription)
        }

        let responseURL = HelperPaths.responseFile(homeDirectory: user.homeDirectory)
        let responseData = try encoder.encode(response)
        try responseData.write(to: responseURL, options: .atomic)
        chown(responseURL.path, user.uid, user.gid)
        chmod(responseURL.path, 0o600)
    }

    private func execute(_ command: HelperCommand) throws -> HelperResponse {
        switch command.action {
        case .ping:
            return HelperResponse(id: command.id, ok: true, message: "helper ready")
        case .setPercent:
            guard let percent = command.percent else {
                throw M4FanError("Missing percent.")
            }
            try validate(percent: percent, allowDangerous: command.allowDangerous, allowZero: command.allowZero)
            let smc = try SMCClient()
            let controller = FanController(smc: smc)
            let fan = try controller.fanInfo(index: command.fanIndex)
            let rpm = try controller.targetRPM(forPercent: percent, fan: fan)
            try validate(rpm: rpm, fan: fan, percent: percent, allowDangerous: command.allowDangerous)
            let strategy = try controller.setTargetRPM(index: command.fanIndex, rpm: rpm)
            return HelperResponse(id: command.id, ok: true, message: "Set fan \(command.fanIndex) to \(Int(rpm.rounded())) RPM (\(strategy.rawValue))")
        case .automatic:
            let smc = try SMCClient()
            let controller = FanController(smc: smc)
            let fans = try controller.allFans()
            for fan in fans {
                try controller.returnToAutomatic(index: fan.index)
            }
            try controller.resetForceTestIfAvailable()
            return HelperResponse(id: command.id, ok: true, message: "Automatic control restored")
        }
    }

    private func validate(percent: Double, allowDangerous: Bool, allowZero: Bool) throws {
        guard percent.isFinite, percent >= 0, percent <= 100 else {
            throw M4FanError("Percent must be between 0 and 100.")
        }
        if percent == 0 && !(allowZero && allowDangerous) {
            throw M4FanError("0 percent requires explicit dangerous zero unlock.")
        }
        if (percent <= 10 || percent >= 95) && !allowDangerous {
            throw M4FanError("Edge fan ranges require dangerous range unlock.")
        }
    }

    private func validate(rpm: Double, fan: FanInfo, percent: Double, allowDangerous: Bool) throws {
        let belowMinimum = fan.minRPM.map { rpm < $0 } ?? false
        let aboveMaximum = fan.maxRPM.map { rpm > $0 } ?? false
        if (belowMinimum || aboveMaximum) && !allowDangerous {
            throw M4FanError("Target \(Int(rpm.rounded())) RPM is outside reported fan limits.")
        }
    }

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

    private func writeFallbackError(_ error: Error) {
        guard let user = currentConsoleUser() else { return }
        let response = HelperResponse(id: lastCommandID ?? "unknown", ok: false, message: error.localizedDescription)
        guard let data = try? encoder.encode(response) else { return }
        let url = HelperPaths.responseFile(homeDirectory: user.homeDirectory)
        try? data.write(to: url, options: .atomic)
        chown(url.path, user.uid, user.gid)
        chmod(url.path, 0o600)
    }
}
