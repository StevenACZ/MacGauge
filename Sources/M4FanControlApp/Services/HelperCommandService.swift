import Foundation
import M4FanCore
import ServiceManagement
import os

@MainActor
final class HelperCommandService: ObservableObject {
    enum HelperState: String {
        case unknown = "Unknown"
        case ready = "Ready"
        case needsAuthorization = "Needs authorization"
        case needsApproval = "Needs approval"
        case unavailable = "Unavailable"
        case stale = "Needs reload"
        case failed = "Failed"
    }

    @Published private(set) var state: HelperState = .unknown

    var isReady: Bool {
        state == .ready
    }

    var statusSummary: String {
        switch state {
        case .unknown:
            return "Checking helper..."
        case .ready:
            return "Helper ready"
        case .needsAuthorization:
            return "Authorize helper in Settings > Safety"
        case .needsApproval:
            return "Approve M4FanControl in System Settings, then return here"
        case .unavailable:
            return "Helper unavailable; register it from Settings > Safety"
        case .stale:
            return "Helper needs reload; open Settings > Safety and reload it"
        case .failed:
            return "Helper failed; check Safety and helper logs"
        }
    }

    private static let readinessTimeout: TimeInterval = 4
    private static let commandTimeout: TimeInterval = 20
    private static let minimumProtocolVersion = HelperResponse.currentProtocolVersion

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let log = Logger(subsystem: "com.stevenacz.M4FanControl", category: "helper-service")
    private var connection: NSXPCConnection?

