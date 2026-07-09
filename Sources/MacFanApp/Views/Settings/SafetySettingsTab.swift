import SwiftUI

struct SafetySettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var helperService: HelperCommandService

    /// False while another tab is selected so decorative motion stops and the
    /// helper state refreshes on every return to this tab.
    let isActive: Bool

    var body: some View {
        SettingsPane {
            helperSurface
            rangesSurface
            restoreSurface
        }
        .onAppear {
            model.refreshHelperState()
        }
        .onChange(of: isActive) { active in
            if active {
                model.refreshHelperState()
            }
        }
    }

    // MARK: - Privileged helper

    private var helperSurface: some View {
        SettingsSurface(icon: "lock.shield", title: "settings.safety.privileged_helper".localized) {
            Text("settings.safety.helper.explainer".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HelperStatusCard(
                state: helperService.state,
                detail: helperDetail,
                isBusy: helperService.isRecovering || helperService.state == .unknown,
                actionTitle: actionTitle,
                actionIcon: actionIcon,
                actionDisabled: model.isWriting,
                action: { model.authorizeHelper() }
            )

            if let currentStep = setupStepIndex {
                HelperSetupSteps(currentStep: currentStep, isActive: isActive)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Anim.mode, value: helperService.state)
    }

    private var helperDetail: String {
        helperService.isReady
            ? "settings.safety.helper.ready_detail".localized
            : helperService.statusSummary
    }

    /// Position in the authorize → approve → ready flow, or nil once the
    /// helper is ready or when it is degraded (the status card handles that).
    private var setupStepIndex: Int? {
        switch helperService.state {
        case .unknown, .needsAuthorization, .reloading:
            return 0
        case .needsApproval:
            return 1
        case .ready, .stale, .unavailable, .failed:
            return nil
        }
    }

    private var actionTitle: String? {
        switch helperService.state {
        case .ready, .reloading, .unknown:
            return nil
        case .needsApproval:
            return "settings.safety.open_settings".localized
        case .stale, .unavailable, .failed:
            return "settings.safety.fix_helper".localized
        case .needsAuthorization:
            return "settings.safety.authorize".localized
        }
    }

    private var actionIcon: String {
        switch helperService.state {
        case .needsApproval:
            return "arrow.up.forward.app"
        case .stale, .unavailable, .failed:
            return "arrow.clockwise"
        default:
            return "lock.open"
        }
    }

    // MARK: - Extreme ranges

    private var rangesSurface: some View {
        SettingsSurface(icon: "speedometer", title: "settings.safety.ranges.title".localized) {
            SettingsToggleRow(
                title: "settings.safety.unlock_ranges".localized,
                subtitle: rangesCaption,
                isOn: $settings.dangerousRangesUnlocked
            )

            SettingsDivider()

            HStack(spacing: 8) {
                Text("settings.safety.ranges.current".localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                if settings.dangerousRangesUnlocked {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .transition(.scale.combined(with: .opacity))
                }

                Text(currentRangeText)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(settings.dangerousRangesUnlocked ? .orange : Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.badgeRadius, style: .continuous)
                            .fill((settings.dangerousRangesUnlocked ? Color.orange : Theme.accent).opacity(0.12))
                    )
            }
            .animation(Theme.Anim.spring, value: settings.dangerousRangesUnlocked)
        }
    }

    private var rangesCaption: String {
        settings.dangerousRangesUnlocked
            ? "settings.safety.ranges.unlocked_caption".localized
            : "settings.safety.ranges.locked_caption".localized
    }

    private var currentRangeText: String {
        let range = model.manualPercentRange
        return "\(Int(range.lowerBound.rounded()))% – \(Int(range.upperBound.rounded()))%"
    }

    // MARK: - Return control to macOS

    private var restoreSurface: some View {
        SettingsSurface(icon: "arrow.triangle.2.circlepath", title: "settings.safety.restore.title".localized) {
            Text("settings.safety.restore.caption".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    model.restoreAutomatic()
                } label: {
                    Label("settings.safety.restore_automatic".localized, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!helperService.isReady || model.isWriting)

                Spacer()
            }
        }
    }
}

/// One glanceable card: state icon, human title and detail, and the single
/// action that moves the helper forward when one exists.
private struct HelperStatusCard: View {
    let state: HelperCommandService.HelperState
    let detail: String
    let isBusy: Bool
    let actionTitle: String?
    let actionIcon: String
    let actionDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TintedIconCircle(icon: state.symbolName, tint: state.tint, size: 36, iconSize: 16, isBusy: isBusy)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.localizedTitle)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let actionTitle {
                Button {
                    action()
                } label: {
                    Label(actionTitle, systemImage: actionIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(actionDisabled)
            }
        }
        .padding(12)
        .cardChrome(
            radius: Theme.Layout.cardRadius,
            fill: state.tint.opacity(0.06),
            stroke: state.tint.opacity(0.18)
        )
    }
}

/// Authorize → approve → ready progress row shown while the helper still
/// needs the user; completed steps get a check, the current one pulses.
private struct HelperSetupSteps: View {
    let currentStep: Int
    let isActive: Bool

    private var steps: [String] {
        [
            "settings.safety.step.authorize".localized,
            "settings.safety.step.approve".localized,
            "settings.safety.step.ready".localized,
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Rectangle()
                        .fill(index <= currentStep ? Theme.accent.opacity(0.5) : Color.primary.opacity(0.12))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 16)
                }
                step(index: index, title: title)
            }
        }
        .padding(.top, 2)
    }

    private func step(index: Int, title: String) -> some View {
        let isDone = index < currentStep
        let isCurrent = index == currentStep
        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(isDone || isCurrent ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.06))
                if isCurrent {
                    PulsingRing(isActive: isActive)
                }
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                }
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.caption2)
                .foregroundStyle(isDone || isCurrent ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 116)
    }
}

private struct PulsingRing: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Theme.accent.opacity(expanded ? 0 : 0.55), lineWidth: 2)
            .scaleEffect(expanded ? 1.65 : 1)
            .onAppear { updatePulse() }
            .onChange(of: isActive) { _ in updatePulse() }
            .onChange(of: reduceMotion) { _ in updatePulse() }
            .accessibilityHidden(true)
    }

    /// Runs the pulse only while the tab is visible (restarting on return)
    /// and never under Reduce Motion.
    private func updatePulse() {
        withAnimation(nil) {
            expanded = false
        }
        guard isActive, !reduceMotion else { return }
        withAnimation(Theme.Anim.pulse.repeatForever(autoreverses: false)) {
            expanded = true
        }
    }
}
