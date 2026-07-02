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
            if showsHelperBanner {
                helperBanner
                    .transition(bannerTransition)
            }
            if model.controlContested {
                StatusBanner(
                    severity: .warning,
                    icon: "exclamationmark.triangle.fill",
                    message: "Fan RPM is not matching the requested target"
                )
                .transition(bannerTransition)
            }
            modeContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
            footer
                .padding(.top, 4)
        }
        .padding(20)
        .frame(width: PopoverLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        .animation(PopoverLayout.modeTransitionAnimation, value: settings.controlMode)
        .animation(PopoverLayout.modeTransitionAnimation, value: model.controlContested)
        .animation(PopoverLayout.modeTransitionAnimation, value: helperService.state)
    }

    private var bannerTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppFormatters.temperaturePrecise(monitor.snapshot.temperatureCelsius, unit: settings.temperatureUnit))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: monitor.snapshot.temperatureCelsius)
                    .frame(minWidth: 132, alignment: .leading)
                Spacer()
                Text(AppFormatters.rpm(headerRPM))
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: headerRPM)
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
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: model.manualDisplayPercent)
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
            HStack {
                Text("Curve target")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    "\(model.effectiveCurveTargetPercent.map(AppFormatters.percent) ?? "--") / \(AppFormatters.rpm(model.curveTargetRPM))"
                )
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: model.effectiveCurveTargetPercent)
            }
            .font(.callout)

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
        HStack(spacing: 10) {
            Button {
                model.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .padding(.horizontal, 2)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button {
                model.quit()
            } label: {
                Label("Exit", systemImage: "power")
                    .padding(.horizontal, 2)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)
        }
    }

    private var headerRPM: Double? {
        switch settings.controlMode {
        case .curve:
            return monitor.snapshot.fan?.currentRPM ?? monitor.snapshot.fan?.targetRPM ?? model.curveTargetRPM
        case .manual:
            return monitor.snapshot.fan?.currentRPM
        }
    }

    private var headerRPMLabel: String {
        settings.controlMode == .curve ? "Actual" : "Current"
    }

    private var showsHelperBanner: Bool {
        !helperService.isReady
    }

    private var helperBanner: some View {
        StatusBanner(
            severity: helperBannerSeverity,
            icon: helperBannerIcon,
            message: helperService.statusSummary,
            showsProgress: helperService.isRecovering || helperService.state == .unknown,
            actionTitle: helperBannerActionTitle,
            action: helperBannerActionTitle == nil ? nil : { model.authorizeHelper() }
        )
    }

    private var helperBannerSeverity: StatusBanner.Severity {
        switch helperService.state {
        case .failed:
            return .error
        case .stale, .unavailable:
            return .warning
        case .unknown, .ready, .reloading, .needsApproval, .needsAuthorization:
            return .info
        }
    }

    private var helperBannerIcon: String {
        switch helperService.state {
        case .needsApproval:
            return "person.badge.shield.checkmark"
        case .failed:
            return "exclamationmark.octagon"
        default:
            return "lock.shield"
        }
    }

    private var helperBannerActionTitle: String? {
        switch helperService.state {
        case .unknown, .ready, .reloading:
            return nil
        case .needsApproval:
            return "Approve"
        case .needsAuthorization:
            return "Authorize"
        case .stale, .unavailable, .failed:
            return "Fix"
        }
    }
}

struct StatusBanner: View {
    enum Severity {
        case info
        case warning
        case error

        var tint: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    let severity: Severity
    let icon: String
    let message: String
    var showsProgress = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
            }
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(severity.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .foregroundStyle(severity.tint)
    }
}
