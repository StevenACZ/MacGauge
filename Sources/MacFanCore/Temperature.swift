import Foundation

public struct TemperatureReading: Sendable {
    public let key: String
    public let type: String
    public let celsius: Double
}

public final class TemperatureReader {
    private let smc: SMCClient

    private let knownTemperatureKeys = TemperatureEstimator.preferredThermalMassKeys

    public init(smc: SMCClient) {
        self.smc = smc
    }

    public func readings(includeAll: Bool) throws -> [TemperatureReading] {
        let direct = knownTemperatureKeys.compactMap { try? readTemperature(key: $0) }
        guard includeAll else {
            return TemperatureEstimator.representativeReadings(from: direct)
        }

        let discovered = try discoveredReadings()
        let combined = (direct + discovered).reduce(into: [String: TemperatureReading]()) { result, reading in
            result[reading.key] = reading
        }

        let all = combined.values.sorted { $0.key < $1.key }
        return includeAll ? all : representativeCandidates(from: all)
    }

    public func representativeTemperature() throws -> Double? {
        let direct = knownTemperatureKeys.compactMap { try? readTemperature(key: $0) }
        if let directTemperature = TemperatureEstimator.representativeTemperature(from: direct) {
            return directTemperature
        }
        return TemperatureEstimator.representativeTemperature(from: try discoveredReadings())
    }

    private func discoveredReadings() throws -> [TemperatureReading] {
        try smc.enumerateKeys()
            .filter { $0.hasPrefix("T") }
            .compactMap { try? readTemperature(key: $0) }
    }

    private func representativeCandidates(from readings: [TemperatureReading]) -> [TemperatureReading] {
        let plausible = readings.filter { $0.celsius >= 20 && $0.celsius <= 110 }
        let preferredPrefixes = [
            "TC", "TG", "TPD", "TPC", "TPM", "TPS",
            "TRD", "TTD", "Ts", "Tm", "Tp", "Tf",
        ]
        let preferred = plausible.filter { reading in
            preferredPrefixes.contains { reading.key.hasPrefix($0) }
        }
        return preferred.isEmpty ? plausible : preferred
    }

    private func readTemperature(key: String) throws -> TemperatureReading? {
        let value = try smc.readKey(key)
        guard ["flt ", "sp78"].contains(value.info.typeName),
            let celsius = value.number,
            celsius.isFinite,
            celsius >= -20,
            celsius <= 130
        else {
            return nil
        }

        return TemperatureReading(key: key, type: value.info.typeName, celsius: celsius)
    }
}

enum TemperatureEstimator {
    static let preferredThermalMassKeys = [
        "TPD0", "TPD5", "TPD7", "TPDX",
        "TRD5", "TRD6", "TRDX",
        "TTD5", "TTDX",
        "Ts0E", "Ts0I", "Tsx1",
        "TfC2", "TfC4",
        "Tg05", "Tg1V",
    ]

    static func representativeTemperature(from readings: [TemperatureReading]) -> Double? {
        let plausible = readings.filter { $0.celsius.isFinite && $0.celsius >= 20 && $0.celsius <= 110 }
        guard !plausible.isEmpty else { return nil }

        let preferred = representativeReadings(from: plausible)
        if preferred.count >= 4 {
            return trimmedMean(preferred.map(\.celsius), trimFraction: 0.15)
        }

        let thermalMass = plausible.filter { isThermalMassCandidate($0.key) }
        if thermalMass.count >= 8 {
            return trimmedMean(thermalMass.map(\.celsius), trimFraction: 0.20)
        }

        return trimmedAverage(plausible.map(\.celsius))
    }

    static func representativeReadings(from readings: [TemperatureReading]) -> [TemperatureReading] {
        let preferredKeys = Set(preferredThermalMassKeys)
        return
            readings
            .filter { preferredKeys.contains($0.key) && $0.celsius.isFinite && $0.celsius >= 20 && $0.celsius <= 110 }
            .sorted { $0.key < $1.key }
    }

    static func isThermalMassCandidate(_ key: String) -> Bool {
        if key.hasPrefix("TPD")
            || key.hasPrefix("TRD")
            || key.hasPrefix("TTD")
            || key.hasPrefix("Ts")
            || key.hasPrefix("TfC")
            || key.hasPrefix("Tg")
            // M1/M2 generations expose die sensors as Tp?? keys.
            || key.hasPrefix("Tp")
        {
            return true
        }
        return ["TPCP", "TPMP", "TPSP", "TSCE", "TSCW"].contains(key)
    }

    private static func trimmedAverage(_ values: [Double]) -> Double? {
        var sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count >= 5 {
            sorted.removeFirst()
            sorted.removeLast()
        }
        return sorted.reduce(0, +) / Double(sorted.count)
    }

    private static func trimmedMean(_ values: [Double], trimFraction: Double) -> Double? {
        var sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let trimCount = min(sorted.count / 3, max(0, Int(Double(sorted.count) * trimFraction)))
        if trimCount > 0, sorted.count > trimCount * 2 {
            sorted.removeFirst(trimCount)
            sorted.removeLast(trimCount)
        }
        return sorted.reduce(0, +) / Double(sorted.count)
    }
}

public struct TemperatureSmoother: Sendable {
    private var current: Double?

    public init(initial: Double? = nil) {
        current = initial
    }

    public mutating func reset(to value: Double? = nil) {
        current = value
    }

    public mutating func update(with rawValue: Double?) -> Double? {
        guard let rawValue, rawValue.isFinite else {
            return nil
        }
        guard let currentValue = current else {
            current = rawValue
            return rawValue
        }

        let delta = rawValue - currentValue
        let maxStep = delta >= 0 ? 5.0 : 4.0
        let limited = currentValue + min(max(delta, -maxStep), maxStep)
        let alpha = delta >= 0 ? 0.45 : 0.35
        let next = currentValue + (limited - currentValue) * alpha
        current = next
        return next
    }
}
