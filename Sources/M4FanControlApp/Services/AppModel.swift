import AppKit
import Foundation
import M4FanCore

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettingsStore
    let monitor: FanMonitor
    let loginManager: LaunchAtLoginManager

    @Published var isWriting = false
    @Published var lastActionMessage = "Ready"

    private let cliService = PrivilegedCLIService()
    private var didRunLiveControl = false

    init() {
        settings = AppSettingsStore()
        monitor = FanMonitor()
        loginManager = LaunchAtLoginManager()
    }

    var manualTargetRPM: Double? {
        targetRPM(percent: settings.manualPercent)
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
    }

    func applyManualPercent() {
        let percent = settings.manualPercent
        runPrivileged(arguments: setArguments(percent: percent), successMessage: "Manual target applied")
    }

    func restoreAutomatic() {
        runPrivileged(arguments: ["auto", "--live", "--i-understand"], successMessage: "Automatic control restored")
    }

    func startCurveRun() {
        let duration = max(60, Int(settings.curveRunMinutes.rounded() * 60))
        var arguments = [
            "curve",
            "--fan", "0",
            "--points", settings.curveCommandPoints,
            "--duration", "\(duration)",
            "--live",
            "--i-understand"
        ]
        if settings.dangerousRangesUnlocked {
            arguments.append("--allow-dangerous")
        }
        runPrivileged(arguments: arguments, background: true, successMessage: "Curve run started")
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
        _ = try? cliService.runPrivilegedSync(arguments: ["auto", "--live", "--i-understand"])
    }

    private func targetRPM(percent: Double) -> Double? {
        guard let fan = monitor.snapshot.fan, let maxRPM = fan.maxRPM else { return nil }
        return max(0, min(100, percent)) / 100.0 * maxRPM
    }

    private func setArguments(percent: Double) -> [String] {
        var arguments = [
            "set",
            "--fan", "0",
            "--percent", "\(Int(percent.rounded()))",
            "--live",
            "--i-understand"
        ]
        if settings.dangerousRangesUnlocked || percent <= 10 || percent >= 95 {
            arguments.append("--allow-dangerous")
        }
        if percent == 0 {
            arguments.append("--allow-zero")
        }
        return arguments
    }

    private func runPrivileged(arguments: [String], background: Bool = false, successMessage: String) {
        isWriting = true
        lastActionMessage = "Awaiting admin approval..."
        Task {
            do {
                let output = try await cliService.runPrivileged(arguments: arguments, background: background)
                didRunLiveControl = true
                monitor.refresh()
                lastActionMessage = output.isEmpty ? successMessage : output
            } catch {
                lastActionMessage = error.localizedDescription
            }
            isWriting = false
        }
    }
}
