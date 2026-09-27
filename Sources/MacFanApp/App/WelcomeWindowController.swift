import AppKit
import Combine
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 520, height: 540)
    private static let completedKey = "hasCompletedWelcome"
    private let model: AppModel
    private var steps: [WelcomeStep] = []
    private var hostingView: NSHostingView<WelcomeView>?
    private var languageSubscription: AnyCancellable?

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

    init(model: AppModel) {
        self.model = model
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show(fanControlOnly: Bool) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        steps =
            fanControlOnly
            ? [.fanControl]
            : (model.monitor.snapshot.isFanless ? [] : [.fanControl]) + [.openAtLogin, .done]
        let window = makeWindow()
        window.contentView = WelcomeWindowSurface(content: makeHostingView(), size: Self.contentSize)
        window.title = windowTitle
        window.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        languageSubscription = LocalizationManager.shared.$bundle.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let hostingView = self.hostingView else { return }
                hostingView.rootView = self.makeRootView()
                self.window?.title = self.windowTitle
            }
        }
    }

    private var windowTitle: String {
        (steps.contains(.done) ? "welcome.title" : "welcome.fan.setup_title").localized
    }

    private func makeRootView() -> WelcomeView {
        WelcomeView(
            model: model,
            helperService: model.helperService,
            loginManager: model.loginManager,
            monitor: model.monitor,
            steps: steps
        ) { [weak self] in
            guard let self else { return }
            if self.steps.contains(.done) {
                UserDefaults.standard.set(true, forKey: Self.completedKey)
            }
            self.close()
        }
    }

    private func makeHostingView() -> NSHostingView<WelcomeView> {
        let hosting = NSHostingView(rootView: makeRootView())
        hosting.sizingOptions = []
        if #available(macOS 14.0, *) { hosting.safeAreaRegions = [] }
        hosting.frame = NSRect(origin: .zero, size: Self.contentSize)
        hostingView = hosting
        return hosting
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        languageSubscription = nil
        hostingView = nil
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
