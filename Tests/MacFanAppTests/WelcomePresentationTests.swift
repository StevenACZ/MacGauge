import XCTest

@testable import MacFanApp

@MainActor
final class WelcomePresentationTests: XCTestCase {
    func testFreshInstallShowsWelcome() {
        XCTAssertTrue(WelcomeWindowController.needsFirstWelcome(persisted: nil))
        XCTAssertTrue(WelcomeWindowController.needsFirstWelcome(persisted: [:]))
    }

    func testConfiguredInstallKeepsExistingExperience() {
        XCTAssertFalse(WelcomeWindowController.needsFirstWelcome(persisted: ["controlMode": "automatic"]))
        XCTAssertFalse(WelcomeWindowController.needsFirstWelcome(persisted: ["performanceMode": "efficient"]))
        XCTAssertFalse(WelcomeWindowController.needsFirstWelcome(persisted: ["helperEverReady": true]))
    }

    func testInterruptedWelcomeResumesAfterSettingsAreWritten() {
        XCTAssertTrue(
            WelcomeWindowController.needsFirstWelcome(persisted: [
                "hasStartedWelcome": true, "performanceMode": "efficient",
            ]))
    }

    func testExplicitCompletionWinsOverInterruptedMarker() {
        XCTAssertFalse(
            WelcomeWindowController.needsFirstWelcome(persisted: [
                "hasCompletedWelcome": true, "hasStartedWelcome": true,
            ]))
    }
}
