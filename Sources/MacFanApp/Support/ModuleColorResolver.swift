import AppKit
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
            multicolor: multicolor(for: .cpu, adaptsToWindowBackground: adaptsToWindowBackground),
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
            multicolor: multicolor(for: .memory, adaptsToWindowBackground: adaptsToWindowBackground),
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
        mode: ModuleColorMode? = nil,
        adaptsToWindowBackground: Bool = false
    ) -> (up: Color, down: Color) {
        switch mode ?? settings.networkColorMode {
        case .multicolor:
            return (
                tint(hexString: settings.networkUpColorHex, adaptsToWindowBackground: adaptsToWindowBackground),
                tint(hexString: settings.networkDownColorHex, adaptsToWindowBackground: adaptsToWindowBackground)
            )
        case .mono, .load:
            return (.primary, .primary)
        case .gray:
            let gray = gray(adaptsToWindowBackground: adaptsToWindowBackground)
            return (gray, gray)
        }
    }

    static func previewStyle(
        for mode: ModuleColorMode,
        metric: PercentModuleStatusLabel.Metric,
        settings: AppSettingsStore
    ) -> AnyShapeStyle {
        switch mode {
        case .multicolor:
            return AnyShapeStyle(multicolor(for: metric, adaptsToWindowBackground: false))
        case .mono:
            return AnyShapeStyle(Color.primary)
        case .gray:
            return AnyShapeStyle(gray(adaptsToWindowBackground: false))
        case .load:
            let hexes =
                metric == .cpu
                ? [settings.cpuNormalColorHex, settings.cpuMediumColorHex, settings.cpuHotColorHex]
                : [settings.memoryNormalColorHex, settings.memoryMediumColorHex, settings.memoryHotColorHex]
            return AnyShapeStyle(
                LinearGradient(
                    colors: hexes.map { menuBarTint(hexString: $0) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    static func menuBarTint(hexString: String) -> Color {
        tint(hexString: hexString, adaptsToWindowBackground: false)
    }

    private static func multicolor(
        for metric: PercentModuleStatusLabel.Metric,
        adaptsToWindowBackground: Bool
    ) -> Color {
        switch metric {
        case .cpu:
            return adaptsToWindowBackground ? Theme.accent : Theme.menuBarAccent
        case .memory:
            return adaptsToWindowBackground ? adaptedIndigo : menuBarIndigo
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
            return gray(adaptsToWindowBackground: adaptsToWindowBackground)
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
    private static let menuBarIndigo = AppearancePalette.menuBarAdapted(.systemIndigo)
    private static var adaptedTints: [String: Color] = [:]

    /// Hierarchical `.secondary` loses its vibrancy blend inside a status item
    /// and renders as a muddy gray on the wallpaper; a plain alpha does not.
    private static func gray(adaptsToWindowBackground: Bool) -> Color {
        adaptsToWindowBackground ? .secondary : Color.primary.opacity(0.55)
    }

    /// A fresh dynamic color per tick would re-arm the tint animations.
    private static func tint(hexString: String, adaptsToWindowBackground: Bool) -> Color {
        let key = (adaptsToWindowBackground ? "window:" : "menubar:") + hexString
        if let cached = adaptedTints[key] {
            return cached
        }
        let base = NSColor(hexString: hexString) ?? .labelColor
        let adapted =
            adaptsToWindowBackground
            ? AppearancePalette.lightAdapted(Color(nsColor: base))
            : AppearancePalette.menuBarAdapted(base)
        adaptedTints[key] = adapted
        return adapted
    }
}
