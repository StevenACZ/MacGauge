import Foundation

public struct FanAnimationRules: Sendable {
    public static let restingDegreesPerSecond: Double = 45
    public static let maximumDegreesPerSecond: Double = 720

    public init() {}

    public func rotationDegreesPerSecond(fan: FanInfo?, cpuPercent: Double?, temperatureCelsius: Double?) -> Double {
        let load = max(fanLoad(fan), cpuLoad(cpuPercent), heatLoad(temperatureCelsius))
        let range = Self.maximumDegreesPerSecond - Self.restingDegreesPerSecond
        return Self.restingDegreesPerSecond + range * pow(load, 1.4)
    }

    func fanLoad(_ fan: FanInfo?) -> Double {
        guard let fan, let maxRPM = fan.maxRPM, maxRPM > 0 else { return 0 }
        guard let rpm = fan.currentRPM ?? fan.targetRPM, rpm.isFinite, rpm > 0 else { return 0 }
        let minimum = fan.minRPM.map { max(0, min($0, maxRPM)) } ?? 0
        return clamped((rpm - minimum) / max(1, maxRPM - minimum))
    }

    func cpuLoad(_ percent: Double?) -> Double {
        guard let percent, percent.isFinite else { return 0 }
        return clamped(percent / 100)
    }

    func heatLoad(_ celsius: Double?) -> Double {
        guard let celsius, celsius.isFinite else { return 0 }
        return clamped((celsius - 50) / 40)
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
