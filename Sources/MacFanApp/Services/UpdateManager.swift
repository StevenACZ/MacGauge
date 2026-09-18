import AppKit
import Foundation
import Sparkle
import os

/// In-app updates via Sparkle. The scheduled daily check only surfaces a
/// pending update (popover card + Settings status); downloading, installing,
/// and relaunching happen when the user clicks Install, with progress
/// mirrored in `phase`. Scheduled-check failures stay silent; only a
/// user-requested install surfaces errors.
@MainActor
final class UpdateManager: ObservableObject {

    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case available(version: String)
        /// nil fraction = size unknown yet (indeterminate spinner).
        case downloading(fraction: Double?)
        case readyToInstall(version: String)
        case installing
        case failed(version: String)
    }

    enum ManualCheckStatus: Equatable {
        case idle
        case checking
        case upToDate
    }

    static let autoCheckDefaultsKey = "autoUpdateCheckEnabled"
    /// Local appcast testing only:
    /// `defaults write com.stevenacz.MacFan updateFeedURLOverride <url>`.
    static let feedURLOverrideDefaultsKey = "updateFeedURLOverride"
    static let resumeCheckAttemptLimit = 40
    static let backgroundCheckInterval: TimeInterval = 30 * 60
    static let backgroundCheckThrottle: TimeInterval = 5 * 60
    private static let resumeCheckRetryDelay = 0.25

    @Published private(set) var phase: Phase = .idle
    /// GitHub release page of the pending update (the appcast item's <link>).
    @Published private(set) var releasePageURL: URL?
    /// Ephemeral "you're up to date" feedback for the Settings pane.
    @Published private(set) var manualCheckStatus: ManualCheckStatus = .idle
    @Published private(set) var autoCheckEnabled: Bool
    @Published private(set) var pendingVersion: String?

    private let log = Logger(subsystem: "com.stevenacz.MacFan", category: "updates")

    private var updater: SPUUpdater?
    private var driver: Driver?
    private var updaterDelegate: UpdaterDelegate?

    private(set) var installRequested = false
    private(set) var installNowRequested = false
    /// True from "Install now" until the resume check reaches Sparkle: the
    /// aborting session's callbacks in that window belong to the old session.
    private(set) var resumeCheckPending = false
    var resumeCheckStarter: @MainActor (UpdateManager) -> Void = { $0.runResumeCheck(attempt: 0) }
    var hasLiveUpdater: @MainActor (UpdateManager) -> Bool = { $0.updater != nil }
    var backgroundCheckStarter: @MainActor (UpdateManager) -> Void = {
        $0.updater?.checkForUpdatesInBackground()
    }
    var userCheckStarter: @MainActor (UpdateManager) -> Void = { $0.updater?.checkForUpdates() }
    var isSessionInProgress: @MainActor (UpdateManager) -> Bool = { $0.updater?.sessionInProgress == true }
    var monotonicClock: @MainActor () -> TimeInterval = {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
    private var pendingInstallReply: ((SPUUserUpdateChoice) -> Void)?
    private var pendingIsInformationOnly = false
    private var expectedDownloadBytes: UInt64 = 0
    private var receivedDownloadBytes: UInt64 = 0
    private var manualCheckPending = false
    private var manualCheckResetTask: Task<Void, Never>?
    private var backgroundCheckTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastBackgroundCheck: TimeInterval?

    init() {
        // Defaults to enabled until the Settings toggle writes the key.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.autoCheckDefaultsKey) == nil {
            autoCheckEnabled = true
        } else {
            autoCheckEnabled = defaults.bool(forKey: Self.autoCheckDefaultsKey)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard updater == nil else { return }

        let driver = Driver(manager: self)
        let updaterDelegate = UpdaterDelegate()
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: updaterDelegate
        )
        updater.automaticallyDownloadsUpdates = false
        updater.automaticallyChecksForUpdates = autoCheckEnabled

        do {
            try updater.start()
        } catch {
            log.error("Updater failed to start: \(error.localizedDescription, privacy: .public)")
            return
        }

        self.driver = driver
        self.updaterDelegate = updaterDelegate
        self.updater = updater
        if autoCheckEnabled { startBackgroundDiscovery() }
    }

    func setAutoCheckEnabled(_ enabled: Bool) {
        autoCheckEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoCheckDefaultsKey)
        updater?.automaticallyChecksForUpdates = enabled
        if enabled {
            startBackgroundDiscovery()
        } else {
            stopBackgroundDiscovery()
        }
    }

    // MARK: - Silent discovery

    var backgroundDiscoveryArmed: Bool { backgroundCheckTimer != nil }

    func startBackgroundDiscovery() {
        guard backgroundCheckTimer == nil else { return }
        let timer = Timer(timeInterval: Self.backgroundCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestBackgroundCheck()
            }
        }
        timer.tolerance = Self.backgroundCheckInterval / 10
        RunLoop.main.add(timer, forMode: .common)
        backgroundCheckTimer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.requestBackgroundCheck()
            }
        }
    }

    func stopBackgroundDiscovery() {
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Popover open, wake, and the repeating timer all land here: a silent
    /// check at most every `backgroundCheckThrottle`, and only while nothing
    /// is already on screen or in flight.
    func requestBackgroundCheck() {
        guard autoCheckEnabled, phase == .idle, !isSessionInProgress(self) else { return }
        let now = monotonicClock()
        if let lastBackgroundCheck, now - lastBackgroundCheck < Self.backgroundCheckThrottle {
            return
        }
        lastBackgroundCheck = now
        backgroundCheckStarter(self)
    }

    // MARK: - User actions

    /// Popover row / Settings click: download a pending update and stop at the
    /// ready card, or retry after a failure. A prepared update is never
    /// installed here. Information-only updates open the release page.
    func installPendingUpdate() {
        guard hasLiveUpdater(self) else { return }
        if pendingIsInformationOnly {
            openReleasePage()
            return
        }
        guard updater?.sessionInProgress != true else { return }
        installNowRequested = false
        installRequested = true
        phase = .downloading(fraction: nil)
        updater?.checkForUpdates()
    }

    /// Update card: install the downloaded update and relaunch. Without a
    /// held reply the session is over, so a user-initiated check resumes the
    /// prepared update, which Sparkle reports back as an installing stage.
    func installNow() {
        guard phase != .installing else { return }
        if let pendingInstallReply {
            self.pendingInstallReply = nil
            installRequested = true
            phase = .installing
            pendingInstallReply(.install)
            return
        }
        guard hasLiveUpdater(self) else { return }
        installRequested = true
        installNowRequested = true
        resumeCheckPending = true
        phase = .installing
        beginResumeCheck()
    }

    /// Must never arm the unattended install: a retry stops at the ready card.
    func retryPendingUpdate() {
        installPendingUpdate()
    }

    private func beginResumeCheck() {
        resumeCheckStarter(self)
    }

    /// Sparkle refuses a new check while the aborted session tears down, so
    /// the resume check waits for `sessionInProgress` to clear.
    func runResumeCheck(attempt: Int) {
        guard resumeCheckPending else { return }
        guard attempt < Self.resumeCheckAttemptLimit else {
            installRequested = false
            installNowRequested = false
            resumeCheckPending = false
            phase = .failed(version: pendingVersion ?? "")
            return
        }
        guard let updater else { return }
        guard updater.sessionInProgress else {
            resumeCheckPending = false
            updater.checkForUpdates()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resumeCheckRetryDelay) { [weak self] in
            self?.runResumeCheck(attempt: attempt + 1)
        }
    }

    func installLater() {
        guard let pendingInstallReply else { return }
        self.pendingInstallReply = nil
        installRequested = false
        pendingInstallReply(.dismiss)
    }

    /// Settings pane: explicit re-check with visible "up to date" feedback.
    /// Never subject to the silent-discovery throttle.
    func checkForUpdatesManually() {
        guard hasLiveUpdater(self), !isSessionInProgress(self) else { return }
        manualCheckResetTask?.cancel()
        manualCheckPending = true
        manualCheckStatus = .checking
        userCheckStarter(self)
    }

    func openReleasePage() {
        guard let releasePageURL else { return }
        NSWorkspace.shared.open(releasePageURL)
    }

    // MARK: - Driver events (pure state transitions, unit-testable)

    func handleUpdateFound(
        version: String,
        releasePage: URL?,
        informationOnly: Bool,
        stage: SPUUserUpdateStage
    ) -> SPUUserUpdateChoice {
        resumeCheckPending = false
        pendingVersion = version
        pendingIsInformationOnly = informationOnly
        releasePageURL = releasePage
        finishManualCheck(status: .idle)

        guard !informationOnly else {
            installRequested = false
            installNowRequested = false
            phase = .available(version: version)
            return .dismiss
        }

        switch stage {
        case .downloaded, .installing:
            guard installNowRequested else {
                installRequested = false
                phase = .readyToInstall(version: version)
                return .dismiss
            }
            phase = .installing
            return .install
        default:
            guard installRequested else {
                installRequested = false
                installNowRequested = false
                phase = .available(version: version)
                return .dismiss
            }
            phase = .downloading(fraction: nil)
            return .install
        }
    }

    func handleDownloadInitiated() {
        expectedDownloadBytes = 0
        receivedDownloadBytes = 0
        phase = .downloading(fraction: nil)
    }

    func handleDownloadExpectedLength(_ length: UInt64) {
        expectedDownloadBytes = length
    }

    func handleDownloadReceived(bytes: UInt64) {
        receivedDownloadBytes += bytes
        guard expectedDownloadBytes > 0 else { return }
        let fraction = min(1.0, Double(receivedDownloadBytes) / Double(expectedDownloadBytes))
        phase = .downloading(fraction: fraction)
    }

    func handleExtractionStarted() {
        phase = .installing
    }

    /// Sparkle waits on this reply, so it is held until the user picks
    /// "Install now" or "Later" — unless the install was already requested.
    /// A ready arriving while the resume check is armed belongs to the old
    /// session: it ends the poll and holds the reply instead of installing.
    func handleReadyToInstall(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !resumeCheckPending else {
            resumeCheckPending = false
            installRequested = false
            installNowRequested = false
            pendingInstallReply = reply
            phase = .readyToInstall(version: pendingVersion ?? "")
            return
        }
        guard !installNowRequested else {
            installNowRequested = false
            pendingInstallReply = nil
            phase = .installing
            reply(.install)
            return
        }
        pendingInstallReply = reply
        phase = .readyToInstall(version: pendingVersion ?? "")
    }

    func handleInstalling() {
        phase = .installing
    }

    func handleNotFound() {
        guard !resumeCheckPending else {
            pendingInstallReply = nil
            return
        }
        installRequested = false
        installNowRequested = false
        pendingInstallReply = nil
        pendingVersion = nil
        pendingIsInformationOnly = false
        releasePageURL = nil
        phase = .idle
        finishManualCheck(status: .upToDate)
    }

    /// Scheduled-check errors stay silent; a user-requested install shows
    /// a retryable failure row instead.
    func handleError(_ message: String) {
        guard !resumeCheckPending else {
            pendingInstallReply = nil
            return
        }
        finishManualCheck(status: .idle)
        installNowRequested = false
        pendingInstallReply = nil
        if installRequested, let pendingVersion {
            log.error("Update install failed: \(message, privacy: .public)")
            phase = .failed(version: pendingVersion)
        } else {
            log.debug("Update check failed silently")
            switch phase {
            case .readyToInstall, .installing:
                phase = .readyToInstall(version: pendingVersion ?? "")
            case .idle, .available, .downloading, .failed:
                phase = pendingVersion.map { .available(version: $0) } ?? .idle
            }
        }
        installRequested = false
    }

    /// Sparkle tears the session down (abort or completion). Keep the
    /// pending row alive; only roll back an in-flight progress state.
    func handleDismissInstallation() {
        guard !resumeCheckPending else {
            pendingInstallReply = nil
            return
        }
        installRequested = false
        installNowRequested = false
        pendingInstallReply = nil
        switch phase {
        case .installing, .readyToInstall:
            phase = .readyToInstall(version: pendingVersion ?? "")
        case .downloading:
            phase = pendingVersion.map { .available(version: $0) } ?? .idle
        case .idle, .available, .failed:
            break
        }
    }

    private func finishManualCheck(status: ManualCheckStatus) {
        guard manualCheckPending else { return }
        manualCheckPending = false
        manualCheckStatus = status
        guard status != .idle else { return }
        manualCheckResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.manualCheckStatus = .idle
        }
    }
}

