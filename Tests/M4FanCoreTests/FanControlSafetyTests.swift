import Testing
@testable import M4FanCore

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

@Test func fanAnimationIntervalsFollowEffectiveRPM() {
    let rules = FanAnimationRules()

    #expect(rules.animationInterval(currentRPM: 1_000, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000) == nil)
    #expect(rules.animationInterval(currentRPM: 1_500, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000) == 2.4)
    #expect(rules.animationInterval(currentRPM: 3_000, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000) == 0.45)
    #expect(rules.animationInterval(currentRPM: 5_000, targetRPM: nil, minRPM: 1_000, maxRPM: 5_000) == 0.12)
}

@Test func fanAnimationUsesTargetRPMWhenCurrentRPMIsUnavailable() {
    let rules = FanAnimationRules()

    #expect(rules.animationInterval(currentRPM: nil, targetRPM: 5_000, minRPM: 1_000, maxRPM: 5_000) == 0.12)
}
