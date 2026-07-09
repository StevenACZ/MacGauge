import AppKit
import Combine
import Foundation
import MacFanCore
import os

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettingsStore
    let monitor: FanMonitor
    let systemStats: SystemStatsMonitor
    let loginManager: LaunchAtLoginManager
    let helperService: HelperCommandService

    @Published var isWriting = false
    @Published var isApplyingFanTarget = false
    @Published var lastActionMessage = "status.ready".localized
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
    private var pendingFanTargetApplyPercent: Double?
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
        systemStats = SystemStatsMonitor()
        loginManager = LaunchAtLoginManager()
        helperService = HelperCommandService()
        bindManualSlider()
        bindControlMode()
        bindHelperReadiness()
        bindControlTick()
        bindCurveSnapshot()
        bindContestedState()
        bindSystemModules()
    }

    var manualTargetRPM: Double? {
        targetRPM(percent: manualDisplayPercent)
    }

    var actualRPM: Double? {
        monitor.snapshot.fan?.currentRPM
    }

    var fans: [FanInfo] {
        monitor.snapshot.fans
    }

    var manualDisplayPercent: Double {
        boundedManualPercent(settings.manualPercent)
    }

    var minimumFanPercent: Double {
        targetRules.minimumPercentFloor(
            fans: monitor.snapshot.fans,
            dangerousUnlocked: settings.dangerousRangesUnlocked
        )
    }

    var manualPercentRange: ClosedRange<Double> {
        targetRules.manualPercentRange(
            fans: monitor.snapshot.fans,
            dangerousUnlocked: settings.dangerousRangesUnlocked
        )
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
        lastActionMessage = "status.checking_helper".localized
        Task {
            do {
                try await helperService.userRepair()
                let cleanupMessage = (try? await helperService.removeLegacyHelper()) ?? "No legacy helper found."
                lastActionMessage =
                    cleanupMessage == "No legacy helper found."
                    ? "status.helper_ready".localized
                    : "status.helper_ready_cleanup".localized(cleanupMessage)
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
        applyManualPercent(percent)
    }

    func restoreAutomatic() {
        guard helperReady else {
            lastActionMessage = helperStatusSummary
            return
        }
        stopCurveRun()
        pendingFanTargetApplyPercent = nil
        isWriting = true
        lastActionMessage = "status.restoring_automatic".localized
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
                // The monitor's own poll already refreshes at the control tick;
                // reading the published snapshot avoids doubling SMC traffic.
                let snapshot = self.monitor.snapshot
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
            lastActionMessage = enabled ? "status.login_enabled".localized : "status.login_disabled".localized
        } catch {
            loginManager.refresh()
            lastActionMessage = "status.login_failed".localized(error.localizedDescription)
        }
    }

    func openSettings(tab: SettingsTab = .general) {
        presentSettings?(tab)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    var needsHelperCoordinationOnQuit: Bool {
        didRunLiveControl && helperReady
    }

    /// Runs the quit-time helper handshake — restore automatic, or only
    /// disarm the helper's dead-man watchdog when the user keeps manual
    /// control on quit — with a hard bound so a hung helper can never block
    /// app termination.
    func coordinateHelperForQuit(timeoutSeconds: Double = 2) async {
        stopCurveRun()
        manualApplyTask?.cancel()
        let service = helperService
        let restoresAutomatic = settings.restoreAutomaticOnQuit
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                if restoresAutomatic {
                    _ = try? await service.restoreAutomatic()
                } else {
                    await service.disarmWatchdog()
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
    }

    func estimatedRPM(for percent: Double) -> Double? {
        targetRPM(percent: boundedManualPercent(percent))
    }

    /// Raw percent-to-RPM conversion for the curve editor (bubble, axis, and
    /// point editor); unlike `estimatedRPM(for:)` it does not clamp the percent
    /// to the manual range, so axis ticks map honestly.
    func rpmEquivalent(for percent: Double) -> Double? {
        targetRPM(percent: percent)
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
                // $state publishes on willSet, so helperReady still reads the
                // old value here; hop one runloop to act on the committed one.
                DispatchQueue.main.async {
                    self?.activateSelectedModeAfterHelperReady()
                }
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
                self?.systemStats.setRefreshInterval(seconds: seconds)
            }
            .store(in: &cancellables)
    }

    /// The system stats monitor only runs while at least one menu bar module
    /// (CPU, RAM, network) is enabled; the Display previews run on simulated
    /// data instead.
    private func bindSystemModules() {
        Publishers.CombineLatest3(
            settings.$showsCPUModule,
            settings.$showsMemoryModule,
            settings.$showsNetworkModule
        )
        .map { $0 || $1 || $2 }
        .removeDuplicates()
        .sink { [weak self] anyModuleActive in
            guard let self else { return }
            if anyModuleActive {
                self.systemStats.start(refreshIntervalSeconds: self.settings.controlTickSeconds)
            } else {
                self.systemStats.stop()
            }
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
            stopCurveRun()
            applyManualPercentNow()
        case .curve:
            pendingModeActivationAfterHelperReady = !helperReady
            pendingFanTargetApplyPercent = nil
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

    private func stopCurveRun() {
        guard curveTask != nil else { return }
        curveRunID = nil
        curveTask?.cancel()
        curveTask = nil
        lastAppliedCurvePercent = nil
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
        lastActionMessage = "status.applying_after_slider".localized
        manualApplyTask = Task { [weak self] in
            let delay = max(0, fireDate.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.applyManualPercent(boundedPercent)
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

    private func applyManualPercent(_ percent: Double) {
        Task {
            await applyManualPercentAsync(percent: percent)
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
            pendingFanTargetApplyPercent = boundedPercent
            log.debug("curve apply queued; percent=\(boundedPercent, privacy: .public)")
            return
        }
        log.info(
            "curve applying percent=\(boundedPercent, privacy: .public) targetRPM=\(self.curveTargetRPM ?? -1, privacy: .public) reason=\(targetOutOfSync ? "target-out-of-sync" : "percent-change", privacy: .public)"
        )
        await applyManualPercentAsync(percent: boundedPercent)
    }

    private var fanTargetOutOfSync: Bool {
        guard didRunLiveControl, let percent = currentLivePercent else {
            return false
        }
        return anyFanContested(fans: monitor.snapshot.fans, percent: percent)
    }

    private func bindContestedState() {
        monitor.$snapshot
            .sink { [weak self] snapshot in
                self?.evaluateControlContested(for: snapshot)
            }
            .store(in: &cancellables)
    }

    private func evaluateControlContested(for snapshot: FanSnapshot) {
        // $snapshot publishes on willSet, so derive the live percent from the
        // received snapshot instead of re-reading the stale stored one.
        let livePercent: Double?
        switch settings.controlMode {
        case .manual:
            livePercent = manualDisplayPercent
        case .curve:
            livePercent = effectiveCurveTargetPercent(for: snapshot.temperatureCelsius)
        }
        guard didRunLiveControl, !snapshot.fans.isEmpty, let percent = livePercent else {
            contestedStreak = 0
            controlContested = false
            return
        }
        let contested = anyFanContested(fans: snapshot.fans, percent: percent)
        if contested {
            contestedStreak += 1
        } else {
            contestedStreak = 0
        }
        controlContested = contestedStreak >= contestedStreakLimit
    }

    // Each fan has its own RPM limits, so the live percent must be converted
    // to a per-fan target before the contested comparison.
    private func anyFanContested(fans: [FanInfo], percent: Double) -> Bool {
        fans.contains { fan in
            FanContestedRules.isContested(
                mode: fan.mode,
                actualRPM: fan.currentRPM,
                targetRPM: try? targetRules.targetRPM(forPercent: percent, fan: fan)
            )
        }
    }

    private var currentLivePercent: Double? {
        switch settings.controlMode {
        case .manual:
            return manualDisplayPercent
        case .curve:
            return effectiveCurveTargetPercent
        }
    }

    private func applyManualPercentAsync(percent: Double) async {
        guard helperReady else {
            lastActionMessage = helperStatusSummary
            return
        }

        let boundedPercent = boundedManualPercent(percent)
        let showsApplyingState = settings.controlMode == .manual
        if fanApplyInFlight {
            pendingFanTargetApplyPercent = boundedPercent
            if showsApplyingState {
                lastActionMessage = "status.apply_queued".localized
            }
            return
        }

        fanApplyInFlight = true
        if showsApplyingState {
            isApplyingFanTarget = true
            lastActionMessage = "status.applying".localized
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
        if let pendingPercent = pendingFanTargetApplyPercent {
            pendingFanTargetApplyPercent = nil
            if settings.controlMode == .curve {
                await applyCurveTargetIfNeeded(percent: pendingPercent)
            } else {
                await applyManualPercentAsync(percent: pendingPercent)
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
