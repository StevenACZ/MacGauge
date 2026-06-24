import Testing
@testable import M4FanCore

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
    #expect(throws: M4FanError.self) {
        _ = try FanCurve(points: [(40, 40)])
    }
}
