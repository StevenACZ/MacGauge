import AppKit
import Combine
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AboutWindowController()

    private static let contentWidth: CGFloat = 380
    private static let frameAutosaveName = "MacFan.about"

    private var subscriptions = Set<AnyCancellable>()

    init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func showAbout() {
        let isNewWindow = window == nil
        if isNewWindow { buildWindow() }
        guard let window else { return }
        window.title = "about.title".localized
        let restoredFrame = isNewWindow && window.setFrameUsingName(Self.frameAutosaveName)
        applyContentSize()
        if isNewWindow && !restoredFrame { window.center() }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        observeContentChanges()
    }

    private func buildWindow() {
        let hosting = NSHostingView(rootView: AboutView())
        hosting.sizingOptions = []
        if #available(macOS 14.0, *) { hosting.safeAreaRegions = [] }

        let size = NSSize(width: Self.contentWidth, height: Self.contentWidth)
        hosting.frame = NSRect(origin: .zero, size: size)

        let targetWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        targetWindow.titleVisibility = .hidden
        targetWindow.titlebarAppearsTransparent = true
        targetWindow.titlebarSeparatorStyle = .none
        targetWindow.backgroundColor = .windowBackgroundColor
        targetWindow.isReleasedWhenClosed = false
        targetWindow.delegate = self
        targetWindow.setFrameAutosaveName(Self.frameAutosaveName)
        targetWindow.contentView = AboutWindowSurface(content: hosting, size: size)

        window = targetWindow
    }

    private func applyContentSize() {
        guard let window else { return }
        let measuring = NSHostingView(rootView: AboutView())
        measuring.sizingOptions = .intrinsicContentSize
        if #available(macOS 14.0, *) { measuring.safeAreaRegions = [] }
        let measured = measuring.fittingSize
        guard measured.height.isFinite, measured.height > 0 else { return }
        let size = NSSize(width: Self.contentWidth, height: ceil(measured.height))
        guard window.contentView?.frame.size != size else { return }
        let top = window.frame.maxY
        window.setContentSize(size)
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
    }

    private func observeContentChanges() {
        subscriptions.removeAll()

        // @Published emits on willSet: resize one runloop hop later, once the
        // SwiftUI tree has rebuilt with the new value.
        LocalizationManager.shared.$bundle
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard self?.window?.isVisible == true else { return }
                    self?.window?.title = "about.title".localized
                    self?.applyContentSize()
                }
            }
            .store(in: &subscriptions)

        Publishers.CombineLatest(
            UpdateManager.shared.$phase.map(Self.layoutKey),
            UpdateManager.shared.$manualCheckStatus
        )
        .removeDuplicates { $0 == $1 }
        .dropFirst()
        .sink { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.window?.isVisible == true else { return }
                self?.applyContentSize()
            }
        }
        .store(in: &subscriptions)
    }

    private static func layoutKey(_ phase: UpdateManager.Phase) -> UpdateManager.Phase {
        if case .downloading = phase { return .downloading(fraction: nil) }
        return phase
    }

    func windowWillClose(_ notification: Notification) {
        subscriptions.removeAll()
    }
}

private final class AboutWindowSurface: NSView {
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
