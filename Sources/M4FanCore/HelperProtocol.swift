import Foundation

@objc(M4FanHelperXPCProtocol)
public protocol M4FanHelperXPCProtocol {
    func runCommand(_ commandData: Data, withReply reply: @escaping (Data) -> Void)
}

public enum HelperAction: String, Codable, Sendable {
    case ping
    case setPercent
    case automatic
    case removeLegacyHelper
}

public struct HelperCommand: Codable, Sendable {
    public var id: String
    public var action: HelperAction
    public var fanIndex: Int
    public var percent: Double?
    public var allowDangerous: Bool
    public var allowZero: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        action: HelperAction,
        fanIndex: Int = 0,
        percent: Double? = nil,
        allowDangerous: Bool = false,
        allowZero: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.fanIndex = fanIndex
        self.percent = percent
        self.allowDangerous = allowDangerous
        self.allowZero = allowZero
        self.createdAt = createdAt
    }
}

public struct HelperResponse: Codable, Sendable {
    public var id: String
    public var ok: Bool
    public var message: String
    public var completedAt: Date

    public init(id: String, ok: Bool, message: String, completedAt: Date = Date()) {
        self.id = id
        self.ok = ok
        self.message = message
        self.completedAt = completedAt
    }
}

public struct HelperCommandSafety: Sendable {
    public init() {}

    public func validate(percent: Double, allowDangerous: Bool, allowZero: Bool) throws {
        guard percent.isFinite, percent >= 0, percent <= 100 else {
            throw M4FanError("Percent must be between 0 and 100.")
        }
        if percent == 0 && !(allowZero && allowDangerous) {
            throw M4FanError("0 percent requires explicit dangerous zero unlock.")
        }
        if (percent <= 10 || percent >= 95) && !allowDangerous {
            throw M4FanError("Edge fan ranges require dangerous range unlock.")
        }
    }

    public func validate(rpm: Double, fan: FanInfo, percent: Double, allowDangerous: Bool) throws {
        let belowMinimum = fan.minRPM.map { rpm < $0 } ?? false
        let aboveMaximum = fan.maxRPM.map { rpm > $0 } ?? false
        if (belowMinimum || aboveMaximum) && !allowDangerous {
            throw M4FanError("Target \(Int(rpm.rounded())) RPM is outside reported fan limits.")
        }
    }
}

public enum HelperPaths {
    public static let label = "com.stevenacz.M4FanControl.XPCHelper"
    public static let launchDaemonPlistName = "\(label).plist"
    public static let bundleProgram = "Contents/MacOS/M4FanHelper"
    public static let machServiceName = label
}

public enum LegacyHelperPaths {
    public static let label = "com.stevenacz.M4FanControl.Helper"
    public static let toolPath = "/Library/PrivilegedHelperTools/\(label)"
    public static let plistPath = "/Library/LaunchDaemons/\(label).plist"
}
