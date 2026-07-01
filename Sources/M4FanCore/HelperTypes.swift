import Foundation

public enum HelperAction: String, Codable, Sendable {
    case ping
    case setPercent
    case automatic
    case removeLegacyHelper
    case shutdown
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
    public static let currentProtocolVersion = 3

    public var id: String
    public var ok: Bool
    public var message: String
    public var completedAt: Date
    public var protocolVersion: Int?
    public var helperVersion: String?
    public var actualRPM: Double?
    public var mode: Int?
    public var contested: Bool?

    public init(
        id: String,
        ok: Bool,
        message: String,
        completedAt: Date = Date(),
        protocolVersion: Int? = HelperResponse.currentProtocolVersion,
        helperVersion: String? = nil,
        actualRPM: Double? = nil,
        mode: Int? = nil,
        contested: Bool? = nil
    ) {
        self.id = id
        self.ok = ok
        self.message = message
        self.completedAt = completedAt
        self.protocolVersion = protocolVersion
        self.helperVersion = helperVersion
        self.actualRPM = actualRPM
        self.mode = mode
        self.contested = contested
    }
}
