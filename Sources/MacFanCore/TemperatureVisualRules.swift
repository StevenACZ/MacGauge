import Foundation

public enum TemperatureBand: String, Codable, Sendable {
    case normal
    case medium
    case hot
}

public struct TemperatureVisualRules: Codable, Sendable {
    public var normalUpperCelsius: Double
    public var hotLowerCelsius: Double

    public init(normalUpperCelsius: Double = 45, hotLowerCelsius: Double = 70) {
        self.normalUpperCelsius = normalUpperCelsius
        self.hotLowerCelsius = max(normalUpperCelsius + 1, hotLowerCelsius)
    }

    public func band(for celsius: Double?) -> TemperatureBand {
        guard let celsius else { return .normal }
        if celsius <= normalUpperCelsius { return .normal }
        if celsius < hotLowerCelsius { return .medium }
        return .hot
    }

}

public struct DebounceWindow: Sendable {
    public var delay: TimeInterval

    public init(delay: TimeInterval) {
        self.delay = max(0, delay)
    }

    public func fireDate(after changeDate: Date) -> Date {
        changeDate.addingTimeInterval(delay)
    }
}
