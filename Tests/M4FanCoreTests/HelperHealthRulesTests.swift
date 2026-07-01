import Foundation
import Testing

@testable import M4FanCore

private let rules = HelperHealthRules()

@Test func unregisteredDaemonNeedsAuthorization() {
    #expect(
        rules.decision(status: .notRegistered, ping: nil, consecutivePingFailures: 0, canRepair: true)
            == .markNeedsAuthorization)
    #expect(
        rules.decision(status: .notFound, ping: nil, consecutivePingFailures: 0, canRepair: true)
            == .markNeedsAuthorization)
}

@Test func approvalPendingIsSurfacedWithoutRepair() {
    #expect(
        rules.decision(status: .requiresApproval, ping: nil, consecutivePingFailures: 0, canRepair: true)
            == .markNeedsApproval)
}

@Test func healthyPingMarksReady() {
    #expect(
        rules.decision(status: .enabled, ping: .ready, consecutivePingFailures: 0, canRepair: false)
            == .markReady)
}

@Test func staleDaemonRestartsWhenRepairAllowed() {
    #expect(
        rules.decision(status: .enabled, ping: .stale, consecutivePingFailures: 0, canRepair: true)
            == .restartDaemon)
}

@Test func staleDaemonDegradesDuringRepairCooldown() {
    #expect(
        rules.decision(status: .enabled, ping: .stale, consecutivePingFailures: 0, canRepair: false)
            == .markDegraded)
}

@Test func transientPingFailureWaitsBeforeRepair() {
    #expect(
        rules.decision(status: .enabled, ping: .failed, consecutivePingFailures: 1, canRepair: true)
            == .waitForNextTick)
}

@Test func persistentPingFailureReregistersWhenRepairAllowed() {
    #expect(
        rules.decision(
            status: .enabled,
            ping: .failed,
            consecutivePingFailures: HelperHealthRules.pingFailureStrikeLimit,
            canRepair: true
        ) == .reregisterDaemon)
}

@Test func persistentPingFailureDegradesDuringRepairCooldown() {
    #expect(
        rules.decision(status: .enabled, ping: .failed, consecutivePingFailures: 5, canRepair: false)
            == .markDegraded)
}

@Test func missingPingWaitsForNextTick() {
    #expect(
        rules.decision(status: .enabled, ping: nil, consecutivePingFailures: 0, canRepair: true)
            == .waitForNextTick)
}

@Test func heartbeatSlowsDownWhenReady() {
    #expect(rules.heartbeatInterval(isReady: true) > rules.heartbeatInterval(isReady: false))
}
