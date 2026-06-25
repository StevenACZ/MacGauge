import Foundation
import M4FanCore

@MainActor
final class AppSettingsStore: ObservableObject {
    private enum Key {
        static let temperatureUnit = "temperatureUnit"
        static let controlMode = "controlMode"
        static let manualPercent = "manualPercent"
        static let curvePoints = "curvePoints"
        static let restoreAutomaticOnQuit = "restoreAutomaticOnQuit"
        static let dangerousRangesUnlocked = "dangerousRangesUnlocked"
        static let curveRunMinutes = "curveRunMinutes"
        static let normalUpperCelsius = "normalUpperCelsius"
        static let hotLowerCelsius = "hotLowerCelsius"
        static let normalColorHex = "normalColorHex"
        static let mediumColorHex = "mediumColorHex"
        static let hotColorHex = "hotColorHex"
        static let animateFanIcon = "animateFanIcon"
    }

    private let defaults: UserDefaults

    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }

    @Published var controlMode: FanControlMode {
        didSet { defaults.set(controlMode.rawValue, forKey: Key.controlMode) }
    }

    @Published var manualPercent: Double {
        didSet { defaults.set(manualPercent, forKey: Key.manualPercent) }
    }

    @Published var curvePoints: [CurvePoint] {
        didSet { saveCurvePoints() }
    }

    @Published var restoreAutomaticOnQuit: Bool {
        didSet { defaults.set(restoreAutomaticOnQuit, forKey: Key.restoreAutomaticOnQuit) }
    }

    @Published var dangerousRangesUnlocked: Bool {
        didSet { defaults.set(dangerousRangesUnlocked, forKey: Key.dangerousRangesUnlocked) }
    }

    @Published var curveRunMinutes: Double {
        didSet { defaults.set(curveRunMinutes, forKey: Key.curveRunMinutes) }
    }

    @Published var normalUpperCelsius: Double {
        didSet { defaults.set(normalUpperCelsius, forKey: Key.normalUpperCelsius) }
    }

    @Published var hotLowerCelsius: Double {
        didSet { defaults.set(hotLowerCelsius, forKey: Key.hotLowerCelsius) }
    }

    @Published var normalColorHex: String {
        didSet { defaults.set(normalColorHex, forKey: Key.normalColorHex) }
    }

    @Published var mediumColorHex: String {
        didSet { defaults.set(mediumColorHex, forKey: Key.mediumColorHex) }
    }

    @Published var hotColorHex: String {
        didSet { defaults.set(hotColorHex, forKey: Key.hotColorHex) }
    }

    @Published var animateFanIcon: Bool {
        didSet { defaults.set(animateFanIcon, forKey: Key.animateFanIcon) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Key.temperatureUnit) ?? "") ?? .celsius
        controlMode = FanControlMode(rawValue: defaults.string(forKey: Key.controlMode) ?? "") ?? .monitor

        let storedPercent = defaults.object(forKey: Key.manualPercent) as? Double
        manualPercent = storedPercent ?? 45

        curvePoints = Self.loadCurvePoints(defaults: defaults)

        if defaults.object(forKey: Key.restoreAutomaticOnQuit) == nil {
            restoreAutomaticOnQuit = true
        } else {
            restoreAutomaticOnQuit = defaults.bool(forKey: Key.restoreAutomaticOnQuit)
        }

        dangerousRangesUnlocked = defaults.bool(forKey: Key.dangerousRangesUnlocked)

        let storedMinutes = defaults.object(forKey: Key.curveRunMinutes) as? Double
        curveRunMinutes = storedMinutes ?? 10

        normalUpperCelsius = defaults.object(forKey: Key.normalUpperCelsius) as? Double ?? 45
        hotLowerCelsius = defaults.object(forKey: Key.hotLowerCelsius) as? Double ?? 70
        normalColorHex = defaults.string(forKey: Key.normalColorHex) ?? "#FFFFFF"
        mediumColorHex = defaults.string(forKey: Key.mediumColorHex) ?? "#FF9500"
        hotColorHex = defaults.string(forKey: Key.hotColorHex) ?? "#FF453A"

        if defaults.object(forKey: Key.animateFanIcon) == nil {
            animateFanIcon = true
        } else {
            animateFanIcon = defaults.bool(forKey: Key.animateFanIcon)
        }
    }

    var curveCommandPoints: String {
        curvePoints
            .sorted { $0.temperatureCelsius < $1.temperatureCelsius }
            .map { point in
                "\(Int(point.temperatureCelsius.rounded())):\(Int(point.percent.rounded()))"
            }
            .joined(separator: ",")
    }

    var curve: FanCurve? {
        try? FanCurve(points: curvePoints.map { ($0.temperatureCelsius, $0.percent) })
    }

    var visualRules: TemperatureVisualRules {
        TemperatureVisualRules(normalUpperCelsius: normalUpperCelsius, hotLowerCelsius: hotLowerCelsius)
    }

    func addCurvePoint() {
        let nextTemperature = min(100, (curvePoints.map(\.temperatureCelsius).max() ?? 60) + 10)
        let nextPercent = min(90, (curvePoints.map(\.percent).max() ?? 50) + 10)
        curvePoints.append(CurvePoint(temperatureCelsius: nextTemperature, percent: nextPercent))
    }

    func removeCurvePoints(at offsets: IndexSet) {
        guard curvePoints.count - offsets.count >= 2 else { return }
        curvePoints.remove(atOffsets: offsets)
    }

    func removeCurvePoint(id: UUID) {
        guard curvePoints.count > 2 else { return }
        curvePoints.removeAll { $0.id == id }
    }

    func resetCurveDefaults() {
        curvePoints = Self.defaultCurvePoints
    }

    func saveCurvePoints() {
        guard let data = try? JSONEncoder().encode(curvePoints) else { return }
        defaults.set(data, forKey: Key.curvePoints)
    }

    private static func loadCurvePoints(defaults: UserDefaults) -> [CurvePoint] {
        guard let data = defaults.data(forKey: Key.curvePoints),
              let decoded = try? JSONDecoder().decode([CurvePoint].self, from: data),
              decoded.count >= 2
        else {
            return defaultCurvePoints
        }
        return decoded
    }

    private static var defaultCurvePoints: [CurvePoint] {
        [
            CurvePoint(temperatureCelsius: 40, percent: 40),
            CurvePoint(temperatureCelsius: 60, percent: 50),
            CurvePoint(temperatureCelsius: 80, percent: 80)
        ]
    }
}
