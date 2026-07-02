import Foundation
import MacFanCore

struct FanSnapshot: Sendable {
    var model = SystemInfo.hardwareModel
    var chip = SystemInfo.chipName
    var thermalState = SystemInfo.thermalState
    var temperatureCelsius: Double?
    var fan: FanInfo?
    var fanCount = 0
    var error: String?
    var updatedAt: Date?
}

@MainActor
final class FanMonitor: ObservableObject {
    @Published private(set) var snapshot = FanSnapshot()

    private var refreshIntervalNanoseconds: UInt64 = FanMonitor.nanoseconds(forInterval: 1)
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<FanSnapshot, Never>?
    private var refreshRunID: UUID?
    private var temperatureSmoother = TemperatureSmoother()
    private let pool = SMCPool()
    private let readQueue = DispatchQueue(label: "com.stevenacz.MacFan.fanmonitor.read", qos: .userInitiated)

    func start(refreshIntervalSeconds: Double = 1) {
        stop()
        temperatureSmoother.reset()
        refreshIntervalNanoseconds = Self.nanoseconds(forInterval: refreshIntervalSeconds)
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.refreshIntervalNanoseconds
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        refreshTask?.cancel()
        pollTask = nil
        refreshTask = nil
        refreshRunID = nil
    }

    func setRefreshInterval(seconds: Double) {
        let interval = Self.nanoseconds(forInterval: seconds)
        guard interval != refreshIntervalNanoseconds else { return }
        refreshIntervalNanoseconds = interval
    }

    func refresh() {
        Task { [weak self] in
            _ = await self?.refreshNow()
        }
    }

    @discardableResult
    func refreshNow() async -> FanSnapshot {
        if let refreshTask {
            return await refreshTask.value
        }

        let runID = UUID()
        refreshRunID = runID

        let task = Task { [weak self, pool, readQueue] in
            let rawSnapshot = await Self.readSnapshotAsync(pool: pool, queue: readQueue)
            guard let self else { return rawSnapshot }
            guard !Task.isCancelled, self.refreshRunID == runID else {
                return self.snapshot
            }

            var nextSnapshot = rawSnapshot
            nextSnapshot.temperatureCelsius = self.temperatureSmoother.update(with: nextSnapshot.temperatureCelsius)
            self.refreshTask = nil
            self.refreshRunID = nil
            self.publish(nextSnapshot)
            return nextSnapshot
        }
        refreshTask = task
        return await task.value
    }

    private func publish(_ nextSnapshot: FanSnapshot) {
        guard snapshot.isMeaningfullyDifferent(from: nextSnapshot) else { return }
        snapshot = nextSnapshot
    }

    nonisolated private static func readSnapshotAsync(pool: SMCPool, queue: DispatchQueue) async -> FanSnapshot {
        await withCheckedContinuation { (continuation: CheckedContinuation<FanSnapshot, Never>) in
            queue.async {
                continuation.resume(returning: Self.readSnapshot(using: pool))
            }
        }
    }

    nonisolated private static func readSnapshot(using pool: SMCPool) -> FanSnapshot {
        do {
            return try pool.withClient { smc in
                let fanController = FanController(smc: smc)
                let temperatureReader = TemperatureReader(smc: smc)
                let fans = try fanController.allFans()
                return FanSnapshot(
                    model: SystemInfo.hardwareModel,
                    chip: SystemInfo.chipName,
                    thermalState: SystemInfo.thermalState,
                    temperatureCelsius: try temperatureReader.representativeTemperature(),
                    fan: fans.first,
                    fanCount: fans.count,
                    error: nil,
                    updatedAt: Date()
                )
            }
        } catch {
            return FanSnapshot(error: error.localizedDescription, updatedAt: Date())
        }
    }

    private static func nanoseconds(forInterval seconds: Double) -> UInt64 {
        let bounded = min(max(seconds, 0.5), 10)
        return UInt64(bounded * 1_000_000_000)
    }
}

extension FanSnapshot {
    fileprivate func isMeaningfullyDifferent(from other: FanSnapshot) -> Bool {
        model != other.model
            || chip != other.chip
            || thermalState != other.thermalState
            || fanCount != other.fanCount
            || error != other.error
            || valueChanged(temperatureCelsius, other.temperatureCelsius, tolerance: 0.2)
            || fanChanged(fan, other.fan)
    }

    private func fanChanged(_ lhs: FanInfo?, _ rhs: FanInfo?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (let lhs?, let rhs?):
            return lhs.index != rhs.index
                || lhs.name != rhs.name
                || lhs.mode != rhs.mode
                || lhs.modeKey != rhs.modeKey
                || valueChanged(lhs.currentRPM, rhs.currentRPM, tolerance: 20)
                || valueChanged(lhs.targetRPM, rhs.targetRPM, tolerance: 20)
                || valueChanged(lhs.minRPM, rhs.minRPM, tolerance: 1)
                || valueChanged(lhs.maxRPM, rhs.maxRPM, tolerance: 1)
        default:
            return true
        }
    }

    private func valueChanged(_ lhs: Double?, _ rhs: Double?, tolerance: Double) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (let lhs?, let rhs?):
            return abs(lhs - rhs) >= tolerance
        default:
            return true
        }
    }
}

final class SMCPool: @unchecked Sendable {
    private var client: SMCClient?
    private let lock = NSLock()

    func withClient<T>(_ body: (SMCClient) throws -> T) throws -> T {
        let reused = try clientOrReuse()
        do {
            return try body(reused)
        } catch let error as SMCError {
            switch error {
            case .ioKit, .openFailed, .driverNotFound:
                invalidate()
                let fresh = try clientOrReuse()
                return try body(fresh)
            default:
                throw error
            }
        }
    }

    func invalidate() {
        lock.lock()
        client = nil
        lock.unlock()
    }

    private func clientOrReuse() throws -> SMCClient {
        lock.lock()
        let existing = client
        lock.unlock()
        if let existing { return existing }
        let new = try SMCClient()
        lock.lock()
        client = new
        lock.unlock()
        return new
    }
}
