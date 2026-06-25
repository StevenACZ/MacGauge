import Foundation

enum FanControlMode: String, CaseIterable, Identifiable {
    case manual
    case curve

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .curve: "Curve"
        }
    }
}
