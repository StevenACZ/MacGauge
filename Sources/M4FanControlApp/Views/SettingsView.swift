import AppKit
import SwiftUI

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

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var loginManager: LaunchAtLoginManager
    @ObservedObject private var helperService: HelperCommandService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab

    init(model: AppModel, initialTab: SettingsTab = .general) {
        self.model = model
        _settings = ObservedObject(initialValue: model.settings)
        _loginManager = ObservedObject(initialValue: model.loginManager)
        _helperService = ObservedObject(initialValue: model.helperService)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            selectedTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .frame(width: 680, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Cerrar") {
                    closeSettingsWindow()
                }
            }
        }
        .tint(.blue)
    }

    private func closeSettingsWindow() {
        if let window = NSApp.keyWindow {
            window.close()
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .control:
            controlTab
        case .display:
            displayTab
        case .safety:
            safetyTab
        }
    }

    private var generalTab: some View {
        settingsPane {
            SettingsSurface(icon: "gearshape", title: "General") {
                SettingsRow(title: "Temperature") {
                    Picker("Temperature unit", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                SettingsDivider()

                SettingsRow(title: "Start at login") {
                    Toggle("", isOn: Binding(
                        get: { loginManager.isEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: "Restore on quit") {
                    Toggle("", isOn: $settings.restoreAutomaticOnQuit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var controlTab: some View {
        settingsPane {
            SettingsSurface(icon: "fanblades", title: "Control") {
                SettingsRow(title: "Mode") {
                    Picker("Default mode", selection: $settings.controlMode) {
                        ForEach(FanControlMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Text(controlModeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch settings.controlMode {
            case .monitor:
                monitorControlSection
            case .manual:
                manualControlSection
            case .curve:
                curveControlSection
            }
        }
    }

    private var controlModeSummary: String {
        switch settings.controlMode {
        case .monitor:
            return "Read-only mode. macOS keeps managing the fans automatically."
        case .manual:
            return "Manual mode applies one fixed fan target."
        case .curve:
            return "Curve mode adjusts the target from the temperature points below."
        }
    }

    private var monitorControlSection: some View {
        SettingsSurface(icon: "eye", title: "Monitor") {
            SettingsRow(title: "Current RPM") {
                Text(AppFormatters.rpm(model.monitor.snapshot.fan?.currentRPM))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            SettingsRow(title: "macOS target") {
                Text(AppFormatters.rpm(model.monitor.snapshot.fan?.targetRPM))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Text("Monitor keeps macOS automatic fan control active and only watches temperature, RPM, and helper status.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var manualControlSection: some View {
        SettingsSurface(icon: "slider.horizontal.3", title: "Manual Target") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Target")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(AppFormatters.percent(model.manualDisplayPercent)) / \(AppFormatters.approximateRPM(model.manualTargetRPM))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $settings.manualPercent, in: model.manualPercentRange, step: 1)
                    .disabled(!helperService.isReady || model.isWriting)

                Text(helperService.isReady ? "Manual changes apply after the slider settles." : "Authorize the helper in Safety before manual controls can write fan targets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var curveControlSection: some View {
        Group {
            SettingsSurface(icon: "point.3.connected.trianglepath.dotted", title: "Curve Points") {
                ForEach(Array($settings.curvePoints.enumerated()), id: \.element.id) { index, $point in
                    curvePointRow(point: $point)

                    if index < settings.curvePoints.count - 1 {
                        SettingsDivider()
                    }
                }

                SettingsDivider()

                HStack {
                    Button {
                        settings.addCurvePoint()
                    } label: {
                        Label("Add Point", systemImage: "plus")
                    }
                    .disabled(model.isWriting)

                    Button("Reset") {
                        settings.resetCurveDefaults()
                    }
                    .disabled(model.isWriting)

                    Spacer()

                    Stepper(value: $settings.curveRunMinutes, in: 1...120, step: 1) {
                        Text("\(Int(settings.curveRunMinutes.rounded())) min run")
                            .monospacedDigit()
                    }
                }
            }
            .disabled(model.isWriting)

            SettingsSurface(icon: "chart.line.uptrend.xyaxis", title: "Preview") {
                CurvePreview(
                    points: settings.curvePoints,
                    currentTemperature: model.monitor.snapshot.temperatureCelsius,
                    targetPercent: model.effectiveCurveTargetPercent,
                    percentRange: model.manualPercentRange
                )
                .frame(height: 120)

                Text(helperService.isReady ? "Curve points are clamped to the current safe manual range." : "Curve runs are locked until the helper is authorized in Safety.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayTab: some View {
        settingsPane {
            SettingsSurface(icon: "paintpalette", title: "Display") {
                SettingsRow(title: "Animate fan icon") {
                    Toggle("", isOn: $settings.animateFanIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                visualThresholdRow(
                    title: "Normal",
                    thresholdLabel: "Up to",
                    value: $settings.normalUpperCelsius,
                    colorHex: colorHexBinding(\.normalColorHex)
                )

                SettingsDivider()

                visualBandRow(
                    title: "Medium",
                    rangeText: "\(Int(settings.normalUpperCelsius.rounded()))-\(Int(settings.hotLowerCelsius.rounded())) C",
                    colorHex: colorHexBinding(\.mediumColorHex)
                )

                SettingsDivider()

                visualThresholdRow(
                    title: "Hot",
                    thresholdLabel: "From",
                    value: $settings.hotLowerCelsius,
                    colorHex: colorHexBinding(\.hotColorHex)
                )
            }
        }
    }

    private var safetyTab: some View {
        settingsPane {
            SettingsSurface(icon: "lock.shield", title: "Safety") {
                SettingsRow(title: "Unlock edge ranges") {
                    Toggle("", isOn: $settings.dangerousRangesUnlocked)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: "Privileged helper") {
                    HStack(spacing: 12) {
                        HelperStatusBadge(state: helperService.state)
                        if !helperService.isReady {
                            Button {
                                model.authorizeHelper()
                            } label: {
                                Label(authorizeButtonTitle, systemImage: authorizeButtonIcon)
                            }
                            .disabled(model.isWriting)
                        }
                    }
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("0 RPM and near-maximum targets can damage hardware or fight macOS thermal management.")
                    Text("The helper is a narrow SMAppService LaunchDaemon with an XPC Mach service. It does not store passwords.")
                    Text("macOS may require one explicit approval from this Safety action before controls are unlocked.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                SettingsDivider()

                HStack {
                    Button {
                        model.restoreAutomatic()
                    } label: {
                        Label("Restore Automatic Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!helperService.isReady || model.isWriting)

                    Spacer()

                    Text(model.lastActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .onAppear {
            model.refreshHelperState()
        }
    }

    private func settingsPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.vertical, 2)
        }
    }

    private var authorizeButtonTitle: String {
        helperService.state == .needsApproval ? "Open Settings" : "Authorize"
    }

    private var authorizeButtonIcon: String {
        helperService.state == .needsApproval ? "arrow.up.forward.app" : "lock.open"
    }

    private func colorHexBinding(_ keyPath: ReferenceWritableKeyPath<AppSettingsStore, String>) -> Binding<String> {
        Binding {
            settings[keyPath: keyPath]
        } set: { hex in
            settings[keyPath: keyPath] = hex
        }
    }

    private func curvePointRow(point: Binding<CurvePoint>) -> some View {
        HStack(spacing: 12) {
            TextField("Temp", value: boundedTemperatureBinding(point.temperatureCelsius), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
            Text("C")
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)

            Slider(value: boundedPercentBinding(point.percent), in: model.manualPercentRange, step: 1)

            Text(AppFormatters.percent(boundedPercent(point.wrappedValue.percent)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)

            Text(AppFormatters.approximateRPM(model.estimatedRPM(for: point.wrappedValue.percent)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 88, alignment: .trailing)

            Button {
                settings.removeCurvePoint(id: point.wrappedValue.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(settings.curvePoints.count > 2 ? Color.red : Color.secondary)
            .disabled(settings.curvePoints.count <= 2 || model.isWriting)
            .help(settings.curvePoints.count > 2 ? "Delete point" : "Keep at least two points")
        }
        .padding(.vertical, 2)
    }

    private func visualThresholdRow(
        title: String,
        thresholdLabel: String,
        value: Binding<Double>,
        colorHex: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 82, alignment: .leading)

            Text(thresholdLabel)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            Text("C")
                .foregroundStyle(.secondary)

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    private func visualBandRow(title: String, rangeText: String, colorHex: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 82, alignment: .leading)

            Text(rangeText)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    private func boundedPercentBinding(_ percent: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { boundedPercent(percent.wrappedValue) },
            set: { percent.wrappedValue = boundedPercent($0) }
        )
    }

    private func boundedTemperatureBinding(_ temperature: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { boundedTemperature(temperature.wrappedValue) },
            set: { temperature.wrappedValue = boundedTemperature($0) }
        )
    }

    private func boundedPercent(_ percent: Double) -> Double {
        min(max(percent, model.manualPercentRange.lowerBound), model.manualPercentRange.upperBound)
    }

    private func boundedTemperature(_ temperature: Double) -> Double {
        min(max(temperature, 0), 100)
    }
}

private struct SettingsSurface<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, alignment: .leading)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 24)
            content()
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.04))
    }
}

private struct CurvePreview: View {
    let points: [CurvePoint]
    let currentTemperature: Double?
    let targetPercent: Double?
    let percentRange: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let plotted = normalizedPoints(in: proxy.size)
            let marker = currentMarker(in: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))

                Path { path in
                    guard let first = plotted.first else { return }
                    path.move(to: first)
                    for point in plotted.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(.secondary, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                ForEach(Array(plotted.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.72), lineWidth: 1)
                        )
                        .position(point)
                }

                if let marker {
                    let labelPosition = currentLabelPosition(for: marker, in: proxy.size)

                    Path { path in
                        path.move(to: CGPoint(x: marker.x, y: 0))
                        path.addLine(to: CGPoint(x: marker.x, y: proxy.size.height))
                    }
                    .stroke(.blue, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))

                    Circle()
                        .fill(.blue)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.72), lineWidth: 1)
                        )
                        .position(marker)

                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.blue.opacity(0.14))
                        )
                        .position(labelPosition)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .accessibilityLabel("Curve preview")
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let sorted = points.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        guard let firstTemperature = sorted.first?.temperatureCelsius,
              let lastTemperature = sorted.last?.temperatureCelsius
        else {
            return []
        }

        let temperatureSpan = max(1, lastTemperature - firstTemperature)
        let percentSpan = max(1, percentRange.upperBound - percentRange.lowerBound)
        let plotRect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 10)
        return sorted.map { point in
            CGPoint(
                x: plotRect.minX + (point.temperatureCelsius - firstTemperature) / temperatureSpan * plotRect.width,
                y: plotRect.maxY - (clampPercent(point.percent) - percentRange.lowerBound) / percentSpan * plotRect.height
            )
        }
    }

    private func currentMarker(in size: CGSize) -> CGPoint? {
        guard let temperature = currentTemperature,
              let percent = targetPercent,
              let firstTemperature = points.map(\.temperatureCelsius).min(),
              let lastTemperature = points.map(\.temperatureCelsius).max()
        else {
            return nil
        }

        let temperatureSpan = max(1, lastTemperature - firstTemperature)
        let clampedTemperature = min(max(temperature, firstTemperature), lastTemperature)
        let percentSpan = max(1, percentRange.upperBound - percentRange.lowerBound)
        let plotRect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 10)
        return CGPoint(
            x: plotRect.minX + (clampedTemperature - firstTemperature) / temperatureSpan * plotRect.width,
            y: plotRect.maxY - (clampPercent(percent) - percentRange.lowerBound) / percentSpan * plotRect.height
        )
    }

    private func currentLabelPosition(for marker: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(marker.x + 38, 42), size.width - 42),
            y: 18
        )
    }

    private func clampPercent(_ percent: Double) -> Double {
        min(max(percent, percentRange.lowerBound), percentRange.upperBound)
    }
}

private struct ColorPresetPicker: View {
    @Binding var selection: String

    private let presets = [
        ColorPreset(name: "White", hex: "#FFFFFF"),
        ColorPreset(name: "Green", hex: "#30D158"),
        ColorPreset(name: "Yellow", hex: "#FFD60A"),
        ColorPreset(name: "Red", hex: "#FF453A")
    ]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(presets) { preset in
                Button {
                    selection = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hexString: preset.hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(borderColor(for: preset), lineWidth: selectionMatches(preset) ? 3 : 1)
                        )
                        .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
            }
        }
    }

    private func selectionMatches(_ preset: ColorPreset) -> Bool {
        selection.uppercased() == preset.hex
    }

    private func borderColor(for preset: ColorPreset) -> Color {
        if selectionMatches(preset) {
            return .accentColor
        }
        return preset.hex == "#FFFFFF" ? .secondary : .clear
    }
}

private struct ColorPreset: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}

private struct HelperStatusBadge: View {
    let state: HelperCommandService.HelperState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch state {
        case .ready:
            return "Authorized"
        case .needsApproval:
            return "Approval needed"
        case .needsAuthorization:
            return "Not authorized"
        case .unavailable:
            return "Unavailable"
        case .failed:
            return "Failed"
        case .unknown:
            return "Checking"
        }
    }

    private var color: Color {
        switch state {
        case .ready:
            return .green
        case .needsApproval:
            return .yellow
        case .needsAuthorization, .unknown:
            return .secondary
        case .unavailable, .failed:
            return .red
        }
    }
}
