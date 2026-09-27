import Foundation

enum SystemSettingsLabels {
    private static let table = loginItemsTable()

    private static let systemLoginItems = lookup(["Login Items & Extensions", "Login Items"])
    private static let systemBackgroundActivity = lookup([
        "Background App Activity", "App Background Activity", "Allow in the Background",
    ])
    private static let systemOpenAtLogin = lookup(["Open at Login"])
    static let application = lookup(["Application"])

    static var loginItems: String {
        systemLoginItems ?? "guide.login_items".localized
    }

    static var backgroundActivity: String {
        systemBackgroundActivity ?? "guide.background_activity".localized
    }

    static var openAtLogin: String {
        systemOpenAtLogin ?? "guide.open_at_login".localized
    }

    private static func lookup(_ keys: [String]) -> String? {
        keys.lazy.compactMap { table[$0] as? String }.first
    }

    /// Picked by the Mac's languages, not through Bundle lookups: those follow
    /// the localization MacGauge itself runs in, which is English on a Mac in
    /// any language MacGauge does not ship.
    private static func loginItemsTable() -> [String: Any] {
        guard let bundle = Bundle(path: "/System/Library/ExtensionKit/Extensions/LoginItems.appex") else { return [:] }
        if let url = bundle.url(forResource: "Localizable", withExtension: "loctable"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        {
            let tables = plist.compactMapValues { $0 as? [String: Any] }
            let localization = Bundle.preferredLocalizations(
                from: Array(tables.keys),
                forPreferences: Locale.preferredLanguages
            ).first
            return localization.flatMap { tables[$0] } ?? [:]
        }
        let localization = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: Locale.preferredLanguages
        ).first
        guard
            let path = bundle.path(
                forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: localization)
        else { return [:] }
        return NSDictionary(contentsOfFile: path) as? [String: Any] ?? [:]
    }
}
