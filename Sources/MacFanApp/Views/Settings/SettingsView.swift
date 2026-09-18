import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var loginManager: LaunchAtLoginManager
    @ObservedObject private var helperService: HelperCommandService
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab

    private let onShowWelcome: () -> Void
    private let onClose: (() -> Void)?

    init(model: AppModel, initialTab: SettingsTab = .general, onShowWelcome: @escaping () -> Void = {}, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onShowWelcome = onShowWelcome
        self.onClose = onClose
        _settings = ObservedObject(initialValue: model.settings)
        _loginManager = ObservedObject(initialValue: model.loginManager)
        _helperService = ObservedObject(initialValue: model.helperService)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            ZStack(alignment: .top) {
                tabContent(
                    GeneralSettingsTab(
                        settings: settings,
                        loginManager: loginManager,
                        setLaunchAtLogin: model.setLaunchAtLogin,
                        onShowWelcome: onShowWelcome
                    ),
                    tab: .general
                )
                tabContent(
                    ControlSettingsTab(
                        model: model,
                        settings: settings,
                        monitor: model.monitor,
                        helperService: helperService,
                        isActive: selectedTab == .control
                    ),
                    tab: .control
                )
                tabContent(
                    DisplaySettingsTab(
                        settings: settings,
                        monitor: model.monitor,
                        isActive: selectedTab == .display
                    ),
                    tab: .display
                )
                tabContent(
                    SafetySettingsTab(
                        model: model,
                        settings: settings,
                        helperService: helperService,
                        isActive: selectedTab == .safety
                    ),
                    tab: .safety
                )
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .frame(width: 680, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .tint(Theme.accent)
        .id(localization.language)
    }

    private var header: some View {
        HStack {
            Picker("popover.settings".localized, selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer(minLength: 12)
            Button("settings.close".localized, action: closeSettingsWindow)
        }
        .padding(.trailing, 8)
    }

    // Tabs stay alive behind an opacity toggle so per-tab state (scroll
    // position, pending edits) survives switching; only the active tab is
    // visible and hit-testable.
    private func tabContent(_ content: some View, tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return
            content
            .frame(width: SettingsLayout.contentWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(isSelected ? 1 : 0)
            .scaleEffect(isSelected ? 1 : 0.98)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .animation(Theme.Anim.smooth, value: selectedTab)
    }

    private func closeSettingsWindow() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
