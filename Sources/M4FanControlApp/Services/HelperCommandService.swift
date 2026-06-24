import Foundation
import M4FanCore

@MainActor
final class HelperCommandService: ObservableObject {
    enum HelperState: String {
        case unknown = "Unknown"
        case ready = "Ready"
        case missing = "Needs authorization"
        case failed = "Failed"
    }

    @Published private(set) var state: HelperState = .unknown

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func refreshState() async {
        do {
            _ = try await send(.init(action: .ping), installIfMissing: false)
            state = .ready
        } catch {
            state = .missing
        }
    }

    func authorizeHelper() async throws {
        try await installHelper()
        _ = try await send(.init(action: .ping), installIfMissing: false)
        state = .ready
    }

    func setPercent(_ percent: Double, allowDangerous: Bool, allowZero: Bool) async throws -> String {
        let response = try await send(
            .init(
                action: .setPercent,
                fanIndex: 0,
                percent: percent,
                allowDangerous: allowDangerous,
                allowZero: allowZero
            ),
            installIfMissing: true
        )
        state = .ready
        return response.message
    }

    func restoreAutomatic() async throws -> String {
        let response = try await send(.init(action: .automatic), installIfMissing: true)
        state = .ready
        return response.message
    }

    private func send(_ command: HelperCommand, installIfMissing: Bool) async throws -> HelperResponse {
        do {
            return try await sendWithoutInstalling(command)
        } catch {
            guard installIfMissing else { throw error }
            try await installHelper()
            return try await sendWithoutInstalling(command)
        }
    }

    private func sendWithoutInstalling(_ command: HelperCommand) async throws -> HelperResponse {
        try encoder.encode(command).write(to: commandURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: commandURL.path)

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let response = try? readResponse(id: command.id) {
                guard response.ok else { throw M4FanError(response.message) }
                return response
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw M4FanError("Helper did not respond.")
    }

    private func readResponse(id: String) throws -> HelperResponse? {
        guard FileManager.default.fileExists(atPath: responseURL.path) else { return nil }
        let response = try decoder.decode(HelperResponse.self, from: Data(contentsOf: responseURL))
        return response.id == id ? response : nil
    }

    private func installHelper() async throws {
        guard let helperURL = Bundle.main.url(forResource: "M4FanHelper", withExtension: nil) else {
            throw M4FanError("Bundled helper was not found.")
        }

        let shellCommand = "\(Self.shellQuote(helperURL.path)) --install-daemon"
        let appleScript = "do shell script \"\(Self.appleScriptString(shellCommand))\" with administrator privileges"

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            try process.run()
            process.waitUntilExit()

            let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw M4FanError((stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.value

        try await Task.sleep(nanoseconds: 800_000_000)
    }

    private var commandURL: URL {
        let directory = HelperPaths.appSupportDirectory(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return HelperPaths.commandFile(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    private var responseURL: URL {
        HelperPaths.responseFile(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
