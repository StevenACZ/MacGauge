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
        let hostingController = NSHostingController(
            rootView: SettingsView(
                model: model,
                initialTab: tab,
                onClose: { [weak self] in
                    self?.settingsWindowController?.window?.close()
                }
            )
        )

        if let window = settingsWindowController?.window {
            configureSettingsWindow(window)
            window.contentViewController = hostingController
            window.contentView?.wantsLayer = true
            window.setContentSize(Self.settingsWindowSize)
            centerSettingsWindow(window)
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
        window.setContentSize(Self.settingsWindowSize)
        centerSettingsWindow(window)

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

    private func centerSettingsWindow(_ window: NSWindow) {
        let screen = screenForSettingsWindow(window)
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let centeredOrigin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )

        window.setFrameOrigin(NSPoint(
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
