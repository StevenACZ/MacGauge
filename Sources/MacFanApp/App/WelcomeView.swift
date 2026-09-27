import SwiftUI

enum WelcomeStep: Hashable {
    case fanControl
    case openAtLogin
    case done
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var helperService: HelperCommandService
    @ObservedObject var loginManager: LaunchAtLoginManager
    @ObservedObject var monitor: FanMonitor
    let steps: [WelcomeStep]
    let finish: () -> Void

    @State private var index = 0

    private var step: WelcomeStep {
        steps[min(index, steps.count - 1)]
    }

    private var isFirstRun: Bool {
        steps.contains(.done)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if steps.count > 1 {
                StepDots(count: steps.count, current: index)
            }
            Group {
                switch step {
                case .fanControl:
                    fanControlStep
                case .openAtLogin:
                    openAtLoginStep
                case .done:
                    doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
            .id(step)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 22)
        .frame(width: WelcomeWindowController.contentSize.width, height: WelcomeWindowController.contentSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .tint(Theme.accent)
        .onChange(of: helperService.state) { state in
            guard step == .fanControl, state == .ready else { return }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if step == .fanControl, steps.count > 1 { advance() }
            }
        }
        .onChange(of: monitor.snapshot.isFanless) { fanless in
            if fanless, step == .fanControl, steps.count > 1 { advance() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text((isFirstRun ? "welcome.title" : "welcome.fan.setup_title").localized)
                    .font(.system(size: 22, weight: .bold))
                Text((isFirstRun ? "welcome.subtitle" : "welcome.fan.setup_subtitle").localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Fan control

    private var fanControlStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeading(icon: "fanblades.fill", title: "welcome.fan.title", message: "welcome.fan.body")
            LoginItemsGuide(isWaiting: !helperService.isReady)
            fanStatus
                .frame(minHeight: 34, alignment: .topLeading)
                .animation(Theme.Anim.mode, value: helperService.state)
        }
    }

    @ViewBuilder
    private var fanStatus: some View {
        switch helperService.state {
        case .ready:
            Label("welcome.fan.ready".localized, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
        case .needsApproval:
            HStack(alignment: .top, spacing: 8) {
                ProgressView().controlSize(.small)
                Text("welcome.fan.waiting".localized(SystemSettingsLabels.backgroundActivity))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .unknown, .reloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("welcome.fan.working".localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .needsAuthorization:
            Text("welcome.fan.what_happens".localized(SystemSettingsLabels.backgroundActivity))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .stale, .unavailable, .failed:
            Label(helperService.statusSummary, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Open at login

    private var openAtLoginStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeading(icon: "power", title: "welcome.login.title", message: "welcome.login.body")
            LoginItemsGuide(section: .openAtLogin, isWaiting: !loginManager.isEnabled)
            if loginManager.isEnabled {
                Label("welcome.login.enabled".localized, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Anim.mode, value: loginManager.isEnabled)
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(icon: "checkmark.seal.fill", title: "welcome.done.title", message: "welcome.done.body")
            VStack(alignment: .leading, spacing: 12) {
                TipRow(icon: "fanblades", text: "welcome.done.fan")
                TipRow(icon: "chart.xyaxis.line", text: "welcome.done.modules")
                TipRow(icon: "command", text: "welcome.done.drag")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardChrome(radius: 14, fill: Theme.accent.opacity(0.08), stroke: Theme.accent.opacity(0.18))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let secondary = secondaryAction {
                Button(secondary.title.localized, action: secondary.run)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            Spacer(minLength: 0)
            Button(action: primaryAction.run) {
                Text(primaryAction.title.localized)
                    .font(.callout.weight(.semibold))
                    .frame(minWidth: 150)
            }
            .prominentActionStyle()
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(primaryAction.isDisabled)
        }
    }

    private struct Action {
        let title: String
        var isDisabled = false
        let run: () -> Void
    }

    private var primaryAction: Action {
        switch step {
        case .fanControl:
            switch helperService.state {
            case .ready:
                return Action(title: steps.count > 1 ? "welcome.continue" : "welcome.done_button", run: advance)
            case .needsApproval:
                return Action(title: "welcome.fan.open_settings", run: model.openLoginItemsSettings)
            case .unknown, .reloading:
                return Action(title: "welcome.fan.allow", isDisabled: true, run: {})
            case .needsAuthorization, .stale, .unavailable, .failed:
                return Action(title: "welcome.fan.allow", isDisabled: model.isWriting, run: model.authorizeHelper)
            }
        case .openAtLogin:
            if loginManager.isEnabled {
                return Action(title: "welcome.continue", run: advance)
            }
            return Action(title: "welcome.login.enable") {
                model.setLaunchAtLogin(true)
                if loginManager.isEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { advance() }
                }
            }
        case .done:
            return Action(title: "welcome.start", run: finish)
        }
    }

    private var secondaryAction: Action? {
        switch step {
        case .fanControl:
            guard !helperService.isReady else { return nil }
            return Action(title: steps.count > 1 ? "welcome.skip" : "welcome.close", run: advance)
        case .openAtLogin:
            guard !loginManager.isEnabled else { return nil }
            return Action(title: "welcome.not_now", run: advance)
        case .done:
            return nil
        }
    }

    private func advance() {
        guard index + 1 < steps.count else {
            finish()
            return
        }
        withAnimation(Theme.Anim.content) {
            index += 1
        }
    }
}

private struct StepHeading: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.localized)
                    .font(.headline)
                Text(message.localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(text.localized)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.accent : Color.primary.opacity(0.15))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.Anim.content, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("welcome.step_count".localized(current + 1, count))
    }
}
