import MacFanCore
import SwiftUI

/// Resolves each module's color style into concrete tints. Shared by the menu
/// bar labels and the detail popovers so the chart the user opens always
/// matches the one in the menu bar.
@MainActor
enum ModuleColorResolver {
    static func cpuChartColor(percent: Double?, settings: AppSettingsStore) -> Color {
        percentChartColor(
            mode: settings.cpuColorMode,
            multicolor: Theme.accent,
            band: SystemLoadRules.loadBand(
                forPercent: percent,
                normalUpperPercent: settings.cpuNormalUpperPercent,
                hotLowerPercent: settings.cpuHotLowerPercent
            ),
            normalHex: settings.cpuNormalColorHex,
            mediumHex: settings.cpuMediumColorHex,
            hotHex: settings.cpuHotColorHex
        )
    }

    static func memoryChartColor(percent: Double?, settings: AppSettingsStore) -> Color {
        percentChartColor(
            mode: settings.memoryColorMode,
            multicolor: .indigo,
            band: SystemLoadRules.loadBand(
                forPercent: percent,
                normalUpperPercent: settings.memoryNormalUpperPercent,
                hotLowerPercent: settings.memoryHotLowerPercent
            ),
            normalHex: settings.memoryNormalColorHex,
            mediumHex: settings.memoryMediumColorHex,
            hotHex: settings.memoryHotColorHex
        )
    }

    /// Rates have no load semantics, so anything but multicolor/gray goes
    /// neutral; multicolor uses the user's own up/down tints.
    static func networkArrowTints(settings: AppSettingsStore) -> (up: Color, down: Color) {
        switch settings.networkColorMode {
        case .multicolor:
            return (
                Color(hexString: settings.networkUpColorHex),
                Color(hexString: settings.networkDownColorHex)
            )
        case .mono, .load:
            return (.primary, .primary)
        case .gray:
            return (.secondary, .secondary)
        }
    }

    private static func percentChartColor(
        mode: ModuleColorMode,
        multicolor: Color,
        band: LoadBand,
        normalHex: String,
        mediumHex: String,
        hotHex: String
    ) -> Color {
        switch mode {
        case .multicolor:
            return multicolor
        case .mono:
            return .primary
        case .gray:
            return .secondary
        case .load:
            switch band {
            case .normal:
                return Color(hexString: normalHex)
            case .elevated:
                return Color(hexString: mediumHex)
            case .high:
                return Color(hexString: hotHex)
            }
        }
    }
}
