import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var loginManager: LaunchAtLoginManager
    @ObservedObject private var helperService: HelperCommandService
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
        VStack(spacing: 0) {
            selectedTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
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
                Button("Cerrar") {
                    closeSettingsWindow()
                }
            }
        }
        .tint(.blue)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab(
                settings: settings,
                loginManager: loginManager,
                setLaunchAtLogin: model.setLaunchAtLogin
            )
        case .control:
            ControlSettingsTab(
                model: model,
                settings: settings,
                monitor: model.monitor,
                helperService: helperService
            )
        case .display:
            DisplaySettingsTab(settings: settings)
        case .safety:
            SafetySettingsTab(
                model: model,
                settings: settings,
                helperService: helperService
            )
        }
    }

    private func closeSettingsWindow() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
