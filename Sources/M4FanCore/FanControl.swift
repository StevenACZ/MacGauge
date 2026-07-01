import Foundation

public struct FanInfo: Sendable {
    public let index: Int
    public let name: String?
    public let currentRPM: Double?
    public let minRPM: Double?
    public let maxRPM: Double?
    public let targetRPM: Double?
    public let mode: Int?
    public let modeKey: String?
}

public enum FanWriteStrategy: String, Sendable {
    case direct
    case ftstUnlock
}

public struct FanWriteResult: Sendable {
    public let strategy: FanWriteStrategy
    public let actualRPM: Double?
    public let mode: Int?
    public let contested: Bool

    public init(strategy: FanWriteStrategy, actualRPM: Double?, mode: Int?, contested: Bool) {
        self.strategy = strategy
        self.actualRPM = actualRPM
        self.mode = mode
        self.contested = contested
    }
}

public enum FanContestedRules {
    public static let manualModeValue = 1
    public static let contestedRPMThreshold = 400.0

    public static func isContested(mode: Int?, actualRPM: Double?, targetRPM: Double?) -> Bool {
        let modeReverted = mode.map { $0 != manualModeValue } ?? false
        let targetMissed =
            actualRPM.flatMap { actual in
                targetRPM.map { target in abs(actual - target) > contestedRPMThreshold }
            } ?? false
        return modeReverted || targetMissed
    }
}

public struct FanTargetRules: Sendable {
    public init() {}

    public func targetRPM(forPercent percent: Double, fan: FanInfo) throws -> Double {
        guard let maxRPM = fan.maxRPM, maxRPM > 0 else {
            throw M4FanError("Cannot convert percent to RPM because F\(fan.index)Mx is unavailable.")
        }
        let boundedPercent = max(0, min(100, percent))
        let requestedRPM = boundedPercent / 100.0 * maxRPM
        guard let minRPM = fan.minRPM, minRPM > 0, boundedPercent > 0 else {
            return requestedRPM
        }
        return max(minRPM, requestedRPM)
    }
}

public final class FanController {
    private let smc: SMCClient
    private let targetRules = FanTargetRules()

    public init(smc: SMCClient) {
        self.smc = smc
    }

    public func fanCount() throws -> Int {
        guard let count = try smc.readKey("FNum").number else { return 0 }
        return max(0, Int(count))
    }

    public func allFans() throws -> [FanInfo] {
        let count = try fanCount()
        return try (0..<count).map { try fanInfo(index: $0) }
    }

    public func fanInfo(index: Int) throws -> FanInfo {
        let mode = try? readMode(index: index)
        return FanInfo(
            index: index,
            name: try? fanName(index: index),
            currentRPM: try? readNumber("F\(index)Ac"),
            minRPM: try? readNumber("F\(index)Mn"),
            maxRPM: try? readNumber("F\(index)Mx"),
            targetRPM: try? readNumber("F\(index)Tg"),
            mode: mode?.mode,
            modeKey: mode?.key
        )
    }

    public func readMode(index: Int) throws -> (key: String, mode: Int) {
        let candidates = ["F\(index)Md", "F\(index)md"]
        for key in candidates {
            if let value = try? smc.readKey(key), let number = value.number {
                return (key, Int(number))
            }
        }
        throw M4FanError("No readable fan mode key found for fan \(index). Tried \(candidates.joined(separator: ", ")).")
    }

    public func forceTestAvailable() -> Bool {
        smc.keyExists("Ftst")
    }

    public func forceTestValue() -> Int? {
        guard let value = try? smc.readKey("Ftst").number else { return nil }
        return Int(value)
    }

    public func setTargetRPM(index: Int, rpm: Double) throws -> FanWriteStrategy {
        let strategy = try enableManualMode(index: index)
        try writeTarget(index: index, rpm: rpm)
        return strategy
    }

    public func setTargetRPMVerified(index: Int, rpm: Double) throws -> FanWriteResult {
        var strategy = try enableManualMode(index: index)
        try writeTarget(index: index, rpm: rpm)

        var mode = (try? readMode(index: index))?.mode
        var actual = try? readNumber("F\(index)Ac")

        let maxReassertions = 3
        var attempts = 0
        while mode != FanContestedRules.manualModeValue, attempts < maxReassertions {
            Thread.sleep(forTimeInterval: 0.08)
            strategy = (try? enableManualMode(index: index)) ?? strategy
            try writeTarget(index: index, rpm: rpm)
            mode = (try? readMode(index: index))?.mode
            actual = try? readNumber("F\(index)Ac")
            attempts += 1
        }

        let contested = FanContestedRules.isContested(mode: mode, actualRPM: actual, targetRPM: rpm)
        return FanWriteResult(strategy: strategy, actualRPM: actual, mode: mode, contested: contested)
    }

    private func writeTarget(index: Int, rpm: Double) throws {
        let targetKey = "F\(index)Tg"
        let info = try smc.keyInfo(targetKey)
        try smc.writeKey(targetKey, bytes: SMCCodec.encodeNumber(rpm, for: info))
    }

    public func returnToAutomatic(index: Int) throws {
        let mode = try readMode(index: index)
        let info = try smc.keyInfo(mode.key)
        try smc.writeKey(mode.key, bytes: SMCCodec.encodeNumber(0, for: info))
    }

    public func resetForceTestIfAvailable() throws {
        guard smc.keyExists("Ftst") else { return }
        let info = try smc.keyInfo("Ftst")
        try smc.writeKey("Ftst", bytes: SMCCodec.encodeNumber(0, for: info))
    }

    public func targetRPM(forPercent percent: Double, fan: FanInfo) throws -> Double {
        try targetRules.targetRPM(forPercent: percent, fan: fan)
    }

    private func enableManualMode(index: Int) throws -> FanWriteStrategy {
        let mode = try readMode(index: index)
        let modeInfo = try smc.keyInfo(mode.key)

        do {
            try smc.writeKey(mode.key, bytes: SMCCodec.encodeNumber(1, for: modeInfo))
            return .direct
        } catch {
            guard smc.keyExists("Ftst") else { throw error }
        }

        let ftstInfo = try smc.keyInfo("Ftst")
        try smc.writeKey("Ftst", bytes: SMCCodec.encodeNumber(1, for: ftstInfo))

        let deadline = Date().addingTimeInterval(10)
        var lastError: Error?
        while Date() < deadline {
            do {
                try smc.writeKey(mode.key, bytes: SMCCodec.encodeNumber(1, for: modeInfo))
                return .ftstUnlock
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        throw lastError ?? M4FanError("Timed out waiting for thermalmonitord to yield fan \(index).")
    }

    private func fanName(index: Int) throws -> String? {
        let value = try smc.readKey("F\(index)ID")
        guard value.bytes.count >= 16 else { return nil }
        let nameBytes = value.bytes.dropFirst(4).prefix(12).filter { $0 >= 32 && $0 < 127 }
        let name = String(bytes: nameBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    private func readNumber(_ key: String) throws -> Double? {
        try smc.readKey(key).number
    }
}
