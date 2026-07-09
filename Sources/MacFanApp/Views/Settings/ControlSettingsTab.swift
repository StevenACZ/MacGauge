import SwiftUI

struct ControlSettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var monitor: FanMonitor
    @ObservedObject var helperService: HelperCommandService

    /// False while another tab is selected so the live curve marker stops
    /// animating behind the hidden tab.
    let isActive: Bool

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "fanblades", title: "settings.control.title".localized) {
                SettingsRow(title: "settings.control.mode".localized) {
                    Picker("settings.control.default_mode".localized, selection: $settings.controlMode) {
                        ForEach(FanControlMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
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
                    helperService: helperService,
                    isActive: isActive
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
        SettingsSurface(icon: "slider.horizontal.3", title: "settings.control.manual_target".localized) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("settings.control.target".localized)
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
    let isActive: Bool

    var body: some View {
        SettingsSurface(icon: "point.3.connected.trianglepath.dotted", title: "settings.control.fan_curve".localized) {
            VStack(alignment: .leading, spacing: 12) {
                CurvePreview(
                    points: settings.curvePoints,
                    currentTemperature: monitor.snapshot.temperatureCelsius,
                    targetPercent: model.effectiveCurveTargetPercent,
                    percentRange: model.manualPercentRange,
                    isEditingEnabled: !model.isWriting,
                    animatesLiveMarker: isActive,
                    estimatedRPM: { model.rpmEquivalent(for: $0) },
                    currentRPM: monitor.snapshot.fan?.currentRPM,
                    updatePoint: { settings.updateCurvePoint($0) },
                    addPoint: { temperature, percent in
                        settings.addCurvePoint(temperatureCelsius: temperature, percent: percent)
                    },
                    deletePoint: { settings.removeCurvePoint(id: $0) },
                    canDeletePoints: settings.curvePoints.count > 2
                )
                .frame(height: 220)

                pointChips

                HStack(spacing: 10) {
                    Button {
                        settings.addCurvePoint()
                    } label: {
                        Label("settings.control.add_point".localized, systemImage: "plus")
                    }

                    Button("settings.control.reset".localized) {
                        settings.resetCurveDefaults()
                    }

                    Spacer()

                    Text("settings.control.curve_hint".localized)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .disabled(model.isWriting)
    }

    private var pointChips: some View {
        let sortedPoints = settings.curvePoints.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        return HStack(spacing: 6) {
            ForEach(sortedPoints) { point in
                CurvePointChip(
                    point: binding(for: point),
                    percentRange: model.manualPercentRange,
                    canRemove: settings.curvePoints.count > 2,
                    estimatedRPM: { model.rpmEquivalent(for: $0) },
                    remove: { settings.removeCurvePoint(id: point.id) }
                )
            }
            Spacer(minLength: 0)
        }
        .animation(Theme.Anim.content, value: settings.curvePoints.map(\.id))
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

/// Compact "45° · 30%" chip; click opens a popover with numeric editing and
/// delete. Complements direct chart manipulation for precise values.
private struct CurvePointChip: View {
    @Binding var point: CurvePoint

    let percentRange: ClosedRange<Double>
    let canRemove: Bool
    let estimatedRPM: (Double) -> Double?
    let remove: () -> Void

    @State private var isEditing = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            Text("\(Int(point.temperatureCelsius.rounded()))° · \(Int(point.percent.rounded()))%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .cardChrome(
                    radius: Theme.Layout.badgeRadius,
                    fill: isHovered || isEditing ? Theme.accent.opacity(0.16) : Theme.Layout.cardFill,
                    stroke: isHovered || isEditing ? Theme.accent.opacity(0.4) : Theme.Layout.cardStroke
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Layout.badgeRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Anim.easeOut) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(role: .destructive, action: remove) {
                Label("curve.delete_point".localized, systemImage: "trash")
            }
            .disabled(!canRemove)
        }
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            CurvePointEditor(
                point: $point,
                percentRange: percentRange,
                canRemove: canRemove,
                estimatedRPM: estimatedRPM,
                remove: {
                    isEditing = false
                    remove()
                }
            )
        }
    }
}

private struct CurvePointEditor: View {
    @Binding var point: CurvePoint

    let percentRange: ClosedRange<Double>
    let canRemove: Bool
    let estimatedRPM: (Double) -> Double?
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("settings.control.temperature".localized)
                    .frame(width: 92, alignment: .leading)
                TextField("", value: temperatureBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                Text("°C")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("settings.control.fan_speed".localized)
                    .frame(width: 92, alignment: .leading)
                TextField("", value: percentBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                Text("%")
                    .foregroundStyle(.secondary)
            }

            if let rpm = estimatedRPM(point.percent) {
                HStack(spacing: 8) {
                    Text("settings.control.estimated_rpm".localized)
                        .frame(width: 92, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(AppFormatters.approximateRPM(rpm))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Theme.Anim.value, value: Int(rpm.rounded()))
                }
                .font(.callout)
            }

            if canRemove {
                Divider()
                Button(role: .destructive, action: remove) {
                    Label("curve.delete_point".localized, systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(width: 210)
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { point.temperatureCelsius },
            set: { point.temperatureCelsius = min(max($0, 0), 100).rounded() }
        )
    }

    private var percentBinding: Binding<Double> {
        Binding(
            get: { point.percent },
            set: { point.percent = min(max($0, percentRange.lowerBound), percentRange.upperBound).rounded() }
        )
    }
}
