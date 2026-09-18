import AppKit
import Sparkle
import XCTest

@testable import MacFanApp

/// Phase-machine coverage for the Sparkle-backed update manager: the driver
/// event handlers are exercised directly, no Sparkle session involved.
@MainActor
final class UpdateManagerTests: XCTestCase {

    private var manager: UpdateManager!
    private var savedAutoCheckDefault: Any?

    override func setUp() {
        super.setUp()
        savedAutoCheckDefault = UserDefaults.standard.object(forKey: UpdateManager.autoCheckDefaultsKey)
        manager = UpdateManager()
    }

    override func tearDown() {
        manager.stopBackgroundDiscovery()
        manager = nil
        if let savedAutoCheckDefault {
            UserDefaults.standard.set(savedAutoCheckDefault, forKey: UpdateManager.autoCheckDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: UpdateManager.autoCheckDefaultsKey)
        }
        savedAutoCheckDefault = nil
        super.tearDown()
    }

    // MARK: - Scheduled check surfaces a pending row

    func testScheduledFoundUpdateIsDismissedAndSurfaced() {
        let choice = manager.handleUpdateFound(
            version: "9.9.9",
            releasePage: URL(string: "https://example.com/release"),
            informationOnly: false,
            stage: .notDownloaded
        )

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertEqual(manager.releasePageURL?.absoluteString, "https://example.com/release")
    }

    func testInformationOnlyUpdateNeverInstalls() {
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: true, stage: .downloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertFalse(manager.installRequested)
        XCTAssertFalse(manager.installNowRequested)
    }

    // MARK: - Download progress

    func testDownloadProgressIsFractionOfExpectedLength() {
        manager.handleDownloadInitiated()
        XCTAssertEqual(manager.phase, .downloading(fraction: nil))

        manager.handleDownloadExpectedLength(1_000)
        manager.handleDownloadReceived(bytes: 250)
        XCTAssertEqual(manager.phase, .downloading(fraction: 0.25))

        manager.handleDownloadReceived(bytes: 750)
        XCTAssertEqual(manager.phase, .downloading(fraction: 1.0))
    }

    func testUnknownContentLengthStaysIndeterminate() {
        manager.handleDownloadInitiated()
        manager.handleDownloadReceived(bytes: 4_096)

        XCTAssertEqual(manager.phase, .downloading(fraction: nil))
    }

    func testDownloadFractionIsCappedAtOne() {
        manager.handleDownloadInitiated()
        manager.handleDownloadExpectedLength(100)
        manager.handleDownloadReceived(bytes: 250)

        XCTAssertEqual(manager.phase, .downloading(fraction: 1.0))
    }

    // MARK: - Install stages

    func testExtractionShowsInstalling() {
        manager.handleExtractionStarted()

        XCTAssertEqual(manager.phase, .installing)
    }