// MARK: - Sparkle user driver

/// Bridges Sparkle's user-interaction callbacks onto the manager's phase.
/// Every callback arrives on the main actor (the protocol is NS_SWIFT_UI_ACTOR).
@MainActor
private final class Driver: NSObject, SPUUserDriver {

    private unowned let manager: UpdateManager

    init(manager: UpdateManager) {
        self.manager = manager
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        // Unreached: SUEnableAutomaticChecks in Info.plist suppresses the prompt.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let choice = manager.handleUpdateFound(
            version: appcastItem.displayVersionString,
            releasePage: appcastItem.infoURL,
            informationOnly: appcastItem.isInformationOnlyUpdate,
            stage: state.stage
        )
        reply(choice)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        manager.handleNotFound()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        manager.handleError(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        manager.handleDownloadInitiated()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        manager.handleDownloadExpectedLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        manager.handleDownloadReceived(bytes: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        manager.handleExtractionStarted()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        manager.handleReadyToInstall(reply: reply)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        manager.handleInstalling()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        manager.handleDismissInstallation()
    }
}

// MARK: - Sparkle updater delegate

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {

    /// Local-testing escape hatch: point the feed at a local appcast.
    /// Production resolves SUFeedURL from Info.plist (return nil).
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: UpdateManager.feedURLOverrideDefaultsKey)
    }
}
