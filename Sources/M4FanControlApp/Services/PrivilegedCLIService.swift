import Foundation

struct PrivilegedCLIService {
    enum CLIServiceError: LocalizedError {
        case missingHelper
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingHelper:
                return "Bundled m4fan helper was not found in the app bundle."
            case .commandFailed(let message):
                return message
            }
        }
    }

    var helperURL: URL? {
        Bundle.main.url(forResource: "m4fan", withExtension: nil)
    }

    func runPrivileged(arguments: [String], background: Bool = false) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runPrivilegedSync(arguments: arguments, background: background)
        }.value
    }

    func runPrivilegedSync(arguments: [String], background: Bool = false) throws -> String {
        guard let helperURL else { throw CLIServiceError.missingHelper }
        var shellCommand = ([helperURL.path] + arguments).map(Self.shellQuote).joined(separator: " ")

        if background {
            let logPath = NSTemporaryDirectory() + "M4FanControl.curve.log"
            shellCommand = "nohup \(shellCommand) > \(Self.shellQuote(logPath)) 2>&1 &"
        }

        let appleScript = "do shell script \"\(Self.appleScriptString(shellCommand))\" with administrator privileges"
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
            throw CLIServiceError.commandFailed((stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
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
