import Foundation
import M4FanCore

struct FanSnapshot {
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

    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        do {
            let smc = try SMCClient()
            let fanController = FanController(smc: smc)
            let temperatureReader = TemperatureReader(smc: smc)
            let fans = try fanController.allFans()
            snapshot = FanSnapshot(
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
            snapshot.error = error.localizedDescription
            snapshot.updatedAt = Date()
        }
    }
}
