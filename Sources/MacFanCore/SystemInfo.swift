import Darwin
import Foundation

public struct SystemInfo {
    public static var hardwareModel: String {
        sysctlString("hw.model") ?? "unknown"
    }

    public static var chipName: String {
        sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
    }

    public static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    public static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    public static var isRoot: Bool {
        geteuid() == 0
    }

    /// Moment the machine booted, from kern.boottime.
    public static var bootDate: Date? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0, bootTime.tv_sec > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000)
    }

    public static var logicalCoreCount: Int {
        sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount
    }

    /// Performance cores on Apple Silicon (perflevel0); nil when unavailable.
    public static var performanceCoreCount: Int? {
        sysctlInt("hw.perflevel0.logicalcpu")
    }

    /// Efficiency cores on Apple Silicon (perflevel1); nil when unavailable.
    public static var efficiencyCoreCount: Int? {
        sysctlInt("hw.perflevel1.logicalcpu")
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else {
            return nil
        }
        return Int(value)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        return String(cString: buffer)
    }
}
