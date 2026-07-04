import Testing

@testable import MacFanCore

private let testFan = FanInfo(
    index: 0,
    name: "Test Fan",
    currentRPM: nil,
    minRPM: 1_000,
    maxRPM: 4_900,
    targetRPM: nil,
    mode: nil,
    modeKey: nil
)

@Test func percentToRPMRespectsReportedMinimum() throws {
    let rules = FanTargetRules()

    #expect(try rules.targetRPM(forPercent: 20, fan: testFan) == 1_000)
    #expect(try rules.targetRPM(forPercent: 45, fan: testFan) == 2_205)
}

@Test func zeroPercentCanStillMapToZeroForExplicitDangerousFlows() throws {
    let rules = FanTargetRules()

    #expect(try rules.targetRPM(forPercent: 0, fan: testFan) == 0)
}

@Test func helperSafetyRejectsZeroWithoutExplicitDangerousUnlock() {
    let safety = HelperCommandSafety()

    #expect(throws: Error.self) {
        try safety.validate(percent: 0, allowDangerous: true, allowZero: false)
    }
    #expect(throws: Error.self) {
        try safety.validate(percent: 0, allowDangerous: false, allowZero: true)
    }
    #expect(throws: Never.self) {
        try safety.validate(percent: 0, allowDangerous: true, allowZero: true)
    }
}

@Test func helperSafetyRequiresDangerousUnlockForEdgePercents() {
    let safety = HelperCommandSafety()

    #expect(throws: Error.self) {
        try safety.validate(percent: 10, allowDangerous: false, allowZero: false)
    }
    #expect(throws: Error.self) {
        try safety.validate(percent: 95, allowDangerous: false, allowZero: false)
    }
    #expect(throws: Never.self) {
        try safety.validate(percent: 45, allowDangerous: false, allowZero: false)
    }
    #expect(throws: Never.self) {
        try safety.validate(percent: 95, allowDangerous: true, allowZero: false)
    }
}

@Test func helperSafetyRejectsInvalidPercentValues() {
    let safety = HelperCommandSafety()

    #expect(throws: Error.self) {
        try safety.validate(percent: -.infinity, allowDangerous: true, allowZero: true)
    }
    #expect(throws: Error.self) {
        try safety.validate(percent: 101, allowDangerous: true, allowZero: true)
    }
    #expect(throws: Error.self) {
        try safety.validate(percent: .nan, allowDangerous: true, allowZero: true)
    }
}

@Test func helperSafetyRejectsRpmOutsideReportedLimitsWithoutUnlock() {
    let safety = HelperCommandSafety()

    #expect(throws: Error.self) {
        try safety.validate(rpm: 500, fan: testFan, percent: 20, allowDangerous: false)
    }
    #expect(throws: Error.self) {
        try safety.validate(rpm: 5_500, fan: testFan, percent: 100, allowDangerous: false)
    }
    #expect(throws: Never.self) {
        try safety.validate(rpm: 5_500, fan: testFan, percent: 100, allowDangerous: true)
    }
}

@Test func fanAnimationSpeedFollowsEffectiveRPM() {
    let rules = FanAnimationRules()

    #expect(rules.rotationDegreesPerSecond(currentRPM: 1_000, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000) == nil)

    let low = rules.rotationDegreesPerSecond(currentRPM: 1_500, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000)
    let mid = rules.rotationDegreesPerSecond(currentRPM: 3_000, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000)
    let high = rules.rotationDegreesPerSecond(currentRPM: 5_000, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000)

    #expect(low != nil && mid != nil && high != nil)
    if let low, let mid, let high {
        #expect(low > 0)
        #expect(low < mid)
        #expect(mid < high)
        #expect(high == 400)
    }
}

@Test func fanAnimationUsesTargetRPMWhenCurrentRPMIsUnavailable() {
    let rules = FanAnimationRules()

    #expect(rules.rotationDegreesPerSecond(currentRPM: nil, targetRPM: 5_000, minRPM: 1_000, maxRPM: 5_000) == 400)
}
