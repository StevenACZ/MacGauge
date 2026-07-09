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

private func makeFan(index: Int = 0, minRPM: Double?, maxRPM: Double?) -> FanInfo {
    FanInfo(
        index: index,
        name: nil,
        currentRPM: nil,
        minRPM: minRPM,
        maxRPM: maxRPM,
        targetRPM: nil,
        mode: nil,
        modeKey: nil
    )
}

@Test func percentToRPMRespectsReportedMinimum() throws {
    let rules = FanTargetRules()

    #expect(try rules.targetRPM(forPercent: 20, fan: testFan) == 1_000)
    #expect(try rules.targetRPM(forPercent: 45, fan: testFan) == 2_205)
}

@Test func zeroPercentCanStillMapToZeroForExplicitDangerousFlows() throws {
    let rules = FanTargetRules()

    #expect(try rules.targetRPM(forPercent: 0, fan: testFan) == 0)
}

@Test func percentToRPMThrowsWithoutUsableMaximum() {
    let rules = FanTargetRules()

    #expect(throws: MacFanError.self) {
        _ = try rules.targetRPM(forPercent: 50, fan: makeFan(minRPM: 1_000, maxRPM: nil))
    }
    #expect(throws: MacFanError.self) {
        _ = try rules.targetRPM(forPercent: 50, fan: makeFan(minRPM: 1_000, maxRPM: 0))
    }
}

@Test func percentToRPMClampsPercentAndHonorsInvertedLimits() throws {
    let rules = FanTargetRules()

    #expect(try rules.targetRPM(forPercent: 150, fan: testFan) == 4_900)
    #expect(try rules.targetRPM(forPercent: -50, fan: testFan) == 0)
    // Inverted min/max still yields the reported minimum, above the maximum.
    #expect(try rules.targetRPM(forPercent: 50, fan: makeFan(minRPM: 5_000, maxRPM: 4_000)) == 5_000)
}

@Test func minimumPercentFloorFallsBackWithoutUsableFans() {
    let rules = FanTargetRules()

    #expect(rules.minimumPercentFloor(fans: [], dangerousUnlocked: false) == 20)
    #expect(rules.minimumPercentFloor(fans: [], dangerousUnlocked: true) == 0)
    #expect(rules.minimumPercentFloor(fans: [makeFan(minRPM: 1_000, maxRPM: nil)], dangerousUnlocked: false) == 20)
}

@Test func minimumPercentFloorUsesSingleFanFloor() {
    let rules = FanTargetRules()
    let floor = 1_000.0 / 4_900.0 * 100

    #expect(rules.minimumPercentFloor(fans: [testFan], dangerousUnlocked: false) == floor)
    #expect(rules.minimumPercentFloor(fans: [testFan], dangerousUnlocked: true) == floor)
}

@Test func minimumPercentFloorPicksStrictestFan() {
    let rules = FanTargetRules()
    let fans = [
        testFan,
        makeFan(index: 1, minRPM: 2_000, maxRPM: 4_000),
        makeFan(index: 2, minRPM: 1_000, maxRPM: nil),
    ]

    #expect(rules.minimumPercentFloor(fans: fans, dangerousUnlocked: false) == 50)
    #expect(rules.minimumPercentFloor(fans: fans, dangerousUnlocked: true) == 50)
}

@Test func minimumPercentFloorKeepsGuardRailAboveTinyFloors() {
    let rules = FanTargetRules()
    let fans = [makeFan(minRPM: 100, maxRPM: 4_900)]

    #expect(rules.minimumPercentFloor(fans: fans, dangerousUnlocked: false) == 20)
    #expect(rules.minimumPercentFloor(fans: fans, dangerousUnlocked: true) == 100.0 / 4_900.0 * 100)
}

@Test func manualPercentRangeBoundsFollowUnlockState() {
    let rules = FanTargetRules()
    let floor = 1_000.0 / 4_900.0 * 100

    #expect(rules.manualPercentRange(fans: [], dangerousUnlocked: false) == 20...90)
    #expect(rules.manualPercentRange(fans: [], dangerousUnlocked: true) == 0...100)
    #expect(rules.manualPercentRange(fans: [testFan], dangerousUnlocked: false) == floor...90)
    #expect(rules.manualPercentRange(fans: [testFan], dangerousUnlocked: true) == floor...100)
}

@Test func manualPercentRangeNeverInvertsWhenFloorExceedsCeiling() {
    let rules = FanTargetRules()
    let fans = [makeFan(minRPM: 4_800, maxRPM: 4_900)]
    let floor = 4_800.0 / 4_900.0 * 100

    #expect(rules.manualPercentRange(fans: fans, dangerousUnlocked: false) == floor...floor)
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

@Test func helperSafetyRpmCheckIsInertWithoutReportedLimits() {
    let safety = HelperCommandSafety()
    let fan = makeFan(minRPM: nil, maxRPM: nil)

    #expect(throws: Never.self) {
        try safety.validate(rpm: 0, fan: fan, percent: 0, allowDangerous: false)
    }
    #expect(throws: Never.self) {
        try safety.validate(rpm: 100_000, fan: fan, percent: 100, allowDangerous: false)
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

@Test func fanAnimationRestsWithoutUsableMaximum() {
    let rules = FanAnimationRules()

    #expect(rules.rotationDegreesPerSecond(currentRPM: 3_000, targetRPM: nil, minRPM: 1_000, maxRPM: nil) == nil)
    #expect(rules.rotationDegreesPerSecond(currentRPM: 3_000, targetRPM: nil, minRPM: 1_000, maxRPM: 0) == nil)
}

@Test func fanAnimationToleratesInvertedLimits() {
    let rules = FanAnimationRules()

    #expect(rules.rotationDegreesPerSecond(currentRPM: 5_000, targetRPM: nil, minRPM: 6_000, maxRPM: 5_000) == nil)
    #expect(rules.rotationDegreesPerSecond(currentRPM: 5_500, targetRPM: nil, minRPM: 6_000, maxRPM: 5_000) == 400)
}

@Test func fanAnimationRestsAtOrBelowNormalizedThreshold() {
    let rules = FanAnimationRules()

    #expect(rules.rotationDegreesPerSecond(currentRPM: 200, targetRPM: nil, minRPM: nil, maxRPM: 5_000) == nil)
    #expect(rules.rotationDegreesPerSecond(currentRPM: 201, targetRPM: nil, minRPM: nil, maxRPM: 5_000) != nil)
}
