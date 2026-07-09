import Testing

@testable import MacFanCore

private let fullRange: ClosedRange<Double> = 0...100

@Test func normalizedClampsAndRoundsEachPoint() {
    let result = CurveEditRules.normalized(
        [(temperature: -5.4, percent: 103), (temperature: 105.6, percent: -2), (temperature: 60.4, percent: 49.6)],
        temperatureRange: fullRange
    )

    #expect(result.map(\.temperature) == [0, 60, 100])
    #expect(result.map(\.percent) == [100, 50, 0])
}

@Test func normalizedKeepsEmptyAndSingleInputsAsIs() {
    #expect(CurveEditRules.normalized([], temperatureRange: fullRange).isEmpty)

    let single = CurveEditRules.normalized([(temperature: 150.7, percent: 42.4)], temperatureRange: fullRange)
    #expect(single.map(\.temperature) == [100])
    #expect(single.map(\.percent) == [42])
}

@Test func normalizedBreaksTemperatureTiesByOriginalOrder() {
    let result = CurveEditRules.normalized(
        [(temperature: 50, percent: 10), (temperature: 50, percent: 20)],
        temperatureRange: fullRange
    )
    #expect(result.map(\.temperature) == [50, 51])
    #expect(result.map(\.percent) == [10, 20])

    let reversed = CurveEditRules.normalized(
        [(temperature: 50, percent: 20), (temperature: 50, percent: 10)],
        temperatureRange: fullRange
    )
    #expect(reversed.map(\.temperature) == [50, 51])
    #expect(reversed.map(\.percent) == [20, 10])
}

@Test func normalizedCascadesSeparationBackwardsFromUpperBound() {
    let result = CurveEditRules.normalized(
        [(temperature: 99, percent: 10), (temperature: 99, percent: 20), (temperature: 99, percent: 30)],
        temperatureRange: fullRange
    )

    #expect(result.map(\.temperature) == [98, 99, 100])
    #expect(result.map(\.percent) == [10, 20, 30])
}

@Test func normalizedCascadesSeparationForwardFromLowerBound() {
    let result = CurveEditRules.normalized(
        [(temperature: 0, percent: 10), (temperature: 0, percent: 20), (temperature: 0, percent: 30)],
        temperatureRange: fullRange
    )

    #expect(result.map(\.temperature) == [0, 1, 2])
    #expect(result.map(\.percent) == [10, 20, 30])
}

@Test func normalizedFloorsAtLowerBoundWhenRangeIsOvercrowded() {
    let result = CurveEditRules.normalized(
        [
            (temperature: 2, percent: 10), (temperature: 2, percent: 20),
            (temperature: 2, percent: 30), (temperature: 2, percent: 40),
        ],
        temperatureRange: 0...2
    )

    #expect(result.map(\.temperature) == [0, 0, 1, 2])
    #expect(result.map(\.percent) == [10, 20, 30, 40])
}

@Test func normalizedLeavesWellSeparatedPointsUntouched() {
    let result = CurveEditRules.normalized(
        [(temperature: 40, percent: 40), (temperature: 60, percent: 50), (temperature: 80, percent: 80)],
        temperatureRange: fullRange
    )

    #expect(result.map(\.temperature) == [40, 60, 80])
    #expect(result.map(\.percent) == [40, 50, 80])
}

@Test func insertionPointSplitsTheWidestGap() {
    let point = CurveEditRules.insertionPoint(
        sortedPoints: [(temperature: 40, percent: 40), (temperature: 60, percent: 50), (temperature: 90, percent: 80)],
        temperatureRange: fullRange
    )

    #expect(point.temperature == 75)
    #expect(point.percent == 65)
}

@Test func insertionPointAppendsAfterLastWhenGapsAreNarrow() {
    let point = CurveEditRules.insertionPoint(
        sortedPoints: [(temperature: 60, percent: 50), (temperature: 61, percent: 51)],
        temperatureRange: fullRange
    )

    #expect(point.temperature == 71)
    #expect(point.percent == 61)
}

@Test func insertionPointAppendsAfterSinglePoint() {
    let point = CurveEditRules.insertionPoint(
        sortedPoints: [(temperature: 60, percent: 50)],
        temperatureRange: fullRange
    )

    #expect(point.temperature == 70)
    #expect(point.percent == 60)
}

@Test func insertionPointClampsTailToRangeAndPercentCap() {
    let point = CurveEditRules.insertionPoint(
        sortedPoints: [(temperature: 95, percent: 85)],
        temperatureRange: fullRange
    )

    #expect(point.temperature == 100)
    #expect(point.percent == 90)
}

@Test func insertionPointDefaultsWhenEmpty() {
    let point = CurveEditRules.insertionPoint(sortedPoints: [], temperatureRange: fullRange)

    #expect(point.temperature == 70)
    #expect(point.percent == 60)
}
