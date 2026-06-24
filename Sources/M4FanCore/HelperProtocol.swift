import Foundation

public enum HelperAction: String, Codable, Sendable {
    case ping
    case setPercent
    case automatic
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

public enum HelperPaths {
    public static let label = "com.stevenacz.M4FanControl.Helper"
    public static let commandFileName = "helper-command.json"
    public static let responseFileName = "helper-response.json"

    public static func appSupportDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("M4FanControl", isDirectory: true)
    }

    public static func commandFile(homeDirectory: URL) -> URL {
        appSupportDirectory(homeDirectory: homeDirectory).appendingPathComponent(commandFileName)
    }

    public static func responseFile(homeDirectory: URL) -> URL {
        appSupportDirectory(homeDirectory: homeDirectory).appendingPathComponent(responseFileName)
    }
}
