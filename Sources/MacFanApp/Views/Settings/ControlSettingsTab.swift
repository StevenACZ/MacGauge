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
                }

                SettingsDivider()

                SettingsRow(title: "Update tick") {
                    Stepper(value: $settings.controlTickSeconds, in: AppSettingsStore.controlTickRange, step: 0.5) {
                        Text(AppFormatters.seconds(settings.controlTickSeconds))
                            .monospacedDigit()
                    }
                }
            }

            switch settings.controlMode {
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
                let sortedPoints = settings.curvePoints.sorted { $0.temperatureCelsius < $1.temperatureCelsius }

                ForEach(Array(sortedPoints.enumerated()), id: \.element.id) { index, point in
                    CurvePointRow(
                        point: binding(for: point),
                        manualPercentRange: model.manualPercentRange,
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
                }
            }
            .disabled(model.isWriting)

            SettingsSurface(icon: "chart.line.uptrend.xyaxis", title: "Preview") {
                CurvePreview(
                    points: settings.curvePoints,
                    currentTemperature: monitor.snapshot.temperatureCelsius,
                    targetPercent: model.effectiveCurveTargetPercent,
                    percentRange: model.manualPercentRange,
                    isEditingEnabled: !model.isWriting,
                    updatePoint: { settings.updateCurvePoint($0) }
                )
                .frame(height: 168)
            }
        }
    }

    private func binding(for point: CurvePoint) -> Binding<CurvePoint> {
        Binding(
            get: {
                settings.curvePoints.first { $0.id == point.id } ?? point
            },
            set: { updatedPoint in
                settings.updateCurvePoint(updatedPoint)
            }
        )
    }
}

private struct CurvePointRow: View {
    @Binding var point: CurvePoint

    let manualPercentRange: ClosedRange<Double>
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
            .accessibilityLabel("Delete curve point")
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
