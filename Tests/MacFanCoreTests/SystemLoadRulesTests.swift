import Testing

@testable import MacFanCore

@Test func cpuUsagePercentFromTickDeltas() {
    let previous = CPULoadTicks(user: 100, system: 50, idle: 850, nice: 0)
    let current = CPULoadTicks(user: 130, system: 60, idle: 910, nice: 0)

    let percent = SystemLoadRules.cpuUsagePercent(previous: previous, current: current)

    #expect(abs((percent ?? -1) - 40) < 0.001)
}

@Test func cpuUsagePercentIsNilWithoutElapsedTicks() {
    let sample = CPULoadTicks(user: 100, system: 50, idle: 850, nice: 0)

    #expect(SystemLoadRules.cpuUsagePercent(previous: sample, current: sample) == nil)
}

@Test func cpuUsagePercentIsNilAfterCounterReset() {
    let previous = CPULoadTicks(user: 100, system: 50, idle: 850, nice: 0)
    let current = CPULoadTicks(user: 10, system: 5, idle: 85, nice: 0)

    #expect(SystemLoadRules.cpuUsagePercent(previous: previous, current: current) == nil)
}

@Test func memoryUsedPercentFromBytes() {
    let percent = SystemLoadRules.memoryUsedPercent(usedBytes: 12_000, totalBytes: 16_000)

    #expect(abs((percent ?? -1) - 75) < 0.001)
}

@Test func memoryUsedPercentClampsAndRejectsZeroTotal() {
    #expect(SystemLoadRules.memoryUsedPercent(usedBytes: 1, totalBytes: 0) == nil)
    #expect(SystemLoadRules.memoryUsedPercent(usedBytes: 20, totalBytes: 10) == 100)
}

@Test func byteRateFromCounterDeltas() {
    let rate = SystemLoadRules.byteRate(previousBytes: 1_000, currentBytes: 3_000, elapsedSeconds: 2)

    #expect(abs((rate ?? -1) - 1_000) < 0.001)
}

@Test func byteRateIsNilOnResetOrZeroElapsed() {
    #expect(SystemLoadRules.byteRate(previousBytes: 3_000, currentBytes: 1_000, elapsedSeconds: 2) == nil)
    #expect(SystemLoadRules.byteRate(previousBytes: 1_000, currentBytes: 3_000, elapsedSeconds: 0) == nil)
}

@Test func memoryPressurePrefersKernelLevelOverPercent() {
    #expect(SystemLoadRules.memoryPressureLevel(sysctlLevel: 1, usedPercent: 95) == .normal)
    #expect(SystemLoadRules.memoryPressureLevel(sysctlLevel: 2, usedPercent: 10) == .elevated)
    #expect(SystemLoadRules.memoryPressureLevel(sysctlLevel: 4, usedPercent: 10) == .high)
}

@Test func memoryPressureFallsBackToPercentWithoutKernelLevel() {
    #expect(SystemLoadRules.memoryPressureLevel(sysctlLevel: nil, usedPercent: 50) == .normal)
    #expect(SystemLoadRules.memoryPressureLevel(sysctlLevel: 0, usedPercent: 80) == .elevated)
    #expect(SystemLoadRules.memoryPressureLevel(sysctlLevel: nil, usedPercent: 95) == .high)
    #expect(SystemLoadRules.memoryPressureLevel(sysctlLevel: nil, usedPercent: nil) == .normal)
}
