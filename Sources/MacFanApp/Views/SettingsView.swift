import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var loginManager: LaunchAtLoginManager
    @ObservedObject private var helperService: HelperCommandService
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab

    private let onClose: (() -> Void)?

    init(model: AppModel, initialTab: SettingsTab = .general, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
        _settings = ObservedObject(initialValue: model.settings)
        _loginManager = ObservedObject(initialValue: model.loginManager)
        _helperService = ObservedObject(initialValue: model.helperService)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .top) {
            tabContent(
                GeneralSettingsTab(
                    settings: settings,
                    loginManager: loginManager,
                    setLaunchAtLogin: model.setLaunchAtLogin
                ),
                tab: .general
            )
            tabContent(
                ControlSettingsTab(
                    model: model,
                    settings: settings,
                    monitor: model.monitor,
                    helperService: helperService
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
                    helperService: helperService
                ),
                tab: .safety
            )
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 20)
        .frame(width: 680, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("settings.close".localized) {
                    closeSettingsWindow()
                }
            }
        }
        .tint(Theme.accent)
        .id(localization.language)
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
