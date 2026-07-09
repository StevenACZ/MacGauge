import AppKit
import SwiftUI

@main
struct MacFanMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The real settings window is AppDelegate.showSettings, which pins the
        // fixed 680x520 content size and snaps back programmatic resizes. This
        // scene only forwards, so the SwiftUI Settings route can never open an
        // unpinned duplicate window.
        Settings {
            SettingsSceneRedirect(model: appDelegate.model)
        }
    }
}

private struct SettingsSceneRedirect: View {
    let model: AppModel

    var body: some View {
        SceneWindowForwarder { window in
            window?.close()
            model.openSettings()
        }
        .frame(width: 0, height: 0)
    }
}

private struct SceneWindowForwarder: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            onWindow(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
