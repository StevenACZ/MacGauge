import AppKit
import Combine
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private static let completedKey = "hasCompletedWelcome"
    private let openSetup: () -> Void
    private var hostingView: NSHostingView<WelcomeView>?
    private var languageSubscription: AnyCancellable?
    private var measuredSizes: [String: NSSize] = [:]

    static var needsFirstWelcome: Bool {
        let persisted = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        return needsFirstWelcome(persisted: persisted)
    }

    static func needsFirstWelcome(persisted: [String: Any]?) -> Bool {
        guard let persisted else { return true }
        guard persisted[completedKey] as? Bool != true else { return false }
        if persisted["hasStartedWelcome"] as? Bool == true { return true }
        let existingKeys = [
            "temperatureUnit", "controlMode", "manualPercent",
            "curvePoints", "restoreAutomaticOnQuit", "dangerousRangesUnlocked",
            "normalUpperCelsius", "hotLowerCelsius", "normalColorHex",
            "mediumColorHex", "hotColorHex", "animateFanIcon",
            "controlTickSeconds", "showsCPUModule", "showsMemoryModule",
            "showsNetworkModule", "menuBarModulesSpacing", "cpuModuleGraphWidth",
            "memoryModuleGraphWidth", "cpuModuleColorMode", "memoryModuleColorMode",
            "networkModuleColorMode", "fanColorStyle", "performanceMode",
            "cpuNormalUpperPercent", "cpuHotLowerPercent", "cpuNormalColorHex",
            "cpuMediumColorHex", "cpuHotColorHex", "memoryNormalUpperPercent",
            "memoryHotLowerPercent", "memoryNormalColorHex", "memoryMediumColorHex",
            "memoryHotColorHex", "networkUpColorHex", "networkDownColorHex",
            "appLanguage", "helperEverReady", "autoUpdateCheckEnabled", "updateFeedURLOverride",
        ]
        return !existingKeys.contains { persisted[$0] != nil }
    }

    init(openSetup: @escaping () -> Void) {
        self.openSetup = openSetup
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func showWelcome() {
        let isNewWindow = window == nil
        rebuildContent()
        guard let window else { return }
        if isNewWindow { window.center() }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        languageSubscription = LocalizationManager.shared.$bundle.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.window?.isVisible == true else { return }
                self?.rebuildContent()
            }
        }
    }

    private func rebuildContent() {
        let view = WelcomeView(openSetup: openSetup) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            self?.close()
        }
        let language = LocalizationManager.shared.language
        let size: NSSize
        if let cached = measuredSizes[language] {
            size = cached
        } else {
            let measuring = NSHostingView(rootView: view)
            measuring.sizingOptions = .intrinsicContentSize
            if #available(macOS 14.0, *) { measuring.safeAreaRegions = [] }
            let measured = measuring.fittingSize
            guard measured.height.isFinite, measured.height > 0 else { return }
            size = NSSize(width: 480, height: ceil(measured.height))
            measuredSizes[language] = size
        }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        if #available(macOS 14.0, *) { hosting.safeAreaRegions = [] }
        hosting.frame = NSRect(origin: .zero, size: size)

        let targetWindow: NSWindow
        if let window {
            targetWindow = window
        } else {
            targetWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            targetWindow.titleVisibility = .hidden
            targetWindow.titlebarAppearsTransparent = true
            targetWindow.titlebarSeparatorStyle = .none
            targetWindow.backgroundColor = .windowBackgroundColor
            targetWindow.isReleasedWhenClosed = false
            targetWindow.delegate = self
            window = targetWindow
        }
        let oldFrame = targetWindow.frame
        targetWindow.title = "welcome.title".localized
        targetWindow.setFrame(
            NSRect(x: oldFrame.minX, y: oldFrame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
        hostingView = hosting
        targetWindow.contentView = WelcomeWindowSurface(content: hosting, size: size)
        hosting.sizingOptions = []
    }

    func windowWillClose(_ notification: Notification) {
        languageSubscription = nil
        hostingView = nil
        measuredSizes.removeAll()
        window?.contentView = nil
        window = nil
    }
}

private final class WelcomeWindowSurface: NSView {
    init(content: NSView, size: NSSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
