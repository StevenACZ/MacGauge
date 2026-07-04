import AppKit
import Darwin
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

/// Samples per-process CPU and memory (`proc_pid_rusage`) across every
/// process the user can read — GUI apps, helpers, and command-line work like
/// compilers — so the top lists match Activity Monitor instead of only
/// counting regular applications. Only polls while a CPU/RAM detail popover
/// is open.
@MainActor
final class ProcessStatsMonitor: ObservableObject {
    /// Rows shown collapsed / after "Show more".
    static let collapsedCount = 5
    static let expandedCount = 15

    @Published private(set) var topCPUApps: [AppResourceUsage] = []
    @Published private(set) var topMemoryApps: [AppResourceUsage] = []
    @Published private(set) var hasSampledCPU = false

    private var pollTask: Task<Void, Never>?
    private var previousCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]
    /// Names and icons are stable per pid; cached so each tick only pays the
    /// NSRunningApplication/proc_name lookups for processes it has not seen.
    private var identityCache: [pid_t: (name: String, icon: NSImage?)] = [:]

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
        identityCache = [:]
    }

    private func sampleNow() {
        let pids = Self.allPIDs()
        let now = Date()
        var usages: [AppResourceUsage] = []
        var nextCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]
        var nextIdentityCache: [pid_t: (name: String, icon: NSImage?)] = [:]

        for pid in pids where pid > 0 {
            // Other users' and most system processes refuse the rusage read;
            // skipping them matches what the user could inspect anyway.
            guard let raw = Self.readRawUsage(pid: pid) else { continue }
            guard let identity = identityCache[pid] ?? Self.identity(pid: pid) else { continue }
            nextIdentityCache[pid] = identity

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
                    name: identity.name,
                    icon: identity.icon,
                    cpuPercent: cpuPercent,
                    memoryBytes: raw.memoryBytes
                )
            )
        }

        previousCPUTimes = nextCPUTimes
        identityCache = nextIdentityCache
        topCPUApps = Array(usages.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(Self.expandedCount))
        topMemoryApps = Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(Self.expandedCount))
    }

    private static func allPIDs() -> [pid_t] {
        let expected = proc_listallpids(nil, 0)
        guard expected > 0 else { return [] }
        // Headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(expected) + 64)
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled)))
    }

    /// GUI apps keep their localized name and icon; everything else falls
    /// back to the BSD process name (compilers, daemons, helpers).
    private static func identity(pid: pid_t) -> (name: String, icon: NSImage?)? {
        if let application = NSRunningApplication(processIdentifier: pid) {
            return (application.localizedName ?? processName(pid: pid) ?? "PID \(pid)", application.icon)
        }
        guard let name = processName(pid: pid) else { return nil }
        return (name, nil)
    }

    private static func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            return String(cString: buffer)
        }
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            return (String(cString: buffer) as NSString).lastPathComponent
        }
        return nil
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
