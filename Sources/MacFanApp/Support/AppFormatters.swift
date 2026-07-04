import Foundation

enum AppFormatters {
    static func temperature(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius else { return "-- \(unit.suffix)" }
        return String(format: "%.0f %@", unit.convert(celsius: celsius), unit.suffix)
    }

    static func temperaturePrecise(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius else { return "formatter.temperature_unavailable".localized }
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

    /// Short RPM for axis labels: "0", "850", "1.2k", "12k".
    static func compactRPM(_ value: Double) -> String {
        guard value >= 1000 else { return "\(Int(value.rounded()))" }
        let thousands = value / 1000
        return thousands >= 10
            ? String(format: "%.0fk", thousands)
            : String(format: "%.1fk", thousands)
    }

    /// Adaptive transfer rate: "12.4 MB/s", "824 KB/s", "12 B/s".
    static func byteRate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0 else { return "--" }
        let megabytes = bytesPerSecond / 1_048_576
        if megabytes >= 100 { return String(format: "%.0f MB/s", megabytes) }
        if megabytes >= 1 { return String(format: "%.1f MB/s", megabytes) }
        let kilobytes = bytesPerSecond / 1024
        if kilobytes >= 1 { return String(format: "%.0f KB/s", kilobytes) }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    /// Narrow rate for the menu bar: "0 KB/s", "12 KB/s", "1.2 MB/s". Never
    /// exceeds three digits so the status item width stays constant.
    static func byteRateCompact(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0 else { return "--" }
        let kilobytes = bytesPerSecond / 1024
        if kilobytes < 999.5 { return String(format: "%.0f KB/s", kilobytes) }
        let megabytes = bytesPerSecond / 1_048_576
        if megabytes < 9.95 { return String(format: "%.1f MB/s", megabytes) }
        if megabytes < 999.5 { return String(format: "%.0f MB/s", megabytes) }
        return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824)
    }

    static func gigabytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "--" }
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// Adaptive byte amount: "1.2 GB", "854 MB", "320 KB".
    static func memoryAmount(_ bytes: UInt64?) -> String {
        guard let bytes else { return "--" }
        let gigabytes = Double(bytes) / 1_073_741_824
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1 { return String(format: "%.0f MB", megabytes) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}
