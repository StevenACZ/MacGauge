import Foundation

enum FanControlMode: String, CaseIterable, Identifiable {
    case monitor
    case manual
    case curve

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monitor: "Monitor"
        case .manual: "Manual"
        case .curve: "Curve"
        }
    }
}
