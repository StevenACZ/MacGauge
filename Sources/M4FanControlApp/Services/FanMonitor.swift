import Foundation
import M4FanCore

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

    private let refreshIntervalNanoseconds: UInt64 = 2_000_000_000
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    func start() {
        stop()
        refresh()
        let interval = refreshIntervalNanoseconds
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        refreshTask?.cancel()
        pollTask = nil
        refreshTask = nil
    }

    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            let nextSnapshot = await Task.detached(priority: .utility) {
                Self.readSnapshot()
            }.value
            guard let self, !Task.isCancelled else { return }
            self.refreshTask = nil
            self.publish(nextSnapshot)
        }
    }

    private func publish(_ nextSnapshot: FanSnapshot) {
        guard snapshot.isMeaningfullyDifferent(from: nextSnapshot) else { return }
        snapshot = nextSnapshot
    }

    nonisolated private static func readSnapshot() -> FanSnapshot {
        do {
            let smc = try SMCClient()
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
        } catch {
            return FanSnapshot(error: error.localizedDescription, updatedAt: Date())
        }
    }
}

private extension FanSnapshot {
    func isMeaningfullyDifferent(from other: FanSnapshot) -> Bool {
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
        case let (lhs?, rhs?):
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
        case let (lhs?, rhs?):
            return abs(lhs - rhs) >= tolerance
        default:
            return true
        }
    }
}
