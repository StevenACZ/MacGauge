import SwiftUI

/// One percent-metric card (CPU or RAM): simulated preview, color mode with
/// optional load bands, and graph length. The two metrics render identically
/// and differ only in icon, title, and which settings they bind.
struct PercentModuleSection: View {
    @ObservedObject var settings: AppSettingsStore
    let simulator: ModulePreviewSimulator
    let metric: PercentModuleStatusLabel.Metric

    var body: some View {
        SettingsSurface(icon: icon, title: title) {
            SimulatedPreviewCapsule {
                SimulatedPercentModulePreview(simulator: simulator, settings: settings, metric: metric)
            }

            HiddenModuleHint(isShown: showsModule)

            SettingsDivider()

            metricRows
        }
        .animation(Theme.Anim.smooth, value: colorMode)
    }

    /// Color style first (with the band editor right under the preview so
    /// threshold drags read live), graph length last.
    @ViewBuilder
    private var metricRows: some View {
        StylePickerRow(
            title: "settings.display.modules.color".localized,
            caption: "settings.display.modules.color.caption".localized,
            options: ModuleColorMode.allCases,
            label: \.localizedName,
            selection: colorModeBinding
        )

        if colorMode == .load {
            SettingsDivider()

            loadBandsRows
        }

        SettingsDivider()

        StylePickerRow(
            title: "settings.display.modules.graph".localized,
            caption: "settings.display.modules.graph.caption".localized,
            options: ModuleGraphWidth.allCases,
            label: \.localizedName,
            selection: graphWidthBinding
        )
    }

    /// The customizable "By load" bands for the module: a 0-100% strip with
    /// draggable thresholds plus per-band rows. Usage bands read
    /// Low/Medium/High — "hot" only makes sense for temperature.
    @ViewBuilder
    private var loadBandsRows: some View {
        let thresholds = thresholdBindings
        let normalHex = settings.colorHexBinding(hexKeyPaths.normal)
        let mediumHex = settings.colorHexBinding(hexKeyPaths.medium)
        let hotHex = settings.colorHexBinding(hexKeyPaths.hot)

        Text("settings.display.load_bands.caption".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        BandsStripEditor(
            normalUpper: thresholds.normalUpper,
            hotLower: thresholds.hotLower,
            normalColor: Color(hexString: normalHex.wrappedValue),
            mediumColor: Color(hexString: mediumHex.wrappedValue),
            hotColor: Color(hexString: hotHex.wrappedValue),
            scale: 0...100,
            unitSuffix: "%"
        )
        .padding(.vertical, 4)

        VisualThresholdRow(
            title: "settings.display.load.low".localized,
            thresholdLabel: "settings.display.up_to".localized,
            value: thresholds.normalUpper,
            colorHex: normalHex,
            unit: "%"
        )

        SettingsDivider()

        VisualBandRow(
            title: "settings.display.load.medium".localized,
            rangeText: "\(Int(thresholds.normalUpper.wrappedValue.rounded()))-\(Int(thresholds.hotLower.wrappedValue.rounded())) %",
            colorHex: mediumHex
        )

        SettingsDivider()

        VisualThresholdRow(
            title: "settings.display.load.high".localized,
            thresholdLabel: "settings.display.from".localized,
            value: thresholds.hotLower,
            colorHex: hotHex,
            unit: "%"
        )
    }

    // MARK: - Per-metric bindings

    private var icon: String {
        metric == .cpu ? "cpu" : "memorychip"
    }

    private var title: String {
        metric == .cpu
            ? "settings.display.module_cpu".localized
            : "settings.display.module_memory".localized
    }

    private var showsModule: Bool {
        metric == .cpu ? settings.showsCPUModule : settings.showsMemoryModule
    }

    private var colorMode: ModuleColorMode {
        metric == .cpu ? settings.cpuColorMode : settings.memoryColorMode
    }

    private var colorModeBinding: Binding<ModuleColorMode> {
        metric == .cpu ? $settings.cpuColorMode : $settings.memoryColorMode
    }

    private var graphWidthBinding: Binding<ModuleGraphWidth> {
        metric == .cpu ? $settings.cpuGraphWidth : $settings.memoryGraphWidth
    }

    private var thresholdBindings: (normalUpper: Binding<Double>, hotLower: Binding<Double>) {
        switch metric {
        case .cpu:
            return settings.orderedThresholdBindings(
                normalUpper: \.cpuNormalUpperPercent,
                hotLower: \.cpuHotLowerPercent,
                floor: 5,
                ceiling: 100,
                gap: 5
            )
        case .memory:
            return settings.orderedThresholdBindings(
                normalUpper: \.memoryNormalUpperPercent,
                hotLower: \.memoryHotLowerPercent,
                floor: 5,
                ceiling: 100,
                gap: 5
            )
        }
    }

    private var hexKeyPaths:
        (
            normal: ReferenceWritableKeyPath<AppSettingsStore, String>,
            medium: ReferenceWritableKeyPath<AppSettingsStore, String>,
            hot: ReferenceWritableKeyPath<AppSettingsStore, String>
        )
    {
        switch metric {
        case .cpu:
            return (\.cpuNormalColorHex, \.cpuMediumColorHex, \.cpuHotColorHex)
        case .memory:
            return (\.memoryNormalColorHex, \.memoryMediumColorHex, \.memoryHotColorHex)
        }
    }
}

/// One percent module (CPU or RAM) rendered exactly like the menu bar but fed
/// by the simulator, so color styles and thresholds show live transitions.
struct SimulatedPercentModulePreview: View {
    @ObservedObject var simulator: ModulePreviewSimulator
    @ObservedObject var settings: AppSettingsStore
    let metric: PercentModuleStatusLabel.Metric

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PercentModuleSegment(
            title: metric == .cpu ? "system.cpu".localized : "system.memory".localized,
            percent: percent,
            history: history,
            color: color,
            graphWidth: graphWidth.width,
            tickSeconds: ModulePreviewSimulator.tickSeconds,
            animated: settings.performanceMode == .full && !reduceMotion
        )
        .frame(height: 22)
        .animation(Theme.Anim.smooth, value: graphWidth)
    }

    private var percent: Double {
        metric == .cpu ? simulator.cpuPercent : simulator.memoryPercent
    }

    private var history: [Double] {
        metric == .cpu ? simulator.cpuHistory : simulator.memoryHistory
    }

    private var graphWidth: ModuleGraphWidth {
        metric == .cpu ? settings.cpuGraphWidth : settings.memoryGraphWidth
    }

    private var color: Color {
        switch metric {
        case .cpu:
            return ModuleColorResolver.cpuChartColor(percent: percent, settings: settings)
        case .memory:
            return ModuleColorResolver.memoryChartColor(percent: percent, settings: settings)
        }
    }
}
