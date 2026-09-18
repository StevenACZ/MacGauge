import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let needsWelcome = WelcomeWindowController.needsFirstWelcome
    let model = AppModel()
    private var welcomeWindowController: WelcomeWindowController?
    private var statusController: StatusItemController?
    private var modulesCoordinator: MenuBarModulesCoordinator?
    private var settingsWindowController: NSWindowController?
    private var isSnappingSettingsWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if needsWelcome { UserDefaults.standard.set(true, forKey: "hasStartedWelcome") }
        model.presentSettings = { [weak self] tab in
            self?.showSettings(tab: tab)
        }
        model.start()
        UpdateManager.shared.start()
        statusController = StatusItemController(model: model)
        modulesCoordinator = MenuBarModulesCoordinator(model: model)
        if needsWelcome { showWelcome() }
    }

    // applicationWillTerminate cannot host the restore: the process exits
    // before any queued async work (or an XPC round-trip) gets to run, so the
    // quit-time restore must gate termination itself.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.needsHelperCoordinationOnQuit else { return .terminateNow }
        Task {
            await model.coordinateHelperForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func showWelcome() {
        if welcomeWindowController == nil {
            welcomeWindowController = WelcomeWindowController { [weak self] in
                self?.showSettings(tab: .safety)
            }
        }
        welcomeWindowController?.showWelcome()
    }

    func showAbout() {
        AboutWindowController.shared.showAbout()
    }

    private func showSettings(tab: SettingsTab) {
        let content = makeSettingsContent(tab: tab)

        if let window = settingsWindowController?.window {
            configureSettingsWindow(window)
            window.contentView = content
            window.setContentSize(Self.settingsWindowSize)
            centerSettingsWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.settingsWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureSettingsWindow(window)
        window.contentView = content
        window.setContentSize(Self.settingsWindowSize)
        centerSettingsWindow(window)

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsContent(tab: SettingsTab) -> NSView {
        let hosting = NSHostingView(
            rootView: SettingsView(
                model: model,
                initialTab: tab,
                onShowWelcome: { [weak self] in self?.showWelcome() },
                onClose: { [weak self] in
                    self?.settingsWindowController?.window?.close()
                }
            )
        )
        hosting.sizingOptions = []
        if #available(macOS 14.0, *) { hosting.safeAreaRegions = [] }

        let container = NSView(frame: NSRect(origin: .zero, size: Self.settingsWindowSize))
        container.wantsLayer = true
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return container
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.title = "MacGauge · " + "popover.settings".localized
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        // The SwiftUI content is a fixed 680x520, but the OS can still resize
        // the window programmatically (Sequoia edge tiling, toolbar reshapes),
        // leaving the content floating in dead space. Pinning min == max keeps
        // every resize path honest.
        window.contentMinSize = Self.settingsWindowSize
        window.contentMaxSize = Self.settingsWindowSize
        window.delegate = self
    }

    private func centerSettingsWindow(_ window: NSWindow) {
        let screen = screenForSettingsWindow(window)
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let centeredOrigin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )

        window.setFrameOrigin(
            NSPoint(
                x: clamp(centeredOrigin.x, lower: visibleFrame.minX, upper: visibleFrame.maxX - windowSize.width),
                y: clamp(centeredOrigin.y, lower: visibleFrame.minY, upper: visibleFrame.maxY - windowSize.height)
            ))
    }

    private func screenForSettingsWindow(_ window: NSWindow) -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? window.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }

    private static let settingsWindowSize = NSSize(width: 680, height: 520)
}

extension AppDelegate: NSWindowDelegate {
    // Belt over the min/max pin: programmatic setFrame calls (window tiling,
    // AppKit toolbar reshapes) can bypass contentMin/MaxSize, so any drifted
    // resize snaps straight back to the designed size.
    func windowDidResize(_ notification: Notification) {
        guard !isSnappingSettingsWindow,
            let window = notification.object as? NSWindow,
            window === settingsWindowController?.window,
            window.contentRect(forFrameRect: window.frame).size != Self.settingsWindowSize
        else { return }
        isSnappingSettingsWindow = true
        window.setContentSize(Self.settingsWindowSize)
        isSnappingSettingsWindow = false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            window === settingsWindowController?.window
        else { return }
        // Drop the SwiftUI tree so a closed settings window stops observing
        // the 1 Hz monitor publishers while the app runs around the clock;
        // reopening always builds a fresh hosting controller.
        DispatchQueue.main.async {
            window.contentView = nil
        }
    }
}
