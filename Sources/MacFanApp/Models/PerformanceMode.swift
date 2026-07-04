import Foundation

/// How much menu bar motion the app pays for. Every animation frame makes
/// AppKit re-layout and re-snapshot the status items, so continuous motion
/// keeps a whole render pipeline hot in an app meant to idle in the
/// background all day.
enum PerformanceMode: String, CaseIterable, Identifiable {
    /// Values and charts step once per tick with no in-between frames, and
    /// the fan icon sits still (its color keeps tracking temperature).
    /// Recommended default.
    case efficient
    /// Continuous animations: sliding charts, rolling digits, 30 fps fan.
    case full

    var id: String { rawValue }

    var localizedName: String {
        "performance.mode.\(rawValue)".localized
    }

    var localizedCaption: String {
        "performance.mode.\(rawValue).caption".localized
    }

    var symbolName: String {
        switch self {
        case .efficient: return "leaf.fill"
        case .full: return "sparkles"
        }
    }
}
