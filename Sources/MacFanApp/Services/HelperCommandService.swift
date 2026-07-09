import Foundation
import MacFanCore
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
        case reloading = "Reloading"
        case failed = "Failed"
    }

    @Published private(set) var state: HelperState = .unknown

    var isReady: Bool {
        state == .ready
    }

    var isRecovering: Bool {
        state == .reloading
    }

    var statusSummary: String {
        switch state {
        case .unknown:
            return "helper.status.checking".localized
        case .ready:
            return "helper.status.ready".localized
        case .needsAuthorization:
            return "helper.status.needs_authorization".localized
        case .needsApproval:
            return "helper.status.needs_approval".localized
        case .unavailable:
            return "helper.status.unavailable".localized
        case .stale:
            return "helper.status.stale".localized
        case .reloading:
            return "helper.status.reloading".localized
        case .failed:
            return "helper.status.failed".localized
        }
    }

    private static let pingTimeout: TimeInterval = 2.5
    private static let commandTimeout: TimeInterval = 20
    private static let minimumProtocolVersion = HelperResponse.currentProtocolVersion
    private static let daemonRelaunchDeadline: TimeInterval = 14
    private static let registerRecoveryDeadline: TimeInterval = 10
    private static let unregisterSettleDeadline: TimeInterval = 3
    private static let autoRepairCooldown: TimeInterval = 120

    private static let everReadyDefaultsKey = "helperEverReady"

    private let rules = HelperHealthRules()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "com.stevenacz.MacFan", category: "helper-service")
    private var connection: NSXPCConnection?
    private var monitorTask: Task<Void, Never>?
    private var healthCheckInFlight = false
    private var repairInFlight = false
    private var consecutivePingFailures = 0
    private var lastAutoRepairAt: Date?

    // MARK: - Health monitoring

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.evaluateHealth(userInitiated: false)
                let interval = self.rules.heartbeatInterval(isReady: self.isReady)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func requestImmediateRefresh() {
        Task { await evaluateHealth(userInitiated: false) }
    }

    /// User-facing repair: authorize, approve, or reload as needed. Never
    /// unregisters a daemon that answers pings with the current protocol.
    func userRepair() async throws {
        await evaluateHealth(userInitiated: true)
        switch state {
        case .ready:
            return
        case .needsApproval:
            throw MacFanError("helper.error.approve_in_settings".localized)
        default:
            throw MacFanError(statusSummary)
        }
    }

    private func evaluateHealth(userInitiated: Bool) async {
        guard !healthCheckInFlight, !repairInFlight else { return }
        healthCheckInFlight = true
        defer { healthCheckInFlight = false }

        let status = daemonStatus()
        var ping: HelperPingOutcome?
        if status == .enabled {
            ping = await pingOutcome()
            consecutivePingFailures = ping == .failed ? consecutivePingFailures + 1 : 0
        } else {
            consecutivePingFailures = 0
        }

        let decision = rules.decision(
            status: status,
            ping: ping,
            consecutivePingFailures: consecutivePingFailures,
            canRepair: userInitiated || autoRepairAllowed
        )

        switch decision {
        case .markReady:
            setState(.ready)
        case .markNeedsAuthorization:
            let wasAuthorizedBefore = defaults.bool(forKey: Self.everReadyDefaultsKey)
            if userInitiated || (wasAuthorizedBefore && autoRepairAllowed) {
                await repair(startingWith: .reregisterDaemon, userInitiated: userInitiated)
            } else {
                setState(.needsAuthorization)
            }
        case .markNeedsApproval:
            setState(.needsApproval)
            if userInitiated {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .waitForNextTick:
            if state == .unknown, ping == .failed {
                setState(.unavailable)
            }
        case .restartDaemon, .reregisterDaemon:
            await repair(startingWith: decision, userInitiated: userInitiated)
        case .markDegraded:
            setState(ping == .stale ? .stale : .unavailable)
        }
    }

    private func repair(startingWith decision: HelperHealthDecision, userInitiated: Bool) async {
        guard !repairInFlight else { return }
        repairInFlight = true
        if !userInitiated {
            lastAutoRepairAt = Date()
        }
        setState(.reloading)
        defer { repairInFlight = false }

        if decision == .restartDaemon {
            log.info("repair: asking outdated daemon to exit so launchd relaunches the current binary")
            _ = try? await sendUnchecked(.init(action: .shutdown), timeout: Self.pingTimeout)
            invalidateConnection()
            if await pingRecovered(within: Self.daemonRelaunchDeadline) {
                setState(.ready)
                log.info("repair: daemon relaunched and answers the current protocol")
                return
            }
            log.warning("repair: daemon restart did not recover; re-registering")
        }

        do {
            try await reregisterDaemon(userInitiated: userInitiated)
        } catch {
            log.error("repair: re-register failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if await pingRecovered(within: Self.registerRecoveryDeadline) {
            setState(.ready)
            log.info("repair: daemon re-registered and ready")
        } else {
            setState(.unavailable)
            log.error("repair: daemon re-registered but did not answer pings yet")
        }
    }

    private func reregisterDaemon(userInitiated: Bool) async throws {
        guard launchDaemonPlistIsBundled else {
            setState(.failed)
            throw MacFanError("Bundled LaunchDaemon plist was not found. Build the app bundle before authorizing the helper.")
        }

        let service = SMAppService.daemon(plistName: HelperPaths.launchDaemonPlistName)
        if service.status == .enabled || service.status == .requiresApproval {
            do {
                try await service.unregister()
                log.info("repair: unregistered existing daemon")
            } catch {
                log.warning("repair: unregister failed: \(error.localizedDescription, privacy: .public)")
            }
            await waitForUnregisterToSettle(service)
        }
        invalidateConnection()

        // BTM can briefly refuse registration right after an unregister
        // ("Operation not permitted"); retry with backoff until it settles.
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
            }
            do {
                try service.register()
                break
            } catch {
                log.warning(
                    "repair: register attempt \(attempt + 1, privacy: .public) returned: \(error.localizedDescription, privacy: .public)"
                )
                if service.status == .enabled || service.status == .requiresApproval {
                    break
                }
            }
        }

        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            setState(.needsApproval)
            if userInitiated {
                SMAppService.openSystemSettingsLoginItems()
            }
            throw MacFanError("helper.error.approve_in_settings".localized)
        case .notFound:
            setState(.failed)
            throw MacFanError("macOS could not find the bundled LaunchDaemon plist.")
        case .notRegistered:
            setState(.failed)
            throw MacFanError("Helper registration did not complete.")
        @unknown default:
            setState(.failed)
            throw MacFanError("Helper registration returned an unknown macOS status.")
        }
    }

    private func waitForUnregisterToSettle(_ service: SMAppService) async {
        let deadline = Date().addingTimeInterval(Self.unregisterSettleDeadline)
        while Date() < deadline, service.status == .enabled {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func pingRecovered(within seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(nanoseconds: 700_000_000)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await pingOutcome() == .ready {
                return true
            }
            invalidateConnection()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return await pingOutcome() == .ready
    }

    private func pingOutcome() async -> HelperPingOutcome {
        do {
            _ = try await send(.init(action: .ping), timeout: Self.pingTimeout)
            return .ready
        } catch is HelperStaleError {
            return .stale
        } catch {
            return .failed
        }
    }

    private var autoRepairAllowed: Bool {
        guard let lastAutoRepairAt else { return true }
        return Date().timeIntervalSince(lastAutoRepairAt) > Self.autoRepairCooldown
    }

    private func daemonStatus() -> HelperDaemonStatus {
        switch SMAppService.daemon(plistName: HelperPaths.launchDaemonPlistName).status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    private func setState(_ newState: HelperState) {
        guard state != newState else { return }
        log.info(
            "helper state \(self.state.rawValue, privacy: .public) -> \(newState.rawValue, privacy: .public)")
        state = newState
        if newState == .ready {
            defaults.set(true, forKey: Self.everReadyDefaultsKey)
        }
    }

    // MARK: - Commands

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
                fanIndexes: nil,
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
        guard isReady else {
            throw MacFanError(statusSummary)
        }
        do {
            return try await send(command, timeout: Self.commandTimeout)
        } catch let error as HelperResponseError {
            throw error
        } catch let error as HelperStaleError {
            setState(.stale)
            requestImmediateRefresh()
            throw error
        } catch {
            setState(.unavailable)
            requestImmediateRefresh()
            throw error
        }
    }

    // MARK: - Transport

    private func send(_ command: HelperCommand, timeout: TimeInterval) async throws -> HelperResponse {
        let response = try await sendUnchecked(command, timeout: timeout)
        guard (response.protocolVersion ?? 0) >= Self.minimumProtocolVersion else {
            throw HelperStaleError()
        }
        return response
    }

    private func sendUnchecked(_ command: HelperCommand, timeout: TimeInterval) async throws -> HelperResponse {
        let commandData = try encoder.encode(command)
        let responseData = try await sendXPC(commandData, timeout: timeout)
        let response = try decoder.decode(HelperResponse.self, from: responseData)

        guard response.id == command.id else {
            throw HelperResponseError(message: "Helper returned a mismatched response.")
        }
        guard response.ok else {
            throw HelperResponseError(message: response.message)
        }
        return response
    }

    private func sendXPC(_ commandData: Data, timeout: TimeInterval) async throws -> Data {
        let connection = activeConnection()

        return try await withCheckedThrowingContinuation { continuation in
            let singleShot = SingleShotContinuation(continuation)
            let timeoutTask = Task { @MainActor [weak self] in
                let delay = UInt64(timeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                // The connection may be wedged mid-call; dropping it here
                // keeps the next command from queueing behind a hung reply.
                if singleShot.resume(throwing: HelperUnavailableError()) {
                    self?.invalidateConnection()
                }
            }

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    timeoutTask.cancel()
                    singleShot.resume(throwing: error)
                }) as? MacFanHelperXPCProtocol
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

    private func invalidateConnection() {
        connection?.invalidate()
        connection = nil
    }

    private func activeConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(
            machServiceName: HelperPaths.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: MacFanHelperXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.connection?.invalidate()
                self.connection = nil
                if !self.repairInFlight {
                    self.requestImmediateRefresh()
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

    private var launchDaemonPlistIsBundled: Bool {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchDaemons", isDirectory: true)
            .appendingPathComponent(HelperPaths.launchDaemonPlistName)
        return FileManager.default.fileExists(atPath: url.path)
    }
}

private final class SingleShotContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    /// Returns whether this call won the race and actually resumed.
    @discardableResult
    func resume(returning value: Value) -> Bool {
        lock.withLock {
            guard let continuation else { return false }
            continuation.resume(returning: value)
            self.continuation = nil
            return true
        }
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        lock.withLock {
            guard let continuation else { return false }
            continuation.resume(throwing: error)
            self.continuation = nil
            return true
        }
    }
}

private struct HelperResponseError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private struct HelperUnavailableError: LocalizedError {
    var errorDescription: String? {
        "helper.error.no_response".localized
    }
}

private struct HelperStaleError: LocalizedError {
    var errorDescription: String? {
        "helper.error.outdated".localized
    }
}
