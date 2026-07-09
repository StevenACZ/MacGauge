import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var monitor: FanMonitor
    @ObservedObject private var helperService: HelperCommandService
    @ObservedObject private var localization = LocalizationManager.shared

    init(model: AppModel) {
        self.model = model
        _settings = ObservedObject(initialValue: model.settings)
        _monitor = ObservedObject(initialValue: model.monitor)
        _helperService = ObservedObject(initialValue: model.helperService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            identityHeader
            metrics
            Divider()
            if monitor.snapshot.isFanless {
                fanlessNotice
            } else {
                controlBar
                if showsHelperBanner {
                    helperBanner
                        .transition(bannerTransition)
                }
                if model.controlContested {
                    StatusBanner(
                        severity: .warning,
                        icon: "exclamationmark.triangle.fill",
                        message: "banner.contested".localized
                    )
                    .transition(bannerTransition)
                }
                modeContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Theme.Layout.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .animation(Theme.Anim.mode, value: settings.controlMode)
        .animation(Theme.Anim.mode, value: model.controlContested)
        .animation(Theme.Anim.mode, value: helperService.state)
        .animation(Theme.Anim.mode, value: monitor.snapshot.isFanless)
        .id(localization.language)
    }

    private var bannerTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    private var identityHeader: some View {
        HStack(spacing: 10) {
            TintedIconCircle(icon: "fan.fill", tint: temperatureTint, size: 32, iconSize: 15)

            VStack(alignment: .leading, spacing: 1) {
                Text("MacGauge")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppFormatters.temperaturePrecise(monitor.snapshot.temperatureCelsius, unit: settings.temperatureUnit))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.value, value: monitor.snapshot.temperatureCelsius)
                    .frame(minWidth: 132, alignment: .leading)
                Spacer()
                if !monitor.snapshot.isFanless {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(AppFormatters.rpm(headerRPM))
                            .font(.system(.title3, design: .rounded, weight: .medium))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(Theme.Anim.value, value: headerRPM)
                        Text(headerRPMLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if monitor.snapshot.fanCount > 1 {
                HStack(spacing: 6) {
                    ForEach(monitor.snapshot.fans, id: \.index) { fan in
                        FanRPMChip(fan: fan)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var fanlessNotice: some View {
        StatusBanner(
            severity: .info,
            icon: "leaf.fill",
            message: "banner.fanless".localized
        )
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Picker("popover.mode".localized, selection: $settings.controlMode) {
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
                    Label("popover.auto".localized, systemImage: "arrow.triangle.2.circlepath")
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
                Text("popover.target".localized)
                Spacer()
                Text("\(AppFormatters.percent(model.manualDisplayPercent)) / \(AppFormatters.rpm(model.manualTargetRPM))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.value, value: model.manualDisplayPercent)
            }

            ManualPercentSlider(
                value: $settings.manualPercent,
                range: model.manualPercentRange,
                step: 1,
                isDisabled: !helperService.isReady || model.isWriting
            )
            .opacity(model.isManualControlActive ? 1 : 0.58)
            .animation(Theme.Anim.easeOut, value: model.isManualControlActive)
        }
    }

    private var curveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("popover.curve_target".localized)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    "\(model.effectiveCurveTargetPercent.map(AppFormatters.percent) ?? "--") / \(AppFormatters.rpm(model.curveTargetRPM))"
                )
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Theme.Anim.value, value: model.effectiveCurveTargetPercent)
            }
            .font(.callout)

            CurvePreview(
                points: settings.curvePoints,
                currentTemperature: monitor.snapshot.temperatureCelsius,
                targetPercent: model.effectiveCurveTargetPercent,
                percentRange: model.manualPercentRange,
                isEditingEnabled: false,
                animatesLiveMarker: true,
                estimatedRPM: { model.rpmEquivalent(for: $0) },
                currentRPM: monitor.snapshot.fan?.currentRPM,
                updatePoint: { _ in }
            )
            .frame(height: 168)
            .clipped()
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            ActionRow(icon: "gearshape", title: "popover.settings".localized) {
                model.openSettings()
            }
            ActionRow(icon: "power", title: "popover.quit".localized, isDestructive: true) {
                model.quit()
            }
        }
    }

    private var subtitle: String {
        let chip = monitor.snapshot.chip
        if monitor.snapshot.isFanless {
            return chip
        }
        let count = monitor.snapshot.fanCount
        guard count > 0 else { return chip }
        return count == 1
            ? "popover.subtitle.one_fan".localized(chip)
            : "popover.subtitle.fans".localized(chip, count)
    }

    private var temperatureTint: Color {
        switch settings.visualRules.band(for: monitor.snapshot.temperatureCelsius) {
        case .normal:
            return Theme.accent
        case .medium:
            return .orange
        case .hot:
            return .red
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
        settings.controlMode == .curve ? "popover.rpm.actual".localized : "popover.rpm.current".localized
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
            return "banner.action.approve".localized
        case .needsAuthorization:
            return "banner.action.authorize".localized
        case .stale, .unavailable, .failed:
            return "banner.action.fix".localized
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
                .lineLimit(3)
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
        .cardChrome(
            radius: Theme.Layout.rowRadius + 1,
            fill: severity.tint.opacity(0.12),
            stroke: severity.tint.opacity(0.18)
        )
        .foregroundStyle(severity.tint)
    }
}
