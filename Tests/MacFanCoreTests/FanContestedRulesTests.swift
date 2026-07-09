import Testing

@testable import MacFanCore

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

@Test func contestedWhenActualFallsFarBelowTarget() {
    #expect(FanContestedRules.isContested(mode: 1, actualRPM: 1_800, targetRPM: 4_900))
}

@Test func notContestedWhenActualWithinThresholdAboveTarget() {
    #expect(!FanContestedRules.isContested(mode: 1, actualRPM: 1_500, targetRPM: 1_200))
}

@Test func notContestedWhenActualWithinThresholdBelowTarget() {
    #expect(!FanContestedRules.isContested(mode: 1, actualRPM: 1_000, targetRPM: 1_200))
}

@Test func notContestedWhenModeUnknownAndActualNearTarget() {
    #expect(!FanContestedRules.isContested(mode: nil, actualRPM: 1_200, targetRPM: 1_200))
}

@Test func contestedWhenModeUnknownAndActualRunaway() {
    #expect(FanContestedRules.isContested(mode: nil, actualRPM: 4_000, targetRPM: 1_133))
}

@Test func notContestedWhenActualOrTargetUnavailable() {
    #expect(!FanContestedRules.isContested(mode: nil, actualRPM: nil, targetRPM: nil))
    #expect(!FanContestedRules.isContested(mode: 1, actualRPM: nil, targetRPM: 1_200))
    #expect(!FanContestedRules.isContested(mode: 1, actualRPM: 1_200, targetRPM: nil))
    #expect(FanContestedRules.isContested(mode: 0, actualRPM: nil, targetRPM: nil))
}

@Test func atWriteNotContestedWhileFanStillSpinningToTarget() {
    // Instantaneous RPM lags seconds behind a write; only the Tg readback
    // matters at write time.
    #expect(!FanContestedRules.isContestedAtWrite(mode: 1, targetReadback: 4_900, requestedRPM: 4_900))
    #expect(!FanContestedRules.isContestedAtWrite(mode: 1, targetReadback: 4_899.75, requestedRPM: 4_900))
}

@Test func atWriteContestedWhenTargetReadbackMisses() {
    #expect(FanContestedRules.isContestedAtWrite(mode: 1, targetReadback: 1_200, requestedRPM: 4_900))
    #expect(FanContestedRules.isContestedAtWrite(mode: 1, targetReadback: 4_903, requestedRPM: 4_900))
}

@Test func atWriteContestedWhenModeReverted() {
    #expect(FanContestedRules.isContestedAtWrite(mode: 0, targetReadback: 4_900, requestedRPM: 4_900))
    #expect(FanContestedRules.isContestedAtWrite(mode: 3, targetReadback: nil, requestedRPM: 4_900))
}

@Test func atWriteToleratesMissingModeAndReadback() {
    #expect(!FanContestedRules.isContestedAtWrite(mode: nil, targetReadback: nil, requestedRPM: 4_900))
    #expect(!FanContestedRules.isContestedAtWrite(mode: nil, targetReadback: 4_901, requestedRPM: 4_900))
}
