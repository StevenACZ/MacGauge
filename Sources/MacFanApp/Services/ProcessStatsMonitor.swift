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
    /// Detail views come and go out of order when the user switches between
    /// the CPU and RAM popovers (the new view's onAppear can land before the
    /// old view's onDisappear), so start/stop are reference-counted — a late
    /// stop from the closing popover must not kill the poll the open one
    /// depends on.
    private var clientCount = 0
    private var previousCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]
    /// Names and icons are stable per pid; cached so each tick only pays the
    /// NSRunningApplication lookup for processes it has not seen.
    private var identityCache: [pid_t: (name: String, icon: NSImage?)] = [:]
    private let readQueue = DispatchQueue(label: "com.stevenacz.MacFan.processstats.read", qos: .utility)

    func start() {
        clientCount += 1
        guard pollTask == nil else { return }
        previousCPUTimes = [:]
        hasSampledCPU = false
        pollTask = Task { [weak self] in
            // First pass seeds the CPU baselines; the quick second pass gets
            // real percentages on screen fast, then settle into a 2 s cadence.
            await self?.sampleNow()
            try? await Task.sleep(nanoseconds: 500_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                await self.sampleNow()
                self.hasSampledCPU = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        clientCount = max(0, clientCount - 1)
        guard clientCount == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
        identityCache = [:]
    }

    private func sampleNow() async {
        // The syscall sweep (hundreds of pids every tick) runs off the main
        // thread; only NSRunningApplication identity resolution — main-thread
        // API — happens here, and the cache limits that to unseen pids.
        let batch = await Self.readSamplesAsync(
            previousCPUTimes: previousCPUTimes,
            namedPIDs: Set(identityCache.keys),
            queue: readQueue
        )
        // stop() can land while the sweep is off-main; a stale publish would
        // repopulate the cache it just cleared.
        guard !Task.isCancelled else { return }

        var usages: [AppResourceUsage] = []
        var nextCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]
        var nextIdentityCache: [pid_t: (name: String, icon: NSImage?)] = [:]

        for sample in batch.samples {
            guard let identity = identityCache[sample.pid] ?? Self.identity(pid: sample.pid, bsdName: sample.bsdName)
            else { continue }
            nextIdentityCache[sample.pid] = identity
            nextCPUTimes[sample.pid] = (sample.cpuNanoseconds, batch.readAt)

            usages.append(
                AppResourceUsage(
                    pid: sample.pid,
                    name: identity.name,
                    icon: identity.icon,
                    cpuPercent: sample.cpuPercent,
                    memoryBytes: sample.memoryBytes
                )
            )
        }

        previousCPUTimes = nextCPUTimes
        identityCache = nextIdentityCache
        topCPUApps = Array(usages.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(Self.expandedCount))
        topMemoryApps = Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(Self.expandedCount))
    }

    /// GUI apps keep their localized name and icon; everything else falls
    /// back to the BSD process name (compilers, daemons, helpers).
    private static func identity(pid: pid_t, bsdName: String?) -> (name: String, icon: NSImage?)? {
        if let application = NSRunningApplication(processIdentifier: pid) {
            return (application.localizedName ?? bsdName ?? "PID \(pid)", application.icon)
        }
        guard let bsdName else { return nil }
        return (bsdName, nil)
    }

    nonisolated private static func readSamplesAsync(
        previousCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)],
        namedPIDs: Set<pid_t>,
        queue: DispatchQueue
    ) async -> ProcessSampleBatch {
        await withCheckedContinuation { (continuation: CheckedContinuation<ProcessSampleBatch, Never>) in
            queue.async {
                continuation.resume(
                    returning: ProcessSampler.readSamples(previousCPUTimes: previousCPUTimes, namedPIDs: namedPIDs)
                )
            }
        }
    }
}

private struct RawProcessSample: Sendable {
    let pid: pid_t
    let cpuNanoseconds: UInt64
    let cpuPercent: Double
    let memoryBytes: UInt64
    /// Resolved off-main via proc_name; nil for pids the caller already named.
    let bsdName: String?
}

private struct ProcessSampleBatch: Sendable {
    let samples: [RawProcessSample]
    let readAt: Date
}

/// Raw pid sweep (proc_listallpids + per-pid rusage + BSD names). Only ever
/// runs on the monitor's read queue, never the main thread.
private enum ProcessSampler {
    private static let machTimebaseFactor: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom > 0 else { return 1 }
        return Double(info.numer) / Double(info.denom)
    }()

    static func readSamples(
        previousCPUTimes: [pid_t: (nanoseconds: UInt64, at: Date)],
        namedPIDs: Set<pid_t>
    ) -> ProcessSampleBatch {
        let now = Date()
        var samples: [RawProcessSample] = []

        for pid in allPIDs() where pid > 0 {
            // Other users' and most system processes refuse the rusage read;
            // skipping them matches what the user could inspect anyway.
            guard let raw = readRawUsage(pid: pid) else { continue }

            var cpuPercent = 0.0
            if let previous = previousCPUTimes[pid], raw.cpuNanoseconds >= previous.nanoseconds {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0 {
                    cpuPercent = Double(raw.cpuNanoseconds - previous.nanoseconds) / 1_000_000_000 / elapsed * 100
                }
            }

            samples.append(
                RawProcessSample(
                    pid: pid,
                    cpuNanoseconds: raw.cpuNanoseconds,
                    cpuPercent: cpuPercent,
                    memoryBytes: raw.memoryBytes,
                    bsdName: namedPIDs.contains(pid) ? nil : processName(pid: pid)
                )
            )
        }
        return ProcessSampleBatch(samples: samples, readAt: now)
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
