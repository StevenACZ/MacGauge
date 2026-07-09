import Foundation

/// Dead-man switch for the privileged helper: armed by manual fan writes,
/// fed by any client activity (pings included), and fired when an armed
/// helper hears nothing for the silence timeout — the signature of a crashed
/// client that left fans pinned manual. A clean quit that intentionally
/// keeps manual control must disarm explicitly.
///
/// Timestamps are awake-time seconds (`CLOCK_UPTIME_RAW`), not wall time, so
/// hours asleep never count toward the silence window and the watchdog
/// cannot fire on wake before the client gets a chance to ping.
public struct HelperWatchdogState: Sendable {
    public static let silenceTimeoutSeconds: TimeInterval = 180
    public static let checkIntervalSeconds: TimeInterval = 30

    public private(set) var isArmed: Bool
    private var lastActivityUptime: TimeInterval

    public init(nowUptime: TimeInterval) {
        isArmed = false
        lastActivityUptime = nowUptime
    }

    public mutating func recordClientActivity(nowUptime: TimeInterval) {
        lastActivityUptime = nowUptime
    }

    public mutating func armForManualControl(nowUptime: TimeInterval) {
        isArmed = true
        lastActivityUptime = nowUptime
    }

    public mutating func disarm() {
        isArmed = false
    }

    public func shouldRestoreAutomatic(nowUptime: TimeInterval) -> Bool {
        isArmed && nowUptime - lastActivityUptime >= Self.silenceTimeoutSeconds
    }
}
