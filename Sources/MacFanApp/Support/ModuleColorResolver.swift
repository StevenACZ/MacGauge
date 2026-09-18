import MacFanCore
import SwiftUI

/// Resolves each module's color style into concrete tints. Shared by the menu
/// bar labels and the detail popovers so the chart the user opens always
/// matches the one in the menu bar.
@MainActor
enum ModuleColorResolver {
    static func cpuChartColor(
        percent: Double?,
        settings: AppSettingsStore,
        adaptsToWindowBackground: Bool = false
    ) -> Color {
        percentChartColor(
            adaptsToWindowBackground: adaptsToWindowBackground,
            mode: settings.cpuColorMode,
            multicolor: adaptsToWindowBackground ? Theme.accent : Theme.rawAccent,
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

    static func memoryChartColor(
        percent: Double?,
        settings: AppSettingsStore,
        adaptsToWindowBackground: Bool = false
    ) -> Color {
        percentChartColor(
            adaptsToWindowBackground: adaptsToWindowBackground,
            mode: settings.memoryColorMode,
            multicolor: adaptsToWindowBackground ? adaptedIndigo : .indigo,
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
    static func networkArrowTints(
        settings: AppSettingsStore,
        adaptsToWindowBackground: Bool = false
    ) -> (up: Color, down: Color) {
        switch settings.networkColorMode {
        case .multicolor:
            return (
                tint(hexString: settings.networkUpColorHex, adaptsToWindowBackground: adaptsToWindowBackground),
                tint(hexString: settings.networkDownColorHex, adaptsToWindowBackground: adaptsToWindowBackground)
            )
        case .mono, .load:
            return (.primary, .primary)
        case .gray:
            return (.secondary, .secondary)
        }
    }

    private static func percentChartColor(
        adaptsToWindowBackground: Bool,
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
                return tint(hexString: normalHex, adaptsToWindowBackground: adaptsToWindowBackground)
            case .elevated:
                return tint(hexString: mediumHex, adaptsToWindowBackground: adaptsToWindowBackground)
            case .high:
                return tint(hexString: hotHex, adaptsToWindowBackground: adaptsToWindowBackground)
            }
        }
    }

    private static let adaptedIndigo = AppearancePalette.lightAdapted(.indigo)
    private static var adaptedTints: [String: Color] = [:]

    /// A fresh dynamic color per tick would re-arm the tint animations.
    private static func tint(hexString: String, adaptsToWindowBackground: Bool) -> Color {
        guard adaptsToWindowBackground else { return Color(hexString: hexString) }
        if let cached = adaptedTints[hexString] {
            return cached
        }
        let adapted = AppearancePalette.lightAdapted(Color(hexString: hexString))
        adaptedTints[hexString] = adapted
        return adapted
    }
}
