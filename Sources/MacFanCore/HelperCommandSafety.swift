import Foundation

public struct HelperCommandSafety: Sendable {
    public init() {}

    public func validate(percent: Double, allowDangerous: Bool, allowZero: Bool) throws {
        guard percent.isFinite, percent >= 0, percent <= 100 else {
            throw MacFanError("Percent must be between 0 and 100.")
        }
        if percent == 0 && !(allowZero && allowDangerous) {
            throw MacFanError("0 percent requires explicit dangerous zero unlock.")
        }
        if (percent <= 10 || percent >= 95) && !allowDangerous {
            throw MacFanError("Edge fan ranges require dangerous range unlock.")
        }
    }

    public func validate(rpm: Double, fan: FanInfo, percent: Double, allowDangerous: Bool) throws {
        let belowMinimum = fan.minRPM.map { rpm < $0 } ?? false
        let aboveMaximum = fan.maxRPM.map { rpm > $0 } ?? false
        if (belowMinimum || aboveMaximum) && !allowDangerous {
            throw MacFanError("Target \(Int(rpm.rounded())) RPM is outside reported fan limits.")
        }
    }
}
