import Foundation

enum StopFlag {
    // sig_atomic_t so assignment from a signal handler is async-signal-safe.
    nonisolated(unsafe) private static var stopRequested: sig_atomic_t = 0

    static var shouldStop: Bool {
        stopRequested != 0
    }

    static func installSignalHandlers() {
        // Touch the static before handlers exist so its lazy initialization
        // never runs inside a signal handler.
        stopRequested = 0
        signal(SIGINT) { _ in StopFlag.stopRequested = 1 }
        signal(SIGTERM) { _ in StopFlag.stopRequested = 1 }
    }
}
