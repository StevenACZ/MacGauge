import Darwin
import Foundation
import MacFanCore

struct SystemLoadSnapshot: Sendable {
    var cpuPercent: Double?
    var memoryPercent: Double?
    var memoryUsedBytes: UInt64?
    var memoryTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    /// Raw kern.memorystatus_vm_pressure_level reading (1/2/4), if available.
    var memoryPressureSysctlLevel: Int?
    var downloadBytesPerSecond: Double?
    var uploadBytesPerSecond: Double?
    /// Bytes moved since monitoring began (survives module toggles).
    var sessionReceivedBytes: UInt64 = 0
    var sessionSentBytes: UInt64 = 0
}

/// Polls host-wide CPU, memory, and network counters on the same tick as the
/// fan monitor and keeps a short history per metric for the popover charts.
/// Uses Mach/BSD host statistics only, so it works on every Apple Silicon Mac.
@MainActor
final class SystemStatsMonitor: ObservableObject {
    static let historyCapacity = 60

    @Published private(set) var snapshot = SystemLoadSnapshot()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []

    private var refreshIntervalNanoseconds: UInt64 = SystemStatsMonitor.nanoseconds(forInterval: 1)
    private var pollTask: Task<Void, Never>?
    private let sampler = SystemLoadSampler()
    private let readQueue = DispatchQueue(label: "com.stevenacz.MacFan.systemstats.read", qos: .utility)

    func start(refreshIntervalSeconds: Double = 1) {
        stop()
        refreshIntervalNanoseconds = Self.nanoseconds(forInterval: refreshIntervalSeconds)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sampleOnce()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: self.refreshIntervalNanoseconds)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func setRefreshInterval(seconds: Double) {
        refreshIntervalNanoseconds = Self.nanoseconds(forInterval: seconds)
    }

    private func sampleOnce() async {
        let sampled = await Self.readSampleAsync(sampler: sampler, queue: readQueue)
        publish(sampled)
    }

    private func publish(_ sampled: SystemLoadSnapshot) {
        var next = sampled
        // Keep the previous value when a tick could not produce one (first
        // read or counter reset) so the charts and labels never flicker.
        next.cpuPercent = sampled.cpuPercent ?? snapshot.cpuPercent
        next.memoryPercent = sampled.memoryPercent ?? snapshot.memoryPercent
        next.memoryUsedBytes = sampled.memoryUsedBytes ?? snapshot.memoryUsedBytes
        next.memoryPressureSysctlLevel = sampled.memoryPressureSysctlLevel ?? snapshot.memoryPressureSysctlLevel
        next.downloadBytesPerSecond = sampled.downloadBytesPerSecond ?? snapshot.downloadBytesPerSecond
        next.uploadBytesPerSecond = sampled.uploadBytesPerSecond ?? snapshot.uploadBytesPerSecond
        snapshot = next

        if let cpu = next.cpuPercent {
            append(cpu, to: &cpuHistory)
        }
        if let memory = next.memoryPercent {
            append(memory, to: &memoryHistory)
        }
        if let download = next.downloadBytesPerSecond {
            append(download, to: &downloadHistory)
        }
        if let upload = next.uploadBytesPerSecond {
            append(upload, to: &uploadHistory)
        }
    }

    private func append(_ value: Double, to history: inout [Double]) {
        // Seed a full flat baseline from the first sample so charts start as
        // a line at the current level instead of climbing out of zero while
        // the real history builds up.
        guard !history.isEmpty else {
            history = [Double](repeating: value, count: Self.historyCapacity)
            return
        }
        history.append(value)
        if history.count > Self.historyCapacity {
            history.removeFirst(history.count - Self.historyCapacity)
        }
    }

    nonisolated private static func readSampleAsync(
        sampler: SystemLoadSampler,
        queue: DispatchQueue
    ) async -> SystemLoadSnapshot {
        await withCheckedContinuation { (continuation: CheckedContinuation<SystemLoadSnapshot, Never>) in
            queue.async {
                continuation.resume(returning: sampler.sample())
            }
        }
    }

    private static func nanoseconds(forInterval seconds: Double) -> UInt64 {
        let bounded = min(max(seconds, 0.5), 10)
        return UInt64(bounded * 1_000_000_000)
    }
}

