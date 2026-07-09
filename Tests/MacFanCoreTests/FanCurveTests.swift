import Testing

@testable import MacFanCore

@Test func interpolatesBetweenCurvePoints() throws {
    let curve = try FanCurve(points: [(40, 40), (60, 50), (80, 80)])

    #expect(curve.percent(for: 40) == 40)
    #expect(curve.percent(for: 50) == 45)
    #expect(curve.percent(for: 70) == 65)
}

@Test func clampsOutsideCurvePointRange() throws {
    let curve = try FanCurve(points: [(40, 40), (60, 50), (80, 80)])

    #expect(curve.percent(for: 20) == 40)
    #expect(curve.percent(for: 100) == 80)
}

@Test func rejectsInvalidCurvePointCount() {
    #expect(throws: MacFanError.self) {
        _ = try FanCurve(points: [(40, 40)])
    }
}

@Test func parsesDefaultCurveWhenRawValueIsNil() throws {
    let curve = try FanCurve.parse(nil)

    #expect(curve.points.count == 2)
    #expect(curve.percent(for: 40) == 40)
    #expect(curve.percent(for: 60) == 50)
}

@Test func parsesCommaSeparatedCurvePoints() throws {
    let curve = try FanCurve.parse("80:80,40:40,60:50")

    #expect(curve.points.map(\.temperature) == [40, 60, 80])
    #expect(curve.percent(for: 70) == 65)
}

@Test func rejectsInvalidCurvePointSyntax() {
    #expect(throws: MacFanError.self) {
        _ = try FanCurve.parse("40:40,bad")
    }
}

@Test func rejectsDuplicateCurvePointTemperatures() {
    #expect(throws: MacFanError.self) {
        _ = try FanCurve(points: [(40, 40), (40, 55), (70, 80)])
    }
}

@Test func rejectsNonFiniteCurvePoints() {
    #expect(throws: MacFanError.self) {
        _ = try FanCurve(points: [(40, 40), (.infinity, 50)])
    }
    #expect(throws: MacFanError.self) {
        _ = try FanCurve(points: [(-.infinity, 40), (60, 50)])
    }
    #expect(throws: MacFanError.self) {
        _ = try FanCurve(points: [(40, .nan), (60, 50)])
    }
    #expect(throws: MacFanError.self) {
        _ = try FanCurve.parse("inf:50,60:50")
    }
}

@Test func parsesCurvePointsWithSurroundingWhitespace() throws {
    let curve = try FanCurve.parse("40:40, 60:50")

    #expect(curve.points.map(\.temperature) == [40, 60])
    #expect(curve.percent(for: 50) == 45)
}

@Test func nearDuplicateTemperaturesFollowEpsilonBoundary() throws {
    #expect(throws: MacFanError.self) {
        _ = try FanCurve(points: [(40, 40), (40.0005, 50)])
    }

    let curve = try FanCurve(points: [(40, 40), (40.002, 50)])
    #expect(curve.points.count == 2)
}

@Test func extremeTemperaturesClampToCurveEndpoints() throws {
    let curve = try FanCurve(points: [(40, 40), (60, 50)])

    #expect(curve.percent(for: -1e9) == 40)
    #expect(curve.percent(for: 1e9) == 50)
    #expect(curve.percent(for: -.infinity) == 40)
    #expect(curve.percent(for: .infinity) == 50)
}
