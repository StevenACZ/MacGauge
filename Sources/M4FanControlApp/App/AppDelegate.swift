import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusController: StatusItemController?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.presentSettings = { [weak self] tab in
            self?.showSettings(tab: tab)
        }
        model.start()
        statusController = StatusItemController(model: model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.restoreAutomaticOnQuitIfNeeded()
    }

    private func showSettings(tab: SettingsTab) {
        let hostingController = NSHostingController(rootView: SettingsView(model: model, initialTab: tab))

        if let window = settingsWindowController?.window {
            configureSettingsWindow(window)
            window.contentViewController = hostingController
            window.contentView?.wantsLayer = true
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 680, height: 520)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        configureSettingsWindow(window)
        window.contentViewController = hostingController
        window.contentView?.wantsLayer = true
        window.setContentSize(NSSize(width: 680, height: 520))
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
    }
}