    func refreshState() async {
        do {
            _ = try await sendWithoutInstalling(.init(action: .ping), timeout: Self.readinessTimeout)
            state = .ready
            log.debug("helper ready")
        } catch let error as HelperStaleError {
            state = .stale
            log.warning("helper stale: \(error.localizedDescription, privacy: .public)")
        } catch {
            state = serviceStateAfterFailedPing()
            log.warning(
                "helper ping failed; state=\(self.state.rawValue, privacy: .public), error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func authorizeHelper() async throws {
        do {
            try registerHelperWithServiceManagement(forceReload: state == .stale || state == .unavailable || state == .failed)
            connection?.invalidate()
            connection = nil
            _ = try await sendWithoutInstalling(.init(action: .ping), timeout: Self.readinessTimeout)
            state = .ready
            log.info("helper authorized")
        } catch let error as HelperStaleError {
            state = .stale
            log.warning("helper authorization left stale daemon: \(error.localizedDescription, privacy: .public)")
            throw error
        } catch {
            state = serviceStateAfterFailedPing()
            log.error(
                "helper authorization failed; state=\(self.state.rawValue, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    struct SetPercentResult: Sendable {
        let message: String
        let actualRPM: Double?
        let mode: Int?
        let contested: Bool
    }

    func setPercent(_ percent: Double, allowDangerous: Bool, allowZero: Bool) async throws -> SetPercentResult {
        let response = try await sendReadyCommand(
            .init(
                action: .setPercent,
                fanIndex: 0,
                percent: percent,
                allowDangerous: allowDangerous,
                allowZero: allowZero
            )
        )
        return SetPercentResult(
            message: response.message,
            actualRPM: response.actualRPM,
            mode: response.mode,
            contested: response.contested ?? false
        )
    }

    func restoreAutomatic() async throws -> String {
        let response = try await sendReadyCommand(.init(action: .automatic))
        return response.message
    }

    func removeLegacyHelper() async throws -> String {
        let response = try await sendReadyCommand(.init(action: .removeLegacyHelper))
        return response.message
    }

    private func sendReadyCommand(_ command: HelperCommand) async throws -> HelperResponse {
        try requireReady()
        do {
            let response = try await sendWithoutInstalling(command, timeout: Self.commandTimeout)
            state = .ready
            return response
        } catch let error as HelperResponseError {
            state = .ready
            throw error
        } catch let error as HelperStaleError {
            state = .stale
            throw error
        } catch let error as HelperUnavailableError {
            state = serviceStateAfterFailedPing()
            throw error
        } catch {
            state = .failed
            throw error
        }
    }

    private func requireReady() throws {
        guard isReady else {
            state = serviceStateAfterFailedPing()
            throw M4FanError(statusSummary)
        }
    }

    private func sendWithoutInstalling(_ command: HelperCommand, timeout: TimeInterval) async throws -> HelperResponse {
        let commandData = try encoder.encode(command)
        let responseData = try await sendXPC(commandData, timeout: timeout)
        let response = try decoder.decode(HelperResponse.self, from: responseData)

        guard response.id == command.id else {
            throw HelperResponseError(message: "Helper returned a mismatched response.")
        }
        guard response.ok else {
            throw HelperResponseError(message: response.message)
        }
        guard (response.protocolVersion ?? 0) >= Self.minimumProtocolVersion else {
            throw HelperStaleError()
        }
        return response
    }

    private func sendXPC(_ commandData: Data, timeout: TimeInterval) async throws -> Data {
        let connection = activeConnection()

        return try await withCheckedThrowingContinuation { continuation in
            let singleShot = SingleShotContinuation(continuation)
            let timeoutTask = Task {
                let delay = UInt64(timeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                singleShot.resume(throwing: HelperUnavailableError())
            }

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    timeoutTask.cancel()
                    singleShot.resume(throwing: error)
                }) as? M4FanHelperXPCProtocol
            else {
                timeoutTask.cancel()
                singleShot.resume(throwing: HelperUnavailableError())
                return
            }

            proxy.runCommand(commandData) { responseData in
                timeoutTask.cancel()
                singleShot.resume(returning: responseData)
            }
        }
    }

    private func activeConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(
            machServiceName: HelperPaths.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: M4FanHelperXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection?.invalidate()
                self?.connection = nil
                if self?.state == .ready {
                    self?.state = .unavailable
                }
            }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func registerHelperWithServiceManagement(forceReload: Bool = false) throws {
        guard launchDaemonPlistIsBundled else {
            throw M4FanError("Bundled LaunchDaemon plist was not found. Build the app bundle before authorizing the helper.")
        }

        let service = SMAppService.daemon(plistName: HelperPaths.launchDaemonPlistName)
        if forceReload {
            switch service.status {
            case .enabled, .requiresApproval:
                do {
                    try service.unregister()
                    log.info("helper unregistered for reload")
                } catch {
                    log.warning("helper unregister before reload failed: \(error.localizedDescription, privacy: .public)")
                }
            case .notRegistered, .notFound:
                break
            @unknown default:
                break
            }
        }

        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            throw M4FanError("Approve M4FanControl in System Settings, then click Authorize again.")
        case .notRegistered, .notFound:
            try service.register()
        @unknown default:
            try service.register()
        }

        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            throw M4FanError("Approve M4FanControl in System Settings, then click Authorize again.")
        case .notFound:
            throw M4FanError("macOS could not find the bundled LaunchDaemon plist.")
        case .notRegistered:
            throw M4FanError("Helper registration did not complete.")
        @unknown default:
            throw M4FanError("Helper registration returned an unknown macOS status.")
        }
    }

    private var launchDaemonPlistIsBundled: Bool {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchDaemons", isDirectory: true)
            .appendingPathComponent(HelperPaths.launchDaemonPlistName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func serviceStateAfterFailedPing() -> HelperState {
        let status = SMAppService.daemon(plistName: HelperPaths.launchDaemonPlistName).status
        switch status {
        case .enabled:
            return .stale
        case .requiresApproval:
            return .needsApproval
        case .notRegistered, .notFound:
            return .needsAuthorization
        @unknown default:
            return .unknown
        }
    }
}

private final class SingleShotContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.withLock {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    func resume(throwing error: Error) {
        lock.withLock {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

private struct HelperResponseError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private struct HelperUnavailableError: LocalizedError {
    var errorDescription: String? {
        "Helper did not respond. Authorize helper in Settings > Safety."
    }
}

private struct HelperStaleError: LocalizedError {
    var errorDescription: String? {
        "Helper is stale. Reload it from Settings > Safety so curve writes can be verified."
    }
}
