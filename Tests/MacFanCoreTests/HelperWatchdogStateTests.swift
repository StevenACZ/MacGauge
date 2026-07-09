import Foundation
import Testing

@testable import MacFanCore

private let timeout = HelperWatchdogState.silenceTimeoutSeconds

@Test func startsDisarmedAndNeverFires() {
    let state = HelperWatchdogState(nowUptime: 100)
    #expect(!state.isArmed)
    #expect(!state.shouldRestoreAutomatic(nowUptime: 100 + timeout * 10))
}

@Test func armedStateFiresOnlyAfterFullSilenceWindow() {
    var state = HelperWatchdogState(nowUptime: 100)
    state.armForManualControl(nowUptime: 100)
    #expect(state.isArmed)
    #expect(!state.shouldRestoreAutomatic(nowUptime: 100))
    #expect(!state.shouldRestoreAutomatic(nowUptime: 100 + timeout - 1))
    #expect(state.shouldRestoreAutomatic(nowUptime: 100 + timeout))
    #expect(state.shouldRestoreAutomatic(nowUptime: 100 + timeout + 1))
}

@Test func clientActivityResetsTheSilenceWindow() {
    var state = HelperWatchdogState(nowUptime: 0)
    state.armForManualControl(nowUptime: 0)
    state.recordClientActivity(nowUptime: timeout - 1)
    #expect(!state.shouldRestoreAutomatic(nowUptime: timeout))
    #expect(!state.shouldRestoreAutomatic(nowUptime: timeout - 1 + timeout - 1))
    #expect(state.shouldRestoreAutomatic(nowUptime: timeout - 1 + timeout))
}

@Test func activityAloneNeverArms() {
    var state = HelperWatchdogState(nowUptime: 0)
    state.recordClientActivity(nowUptime: 10)
    #expect(!state.isArmed)
    #expect(!state.shouldRestoreAutomatic(nowUptime: timeout * 10))
}

@Test func disarmStopsAnOverdueWatchdog() {
    var state = HelperWatchdogState(nowUptime: 0)
    state.armForManualControl(nowUptime: 0)
    state.disarm()
    #expect(!state.isArmed)
    #expect(!state.shouldRestoreAutomatic(nowUptime: timeout * 2))
}

@Test func rearmingAfterDisarmStartsAFreshWindow() {
    var state = HelperWatchdogState(nowUptime: 0)
    state.armForManualControl(nowUptime: 0)
    state.disarm()
    state.armForManualControl(nowUptime: timeout * 2)
    #expect(!state.shouldRestoreAutomatic(nowUptime: timeout * 2 + timeout - 1))
    #expect(state.shouldRestoreAutomatic(nowUptime: timeout * 3))
}
