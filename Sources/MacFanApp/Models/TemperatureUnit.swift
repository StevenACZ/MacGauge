import Foundation

enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .celsius: "unit.celsius".localized
        case .fahrenheit: "unit.fahrenheit".localized
        }
    }

    var suffix: String {
        switch self {
        case .celsius: "C"
        case .fahrenheit: "F"
        }
    }

    func convert(celsius: Double) -> Double {
        switch self {
        case .celsius:
            return celsius
        case .fahrenheit:
            return celsius * 9.0 / 5.0 + 32.0
        }
    }
}
