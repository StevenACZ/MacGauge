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
    @Published var lastActionMessage = "Ready"
    @Published var isManualControlActive = false

    private let debounceWindow = DebounceWindow(delay: 0.55)
    private var cancellables = Set<AnyCancellable>()
    private var manualApplyTask: Task<Void, Never>?
    private var curveTask: Task<Void, Never>?
    private var didRunLiveControl = false
    private var suppressManualApply = false

    init() {
        settings = AppSettingsStore()
        monitor = FanMonitor()
        loginManager = LaunchAtLoginManager()
        helperService = HelperCommandService()
        bindManualSlider()
    }

    var manualTargetRPM: Double? {
        targetRPM(percent: settings.manualPercent)
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

    var curveTargetPercent: Double? {
        guard let temperature = monitor.snapshot.temperatureCelsius,
              let curve = settings.curve
        else {
            return nil
        }
        return curve.percent(for: temperature)
    }

    var curveTargetRPM: Double? {
        guard let percent = curveTargetPercent else { return nil }
        return targetRPM(percent: percent)
    }

    func start() {
        monitor.start()
        Task { await helperService.refreshState() }
    }

    func authorizeHelper() {
        isWriting = true
        lastActionMessage = "Awaiting admin approval..."
        Task {
            do {
                try await helperService.authorizeHelper()
                lastActionMessage = "Helper authorized"
            } catch {
                lastActionMessage = error.localizedDescription
            }
            isWriting = false
        }
    }

    func applyManualPercentNow() {
        let percent = settings.manualPercent
        applyManualPercent(percent: percent, message: "Manual target applied")
    }

    func restoreAutomatic() {
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
            curveTask?.cancel()
            curveTask = nil
            lastActionMessage = "Curve stopped"
            return
        }

        let durationSeconds = max(60, settings.curveRunMinutes * 60)
        let startedAt = Date()
        lastActionMessage = "Curve running"
        curveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Date().timeIntervalSince(startedAt) >= durationSeconds { break }
                await MainActor.run {
                    if let percent = self.curveTargetPercent {
                        self.applyManualPercent(percent: percent, message: "Curve target applied")
                    }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            await MainActor.run {
                self?.curveTask = nil
                self?.lastActionMessage = "Curve finished"
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

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func restoreAutomaticOnQuitIfNeeded() {
        guard settings.restoreAutomaticOnQuit, didRunLiveControl else { return }
        Task { try? await helperService.restoreAutomatic() }
    }

    private func targetRPM(percent: Double) -> Double? {
        guard let fan = monitor.snapshot.fan, let maxRPM = fan.maxRPM else { return nil }
        return max(0, min(100, percent)) / 100.0 * maxRPM
    }

    private func bindManualSlider() {
        settings.$manualPercent
            .dropFirst()
            .sink { [weak self] percent in
                self?.scheduleManualApply(percent: percent)
            }
            .store(in: &cancellables)
    }

    private func scheduleManualApply(percent: Double) {
        guard !suppressManualApply else { return }
        guard settings.controlMode == .manual else { return }
        isManualControlActive = true
        manualApplyTask?.cancel()
        let fireDate = debounceWindow.fireDate(after: Date())
        lastActionMessage = "Applying after slider settles..."
        manualApplyTask = Task { [weak self] in
            let delay = max(0, fireDate.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.applyManualPercent(percent: percent, message: "Manual target applied")
            }
        }
    }

    private func applyManualPercent(percent: Double, message: String) {
        isWriting = true
        lastActionMessage = helperService.state == .ready ? "Applying..." : "Authorizing helper..."
        Task {
            do {
                let output = try await helperService.setPercent(
                    percent,
                    allowDangerous: settings.dangerousRangesUnlocked || percent <= 10 || percent >= 95,
                    allowZero: percent == 0 && settings.dangerousRangesUnlocked
                )
                didRunLiveControl = true
                monitor.refresh()
                lastActionMessage = output.isEmpty ? message : output
            } catch {
                lastActionMessage = error.localizedDescription
            }
            isWriting = false
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
