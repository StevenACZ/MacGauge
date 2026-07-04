import Foundation

public struct FanAnimationRules: Sendable {
    public init() {}

    /// Continuous angular speed for the menu bar fan icon, derived from the
    /// fan's position inside its RPM range. `nil` means the fan is effectively
    /// stopped and the icon should rest. The exponent keeps low speeds calm
    /// while still reaching a fast spin near the maximum.
    public func rotationDegreesPerSecond(currentRPM: Double?, targetRPM: Double?, minRPM: Double?, maxRPM: Double?) -> Double? {
        guard let maxRPM, maxRPM > 0 else { return nil }
        guard let rpm = currentRPM ?? targetRPM, rpm.isFinite, rpm > 0 else { return nil }

        let minimum = minRPM.map { max(0, min($0, maxRPM)) } ?? 0
        let normalized = max(0, min(1, (rpm - minimum) / max(1, maxRPM - minimum)))
        guard normalized > 0.04 else { return nil }

        return 20 + 380 * pow(normalized, 1.6)
    }
}
