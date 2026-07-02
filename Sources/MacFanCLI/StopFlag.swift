import Foundation

enum StopFlag {
    nonisolated(unsafe) static var shouldStop = false

    static func installSignalHandlers() {
        signal(SIGINT) { _ in StopFlag.shouldStop = true }
        signal(SIGTERM) { _ in StopFlag.shouldStop = true }
    }
}
