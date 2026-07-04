import Foundation

/// One reading of the host CPU tick counters (HOST_CPU_LOAD_INFO). Ticks are
/// cumulative since boot, so usage is always derived from two samples.
public struct CPULoadTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Memory pressure band shown next to the RAM stats.
public enum MemoryPressureLevel: Equatable, Sendable {
    case normal
    case elevated
    case high
}

/// Coarse effort band for the load-tinted menu bar charts. Maps onto the
/// same normal → medium → hot colors the fan temperature bands use.
public enum LoadBand: Equatable, Sendable {
    case normal
    case elevated
    case high
}

/// Pure math for the system load charts (CPU, memory, network). Kept UI-free
/// and chip-agnostic so it behaves identically on every Apple Silicon Mac.
public enum SystemLoadRules {
    /// Busy percent between two cumulative tick samples, or nil when the
    /// samples cannot produce a meaningful delta (first read, counter reset).
    public static func cpuUsagePercent(previous: CPULoadTicks, current: CPULoadTicks) -> Double? {
        guard current.user >= previous.user,
            current.system >= previous.system,
            current.idle >= previous.idle,
            current.nice >= previous.nice
        else {
            return nil
        }
        let busy = (current.user - previous.user) + (current.system - previous.system) + (current.nice - previous.nice)
        let total = busy + (current.idle - previous.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total) * 100
    }

    /// Used-memory percent clamped to 0...100.
    public static func memoryUsedPercent(usedBytes: UInt64, totalBytes: UInt64) -> Double? {
        guard totalBytes > 0 else { return nil }
        return min(100, Double(usedBytes) / Double(totalBytes) * 100)
    }

    /// Bytes per second between two cumulative interface counters, or nil when
    /// the counter reset (interface re-created) or no time elapsed.
    public static func byteRate(previousBytes: UInt64, currentBytes: UInt64, elapsedSeconds: Double) -> Double? {
        guard elapsedSeconds > 0, currentBytes >= previousBytes else { return nil }
        return Double(currentBytes - previousBytes) / elapsedSeconds
    }

    /// CPU effort band; ceilings picked so brief spikes stay quiet and only
    /// sustained heavy use turns the chart hot.
    public static func cpuLoadBand(forPercent percent: Double?) -> LoadBand {
        switch percent ?? 0 {
        case ..<60:
            return .normal
        case ..<85:
            return .elevated
        default:
            return .high
        }
    }

    /// Memory band mirrors the pressure level — used percent alone
    /// overstates pressure on macOS.
    public static func memoryLoadBand(forPressure pressure: MemoryPressureLevel) -> LoadBand {
        switch pressure {
        case .normal:
            return .normal
        case .elevated:
            return .elevated
        case .high:
            return .high
        }
    }

    /// Band from the kernel's own pressure level
    /// (`kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning,
    /// 4 critical), falling back to used-percent thresholds when the sysctl
    /// is unavailable.
    public static func memoryPressureLevel(sysctlLevel: Int?, usedPercent: Double?) -> MemoryPressureLevel {
        switch sysctlLevel {
        case 1:
            return .normal
        case 2:
            return .elevated
        case 4:
            return .high
        default:
            break
        }
        switch usedPercent ?? 0 {
        case ..<75:
            return .normal
        case ..<90:
            return .elevated
        default:
            return .high
        }
    }
}
