import Foundation

/// Feeds the Display-tab previews with simulated activity instead of live
/// readings: usage sweeps from idle to ~95% and back down, network climbs
/// from a few KB/s into the MB/s range and back, so the user watches their
/// color thresholds trip in real time without having to load the Mac.
@MainActor
final class ModulePreviewSimulator: ObservableObject {
    @Published private(set) var cpuPercent: Double = 12
    @Published private(set) var memoryPercent: Double = 35
    @Published private(set) var uploadBytesPerSecond: Double = 2_048
    @Published private(set) var downloadBytesPerSecond: Double = 12_288
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []

    static let tickSeconds: Double = 0.8

    private var timer: Timer?
    private var tick = 0

    func setRunning(_ running: Bool) {
        if running {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard timer == nil else { return }
        step()
        let timer = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.step()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        tick += 1

        cpuPercent = clampPercent(Self.sweep(tick: tick, period: 30, floor: 8, peak: 96, jitter: 4))
        memoryPercent = clampPercent(Self.sweep(tick: tick + 12, period: 44, floor: 28, peak: 92, jitter: 2))

        // Rates sweep in log space so the label walks the KB/s → MB/s ranges
        // instead of spending the whole cycle inside one unit.
        let magnitude = Self.sweep(tick: tick + 5, period: 36, floor: 3.3, peak: 7.2, jitter: 0.15)
        downloadBytesPerSecond = pow(10, magnitude)
        uploadBytesPerSecond = pow(10, max(3.0, magnitude - 0.9))

        append(&cpuHistory, cpuPercent)
        append(&memoryHistory, memoryPercent)
    }

    /// Triangle wave between floor and peak, smoothstep-eased so it leans
    /// into the ramps like real load, plus jitter so it never looks
    /// synthetic-flat.
    private static func sweep(tick: Int, period: Int, floor: Double, peak: Double, jitter: Double) -> Double {
        let phase = Double(tick % period) / Double(period)
        let triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2
        let eased = triangle * triangle * (3 - 2 * triangle)
        return floor + eased * (peak - floor) + Double.random(in: -jitter...jitter)
    }

    private func clampPercent(_ value: Double) -> Double {
        min(max(value, 2), 99)
    }

    /// Mirrors the real monitor: the first sample seeds the whole window flat
    /// so the sparkline never climbs out of zero.
    private func append(_ history: inout [Double], _ value: Double) {
        if history.isEmpty {
            history = [Double](repeating: value, count: SystemStatsMonitor.historyCapacity)
            return
        }
        history.append(value)
        if history.count > SystemStatsMonitor.historyCapacity {
            history.removeFirst(history.count - SystemStatsMonitor.historyCapacity)
        }
    }
}
