import Foundation

public struct FanAnimationRules: Sendable {
    public init() {}

    public func animationInterval(currentRPM: Double?, targetRPM: Double?, minRPM: Double?, maxRPM: Double?) -> TimeInterval? {
        guard let maxRPM, maxRPM > 0 else { return nil }
        guard let rpm = currentRPM ?? targetRPM, rpm.isFinite, rpm > 0 else { return nil }

        let minimum = minRPM.map { max(0, min($0, maxRPM)) } ?? 0
        let normalized = max(0, min(1, (rpm - minimum) / max(1, maxRPM - minimum)))
        guard normalized > 0.04 else { return nil }

        switch normalized {
        case ..<0.18:
            return 2.4
        case ..<0.45:
            return 1.0
        case ..<0.8:
            return 0.45
        default:
            return 0.12
        }
    }
}
