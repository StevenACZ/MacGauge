import Foundation

public enum HelperDaemonStatus: String, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
}

public enum HelperPingOutcome: String, Sendable {
    case ready
    case stale
    case failed
}

public enum HelperHealthDecision: Equatable, Sendable {
    case markReady
    case markNeedsAuthorization
    case markNeedsApproval
    case waitForNextTick
    case restartDaemon
    case reregisterDaemon
    case markDegraded
}

public struct HelperHealthRules: Sendable {
    public static let pingFailureStrikeLimit = 2
    public static let readyHeartbeatSeconds: TimeInterval = 15
    public static let recoveryHeartbeatSeconds: TimeInterval = 3

    public init() {}

    public func decision(
        status: HelperDaemonStatus,
        ping: HelperPingOutcome?,
        consecutivePingFailures: Int,
        canRepair: Bool
    ) -> HelperHealthDecision {
        switch status {
        case .notRegistered, .notFound:
            return .markNeedsAuthorization
        case .requiresApproval:
            return .markNeedsApproval
        case .enabled:
            switch ping {
            case nil:
                return .waitForNextTick
            case .ready:
                return .markReady
            case .stale:
                return canRepair ? .restartDaemon : .markDegraded
            case .failed:
                guard consecutivePingFailures >= Self.pingFailureStrikeLimit else {
                    return .waitForNextTick
                }
                return canRepair ? .reregisterDaemon : .markDegraded
            }
        }
    }

    public func heartbeatInterval(isReady: Bool) -> TimeInterval {
        isReady ? Self.readyHeartbeatSeconds : Self.recoveryHeartbeatSeconds
    }
}
