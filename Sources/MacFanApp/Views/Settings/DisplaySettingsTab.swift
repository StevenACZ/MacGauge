import MacFanCore
import SwiftUI

/// The visual-configuration screen: a section sidebar on the left (fan +
/// temperature, modules, and the CPU/RAM/network charts) and one card at a
/// time on the right. Module previews run on simulated activity so the user
/// watches their colors and thresholds react without loading the Mac.
struct DisplaySettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var monitor: FanMonitor

    /// False while another tab is selected so the live previews stop ticking.
    let isActive: Bool

    @State private var section: DisplaySection = .fan
    /// Held as plain @State so only the preview subviews observe its ticks;
    /// the tab itself never re-renders per tick.
    @State private var simulator = ModulePreviewSimulator()

    private let animationRules = FanAnimationRules()

    private enum DisplaySection: String, CaseIterable, Identifiable {
        case fan
        case modules
        case cpu
        case memory
        case network

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .fan: return "fanblades"
            case .modules: return "menubar.rectangle"
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .network: return "network"
            }
        }

        var localizedName: String {
            switch self {
            case .fan: return "settings.display.section.fan_temp".localized
            case .modules: return "settings.display.section.modules".localized
            case .cpu: return "system.cpu".localized
            case .memory: return "system.memory".localized
            case .network: return "system.network".localized
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            sectionSidebar

            SettingsPane {
                switch section {
                case .fan:
                    menuBarItemSurface
                    temperatureBandsSurface
                case .modules:
                    modulesSurface
                case .cpu:
                    cpuModuleSurface
                case .memory:
                    memoryModuleSurface
                case .network:
                    networkModuleSurface
                }
            }
        }
        .onChange(of: isActive) { _ in updateSimulation() }
        .onChange(of: section) { _ in updateSimulation() }
        .onAppear { updateSimulation() }
        .onDisappear { simulator.setRunning(false) }
    }

    /// The simulator only ticks while a section with module previews is
    /// visible; the fan section reads the real monitor instead.
    private func updateSimulation() {
        simulator.setRunning(isActive && section != .fan)
    }

    // MARK: - Section sidebar

    private var sectionSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DisplaySection.allCases) { item in
                sidebarRow(item)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 156)
    }

    private func sidebarRow(_ item: DisplaySection) -> some View {
        let isSelected = section == item
        return Button {
            section = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .center)
                Text(item.localizedName)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.hover, value: isSelected)
    }

    // MARK: - Menu bar item (fan)

    private var menuBarItemSurface: some View {
        SettingsSurface(icon: "fanblades", title: "settings.display.menubar_item".localized) {
            HStack {
                Spacer(minLength: 0)
                MenuBarItemPreview(
                    temperatureText: AppFormatters.temperature(
                        monitor.snapshot.temperatureCelsius,
                        unit: settings.temperatureUnit
                    ),
                    color: fanPreviewColor,
                    degreesPerSecond: previewDegreesPerSecond,
                    isPaused: !isActive
                )
                Spacer(minLength: 0)
            }

            Text("settings.display.preview.caption".localized)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            SettingsDivider()

            SettingsRow(
                title: "settings.display.animate_icon".localized,
                subtitle: "settings.display.animate_icon.caption".localized,
                trailingWidth: 60
            ) {
                Toggle("", isOn: $settings.animateFanIcon)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(settings.performanceMode == .efficient)
            }

            if settings.performanceMode == .efficient {
                Label(
                    "settings.display.animate_icon.efficient_notice".localized,
                    systemImage: "leaf.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            SettingsDivider()

            stylePickerRow(
                title: "settings.display.modules.color".localized,
                caption: "fan.color.caption".localized,
                options: FanColorStyle.allCases,
                label: \.localizedName,
                selection: $settings.fanColorStyle
            )
        }
    }

    private var currentBandColor: Color {
        switch settings.visualRules.band(for: monitor.snapshot.temperatureCelsius) {
        case .normal:
            return Color(hexString: settings.normalColorHex)
        case .medium:
            return Color(hexString: settings.mediumColorHex)
        case .hot:
            return Color(hexString: settings.hotColorHex)
        }
    }

    /// Mirrors StatusItemController.statusColor for the always-dark preview.
    private var fanPreviewColor: Color {
        switch settings.fanColorStyle {
        case .temperature:
            return currentBandColor
        case .mono:
            return .white
        case .gray:
            return Color(nsColor: .systemGray)
        }
    }

    private var previewDegreesPerSecond: Double {
        // Mirrors the real status item: Efficient keeps the icon still.
        guard settings.animateFanIcon, settings.performanceMode == .full else { return 0 }
        let fan = monitor.snapshot.fan
        return animationRules.rotationDegreesPerSecond(
            currentRPM: fan?.currentRPM,
            targetRPM: fan?.targetRPM,
            minRPM: fan?.minRPM,
            maxRPM: fan?.maxRPM
        ) ?? 0
    }

    // MARK: - Temperature bands

    private var temperatureBandsSurface: some View {
        SettingsSurface(icon: "thermometer.medium", title: "settings.display.bands.title".localized) {
            Text("settings.display.bands.caption".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            BandsStripEditor(
                normalUpper: normalUpperBinding,
                hotLower: hotLowerBinding,
                normalColor: Color(hexString: settings.normalColorHex),
                mediumColor: Color(hexString: settings.mediumColorHex),
                hotColor: Color(hexString: settings.hotColorHex)
            )
            .padding(.vertical, 4)

            SettingsDivider()

            visualThresholdRow(
                title: "settings.display.normal".localized,
                thresholdLabel: "settings.display.up_to".localized,
                value: normalUpperBinding,
                colorHex: colorHexBinding(\.normalColorHex)
            )

            SettingsDivider()

            visualBandRow(
                title: "settings.display.medium".localized,
                rangeText: "\(Int(settings.normalUpperCelsius.rounded()))-\(Int(settings.hotLowerCelsius.rounded())) °C",
                colorHex: colorHexBinding(\.mediumColorHex)
            )

            SettingsDivider()

            visualThresholdRow(
                title: "settings.display.hot".localized,
                thresholdLabel: "settings.display.from".localized,
                value: hotLowerBinding,
                colorHex: colorHexBinding(\.hotColorHex)
            )
        }
    }

    /// Thresholds stay ordered with a visible middle band: the normal ceiling
    /// can never climb into the hot floor and vice versa.
    private var normalUpperBinding: Binding<Double> {
        Binding {
            settings.normalUpperCelsius
        } set: { value in
            guard value.isFinite else { return }
            settings.normalUpperCelsius = min(max(value.rounded(), 20), settings.hotLowerCelsius - 5)
        }
    }

    private var hotLowerBinding: Binding<Double> {
        Binding {
            settings.hotLowerCelsius
        } set: { value in
            guard value.isFinite else { return }
            settings.hotLowerCelsius = max(min(value.rounded(), 95), settings.normalUpperCelsius + 5)
        }
    }

    private func colorHexBinding(_ keyPath: ReferenceWritableKeyPath<AppSettingsStore, String>) -> Binding<String> {
        Binding {
            settings[keyPath: keyPath]
        } set: { hex in
            settings[keyPath: keyPath] = hex
        }
    }

    // These rows sit next to the 156pt sidebar, so their rigid widths must
    // stay under SettingsLayout.contentWidth − sidebar − card padding or the
    // whole settings window loses its margins (the tab ZStack adopts the
    // widest tab's minimum width).
    private func visualThresholdRow(
        title: String,
        thresholdLabel: String,
        value: Binding<Double>,
        colorHex: Binding<String>,
        unit: String = "°C"
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 72, alignment: .leading)

            Text(thresholdLabel)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
            Text(unit)
                .foregroundStyle(.secondary)

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    private func visualBandRow(title: String, rangeText: String, colorHex: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 72, alignment: .leading)

            Text(rangeText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Theme.Anim.smooth, value: rangeText)

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Menu bar modules

    private var modulesSurface: some View {
        SettingsSurface(icon: "menubar.rectangle", title: "settings.display.menubar_modules".localized) {
            simulatedPreviewCapsule {
                SimulatedModulesBarPreview(simulator: simulator, settings: settings)
            }

            SettingsDivider()

            stylePickerRow(
                title: "settings.display.modules.spacing".localized,
                caption: "settings.display.modules.spacing.caption".localized,
                options: ModuleSpacingLevel.allCases,
                label: \.localizedName,
                selection: $settings.moduleSpacing
            )

            SettingsDivider()

            SettingsRow(
                title: "settings.display.module_cpu".localized,
                subtitle: "settings.display.module_cpu.caption".localized,
                icon: "cpu",
                trailingWidth: 60
            ) {
                Toggle("", isOn: $settings.showsCPUModule)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(
                title: "settings.display.module_memory".localized,
                subtitle: "settings.display.module_memory.caption".localized,
                icon: "memorychip",
                trailingWidth: 60
            ) {
                Toggle("", isOn: $settings.showsMemoryModule)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(
                title: "settings.display.module_network".localized,
                subtitle: "settings.display.module_network.caption".localized,
                icon: "network",
                trailingWidth: 60
            ) {
                Toggle("", isOn: $settings.showsNetworkModule)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .animation(Theme.Anim.smooth, value: enabledModules)
    }

    private var enabledModules: [SystemModuleKind] {
        var modules: [SystemModuleKind] = []
        if settings.showsCPUModule { modules.append(.cpu) }
        if settings.showsMemoryModule { modules.append(.memory) }
        if settings.showsNetworkModule { modules.append(.network) }
        return modules
    }

    // MARK: - CPU / RAM / network charts

    private var cpuModuleSurface: some View {
        SettingsSurface(icon: "cpu", title: "settings.display.module_cpu".localized) {
            simulatedPreviewCapsule {
                SimulatedPercentModulePreview(simulator: simulator, settings: settings, metric: .cpu)
            }

            hiddenHint(isShown: settings.showsCPUModule)

            SettingsDivider()

            percentMetricRows(
                colorMode: $settings.cpuColorMode,
                graphWidth: $settings.cpuGraphWidth,
                normalUpper: \.cpuNormalUpperPercent,
                hotLower: \.cpuHotLowerPercent,
                normalHex: \.cpuNormalColorHex,
                mediumHex: \.cpuMediumColorHex,
                hotHex: \.cpuHotColorHex
            )
        }
        .animation(Theme.Anim.smooth, value: settings.cpuColorMode)
    }

    private var memoryModuleSurface: some View {
        SettingsSurface(icon: "memorychip", title: "settings.display.module_memory".localized) {
            simulatedPreviewCapsule {
                SimulatedPercentModulePreview(simulator: simulator, settings: settings, metric: .memory)
            }

            hiddenHint(isShown: settings.showsMemoryModule)

            SettingsDivider()

            percentMetricRows(
                colorMode: $settings.memoryColorMode,
                graphWidth: $settings.memoryGraphWidth,
                normalUpper: \.memoryNormalUpperPercent,
                hotLower: \.memoryHotLowerPercent,
                normalHex: \.memoryNormalColorHex,
                mediumHex: \.memoryMediumColorHex,
                hotHex: \.memoryHotColorHex
            )
        }
        .animation(Theme.Anim.smooth, value: settings.memoryColorMode)
    }

    private var networkModuleSurface: some View {
        SettingsSurface(icon: "network", title: "settings.display.module_network".localized) {
            simulatedPreviewCapsule {
                SimulatedNetworkModulePreview(simulator: simulator, settings: settings)
            }

            hiddenHint(isShown: settings.showsNetworkModule)

            SettingsDivider()

            networkMetricRows
        }
        .animation(Theme.Anim.smooth, value: settings.networkColorMode)
    }

    @ViewBuilder
    private func hiddenHint(isShown: Bool) -> some View {
        if !isShown {
            Label("settings.display.module.hidden_hint".localized, systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Color style first (with the band editor right under the preview so
    /// threshold drags read live), graph length last.
    @ViewBuilder
    private func percentMetricRows(
        colorMode: Binding<ModuleColorMode>,
        graphWidth: Binding<ModuleGraphWidth>,
        normalUpper: ReferenceWritableKeyPath<AppSettingsStore, Double>,
        hotLower: ReferenceWritableKeyPath<AppSettingsStore, Double>,
        normalHex: ReferenceWritableKeyPath<AppSettingsStore, String>,
        mediumHex: ReferenceWritableKeyPath<AppSettingsStore, String>,
        hotHex: ReferenceWritableKeyPath<AppSettingsStore, String>
    ) -> some View {
        stylePickerRow(
            title: "settings.display.modules.color".localized,
            caption: "settings.display.modules.color.caption".localized,
            options: ModuleColorMode.allCases,
            label: \.localizedName,
            selection: colorMode
        )

        if colorMode.wrappedValue == .load {
            SettingsDivider()

            let thresholds = percentThresholdBindings(normalUpper: normalUpper, hotLower: hotLower)
            loadBandsRows(
                normalUpper: thresholds.normalUpper,
                hotLower: thresholds.hotLower,
                normalHex: colorHexBinding(normalHex),
                mediumHex: colorHexBinding(mediumHex),
                hotHex: colorHexBinding(hotHex)
            )
        }

        SettingsDivider()

        stylePickerRow(
            title: "settings.display.modules.graph".localized,
            caption: "settings.display.modules.graph.caption".localized,
            options: ModuleGraphWidth.allCases,
            label: \.localizedName,
            selection: graphWidth
        )
    }

    @ViewBuilder
    private var networkMetricRows: some View {
        stylePickerRow(
            title: "settings.display.modules.color".localized,
            caption: "settings.display.modules.color.caption.network".localized,
            options: [.multicolor, .mono, .gray],
            label: \.localizedName,
            selection: $settings.networkColorMode
        )

        if settings.networkColorMode == .multicolor {
            SettingsDivider()

            networkColorRow(
                title: "settings.display.network.upload_color".localized,
                symbol: "arrow.up",
                colorHex: colorHexBinding(\.networkUpColorHex)
            )

            SettingsDivider()

            networkColorRow(
                title: "settings.display.network.download_color".localized,
                symbol: "arrow.down",
                colorHex: colorHexBinding(\.networkDownColorHex)
            )
        }
    }

    /// The customizable "By load" bands for one percent module: a 0-100%
    /// strip with draggable thresholds plus per-band rows. Usage bands read
    /// Low/Medium/High — "hot" only makes sense for temperature.
    @ViewBuilder
    private func loadBandsRows(
        normalUpper: Binding<Double>,
        hotLower: Binding<Double>,
        normalHex: Binding<String>,
        mediumHex: Binding<String>,
        hotHex: Binding<String>
    ) -> some View {
        Text("settings.display.load_bands.caption".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        BandsStripEditor(
            normalUpper: normalUpper,
            hotLower: hotLower,
            normalColor: Color(hexString: normalHex.wrappedValue),
            mediumColor: Color(hexString: mediumHex.wrappedValue),
            hotColor: Color(hexString: hotHex.wrappedValue),
            scale: 0...100,
            unitSuffix: "%"
        )
        .padding(.vertical, 4)

        visualThresholdRow(
            title: "settings.display.load.low".localized,
            thresholdLabel: "settings.display.up_to".localized,
            value: normalUpper,
            colorHex: normalHex,
            unit: "%"
        )

        SettingsDivider()

        visualBandRow(
            title: "settings.display.load.medium".localized,
            rangeText: "\(Int(normalUpper.wrappedValue.rounded()))-\(Int(hotLower.wrappedValue.rounded())) %",
            colorHex: mediumHex
        )

        SettingsDivider()

        visualThresholdRow(
            title: "settings.display.load.high".localized,
            thresholdLabel: "settings.display.from".localized,
            value: hotLower,
            colorHex: hotHex,
            unit: "%"
        )
    }

    /// Clamped, ordered bindings for one module's percent thresholds: the
    /// normal ceiling can never climb into the hot floor and vice versa.
    private func percentThresholdBindings(
        normalUpper: ReferenceWritableKeyPath<AppSettingsStore, Double>,
        hotLower: ReferenceWritableKeyPath<AppSettingsStore, Double>
    ) -> (normalUpper: Binding<Double>, hotLower: Binding<Double>) {
        (
            normalUpper: Binding {
                settings[keyPath: normalUpper]
            } set: { value in
                guard value.isFinite else { return }
                settings[keyPath: normalUpper] = min(max(value.rounded(), 5), settings[keyPath: hotLower] - 5)
            },
            hotLower: Binding {
                settings[keyPath: hotLower]
            } set: { value in
                guard value.isFinite else { return }
                settings[keyPath: hotLower] = max(min(value.rounded(), 100), settings[keyPath: normalUpper] + 5)
            }
        )
    }

    private func networkColorRow(title: String, symbol: String, colorHex: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    /// Dark capsule mock of the menu bar around simulated module content,
    /// with the simulated-data note underneath. Forcing the dark scheme keeps
    /// label-colored styles readable in light mode.
    private func simulatedPreviewCapsule<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Spacer(minLength: 0)
                content()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.82))
                    )
                    .environment(\.colorScheme, .dark)
                Spacer(minLength: 0)
            }

            Text("settings.display.preview.simulated".localized)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func stylePickerRow<Value: Hashable & Identifiable>(
        title: String,
        caption: String,
        options: [Value],
        label: KeyPath<Value, String>,
        selection: Binding<Value>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Simulated previews

/// One percent module (CPU or RAM) rendered exactly like the menu bar but fed
/// by the simulator, so color styles and thresholds show live transitions.
private struct SimulatedPercentModulePreview: View {
    @ObservedObject var simulator: ModulePreviewSimulator
    @ObservedObject var settings: AppSettingsStore
    let metric: PercentModuleStatusLabel.Metric

    var body: some View {
        PercentModuleSegment(
            title: metric == .cpu ? "system.cpu".localized : "system.memory".localized,
            percent: percent,
            history: history,
            color: color,
            graphWidth: graphWidth.width,
            tickSeconds: ModulePreviewSimulator.tickSeconds,
            animated: settings.performanceMode == .full
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

private struct SimulatedNetworkModulePreview: View {
    @ObservedObject var simulator: ModulePreviewSimulator
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        let tints = ModuleColorResolver.networkArrowTints(settings: settings)
        NetworkModuleSegment(
            upload: simulator.uploadBytesPerSecond,
            download: simulator.downloadBytesPerSecond,
            upTint: tints.up,
            downTint: tints.down,
            animated: settings.performanceMode == .full
        )
        .frame(height: 22)
    }
}

/// All enabled modules side by side with the chosen spacing, approximating
/// how the menu bar lays them out (Together fuses them with hairline gaps).
private struct SimulatedModulesBarPreview: View {
    @ObservedObject var simulator: ModulePreviewSimulator
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        let modules = enabledModules
        if modules.isEmpty {
            Label("settings.display.modules.none_hint".localized, systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } else {
            HStack(spacing: settings.moduleSpacing == .together ? 2 : 8) {
                ForEach(modules) { module in
                    segment(for: module)
                        .padding(.horizontal, settings.moduleSpacing.padding)
                }
            }
            .frame(height: 22)
            .animation(Theme.Anim.smooth, value: settings.moduleSpacing)
        }
    }

    private var enabledModules: [SystemModuleKind] {
        var modules: [SystemModuleKind] = []
        if settings.showsCPUModule { modules.append(.cpu) }
        if settings.showsMemoryModule { modules.append(.memory) }
        if settings.showsNetworkModule { modules.append(.network) }
        return modules
    }

    @ViewBuilder
    private func segment(for module: SystemModuleKind) -> some View {
        switch module {
        case .cpu:
            SimulatedPercentModulePreview(simulator: simulator, settings: settings, metric: .cpu)
        case .memory:
            SimulatedPercentModulePreview(simulator: simulator, settings: settings, metric: .memory)
        case .network:
            SimulatedNetworkModulePreview(simulator: simulator, settings: settings)
        }
    }
}

/// Faithful mock of the status item: the same renderer, icon size, and colors
/// the menu bar uses, spinning at the fan's real animation speed.
private struct MenuBarItemPreview: View {
    let temperatureText: String
    let color: Color
    let degreesPerSecond: Double
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: degreesPerSecond <= 0 || isPaused)) { timeline in
            let rotation =
                degreesPerSecond > 0
                ? (timeline.date.timeIntervalSinceReferenceDate * degreesPerSecond).truncatingRemainder(dividingBy: 360)
                : 0
            HStack(spacing: 4) {
                if let icon = FanIconRenderer.image(color: NSColor(color), rotation: rotation) {
                    Image(nsImage: icon)
                }
                Text(temperatureText)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .animation(Theme.Anim.smooth, value: temperatureText)
        .accessibilityLabel("settings.display.menubar_item".localized)
    }
}

/// Interactive band strip: three colored bands with two draggable handles on
/// the thresholds, over a configurable scale (30-90 °C for temperature,
/// 0-100 % for the load charts). Text fields next to it keep precise entry
/// available.
private struct BandsStripEditor: View {
    @Binding var normalUpper: Double
    @Binding var hotLower: Double

    let normalColor: Color
    let mediumColor: Color
    let hotColor: Color

    var scale: ClosedRange<Double> = 30...90
    var unitSuffix: String = "°"

    @State private var activeHandle: Handle?

    private enum Handle {
        case normal
        case hot
    }

    private let barHeight: CGFloat = 26
    private let handleSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        segment(normalColor)
                            .frame(width: position(of: normalUpper, in: width))
                        segment(mediumColor)
                            .frame(width: max(0, position(of: hotLower, in: width) - position(of: normalUpper, in: width)))
                        segment(hotColor)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    handle(.normal, value: normalUpper, width: width)
                    handle(.hot, value: hotLower, width: width)
                }
                .coordinateSpace(name: "temperature-bands")
                .animation(activeHandle == nil ? Theme.Anim.spring : nil, value: normalUpper)
                .animation(activeHandle == nil ? Theme.Anim.spring : nil, value: hotLower)
            }
            .frame(height: barHeight)

            HStack {
                Text("\(Int(scale.lowerBound))\(unitSuffix)")
                Spacer()
                Text("\(Int(scale.upperBound))\(unitSuffix)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    private func segment(_ color: Color) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private func handle(_ kind: Handle, value: Double, width: CGFloat) -> some View {
        let isDragging = activeHandle == kind
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: isDragging ? 3 : 1.5, y: 1)
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(0.75))
            }
            .frame(width: handleSize, height: handleSize)
            .scaleEffect(isDragging ? 1.18 : 1)
            .animation(Theme.Anim.hover, value: isDragging)
        }
        .position(x: position(of: value, in: width), y: barHeight / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("temperature-bands"))
                .onChanged { drag in
                    activeHandle = kind
                    let temperature = temperature(at: drag.location.x, in: width)
                    switch kind {
                    case .normal:
                        normalUpper = temperature
                    case .hot:
                        hotLower = temperature
                    }
                }
                .onEnded { _ in
                    activeHandle = nil
                }
        )
        .accessibilityLabel(
            kind == .normal
                ? "settings.display.normal".localized
                : "settings.display.hot".localized
        )
        .accessibilityValue("\(Int(value.rounded())) \(unitSuffix)")
    }

    private func position(of temperature: Double, in width: CGFloat) -> CGFloat {
        let clamped = min(max(temperature, scale.lowerBound), scale.upperBound)
        let fraction = (clamped - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
        return CGFloat(fraction) * width
    }

    private func temperature(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return scale.lowerBound }
        let fraction = Double(min(max(x / width, 0), 1))
        return (scale.lowerBound + fraction * (scale.upperBound - scale.lowerBound)).rounded()
    }
}
