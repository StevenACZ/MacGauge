import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        statusController = StatusItemController(model: model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.restoreAutomaticOnQuitIfNeeded()
    }
}
