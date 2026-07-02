import Combine
import SwiftUI

/// MacFan localization manager.
///
/// Concurrency: lookups may run from any thread, so `localizedString` is
/// nonisolated and reads `activeBundle` — a benign-race mirror only written
/// on language changes. The Published bundle drives SwiftUI refreshes on the
/// main actor.
class LocalizationManager: ObservableObject {
    nonisolated static let shared = LocalizationManager()

    /// New installs follow the macOS UI language (es/en supported); users can
    /// still override it in Settings, which persists to the same key.
    nonisolated static var systemDefaultLanguage: String {
        Locale.preferredLanguages.first?.hasPrefix("es") == true ? "es" : "en"
    }

    @AppStorage("appLanguage") var language: String = LocalizationManager.systemDefaultLanguage {
        didSet {
            updateBundle()
        }
    }

    @Published var bundle: Bundle?

    private nonisolated(unsafe) var activeBundle: Bundle?

    var locale: Locale {
        Locale(identifier: language)
    }

    private nonisolated init() {
        let language =
            UserDefaults.standard.string(forKey: "appLanguage")
            ?? Self.systemDefaultLanguage
        activeBundle = Self.resolveBundle(for: language)
    }

    private func updateBundle() {
        let resolved = Self.resolveBundle(for: language)
        activeBundle = resolved
        bundle = resolved
    }

    /// Resources live in the SwiftPM module bundle; fall back to `Bundle.main`
    /// for safety when the module bundle lacks the requested localization.
    private nonisolated static func resolveBundle(for language: String) -> Bundle {
        if let path = Bundle.module.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            return bundle
        }
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            return bundle
        }
        return Bundle.module
    }

    nonisolated func localizedString(_ key: String, arguments: CVarArg...) -> String {
        let selectedBundle = activeBundle ?? Bundle.module
        let format = selectedBundle.localizedString(forKey: key, value: nil, table: "Localizable")

        if arguments.isEmpty {
            return format
        }

        return String(format: format, arguments: arguments)
    }
}
