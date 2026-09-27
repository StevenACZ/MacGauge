import CoreGraphics
import Foundation

/// System modules available in the menu bar, in their fixed left-to-right
/// order.
enum SystemModuleKind: String, CaseIterable, Identifiable {
    case network
    case cpu
    case memory

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .cpu:
            return "system.cpu".localized
        case .memory:
            return "system.memory".localized
        case .network:
            return "system.network".localized
        }
    }
}

/// Breathing room each module keeps around itself in the menu bar. At
/// Together the modules fuse into a single status item so even the system's
/// own gap between items disappears; the other levels keep independent items
/// and this padding is what separates them on top of that system gap.
enum ModuleSpacingLevel: String, CaseIterable, Identifiable {
    case together
    case tight
    case regular
    case roomy

    static let fusedModuleGap: CGFloat = 6

    var id: String { rawValue }

    var padding: CGFloat {
        switch self {
        case .together, .tight:
            return 0
        case .regular:
            return 1
        case .roomy:
            return 3
        }
    }

    var localizedName: String {
        "module.spacing.\(rawValue)".localized
    }
}

/// Length of the CPU/RAM sparkline charts in the menu bar.
enum ModuleGraphWidth: String, CaseIterable, Identifiable {
    case compact
    case medium
    case wide

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .compact:
            return 18
        case .medium:
            return 26
        case .wide:
            return 40
        }
    }

    var localizedName: String {
        "module.graph.\(rawValue)".localized
    }
}

/// How one module's chart or arrows are tinted.
enum ModuleColorMode: String, CaseIterable, Identifiable {
    /// The module keeps its own tint (teal CPU, indigo RAM, orange/blue net).
    case multicolor
    /// The menu bar's label color.
    case mono
    /// Charts and arrows in gray; values stay in the label color.
    case gray
    /// The chart takes the temperature-band colors as usage climbs.
    case load

    var id: String { rawValue }

    var localizedName: String {
        "module.color.\(rawValue)".localized
    }
}

/// How the fan icon and temperature text are tinted.
enum FanColorStyle: String, CaseIterable, Identifiable {
    /// The temperature-band colors (current behavior).
    case temperature
    /// The menu bar's label color.
    case mono
    /// Always gray.
    case gray

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .temperature:
            return "module.color.temperature".localized
        case .mono:
            return "module.color.mono".localized
        case .gray:
            return "module.color.gray".localized
        }
    }
}
