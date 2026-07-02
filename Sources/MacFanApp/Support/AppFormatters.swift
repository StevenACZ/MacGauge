import Foundation

enum AppFormatters {
    static func temperature(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius else { return "-- \(unit.suffix)" }
        return String(format: "%.0f %@", unit.convert(celsius: celsius), unit.suffix)
    }

    static func temperaturePrecise(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius else { return "Unavailable" }
        return String(format: "%.1f %@", unit.convert(celsius: celsius), unit.suffix)
    }

    static func rpm(_ value: Double?) -> String {
        guard let value else { return "-- RPM" }
        return "\(Int(value.rounded())) RPM"
    }

    static func approximateRPM(_ value: Double?) -> String {
        guard let value else { return "-- RPM" }
        return "~ \(Int(value.rounded())) RPM"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func seconds(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value)) s"
        }
        return String(format: "%.1f s", value)
    }
}