/// Reads the raw host counters and turns them into per-tick deltas. Only ever
/// touched from the monitor's read queue, which keeps its state single-threaded.
private final class SystemLoadSampler: @unchecked Sendable {
    /// Cached once: every mach_host_self() call adds a reference to the port.
    private static let host = mach_host_self()

    private var previousTicks: CPULoadTicks?
    private var previousNetwork: (received: UInt64, sent: UInt64, readAt: Date)?
    private var sessionReceived: UInt64 = 0
    private var sessionSent: UInt64 = 0

    func sample() -> SystemLoadSnapshot {
        var snapshot = SystemLoadSnapshot()

        if let ticks = Self.readCPUTicks() {
            if let previousTicks {
                snapshot.cpuPercent = SystemLoadRules.cpuUsagePercent(previous: previousTicks, current: ticks)
            }
            previousTicks = ticks
        }

        if let usedBytes = Self.readMemoryUsedBytes() {
            snapshot.memoryUsedBytes = usedBytes
            snapshot.memoryPercent = SystemLoadRules.memoryUsedPercent(
                usedBytes: usedBytes,
                totalBytes: snapshot.memoryTotalBytes
            )
        }
        snapshot.memoryPressureSysctlLevel = Self.readMemoryPressureLevel()

        if let counters = Self.readNetworkCounters() {
            let readAt = Date()
            if let previousNetwork {
                let elapsed = readAt.timeIntervalSince(previousNetwork.readAt)
                snapshot.downloadBytesPerSecond = SystemLoadRules.byteRate(
                    previousBytes: previousNetwork.received,
                    currentBytes: counters.received,
                    elapsedSeconds: elapsed
                )
                snapshot.uploadBytesPerSecond = SystemLoadRules.byteRate(
                    previousBytes: previousNetwork.sent,
                    currentBytes: counters.sent,
                    elapsedSeconds: elapsed
                )
                if counters.received >= previousNetwork.received {
                    sessionReceived &+= counters.received - previousNetwork.received
                }
                if counters.sent >= previousNetwork.sent {
                    sessionSent &+= counters.sent - previousNetwork.sent
                }
            }
            previousNetwork = (counters.received, counters.sent, readAt)
        }
        snapshot.sessionReceivedBytes = sessionReceived
        snapshot.sessionSentBytes = sessionSent

        return snapshot
    }

    private static func readCPUTicks() -> CPULoadTicks? {
        var size = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPointer in
                host_statistics(host, HOST_CPU_LOAD_INFO, reboundPointer, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPULoadTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func readMemoryUsedBytes() -> UInt64? {
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // Mirrors Activity Monitor's "Memory Used": app memory (internal minus
        // purgeable) plus wired plus compressed.
        let pageSize = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let appPages = internalPages - min(internalPages, UInt64(stats.purgeable_count))
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return usedPages * pageSize
    }

    private static func readMemoryPressureLevel() -> Int? {
        var level: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        return Int(level)
    }

    private static func readNetworkCounters() -> (received: UInt64, sent: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor = addresses
        while let entry = cursor {
            let interface = entry.pointee
            cursor = interface.ifa_next

            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let flags = Int32(bitPattern: UInt32(interface.ifa_flags))
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            // Skip peer-to-peer side channels (AirDrop/low-latency WLAN) so
            // the chart reflects real user traffic.
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("awdl"), !name.hasPrefix("llw") else { continue }

            // getifaddrs only carries 32-bit byte counters, which wrap every
            // 4 GiB and freeze the displayed rate; prefer the 64-bit sysctl
            // row and keep the 32-bit read as the fallback.
            if let counters = read64BitCounters(interfaceIndex: if_nametoindex(name)) {
                received &+= counters.received
                sent &+= counters.sent
            } else if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                received &+= UInt64(data.pointee.ifi_ibytes)
                sent &+= UInt64(data.pointee.ifi_obytes)
            }
        }
        return (received, sent)
    }

    private static func read64BitCounters(interfaceIndex: UInt32) -> (received: UInt64, sent: UInt64)? {
        guard interfaceIndex != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(interfaceIndex), IFDATA_GENERAL]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, u_int(mib.count), &data, &size, nil, 0) == 0 else { return nil }
        return (data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes)
    }
}
