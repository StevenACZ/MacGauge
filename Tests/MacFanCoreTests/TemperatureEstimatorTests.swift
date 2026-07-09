import Testing

@testable import MacFanCore

@Test func temperatureEstimatorUsesPreferredThermalMassSensors() {
    let result = TemperatureEstimator.representativeTemperature(from: [
        TemperatureReading(key: "TVS0", type: "flt ", celsius: 40),
        TemperatureReading(key: "TCMz", type: "flt ", celsius: 102),
        TemperatureReading(key: "TPD0", type: "flt ", celsius: 65),
        TemperatureReading(key: "TPD5", type: "flt ", celsius: 66),
        TemperatureReading(key: "TRD5", type: "flt ", celsius: 60),
        TemperatureReading(key: "TTD5", type: "flt ", celsius: 62),
        TemperatureReading(key: "Ts0E", type: "flt ", celsius: 63),
        TemperatureReading(key: "TfC2", type: "flt ", celsius: 64),
        TemperatureReading(key: "Tg05", type: "flt ", celsius: 68),
    ])

    #expect(result == 64)
}

@Test func temperatureEstimatorFallsBackToThermalMassFamilies() {
    let result = TemperatureEstimator.representativeTemperature(from: [
        TemperatureReading(key: "TVS0", type: "flt ", celsius: 40),
        TemperatureReading(key: "TPD1", type: "flt ", celsius: 70),
        TemperatureReading(key: "TRD1", type: "flt ", celsius: 72),
        TemperatureReading(key: "TTD1", type: "flt ", celsius: 71),
        TemperatureReading(key: "Ts00", type: "flt ", celsius: 73),
        TemperatureReading(key: "TfC0", type: "flt ", celsius: 74),
        TemperatureReading(key: "Tg04", type: "flt ", celsius: 90),
        TemperatureReading(key: "TPCP", type: "flt ", celsius: 69),
        TemperatureReading(key: "TSCW", type: "flt ", celsius: 70),
        TemperatureReading(key: "TPSP", type: "flt ", celsius: 70),
    ])

    #expect(abs((result ?? 0) - 71.4285) < 0.001)
}

@Test func temperatureEstimatorFallsBackToTrimmedAverageWithoutPrimaryGroups() {
    let result = TemperatureEstimator.representativeTemperature(from: [
        TemperatureReading(key: "TA0P", type: "flt ", celsius: 30),
        TemperatureReading(key: "TA1P", type: "flt ", celsius: 40),
        TemperatureReading(key: "TB0T", type: "flt ", celsius: 50),
        TemperatureReading(key: "TB1T", type: "flt ", celsius: 60),
        TemperatureReading(key: "TB2T", type: "flt ", celsius: 110),
    ])

    #expect(result == 50)
}

@Test func temperatureEstimatorIdentifiesThermalMassFamilies() {
    #expect(TemperatureEstimator.isThermalMassCandidate("TPD1"))
    #expect(TemperatureEstimator.isThermalMassCandidate("TRD1"))
    #expect(TemperatureEstimator.isThermalMassCandidate("TTD1"))
    #expect(TemperatureEstimator.isThermalMassCandidate("Ts00"))
    #expect(TemperatureEstimator.isThermalMassCandidate("TfC0"))
    #expect(TemperatureEstimator.isThermalMassCandidate("Tg04"))
    #expect(!TemperatureEstimator.isThermalMassCandidate("TVS0"))
    #expect(!TemperatureEstimator.isThermalMassCandidate("TW0P"))
}

@Test func temperatureSmootherLimitsSingleTickSpikes() {
    var smoother = TemperatureSmoother(initial: 60)

    #expect(abs((smoother.update(with: 90) ?? 0) - 62.25) < 0.001)
    #expect(abs((smoother.update(with: 90) ?? 0) - 64.5) < 0.001)
}

@Test func temperatureSmootherCoolsDownGradually() {
    var smoother = TemperatureSmoother(initial: 70)

    #expect(abs((smoother.update(with: 40) ?? 0) - 68.6) < 0.001)
}

@Test func temperatureSmootherIgnoresMissingAndNonFiniteReadings() {
    var smoother = TemperatureSmoother(initial: 60)

    #expect(smoother.update(with: nil) == nil)
    #expect(smoother.update(with: .nan) == nil)
    #expect(smoother.update(with: .infinity) == nil)
    // Dropped samples must not disturb the smoothed state.
    #expect(smoother.update(with: 60) == 60)
}

@Test func temperatureSmootherResetRestartsFromNextReading() {
    var smoother = TemperatureSmoother(initial: 60)

    smoother.reset()
    #expect(smoother.update(with: 90) == 90)

    smoother.reset(to: 40)
    #expect(abs((smoother.update(with: 90) ?? 0) - 42.25) < 0.001)
}
