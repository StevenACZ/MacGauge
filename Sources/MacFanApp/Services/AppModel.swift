import AppKit
import Combine
import Foundation
import MacFanCore
import os

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
    @Published private(set) var controlContested = false

    var presentSettings: ((SettingsTab) -> Void)?

    private var fanApplyInFlight = false
    private let debounceWindow = DebounceWindow(delay: 0.55)
    private let targetRules = FanTargetRules()
    private var cancellables = Set<AnyCancellable>()
    private var manualApplyTask: Task<Void, Never>?
    private var curveTask: Task<Void, Never>?
    private var curveRunID: UUID?
    private var pendingFanTargetApply: (percent: Double, message: String)?
    private var lastAppliedCurvePercent: Double?
    private var didRunLiveControl = false
    private var suppressManualApply = false
    private var pendingModeActivationAfterHelperReady = false
    private let contestedStreakLimit = 2
    private var contestedStreak = 0
    private let log = Logger(subsystem: "com.stevenacz.MacFan", category: "app-model")

    init() {
        settings = AppSettingsStore()
        monitor = FanMonitor()
        loginManager = LaunchAtLoginManager()
        helperService = HelperCommandService()
        bindManualSlider()
        bindControlMode()
        bindHelperReadiness()
        bindControlTick()
        bindCurveSnapshot()
        bindContestedState()
    }

    var manualTargetRPM: Double? {
        targetRPM(percent: manualDisplayPercent)
    }

    var actualRPM: Double? {
        monitor.snapshot.fan?.currentRPM
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
        helperService.startMonitoring()
        log.info(
            "app started mode=\(self.settings.controlMode.rawValue, privacy: .public)"
        )
    }

    func authorizeHelper() {
        isWriting = true
        lastActionMessage = "Checking helper..."
        Task {
            do {
                try await helperService.userRepair()
                let cleanupMessage = (try? await helperService.removeLegacyHelper()) ?? "No legacy helper found."
                lastActionMessage =
                    cleanupMessage == "No legacy helper found."
                    ? "Helper ready"
                    : "Helper ready. \(cleanupMessage)"
                log.info("helper repaired cleanup=\(cleanupMessage, privacy: .public)")
                activateSelectedModeAfterHelperReady()
            } catch {
                lastActionMessage = error.localizedDescription
                log.error("helper repair failed: \(error.localizedDescription, privacy: .public)")
            }
            isWriting = false
        }
    }

    func refreshHelperState() {
        helperService.requestImmediateRefresh()
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
        curveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await self.monitor.refreshNow()
                let percent = self.effectiveCurveTargetPercent(for: snapshot.temperatureCelsius)
                self.log.debug(
                    "curve tick temp=\(snapshot.temperatureCelsius ?? -1, privacy: .public) percent=\(percent ?? -1, privacy: .public) writing=\(self.isWriting, privacy: .public) helperReady=\(self.helperReady, privacy: .public)"
                )
                if !self.isWriting, let percent {
                    await self.applyCurveTargetIfNeeded(percent: percent)
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
                self?.activateSelectedModeAfterHelperReady()
            }
            .store(in: &cancellables)
    }

    private func bindCurveSnapshot() {
        monitor.$snapshot
            .map { [weak self] snapshot in
                self?.effectiveCurveTargetPercent(for: snapshot.temperatureCelsius)
            }
            .removeDuplicates { [weak self] lhs, rhs in
                self?.curvePercentChangeIsNegligible(lhs, rhs) ?? (lhs == nil && rhs == nil)
            }
            .sink { [weak self] percent in
                guard let self,
                    self.settings.controlMode == .curve,
                    self.helperReady,
                    !self.isWriting,
                    !self.fanApplyInFlight,
                    let percent
                else {
                    return
                }
                Task {
                    await self.applyCurveTargetIfNeeded(percent: percent)
                }
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
            lastAppliedCurvePercent = nil
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
        lastAppliedCurvePercent = nil
        if let message {
            lastActionMessage = message
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
        Task {
            await applyManualPercentAsync(percent: percent, message: message)
        }
    }

    private func applyCurveTargetIfNeeded(percent: Double) async {
        guard settings.controlMode == .curve, helperReady, !isWriting else { return }
        let boundedPercent = boundedManualPercent(percent)
        let targetOutOfSync = fanTargetOutOfSync
        guard !curvePercentChangeIsNegligible(lastAppliedCurvePercent, boundedPercent) || targetOutOfSync else {
            log.debug("curve apply skipped; percent unchanged and fan in sync")
            return
        }
        guard !fanApplyInFlight else {
            pendingFanTargetApply = (boundedPercent, "Curve target applied")
            log.debug("curve apply queued; percent=\(boundedPercent, privacy: .public)")
            return
        }
        log.info(
            "curve applying percent=\(boundedPercent, privacy: .public) targetRPM=\(self.curveTargetRPM ?? -1, privacy: .public) reason=\(targetOutOfSync ? "target-out-of-sync" : "percent-change", privacy: .public)"
        )
        await applyManualPercentAsync(percent: boundedPercent, message: "Curve target applied")
    }

    private var fanTargetOutOfSync: Bool {
        guard didRunLiveControl,
            let fan = monitor.snapshot.fan,
            let targetRPM = currentLiveTargetRPM
        else {
            return false
        }
        return FanContestedRules.isContested(
            mode: fan.mode,
            actualRPM: fan.currentRPM,
            targetRPM: targetRPM
        )
    }

    private func bindContestedState() {
        monitor.$snapshot
            .sink { [weak self] snapshot in
                self?.evaluateControlContested(for: snapshot)
            }
            .store(in: &cancellables)
    }

    private func evaluateControlContested(for snapshot: FanSnapshot) {
        guard didRunLiveControl, let fan = snapshot.fan else {
            contestedStreak = 0
            controlContested = false
            return
        }
        let contested = FanContestedRules.isContested(
            mode: fan.mode,
            actualRPM: fan.currentRPM,
            targetRPM: currentLiveTargetRPM
        )
        if contested {
            contestedStreak += 1
        } else {
            contestedStreak = 0
        }
        controlContested = contestedStreak >= contestedStreakLimit
    }

    private var currentLiveTargetRPM: Double? {
        switch settings.controlMode {
        case .manual:
            return manualTargetRPM
        case .curve:
            return curveTargetRPM
        }
    }

    private func applyManualPercentAsync(percent: Double, message: String) async {
        guard helperReady else {
            lastActionMessage = helperStatusSummary
            return
        }

        let boundedPercent = boundedManualPercent(percent)
        let showsApplyingState = settings.controlMode == .manual
        if fanApplyInFlight {
            pendingFanTargetApply = (boundedPercent, message)
            if showsApplyingState {
                lastActionMessage = "Apply queued"
            }
            return
        }

        fanApplyInFlight = true
        if showsApplyingState {
            isApplyingFanTarget = true
            lastActionMessage = "Applying..."
        }
        do {
            let result = try await helperService.setPercent(
                boundedPercent,
                allowDangerous: settings.dangerousRangesUnlocked,
                allowZero: boundedPercent == 0 && settings.dangerousRangesUnlocked
            )
            log.info(
                "fan target applied mode=\(self.settings.controlMode.rawValue, privacy: .public) percent=\(boundedPercent, privacy: .public) actualRPM=\(result.actualRPM ?? -1, privacy: .public) smcMode=\(result.mode ?? -1, privacy: .public) contested=\(result.contested, privacy: .public)"
            )
            didRunLiveControl = true
            if settings.controlMode == .curve {
                lastAppliedCurvePercent = boundedPercent
            }
            if showsApplyingState {
                lastActionMessage = result.message
            }
            _ = await monitor.refreshNow()
        } catch {
            lastActionMessage = error.localizedDescription
            log.error("fan target apply failed: \(error.localizedDescription, privacy: .public)")
        }
        fanApplyInFlight = false
        if showsApplyingState {
            isApplyingFanTarget = false
        }
        if let pending = pendingFanTargetApply {
            pendingFanTargetApply = nil
            if settings.controlMode == .curve {
                await applyCurveTargetIfNeeded(percent: pending.percent)
            } else {
                await applyManualPercentAsync(percent: pending.percent, message: pending.message)
            }
        }
    }

    private func curvePercentChangeIsNegligible(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let lhs?, let rhs?):
            return abs(lhs - rhs) < 0.25
        default:
            return false
        }
    }

    private func resetManualSliderToAutomatic() {
        manualApplyTask?.cancel()
        suppressManualApply = true
        settings.manualPercent = minimumFanPercent
        suppressManualApply = false
        isManualControlActive = false
    }

    private func activateSelectedModeAfterHelperReady() {
        if pendingModeActivationAfterHelperReady {
            pendingModeActivationAfterHelperReady = false
            activateSelectedModeIfNeeded()
            return
        }

        if settings.controlMode == .curve {
            log.info("starting persisted curve mode after helper became ready")
            startCurveRun()
        }
    }
}
