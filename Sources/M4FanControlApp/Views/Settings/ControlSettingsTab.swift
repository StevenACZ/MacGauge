import SwiftUI

struct ControlSettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var helperService: HelperCommandService

    var body: some View {
        SettingsPane {
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
                MonitorControlSection(monitor: monitor)
            case .manual:
                ManualControlSection(
                    model: model,
                    settings: settings,
                    helperService: helperService
                )
            case .curve:
                CurveControlSection(
                    model: model,
                    settings: settings,
                    monitor: monitor,
                    helperService: helperService
                )
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
}

private struct MonitorControlSection: View {
    @ObservedObject var monitor: FanMonitor

    var body: some View {
        SettingsSurface(icon: "eye", title: "Monitor") {
            SettingsRow(title: "Current RPM") {
                Text(AppFormatters.rpm(monitor.snapshot.fan?.currentRPM))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            SettingsRow(title: "macOS target") {
                Text(AppFormatters.rpm(monitor.snapshot.fan?.targetRPM))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            SettingsDivider()

            Text("Monitor keeps macOS automatic fan control active and only watches temperature, RPM, and helper status.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ManualControlSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var helperService: HelperCommandService

    var body: some View {
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
}

private struct CurveControlSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var helperService: HelperCommandService

    var body: some View {
        Group {
            SettingsSurface(icon: "point.3.connected.trianglepath.dotted", title: "Curve Points") {
                ForEach(Array($settings.curvePoints.enumerated()), id: \.element.id) { index, $point in
                    CurvePointRow(
                        point: $point,
                        manualPercentRange: model.manualPercentRange,
                        estimatedRPM: model.estimatedRPM,
                        canRemove: settings.curvePoints.count > 2,
                        isWriting: model.isWriting,
                        remove: {
                            settings.removeCurvePoint(id: point.id)
                        }
                    )

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
                    currentTemperature: monitor.snapshot.temperatureCelsius,
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
}

private struct CurvePointRow: View {
    @Binding var point: CurvePoint

    let manualPercentRange: ClosedRange<Double>
    let estimatedRPM: (Double) -> Double?
    let canRemove: Bool
    let isWriting: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Temp", value: boundedTemperatureBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
            Text("C")
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)

            Slider(value: boundedPercentBinding, in: manualPercentRange, step: 1)

            Text(AppFormatters.percent(boundedPercent(point.percent)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)

            Text(AppFormatters.approximateRPM(estimatedRPM(point.percent)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 88, alignment: .trailing)

            Button {
                remove()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canRemove ? Color.red : Color.secondary)
            .disabled(!canRemove || isWriting)
            .help(canRemove ? "Delete point" : "Keep at least two points")
        }
        .padding(.vertical, 2)
    }

    private var boundedPercentBinding: Binding<Double> {
        Binding(
            get: { boundedPercent(point.percent) },
            set: { point.percent = boundedPercent($0) }
        )
    }

    private var boundedTemperatureBinding: Binding<Double> {
        Binding(
            get: { boundedTemperature(point.temperatureCelsius) },
            set: { point.temperatureCelsius = boundedTemperature($0) }
        )
    }

    private func boundedPercent(_ percent: Double) -> Double {
        min(max(percent, manualPercentRange.lowerBound), manualPercentRange.upperBound)
    }

    private func boundedTemperature(_ temperature: Double) -> Double {
        min(max(temperature, 0), 100)
    }
}
