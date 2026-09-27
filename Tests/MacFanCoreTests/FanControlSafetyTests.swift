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

private func fan(current: Double?, target: Double? = nil, min: Double?, max: Double?) -> FanInfo {
    FanInfo(index: 0, name: nil, currentRPM: current, minRPM: min, maxRPM: max, targetRPM: target, mode: nil, modeKey: nil)
}

@Test func fanAnimationTurnsSlowlyWhenTheMacIsCalm() {
    let rules = FanAnimationRules()

    #expect(rules.rotationDegreesPerSecond(fan: nil, cpuPercent: nil, temperatureCelsius: nil) == FanAnimationRules.restingDegreesPerSecond)
    #expect(
        rules.rotationDegreesPerSecond(fan: fan(current: 0, min: 1_000, max: 5_000), cpuPercent: 0, temperatureCelsius: 38)
            == FanAnimationRules.restingDegreesPerSecond
    )
}

@Test func fanAnimationSpeedsUpWithLoad() {
    let rules = FanAnimationRules()

    let calm = rules.rotationDegreesPerSecond(fan: nil, cpuPercent: 10, temperatureCelsius: 40)
    let busy = rules.rotationDegreesPerSecond(fan: nil, cpuPercent: 50, temperatureCelsius: 40)
    let stressed = rules.rotationDegreesPerSecond(fan: nil, cpuPercent: 100, temperatureCelsius: 40)

    #expect(calm > FanAnimationRules.restingDegreesPerSecond)
    #expect(calm < busy)
    #expect(busy < stressed)
    #expect(stressed == FanAnimationRules.maximumDegreesPerSecond)
}

@Test func fanAnimationFollowsTheBusiestSignal() {
    let rules = FanAnimationRules()

    let hotButIdle = rules.rotationDegreesPerSecond(fan: nil, cpuPercent: 5, temperatureCelsius: 90)
    let fanFlatOut = rules.rotationDegreesPerSecond(fan: fan(current: 5_000, min: 1_000, max: 5_000), cpuPercent: 5, temperatureCelsius: 40)
    let fanFromTarget = rules.rotationDegreesPerSecond(
        fan: fan(current: nil, target: 5_000, min: 1_000, max: 5_000),
        cpuPercent: nil,
        temperatureCelsius: nil
    )

    #expect(hotButIdle == FanAnimationRules.maximumDegreesPerSecond)
    #expect(fanFlatOut == FanAnimationRules.maximumDegreesPerSecond)
    #expect(fanFromTarget == FanAnimationRules.maximumDegreesPerSecond)
}

@Test func fanAnimationIgnoresUnusableFanLimits() {
    let rules = FanAnimationRules()
    let resting = FanAnimationRules.restingDegreesPerSecond

    for unusableMaximum in [nil, 0.0] {
        let fanWithoutRange = fan(current: 3_000, min: 1_000, max: unusableMaximum)
        #expect(rules.rotationDegreesPerSecond(fan: fanWithoutRange, cpuPercent: nil, temperatureCelsius: nil) == resting)
    }
    #expect(
        rules.rotationDegreesPerSecond(fan: fan(current: 5_500, min: 6_000, max: 5_000), cpuPercent: nil, temperatureCelsius: nil)
            == FanAnimationRules.maximumDegreesPerSecond
    )
    #expect(rules.rotationDegreesPerSecond(fan: nil, cpuPercent: .nan, temperatureCelsius: .infinity) == resting)
}
