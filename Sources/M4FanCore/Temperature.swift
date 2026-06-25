import Foundation

public struct TemperatureReading: Sendable {
    public let key: String
    public let type: String
    public let celsius: Double
}

public final class TemperatureReader {
    private let smc: SMCClient

    private let knownTemperatureKeys = [
        "TC0F", "TC0D", "TC0P", "TC0H",
        "TG0D", "TG0P", "TG0H",
        "TA0P", "TA1P",
        "TB0T", "TB1T", "TB2T", "TB3T",
        "TM0P", "TM0S",
        "Ts0P", "Tm0P", "Tp0P",
        "Th0H", "Th1H", "Th2H"
    ]

    public init(smc: SMCClient) {
        self.smc = smc
    }

    public func readings(includeAll: Bool) throws -> [TemperatureReading] {
        let direct = knownTemperatureKeys.compactMap { try? readTemperature(key: $0) }
        guard includeAll else {
            return representativeCandidates(from: direct)
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
        var candidates = representativeCandidates(from: direct)
        if candidates.isEmpty {
            candidates = representativeCandidates(from: try discoveredReadings())
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.map(\.celsius).reduce(0, +) / Double(candidates.count)
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
            "TRD", "TTD", "Ts", "Tm", "Tpx", "Tf"
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
