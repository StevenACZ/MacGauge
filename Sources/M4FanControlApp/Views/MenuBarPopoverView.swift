import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var monitor: FanMonitor
    @ObservedObject private var helperService: HelperCommandService

    init(model: AppModel) {
        self.model = model
        _settings = ObservedObject(initialValue: model.settings)
        _monitor = ObservedObject(initialValue: model.monitor)
        _helperService = ObservedObject(initialValue: model.helperService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            modePicker
            modeContent
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppFormatters.temperaturePrecise(monitor.snapshot.temperatureCelsius, unit: settings.temperatureUnit))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                Text(AppFormatters.rpm(monitor.snapshot.fan?.currentRPM))
                    .font(.system(.title3, design: .rounded, weight: .medium))
            }

            HStack {
                Text(monitor.snapshot.chip)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Current")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if let error = monitor.snapshot.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $settings.controlMode) {
            ForEach(FanControlMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch settings.controlMode {
        case .manual:
            manualContent
        case .curve:
            curveContent
        }
    }

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Target")
                Spacer()
                Text("\(AppFormatters.percent(model.manualDisplayPercent)) / \(AppFormatters.rpm(model.manualTargetRPM))")
                    .foregroundStyle(.secondary)
            }

            Slider(value: $settings.manualPercent, in: model.manualPercentRange, step: 1)
                .opacity(model.isManualControlActive ? 1 : 0.58)
                .disabled(!helperService.isReady || model.isWriting)

            if !helperService.isReady {
                helperNotice
            }

            HStack {
                Button {
                    model.restoreAutomatic()
                } label: {
                    Label("Auto", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!helperService.isReady || model.isWriting)

                Spacer()

                Text(manualStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var curveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricRow("Curve target", value: "\(model.effectiveCurveTargetPercent.map(AppFormatters.percent) ?? "--") / \(AppFormatters.rpm(model.curveTargetRPM))")
            metricRow("Status", value: curveStatusText)

            if !helperService.isReady {
                helperNotice
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.lastActionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button {
                    model.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Spacer()

                Button {
                    model.quit()
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }

    private var helperNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text(model.helperStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Settings") {
                model.openSettings(tab: .safety)
            }
            .controlSize(.small)
        }
    }

    private var manualStatusText: String {
        if !helperService.isReady { return "Locked" }
        if model.isApplyingFanTarget { return "Applying..." }
        return model.isManualControlActive ? "Auto-apply" : "Automatic"
    }

    private var curveStatusText: String {
        if !helperService.isReady { return "Locked" }
        if model.isApplyingFanTarget { return "Applying..." }
        return "Running"
    }
}
