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
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(width: PopoverLayout.width, height: popoverHeight, alignment: .topLeading)
        .animation(PopoverLayout.modeTransitionAnimation, value: settings.controlMode)
    }

    private var popoverHeight: CGFloat {
        PopoverLayout.height(for: settings.controlMode)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppFormatters.temperaturePrecise(monitor.snapshot.temperatureCelsius, unit: settings.temperatureUnit))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 132, alignment: .leading)
                Spacer()
                Text(AppFormatters.rpm(headerRPM))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 96, alignment: .trailing)
            }

            HStack {
                Text(monitor.snapshot.chip)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(headerRPMLabel)
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
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .curve:
            curveContent
                .transition(.opacity.combined(with: .move(edge: .top)))
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

            CurvePreview(
                points: settings.curvePoints,
                currentTemperature: monitor.snapshot.temperatureCelsius,
                targetPercent: model.effectiveCurveTargetPercent,
                percentRange: model.manualPercentRange,
                isEditingEnabled: false,
                animatesLiveMarker: true,
                updatePoint: { _ in }
            )
            .frame(height: 168)
            .clipped()

            if !helperService.isReady {
                helperNotice
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = footerMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 12) {
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

    private var headerRPM: Double? {
        switch settings.controlMode {
        case .curve:
            return model.curveTargetRPM ?? monitor.snapshot.fan?.targetRPM ?? monitor.snapshot.fan?.currentRPM
        case .manual:
            return monitor.snapshot.fan?.currentRPM
        }
    }

    private var headerRPMLabel: String {
        settings.controlMode == .curve ? "Target" : "Current"
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

    private var footerMessage: String? {
        if isActionableError(model.lastActionMessage) { return model.lastActionMessage }
        return nil
    }

    private func isActionableError(_ message: String) -> Bool {
        let ignored = [
            "Ready",
            "Curve running",
            "Curve target applied",
            "Manual target applied",
            "Applying...",
            "Apply queued",
            "Applying after slider settles..."
        ]
        guard !ignored.contains(message) else { return false }
        guard !isHelperReadinessMessage(message) else { return false }
        if message.hasPrefix("Set fan ") { return false }
        return true
    }

    private func isHelperReadinessMessage(_ message: String) -> Bool {
        message == model.helperStatusSummary
            || message.contains("Settings > Safety")
            || message.hasPrefix("Authorize helper")
            || message.hasPrefix("Helper authorized")
    }
}
