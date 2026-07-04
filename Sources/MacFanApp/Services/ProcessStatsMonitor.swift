import AppKit
import Foundation

struct AppResourceUsage: Identifiable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    /// Activity Monitor convention: 100 means one full core.
    var cpuPercent: Double
    var memoryBytes: UInt64

    var id: pid_t { pid }
}

/// Samples per-app CPU and memory (`proc_pid_rusage`) for the user's running
/// applications. Only polls while a CPU/RAM detail popover is open.
@MainActor
final class ProcessStatsMonitor: ObservableObject {
    @Published private(set) var topCPUApps: [AppResourceUsage] = []
    @Published private(set) var topMemoryApps: [AppResourceUsage] = []
    @Published private(set) var hasSampledCPU = false

    private var pollTask: Task<Void, Never>?
    private var previousCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]

    private static let machTimebaseFactor: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom > 0 else { return 1 }
        return Double(info.numer) / Double(info.denom)
    }()

    func start() {
        guard pollTask == nil else { return }
        previousCPUTimes = [:]
        hasSampledCPU = false
        pollTask = Task { [weak self] in
            // First pass seeds the CPU baselines; the quick second pass gets
            // real percentages on screen fast, then settle into a 2 s cadence.
            self?.sampleNow()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                self.sampleNow()
                self.hasSampledCPU = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func sampleNow() {
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy != .prohibited && $0.processIdentifier > 0
        }
        let now = Date()
        var usages: [AppResourceUsage] = []
        var nextCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]

        for application in applications {
            let pid = application.processIdentifier
            guard let raw = Self.readRawUsage(pid: pid) else { continue }

            nextCPUTimes[pid] = (raw.cpuNanoseconds, now)
            var cpuPercent = 0.0
            if let previous = previousCPUTimes[pid], raw.cpuNanoseconds >= previous.nanoseconds {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0 {
                    cpuPercent = Double(raw.cpuNanoseconds - previous.nanoseconds) / 1_000_000_000 / elapsed * 100
                }
            }

            usages.append(
                AppResourceUsage(
                    pid: pid,
                    name: application.localizedName ?? "PID \(pid)",
                    icon: application.icon,
                    cpuPercent: cpuPercent,
                    memoryBytes: raw.memoryBytes
                )
            )
        }

        previousCPUTimes = nextCPUTimes
        topCPUApps = Array(usages.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        topMemoryApps = Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
    }

    private static func readRawUsage(pid: pid_t) -> (cpuNanoseconds: UInt64, memoryBytes: UInt64)? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, reboundPointer)
            }
        }
        guard result == 0 else { return nil }
        let machTime = info.ri_user_time &+ info.ri_system_time
        let nanoseconds = UInt64(Double(machTime) * machTimebaseFactor)
        return (nanoseconds, info.ri_phys_footprint)
    }
}
