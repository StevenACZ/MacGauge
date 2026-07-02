import Foundation

enum SettingsTab: CaseIterable, Hashable, Identifiable {
    case general
    case control
    case display
    case safety

    var id: Self { self }

    var label: String {
        switch self {
        case .general: "settings.tab.general".localized
        case .control: "settings.tab.control".localized
        case .display: "settings.tab.display".localized
        case .safety: "settings.tab.safety".localized
        }
    }
}
