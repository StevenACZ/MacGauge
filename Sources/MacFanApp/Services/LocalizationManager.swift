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

    /// SwiftPM's generated `Bundle.module` accessor only checks the main
    /// bundle root and the absolute `.build` path of the build machine, so a
    /// staged .app (resources in `Contents/Resources`) would abort at launch
    /// on every other Mac. Resolve the packaged locations first and keep
    /// `Bundle.module` only as the dev fallback (`swift run` / `swift test`).
    private nonisolated static let resourceBundle: Bundle = {
        let bundleName = "MacFan_MacFanApp.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,  // staged app: MacFan.app/Contents/Resources
            Bundle.main.bundleURL,  // bare executable next to the bundle
        ]
        for candidate in candidates {
            let url = candidate?.appendingPathComponent(bundleName)
            if let url, FileManager.default.fileExists(atPath: url.path),
                let bundle = Bundle(url: url)
            {
                return bundle
            }
        }
        return Bundle.module
    }()

    /// Resources live in the SwiftPM module bundle; fall back to `Bundle.main`
    /// for safety when the module bundle lacks the requested localization.
    private nonisolated static func resolveBundle(for language: String) -> Bundle {
        if let path = resourceBundle.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            return bundle
        }
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            return bundle
        }
        return resourceBundle
    }

    nonisolated func localizedString(_ key: String, arguments: CVarArg...) -> String {
        let selectedBundle = activeBundle ?? Self.resourceBundle
        let format = selectedBundle.localizedString(forKey: key, value: nil, table: "Localizable")

        if arguments.isEmpty {
            return format
        }

        return String(format: format, arguments: arguments)
    }
}