    func testReadyToInstallHoldsTheReplyAndSurfacesTheChoice() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertTrue(choices.isEmpty)
    }

    func testInstallNowRepliesInstall() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        manager.installNow()

        XCTAssertEqual(choices, [.install])
        XCTAssertEqual(manager.phase, .installing)
    }

    func testInstallLaterRepliesDismissAndKeepsTheCard() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        manager.installLater()

        XCTAssertEqual(choices, [.dismiss])
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testDismissAfterLaterKeepsTheNextReadyToInstallWaiting() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleReadyToInstall { _ in }
        manager.installLater()
        manager.handleDismissInstallation()

        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertTrue(choices.isEmpty)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testScheduledCheckOnPreparedUpdateSurfacesReadyToInstall() {
        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testInstallNowRepliesExactlyOnceWhenPressedTwice() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        manager.installNow()
        manager.handleReadyToInstall { choices.append($0) }
        manager.handleInstalling()
        manager.installNow()

        XCTAssertEqual(choices, [.install])
        XCTAssertEqual(manager.phase, .installing)
    }

    func testInstallNowSurfacesALaterFailure() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.handleReadyToInstall { _ in }
        manager.installNow()

        manager.handleError("installer died")

        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))
    }

    func testLaterThenScheduledCheckKeepsReadyToInstall() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleReadyToInstall { _ in }
        manager.installLater()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    // MARK: - Retry after a failure

    func testRetryStopsAtReadyToInstallInsteadOfInstalling() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.hasLiveUpdater = { _ in true }
        manager.installPendingUpdate()
        manager.handleError("download died")
        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))

        manager.retryPendingUpdate()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleDownloadInitiated()

        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertTrue(choices.isEmpty)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.installNowRequested)
    }

    func testRetryOnADownloadedStageStopsAtTheReadyCard() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.hasLiveUpdater = { _ in true }
        manager.installPendingUpdate()
        manager.handleError("installer died")
        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))

        manager.retryPendingUpdate()
        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.installNowRequested)
    }

    func testRetryOnAPreparedStageStopsAtTheReadyCard() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.hasLiveUpdater = { _ in true }
        manager.installPendingUpdate()
        manager.handleError("installer died")

        manager.retryPendingUpdate()
        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertEqual(choice, .dismiss)
        XCTAssertTrue(choices.isEmpty)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testRetryThenInstallNowStillInstalls() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.hasLiveUpdater = { _ in true }
        manager.retryPendingUpdate()
        var choices: [SPUUserUpdateChoice] = []
        choices.append(
            manager.handleUpdateFound(
                version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded))
        manager.handleReadyToInstall { choices.append($0) }
        XCTAssertEqual(choices, [.install])

        manager.installNow()

        XCTAssertEqual(choices, [.install, .install])
        XCTAssertEqual(manager.phase, .installing)
    }

    func testRetryOnAPreparedStageSendsNoReplyUntilInstallNow() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }

        manager.retryPendingUpdate()
        var choices: [SPUUserUpdateChoice] = []
        choices.append(
            manager.handleUpdateFound(
                version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded))
        manager.handleReadyToInstall { choices.append($0) }
        XCTAssertEqual(choices, [.dismiss])
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))

        manager.installNow()

        XCTAssertEqual(choices, [.dismiss, .install])
        XCTAssertEqual(manager.phase, .installing)
    }

    // MARK: - Update button never installs a prepared update

    func testUpdateButtonOnAPreparedStageStopsAtTheReadyCard() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.installPendingUpdate()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.installRequested)
        XCTAssertFalse(manager.installNowRequested)
    }

    func testUpdateButtonAfterAnInstallNowIntentStillStopsAtTheReadyCard() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()
        manager.installPendingUpdate()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    // MARK: - Errors

    func testScheduledCheckErrorStaysSilent() {
        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        XCTAssertEqual(choice, .dismiss)

        manager.handleError("network down")

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testScheduledCheckErrorWithNothingPendingIsIdle() {
        manager.handleError("network down")

        XCTAssertEqual(manager.phase, .idle)
    }

    // MARK: - Session teardown

    func testDismissDuringDownloadRollsBackToAvailable() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleDownloadInitiated()

        manager.handleDismissInstallation()

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testDismissKeepsPendingRowAlive() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        manager.handleDismissInstallation()

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testInstallNowWithoutHeldReplyStartsTheResumeCheck() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        var resumeChecks = 0
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in resumeChecks += 1 }

        manager.installNow()

        XCTAssertEqual(resumeChecks, 1)
        XCTAssertEqual(manager.phase, .installing)
        XCTAssertTrue(manager.installRequested)
        XCTAssertTrue(manager.installNowRequested)
    }

    func testResumedDownloadedStageInstallsAndKeepsTheInstallNowIntent() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)

        XCTAssertEqual(choice, .install)
        XCTAssertTrue(manager.installNowRequested)
        XCTAssertEqual(manager.phase, .installing)
    }

    func testResumedReadyToInstallInstallsImmediatelyAndClearsTheIntent() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)

        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertEqual(choices, [.install])
        XCTAssertFalse(manager.installNowRequested)
        XCTAssertEqual(manager.phase, .installing)
    }

    func testInstallLaterRepliesExactlyOnceWhenPressedTwice() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        manager.installLater()
        manager.installLater()

        XCTAssertEqual(choices, [.dismiss])
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testDismissWhileInstallingKeepsThePreparedUpdate() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleReadyToInstall { _ in }
        manager.installNow()

        manager.handleDismissInstallation()

        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.installRequested)
    }

    func testInstallNowWhileInstallingDoesNotStartASecondResumeCheck() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        var resumeChecks = 0
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in resumeChecks += 1 }
        manager.installNow()

        manager.installNow()

        XCTAssertEqual(resumeChecks, 1)
    }

    func testLaterAfterAnAbortedInstallKeepsReadyToInstall() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleReadyToInstall { _ in }
        manager.installNow()
        manager.handleDismissInstallation()

        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }
        XCTAssertTrue(choices.isEmpty)
        manager.installLater()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        XCTAssertEqual(choices, [.dismiss])
        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testDismissDuringThePendingResumeKeepsTheInstallArmed() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()

        manager.handleDismissInstallation()

        XCTAssertEqual(manager.phase, .installing)
        XCTAssertTrue(manager.installRequested)
        XCTAssertTrue(manager.installNowRequested)

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        XCTAssertEqual(choice, .install)
        XCTAssertEqual(manager.phase, .installing)
    }

    func testNotFoundDuringThePendingResumeKeepsTheInstallArmed() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()

        manager.handleNotFound()

        XCTAssertEqual(manager.phase, .installing)
        XCTAssertTrue(manager.installRequested)
        XCTAssertTrue(manager.installNowRequested)
    }

    func testErrorDuringThePendingResumeKeepsTheInstallArmed() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()

        manager.handleError("old session aborted")

        XCTAssertEqual(manager.phase, .installing)
        XCTAssertTrue(manager.installRequested)
        XCTAssertTrue(manager.installNowRequested)
    }

    func testReadyDuringThePendingResumeHoldsTheReplyAndEndsThePoll() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()

        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertTrue(choices.isEmpty)
        XCTAssertFalse(manager.resumeCheckPending)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))

        manager.runResumeCheck(attempt: UpdateManager.resumeCheckAttemptLimit)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))

        manager.installNow()

        XCTAssertEqual(choices, [.install])
        XCTAssertEqual(manager.phase, .installing)
    }

    func testExhaustedResumeCheckFailsAndDisarmsTheInstall() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { $0.runResumeCheck(attempt: UpdateManager.resumeCheckAttemptLimit) }

        manager.installNow()

        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))
        XCTAssertFalse(manager.installRequested)
        XCTAssertFalse(manager.installNowRequested)
    }

    func testTheNewSessionEndsTheResumeLoop() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)
        XCTAssertEqual(choice, .install)
        XCTAssertFalse(manager.resumeCheckPending)

        manager.runResumeCheck(attempt: 3)

        XCTAssertEqual(manager.phase, .installing)
        XCTAssertTrue(manager.installRequested)
        XCTAssertTrue(manager.installNowRequested)
    }

    func testExhaustionAfterTheNewSessionStartedNeverFails() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        manager.hasLiveUpdater = { _ in true }
        manager.resumeCheckStarter = { _ in }
        manager.installNow()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)

        manager.runResumeCheck(attempt: UpdateManager.resumeCheckAttemptLimit)

        XCTAssertEqual(manager.phase, .installing)
        XCTAssertTrue(manager.installRequested)
        XCTAssertTrue(manager.installNowRequested)
    }

    func testInstallNowWithoutAnUpdaterLeavesThePhaseUnchanged() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)
        var resumeChecks = 0
        manager.resumeCheckStarter = { _ in resumeChecks += 1 }

        manager.installNow()

        XCTAssertEqual(resumeChecks, 0)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.installNowRequested)
    }

    func testDismissFromReadyToInstallKeepsTheCard() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        manager.handleDismissInstallation()

        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testUnrequestedErrorKeepsAPreparedUpdate() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        manager.handleError("network down")

        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testReadyToInstallWithoutAKnownVersionStillHoldsTheReply() {
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertTrue(choices.isEmpty)
        XCTAssertEqual(manager.phase, .readyToInstall(version: ""))
    }

    // MARK: - Silent discovery

    private var discoveryNow: TimeInterval = 0
    private var backgroundChecks = 0

    private func armDiscovery() {
        discoveryNow = 0
        backgroundChecks = 0
        manager.setAutoCheckEnabled(true)
        manager.stopBackgroundDiscovery()
        manager.monotonicClock = { [unowned self] in self.discoveryNow }
        manager.backgroundCheckStarter = { [unowned self] _ in self.backgroundChecks += 1 }
        manager.isSessionInProgress = { _ in false }
        manager.hasLiveUpdater = { _ in true }
    }

    func testPopoverOpenAsksForASilentCheck() {
        armDiscovery()

        manager.popoverDidOpen()

        XCTAssertEqual(backgroundChecks, 1)
        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(manager.manualCheckStatus, .idle)
    }

    func testEveryPopoverControllerCallsThePopoverHook() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MacFanApp/App")

        for controller in ["StatusItemController", "MetricStatusItemController", "FusedModulesStatusItemController"] {
            let source = try String(
                contentsOf: sources.appendingPathComponent("\(controller).swift"), encoding: .utf8)
            XCTAssertTrue(source.contains("UpdateManager.shared.popoverDidOpen()"), controller)
        }
    }

    func testTheDiscoveryTimerRunsOnTheRunLoopAndAsksForACheck() {
        armDiscovery()
        let fired = expectation(description: "the discovery timer asked for a silent check")
        fired.assertForOverFulfill = false
        manager.backgroundCheckStarter = { [unowned self] _ in
            self.backgroundChecks += 1
            fired.fulfill()
        }
        manager.backgroundCheckIntervalProvider = { 0.05 }

        manager.startBackgroundDiscovery()

        XCTAssertTrue(manager.backgroundDiscoveryArmed)
        waitForExpectations(timeout: 5)
        manager.stopBackgroundDiscovery()
        XCTAssertEqual(backgroundChecks, 1)
    }

    func testWakeAndTimerShareTheFiveMinuteThrottle() {
        armDiscovery()

        manager.requestBackgroundCheck()
        discoveryNow = UpdateManager.backgroundCheckThrottle - 1
        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 1)

        discoveryNow = UpdateManager.backgroundCheckThrottle
        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 2)
    }

    func testBackgroundCheckIsSkippedWhileASessionIsInProgress() {
        armDiscovery()
        manager.isSessionInProgress = { _ in true }

        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 0)
    }

    func testBackgroundCheckIsSkippedWhileADownloadRuns() {
        armDiscovery()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.installPendingUpdate()
        manager.handleDownloadInitiated()

        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 0)
        XCTAssertEqual(manager.phase, .downloading(fraction: nil))
    }

    func testManualCheckIsNeverThrottled() {
        armDiscovery()
        var userChecks = 0
        manager.userCheckStarter = { _ in userChecks += 1 }
        manager.requestBackgroundCheck()

        manager.checkForUpdatesManually()
        manager.checkForUpdatesManually()

        XCTAssertEqual(userChecks, 2)
        XCTAssertEqual(manager.manualCheckStatus, .checking)
    }

    func testManualCheckDuringASilentSessionRunsWhenTheSessionEnds() {
        armDiscovery()
        var sessionInProgress = true
        var userChecks = 0
        manager.isSessionInProgress = { _ in sessionInProgress }
        manager.userCheckStarter = { _ in userChecks += 1 }
        manager.manualCheckStarter = { _ in }

        manager.checkForUpdatesManually()

        XCTAssertEqual(manager.manualCheckStatus, .checking)
        XCTAssertEqual(userChecks, 0)

        sessionInProgress = false
        manager.runManualCheck(attempt: 1)

        XCTAssertEqual(userChecks, 1)
        XCTAssertEqual(manager.manualCheckStatus, .checking)

        manager.handleNotFound()

        XCTAssertEqual(manager.manualCheckStatus, .upToDate)
    }

    func testManualCheckGivesUpQuietlyWhenTheSessionNeverEnds() {
        armDiscovery()
        var userChecks = 0
        manager.isSessionInProgress = { _ in true }
        manager.userCheckStarter = { _ in userChecks += 1 }
        manager.manualCheckStarter = { _ in }

        manager.checkForUpdatesManually()
        XCTAssertEqual(manager.manualCheckStatus, .checking)

        manager.runManualCheck(attempt: UpdateManager.resumeCheckAttemptLimit)

        XCTAssertEqual(userChecks, 0)
        XCTAssertEqual(manager.manualCheckStatus, .idle)
        XCTAssertEqual(manager.phase, .idle)
    }

    func testUpdateClickDuringTheSilentSessionTeardownStillDownloads() {
        armDiscovery()
        var sessionInProgress = true
        var userChecks = 0
        manager.isSessionInProgress = { _ in sessionInProgress }
        manager.userCheckStarter = { _ in userChecks += 1 }
        manager.resumeCheckStarter = { _ in }
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        manager.installPendingUpdate()

        XCTAssertEqual(manager.phase, .downloading(fraction: nil))
        XCTAssertEqual(userChecks, 0)

        sessionInProgress = false
        manager.runResumeCheck(attempt: 1)

        XCTAssertEqual(userChecks, 1)
        XCTAssertFalse(manager.resumeCheckPending)
        XCTAssertFalse(manager.installNowRequested)

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertEqual(choice, .dismiss)
        XCTAssertTrue(choices.isEmpty)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    func testUpdateClickDuringARunningDownloadIsIgnored() {
        armDiscovery()
        var userChecks = 0
        var resumeStarts = 0
        manager.isSessionInProgress = { _ in true }
        manager.userCheckStarter = { _ in userChecks += 1 }
        manager.resumeCheckStarter = { _ in resumeStarts += 1 }
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.installPendingUpdate()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleDownloadInitiated()
        manager.handleDownloadExpectedLength(1_000)
        manager.handleDownloadReceived(bytes: 400)
        XCTAssertEqual(manager.phase, .downloading(fraction: 0.4))
        XCTAssertEqual(resumeStarts, 1)

        manager.installPendingUpdate()

        XCTAssertEqual(manager.phase, .downloading(fraction: 0.4))
        XCTAssertFalse(manager.resumeCheckPending)
        XCTAssertEqual(resumeStarts, 1)
        XCTAssertEqual(userChecks, 0)
    }

    func testUpdateClickWhileInstallingIsIgnored() {
        armDiscovery()
        var resumeStarts = 0
        manager.isSessionInProgress = { _ in true }
        manager.resumeCheckStarter = { _ in resumeStarts += 1 }
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.installPendingUpdate()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleExtractionStarted()

        manager.installPendingUpdate()

        XCTAssertEqual(manager.phase, .installing)
        XCTAssertFalse(manager.resumeCheckPending)
        XCTAssertEqual(resumeStarts, 1)
    }

    func testRetryAfterAFailedDownloadStillStartsTheResumePath() {
        armDiscovery()
        var resumeStarts = 0
        manager.isSessionInProgress = { _ in true }
        manager.resumeCheckStarter = { _ in resumeStarts += 1 }
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.installPendingUpdate()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleError("download died")
        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))

        manager.retryPendingUpdate()

        XCTAssertEqual(manager.phase, .downloading(fraction: nil))
        XCTAssertTrue(manager.resumeCheckPending)
        XCTAssertEqual(resumeStarts, 2)
    }

    func testDisabledAutoChecksFireNoTrigger() {
        armDiscovery()
        manager.startBackgroundDiscovery()
        XCTAssertTrue(manager.backgroundDiscoveryArmed)

        manager.setAutoCheckEnabled(false)
        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 0)
        XCTAssertFalse(manager.backgroundDiscoveryArmed)
    }

    func testWakeNotificationAsksForASilentCheck() {
        armDiscovery()
        manager.startBackgroundDiscovery()
        defer { manager.stopBackgroundDiscovery() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification, object: nil)

        XCTAssertTrue(manager.backgroundDiscoveryArmed)
        XCTAssertEqual(backgroundChecks, 1)
    }

    func testEnablingAutoChecksArmsTheTimerAndDisablingInvalidatesIt() {
        manager.setAutoCheckEnabled(true)
        XCTAssertTrue(manager.backgroundDiscoveryArmed)

        manager.setAutoCheckEnabled(false)

        XCTAssertFalse(manager.backgroundDiscoveryArmed)
    }

    func testSilentCheckThatFindsNothingChangesNoVisibleState() {
        armDiscovery()
        manager.requestBackgroundCheck()

        manager.handleNotFound()

        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(manager.manualCheckStatus, .idle)
        XCTAssertNil(manager.pendingVersion)
    }

    func testSilentCheckThatFailsChangesNoVisibleState() {
        armDiscovery()
        manager.requestBackgroundCheck()

        manager.handleError("offline")

        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(manager.manualCheckStatus, .idle)
    }

    func testSilentCheckThatFindsAnUpdateShowsTheAvailableCard() {
        armDiscovery()
        manager.requestBackgroundCheck()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testSilentCheckOnAPreparedUpdateStillWaitsForInstallNow() {
        armDiscovery()
        manager.requestBackgroundCheck()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .downloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
    }

    // MARK: - Quiet checks from a resting card

    private func armLaterState() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleReadyToInstall { _ in }
        manager.installLater()
    }

    private func armFailedCard() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.installPendingUpdate()
        manager.handleError("download died")
    }

    func testIdleAllowsAQuietCheck() {
        XCTAssertTrue(manager.phaseAllowsQuietCheck)
    }

    func testAnAvailableCardAllowsAQuietCheck() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertTrue(manager.phaseAllowsQuietCheck)
    }

    func testAFailedCardAllowsAQuietCheck() {
        armDiscovery()
        armFailedCard()

        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))
        XCTAssertTrue(manager.phaseAllowsQuietCheck)
    }

    func testDownloadingAndInstallingBlockAQuietCheck() {
        manager.handleDownloadInitiated()
        XCTAssertFalse(manager.phaseAllowsQuietCheck)

        manager.handleExtractionStarted()
        XCTAssertFalse(manager.phaseAllowsQuietCheck)
    }

    func testAHeldReadyReplyBlocksAQuietCheck() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.handleReadyToInstall { _ in }

        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.phaseAllowsQuietCheck)
    }

    func testThePostLaterReadyCardBlocksAQuietCheck() {
        armLaterState()

        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.phaseAllowsQuietCheck)
    }

    func testAUserCheckInFlightBlocksAQuietCheck() {
        armDiscovery()
        manager.isSessionInProgress = { _ in true }
        manager.manualCheckStarter = { _ in }

        manager.checkForUpdatesManually()

        XCTAssertFalse(manager.phaseAllowsQuietCheck)
    }

    func testAnArmedInstallBlocksAQuietCheck() {
        armDiscovery()
        manager.resumeCheckStarter = { _ in }
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        manager.installPendingUpdate()

        XCTAssertTrue(manager.installRequested)
        XCTAssertTrue(manager.resumeCheckPending)
        XCTAssertFalse(manager.phaseAllowsQuietCheck)
    }

    func testAnArmedInstallNowBlocksAQuietCheck() {
        armDiscovery()
        manager.resumeCheckStarter = { _ in }
        armLaterState()

        manager.installNow()

        XCTAssertTrue(manager.installNowRequested)
        XCTAssertFalse(manager.phaseAllowsQuietCheck)
    }

    func testAQuietCheckRunsFromAFailedCard() {
        armDiscovery()
        armFailedCard()

        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 1)
        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))
    }

    func testABackgroundCheckWithoutALiveUpdaterIsSkippedAndKeepsTheThrottle() {
        armDiscovery()
        manager.hasLiveUpdater = { _ in false }

        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 0)

        manager.hasLiveUpdater = { _ in true }
        manager.requestBackgroundCheck()

        XCTAssertEqual(backgroundChecks, 1)
    }

    func testAScheduledSameVersionKeepsTheFailedCard() {
        armDiscovery()
        armFailedCard()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(backgroundChecks, 0)
        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))
        XCTAssertEqual(manager.pendingVersion, "9.9.9")
    }

    func testAnUnattendedSameVersionKeepsTheAvailableCard() {
        armDiscovery()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.requestBackgroundCheck()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertFalse(manager.installRequested)
    }

    func testAnUnattendedStagedUpdateAfterLaterKeepsTheReadyCard() {
        armDiscovery()
        armLaterState()

        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9"))
        XCTAssertFalse(manager.installRequested)
        XCTAssertFalse(manager.installNowRequested)
    }

    func testAnUnattendedOlderVersionKeepsTheAvailableCard() {
        armDiscovery()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.requestBackgroundCheck()

        let choice = manager.handleUpdateFound(
            version: "9.9.8", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertEqual(manager.pendingVersion, "9.9.9")
    }

    func testAnUnattendedNewerVersionReplacesTheAvailableCard() {
        armDiscovery()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.requestBackgroundCheck()

        let choice = manager.handleUpdateFound(
            version: "9.9.10", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.10"))
        XCTAssertFalse(manager.installNowRequested)
    }

    func testAnUnattendedNewerVersionReplacesTheFailedCard() {
        armDiscovery()
        armFailedCard()
        manager.requestBackgroundCheck()

        let choice = manager.handleUpdateFound(
            version: "9.9.10", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.10"))
        XCTAssertFalse(manager.installRequested)
    }

    func testAnUnattendedNotFoundKeepsTheCard() {
        armDiscovery()
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.requestBackgroundCheck()

        manager.handleNotFound()

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertEqual(manager.pendingVersion, "9.9.9")
        XCTAssertEqual(manager.manualCheckStatus, .idle)
    }

    func testAnUnattendedErrorKeepsTheFailedCard() {
        armDiscovery()
        armFailedCard()
        manager.requestBackgroundCheck()

        manager.handleError("offline")

        XCTAssertEqual(manager.phase, .failed(version: "9.9.9"))
        XCTAssertEqual(manager.manualCheckStatus, .idle)
    }

    func testAQuietCheckWithoutAnyCallbackStillAnswersALaterManualCheck() {
        armDiscovery()
        var userChecks = 0
        manager.userCheckStarter = { _ in userChecks += 1 }
        manager.requestBackgroundCheck()

        manager.checkForUpdatesManually()
        XCTAssertEqual(userChecks, 1)
        XCTAssertEqual(manager.manualCheckStatus, .checking)

        manager.handleNotFound()

        XCTAssertEqual(manager.manualCheckStatus, .upToDate)
        XCTAssertEqual(manager.phase, .idle)
    }

    func testAQuietCheckWithoutAnyCallbackStillDownloadsOnTheUpdateClick() {
        armDiscovery()
        var resumeStarts = 0
        manager.resumeCheckStarter = { _ in resumeStarts += 1 }
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.requestBackgroundCheck()
        XCTAssertEqual(backgroundChecks, 1)

        manager.installPendingUpdate()

        XCTAssertEqual(manager.phase, .downloading(fraction: nil))
        XCTAssertEqual(resumeStarts, 1)
    }

    func testAManualCheckKeepsItsSpinnerUntilItsOwnSessionAnswers() {
        armDiscovery()
        var sessionInProgress = false
        var userChecks = 0
        manager.isSessionInProgress = { _ in sessionInProgress }
        manager.userCheckStarter = { _ in userChecks += 1 }
        manager.manualCheckStarter = { _ in }
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)
        manager.requestBackgroundCheck()
        sessionInProgress = true

        manager.checkForUpdatesManually()
        let quietChoice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(quietChoice, .dismiss)
        XCTAssertEqual(manager.manualCheckStatus, .checking)
        XCTAssertFalse(manager.phaseAllowsQuietCheck)
        XCTAssertEqual(userChecks, 0)

        sessionInProgress = false
        manager.runManualCheck(attempt: 1)
        let manualChoice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(manualChoice, .dismiss)
        XCTAssertEqual(userChecks, 1)
        XCTAssertEqual(manager.manualCheckStatus, .idle)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testAManualCheckFromAFailedCardShowsTheSameVersionAsAvailable() {
        armDiscovery()
        armFailedCard()
        manager.userCheckStarter = { _ in }

        manager.checkForUpdatesManually()
        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertEqual(manager.manualCheckStatus, .idle)
    }

    func testInstallNowStillInstallsFromTheAfterLaterState() {
        armDiscovery()
        var resumeStarts = 0
        manager.resumeCheckStarter = { _ in resumeStarts += 1 }
        armLaterState()

        manager.installNow()
        let choice = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .installing)

        XCTAssertEqual(choice, .install)
        XCTAssertEqual(resumeStarts, 1)
        XCTAssertEqual(manager.phase, .installing)
    }

    // MARK: - Up to date

    func testNotFoundAfterAManualCheckClearsPendingState() {
        armDiscovery()
        manager.userCheckStarter = { _ in }
        _ = manager.handleUpdateFound(
            version: "9.9.9",
            releasePage: URL(string: "https://example.com/release"),
            informationOnly: false,
            stage: .notDownloaded
        )
        manager.checkForUpdatesManually()

        manager.handleNotFound()

        XCTAssertEqual(manager.phase, .idle)
        XCTAssertNil(manager.releasePageURL)
    }
}
