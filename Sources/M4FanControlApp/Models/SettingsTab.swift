import Foundation

enum SettingsTab: CaseIterable, Hashable, Identifiable {
    case general
    case control
    case display
    case safety

    var id: Self { self }

    var label: String {
        switch self {
        case .general: "General"
        case .control: "Control"
        case .display: "Display"
        case .safety: "Safety"
        }
    }
}
