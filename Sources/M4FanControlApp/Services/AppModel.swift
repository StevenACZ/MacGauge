import AppKit
import Combine
import Foundation
import M4FanCore

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettingsStore
    let monitor: FanMonitor
    let loginManager: LaunchAtLoginManager
    let helperService: HelperCommandService

    @Published var isWriting = false
    @Published var isApplyingFanTarget = false
    @Published var lastActionMessage = "Ready"
    @Published var isManualControlActive = false

    var presentSettings: ((SettingsTab) -> Void)?

    private let debounceWindow = DebounceWindow(delay: 0.55)
    private let targetRules = FanTargetRules()
    private var cancellables = Set<AnyCancellable>()
    private var manualApplyTask: Task<Void, Never>?
    private var curveTask: Task<Void, Never>?
    private var curveRunID: UUID?
    private var helperApprovalPollTask: Task<Void, Never>?
    private var pendingFanTargetApply: (percent: Double, message: String)?
    private var didRunLiveControl = false
    private var suppressManualApply = false
    private var pendingModeActivationAfterHelperReady = false

    init() {
        settings = AppSettingsStore()
        monitor = FanMonitor()
        loginManager = LaunchAtLoginManager()
        helperService = HelperCommandService()
        bindManualSlider()
        bindControlMode()
        bindHelperReadiness()
        bindControlTick()
    }

    var manualTargetRPM: Double? {
        targetRPM(percent: manualDisplayPercent)
    }

    var manualDisplayPercent: Double {
        boundedManualPercent(settings.manualPercent)
    }

    var minimumFanPercent: Double {
        guard let fan = monitor.snapshot.fan,
              let minRPM = fan.minRPM,
              let maxRPM = fan.maxRPM,
              maxRPM > 0
        else {
            return settings.dangerousRangesUnlocked ? 0 : 20
        }
        return max(settings.dangerousRangesUnlocked ? 0 : 20, min(100, minRPM / maxRPM * 100))
    }

    var manualPercentRange: ClosedRange<Double> {
        let lower = minimumFanPercent
        let upper = min(100, max(lower, settings.dangerousRangesUnlocked ? 100 : 90))
        return lower...upper
    }

    var curveTargetPercent: Double? {
        curveTargetPercent(for: monitor.snapshot.temperatureCelsius)
    }

    var effectiveCurveTargetPercent: Double? {
        guard let percent = curveTargetPercent else { return nil }
        return boundedManualPercent(percent)
    }

    var curveTargetRPM: Double? {
        guard let percent = effectiveCurveTargetPercent else { return nil }
        return targetRPM(percent: percent)
    }

    var helperReady: Bool {
        helperService.isReady
    }

    var helperStatusSummary: String {
        helperService.statusSummary
    }

    func start() {
        monitor.start(refreshIntervalSeconds: settings.controlTickSeconds)
        Task { await helperService.refreshState() }
    }

    func authorizeHelper() {
        isWriting = true
        lastActionMessage = "Registering helper..."
        helperApprovalPollTask?.cancel()
        Task {
            do {
                try await helperService.authorizeHelper()
                let cleanupMessage = try await helperService.removeLegacyHelper()
                lastActionMessage = cleanupMessage == "No legacy helper found."
                    ? "Helper authorized"
                    : "Helper authorized. \(cleanupMessage)"
                helperApprovalPollTask?.cancel()
                activatePendingModeIfNeeded()
            } catch {
                lastActionMessage = error.localizedDescription
                if helperService.state == .needsApproval || helperService.state == .unavailable {
                    beginHelperApprovalPolling()
                }
            }
            isWriting = false
        }
    }

    func refreshHelperState() {
        Task { await helperService.refreshState() }
    }

    func applyManualPercentNow() {
        guard helperReady else {
            lastActionMessage = helperStatusSummary
            return
        }
        let percent = manualDisplayPercent
        isManualControlActive = true
        applyManualPercent(percent: percent, message: "Manual target applied")
    }

    func restoreAutomatic() {
        guard helperReady else {
            lastActionMessage = helperStatusSummary
            return
        }
        stopCurveRun(message: nil)
        pendingFanTargetApply = nil
        isWriting = true
        lastActionMessage = "Restoring automatic..."
        Task {
            do {
                lastActionMessage = try await helperService.restoreAutomatic()
                didRunLiveControl = false
                monitor.refresh()
                resetManualSliderToAutomatic()
            } catch {
                lastActionMessage = error.localizedDescription
            }
            isWriting = false
        }
    }

    func startCurveRun() {
        if curveTask != nil {
            return
        }

        guard helperReady else {
            lastActionMessage = helperStatusSummary
            return
        }

        let runID = UUID()
        curveRunID = runID
        lastActionMessage = "Curve running"
        curveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await self.monitor.refreshNow()
                if !self.isWriting,
                   let percent = self.effectiveCurveTargetPercent(for: snapshot.temperatureCelsius) {
                    self.applyManualPercent(percent: percent, message: "Curve target applied")
                }
                try? await Task.sleep(nanoseconds: self.controlTickNanoseconds)
            }
            await MainActor.run {
                guard self?.curveRunID == runID else { return }
                self?.curveTask = nil
                self?.curveRunID = nil
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginManager.setEnabled(enabled)
            lastActionMessage = enabled ? "Start at login enabled" : "Start at login disabled"
        } catch {
            loginManager.refresh()
            lastActionMessage = "Login item failed: \(error.localizedDescription)"
        }
    }

    func openSettings(tab: SettingsTab = .general) {
        presentSettings?(tab)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func restoreAutomaticOnQuitIfNeeded() {
        guard settings.restoreAutomaticOnQuit, didRunLiveControl, helperReady else { return }
        Task { try? await helperService.restoreAutomatic() }
    }

    func estimatedRPM(for percent: Double) -> Double? {
        targetRPM(percent: boundedManualPercent(percent))
    }

    private func targetRPM(percent: Double) -> Double? {
        guard let fan = monitor.snapshot.fan else { return nil }
        return try? targetRules.targetRPM(forPercent: percent, fan: fan)
    }

    private func bindManualSlider() {
        settings.$manualPercent
            .dropFirst()
            .sink { [weak self] percent in
                self?.scheduleManualApply(percent: percent)
            }
            .store(in: &cancellables)
    }

    private func bindControlMode() {
        settings.$controlMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.handleControlModeChange(mode)
            }
            .store(in: &cancellables)
    }

    private func bindHelperReadiness() {
        helperService.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard state == .ready else { return }
                self?.helperApprovalPollTask?.cancel()
                self?.helperApprovalPollTask = nil
                self?.activatePendingModeIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func bindControlTick() {
        settings.$controlTickSeconds
            .removeDuplicates()
            .sink { [weak self] seconds in
                self?.monitor.setRefreshInterval(seconds: seconds)
            }
            .store(in: &cancellables)
    }

    private func curveTargetPercent(for temperature: Double?) -> Double? {
        guard let temperature,
              let curve = settings.curve
        else {
            return nil
        }
        return curve.percent(for: temperature)
    }

    private func effectiveCurveTargetPercent(for temperature: Double?) -> Double? {
        guard let percent = curveTargetPercent(for: temperature) else { return nil }
        return boundedManualPercent(percent)
    }

    private func handleControlModeChange(_ mode: FanControlMode) {
        switch mode {
        case .manual:
            pendingModeActivationAfterHelperReady = !helperReady
            stopCurveRun(message: nil)
            applyManualPercentNow()
        case .curve:
            pendingModeActivationAfterHelperReady = !helperReady
            pendingFanTargetApply = nil
            manualApplyTask?.cancel()
            isManualControlActive = false
            startCurveRun()
        }
    }

    private func activateSelectedModeIfNeeded() {
        guard helperReady else { return }

        switch settings.controlMode {
        case .manual:
            applyManualPercentNow()
        case .curve:
            startCurveRun()
        }
    }

    private func activatePendingModeIfNeeded() {
        guard pendingModeActivationAfterHelperReady else { return }
        pendingModeActivationAfterHelperReady = false
        activateSelectedModeIfNeeded()
    }

    private func stopCurveRun(message: String?) {
        guard curveTask != nil else {
            if let message {
                lastActionMessage = message
            }
            return
        }
        curveRunID = nil
        curveTask?.cancel()
        curveTask = nil
        if let message {
            lastActionMessage = message
        }
    }

    private func beginHelperApprovalPolling() {
        helperApprovalPollTask?.cancel()
        helperApprovalPollTask = Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self else { return }
                await self.helperService.refreshState()
                guard self.helperService.isReady else { continue }
                self.helperApprovalPollTask = nil
                self.lastActionMessage = "Helper authorized"
                self.activatePendingModeIfNeeded()
                return
            }
            await MainActor.run {
                self?.helperApprovalPollTask = nil
            }
        }
    }

    private func scheduleManualApply(percent: Double) {
        guard !suppressManualApply else { return }
        guard settings.controlMode == .manual else { return }
        manualApplyTask?.cancel()
        guard helperReady else {
            isManualControlActive = false
            lastActionMessage = helperStatusSummary
            return
        }
        isManualControlActive = true
        let boundedPercent = boundedManualPercent(percent)
        let fireDate = debounceWindow.fireDate(after: Date())
        lastActionMessage = "Applying after slider settles..."
        manualApplyTask = Task { [weak self] in
            let delay = max(0, fireDate.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.applyManualPercent(percent: boundedPercent, message: "Manual target applied")
            }
        }
    }

    private func boundedManualPercent(_ percent: Double) -> Double {
        min(max(percent, manualPercentRange.lowerBound), manualPercentRange.upperBound)
    }

    private var controlTickNanoseconds: UInt64 {
        let seconds = min(
            max(settings.controlTickSeconds, AppSettingsStore.controlTickRange.lowerBound),
            AppSettingsStore.controlTickRange.upperBound
        )
        return UInt64(seconds * 1_000_000_000)
    }

    private func applyManualPercent(percent: Double, message: String) {
        guard helperReady else {
            lastActionMessage = helperStatusSummary
            return
        }

        let boundedPercent = boundedManualPercent(percent)
        if isApplyingFanTarget {
            pendingFanTargetApply = (boundedPercent, message)
            lastActionMessage = "Apply queued"
            return
        }

        isApplyingFanTarget = true
        lastActionMessage = "Applying..."
        Task {
            do {
                let output = try await helperService.setPercent(
                    boundedPercent,
                    allowDangerous: settings.dangerousRangesUnlocked,
                    allowZero: boundedPercent == 0 && settings.dangerousRangesUnlocked
                )
                didRunLiveControl = true
                monitor.refresh()
                lastActionMessage = output.isEmpty ? message : output
            } catch {
                lastActionMessage = error.localizedDescription
            }
            isApplyingFanTarget = false
            if let pendingFanTargetApply {
                self.pendingFanTargetApply = nil
                applyManualPercent(percent: pendingFanTargetApply.percent, message: pendingFanTargetApply.message)
            }
        }
    }

    private func resetManualSliderToAutomatic() {
        manualApplyTask?.cancel()
        suppressManualApply = true
        settings.manualPercent = minimumFanPercent
        suppressManualApply = false
        isManualControlActive = false
    }
}
