import Sparkle
import XCTest

@testable import MacFanApp

/// Phase-machine coverage for the Sparkle-backed update manager: the driver
/// event handlers are exercised directly, no Sparkle session involved.
@MainActor
final class UpdateManagerTests: XCTestCase {

    private var manager: UpdateManager!

    override func setUp() {
        super.setUp()
        manager = UpdateManager()
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

    // MARK: - Up to date

    func testNotFoundClearsPendingState() {
        _ = manager.handleUpdateFound(
            version: "9.9.9", releasePage: nil, informationOnly: false, stage: .notDownloaded)

        manager.handleNotFound()

        XCTAssertEqual(manager.phase, .idle)
        XCTAssertNil(manager.releasePageURL)
    }
}
