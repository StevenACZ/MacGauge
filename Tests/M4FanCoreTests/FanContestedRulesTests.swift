import Testing

@testable import M4FanCore

@Test func contestedWhenFanModeRevertedFromManual() {
    #expect(FanContestedRules.isContested(mode: 3, actualRPM: 1_200, targetRPM: 1_200))
    #expect(FanContestedRules.isContested(mode: 0, actualRPM: 1_200, targetRPM: 1_200))
}

@Test func notContestedWhenManualModeAndActualNearTarget() {
    #expect(!FanContestedRules.isContested(mode: 1, actualRPM: 1_180, targetRPM: 1_200))
}

@Test func contestedWhenActualFarExceedsTarget() {
    #expect(FanContestedRules.isContested(mode: 1, actualRPM: 4_000, targetRPM: 1_133))
}

@Test func notContestedWhenActualWithinThresholdAboveTarget() {
    #expect(!FanContestedRules.isContested(mode: 1, actualRPM: 1_500, targetRPM: 1_200))
}

@Test func notContestedWhenModeUnknownAndActualNearTarget() {
    #expect(!FanContestedRules.isContested(mode: nil, actualRPM: 1_200, targetRPM: 1_200))
}

@Test func contestedWhenModeUnknownAndActualRunaway() {
    #expect(FanContestedRules.isContested(mode: nil, actualRPM: 4_000, targetRPM: 1_133))
}
