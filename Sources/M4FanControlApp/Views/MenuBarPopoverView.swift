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
            controlBar
            modeContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 37)
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
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: $settings.controlMode) {
                ForEach(FanControlMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer(minLength: 0)

            if settings.controlMode == .manual {
                Button {
                    model.restoreAutomatic()
                } label: {
                    Label("Auto", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!helperService.isReady || model.isWriting)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            ManualPercentSlider(
                value: $settings.manualPercent,
                range: model.manualPercentRange,
                step: 1,
                isDisabled: !helperService.isReady || model.isWriting
            )
            .opacity(model.isManualControlActive ? 1 : 0.58)
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
        }
    }

    private var footer: some View {
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
                Label("Exit", systemImage: "power")
            }
            .foregroundStyle(.red)
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
}
