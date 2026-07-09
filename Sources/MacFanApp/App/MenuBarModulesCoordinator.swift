import AppKit
import Combine
import SwiftUI

/// Creates and tears down the optional CPU/RAM/network menu bar items as the
/// Display settings toggles change. Owns the shared detail-data monitors.
/// At Together spacing the modules fuse into one status item; every other
/// level keeps one independent item per module. The remaining style settings
/// (padding, graph length, colors) apply live through the label views.
@MainActor
final class MenuBarModulesCoordinator {
    private let model: AppModel
    private let processMonitor = ProcessStatsMonitor()
    private let networkInfoMonitor = NetworkInfoMonitor()

    private var cpuController: MetricStatusItemController?
    private var memoryController: MetricStatusItemController?
    private var networkController: MetricStatusItemController?
    private var fusedController: FusedModulesStatusItemController?
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model

        Publishers.CombineLatest4(
            model.settings.$showsCPUModule.removeDuplicates(),
            model.settings.$showsMemoryModule.removeDuplicates(),
            model.settings.$showsNetworkModule.removeDuplicates(),
            model.settings.$moduleSpacing.map { $0 == .together }.removeDuplicates()
        )
        .sink { [weak self] _ in
            // @Published emits on willSet; hop one runloop turn so sync reads
            // the committed toggle and spacing values from the store.
            DispatchQueue.main.async {
                self?.sync()
            }
        }
        .store(in: &cancellables)

        // The animated flag is captured when a detail view is built; rebuild
        // live so a Reduce Motion change reaches labels and open popovers.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                self?.rebuildModuleViews()
            }
            .store(in: &cancellables)
    }

    private func sync() {
        let modules = model.settings.enabledModules
        guard model.settings.moduleSpacing != .together else {
            cpuController = nil
            memoryController = nil
            networkController = nil
            syncFused(modules: modules)
            return
        }
        fusedController = nil

        // Creation order fixes the default left-to-right order to
        // CPU · RAM · NET, always left of the fan item.
        if modules.contains(.network), networkController == nil {
            networkController = makeNetworkController()
        } else if !modules.contains(.network) {
            networkController = nil
        }

        if modules.contains(.memory), memoryController == nil {
            memoryController = makeMemoryController()
        } else if !modules.contains(.memory) {
            memoryController = nil
        }

        if modules.contains(.cpu), cpuController == nil {
            cpuController = makeCPUController()
        } else if !modules.contains(.cpu) {
            cpuController = nil
        }
    }

    private func syncFused(modules: [SystemModuleKind]) {
        guard !modules.isEmpty else {
            fusedController = nil
            return
        }

        if let fusedController {
            fusedController.setModules(modules)
        } else {
            fusedController = FusedModulesStatusItemController(
                model: model,
                networkInfoMonitor: networkInfoMonitor,
                modules: modules,
                makeDetail: { [weak self] module in
                    self?.makeDetailContent(for: module) ?? AnyView(EmptyView())
                }
            )
        }
    }

    private func rebuildModuleViews() {
        cpuController?.rebuildViews()
        memoryController?.rebuildViews()
        networkController?.rebuildViews()
        fusedController?.rebuildViews()
    }

    /// Single construction point for the module detail popovers, shared by
    /// the split items and the fused item.
    private func makeDetailContent(for kind: SystemModuleKind) -> AnyView {
        // Reduce Motion gates continuous chart motion like Efficient mode.
        let animated =
            model.settings.performanceMode == .full
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        switch kind {
        case .cpu:
            return AnyView(
                CPUModuleDetailView(
                    stats: model.systemStats,
                    processes: processMonitor,
                    settings: model.settings,
                    tickSeconds: model.settings.controlTickSeconds,
                    animated: animated
                )
            )
        case .memory:
            return AnyView(
                MemoryModuleDetailView(
                    stats: model.systemStats,
                    processes: processMonitor,
                    settings: model.settings,
                    tickSeconds: model.settings.controlTickSeconds,
                    animated: animated
                )
            )
        case .network:
            return AnyView(
                NetworkModuleDetailView(
                    stats: model.systemStats,
                    info: networkInfoMonitor,
                    settings: model.settings,
                    tickSeconds: model.settings.controlTickSeconds,
                    animated: animated
                )
            )
        }
    }

    private func makeCPUController() -> MetricStatusItemController {
        let model = self.model
        return MetricStatusItemController(
            configuration: .init(
                autosaveName: "MacFan.module.cpu",
                makeAccessibilityTitle: { "system.cpu".localized },
                makeLabel: {
                    AnyView(
                        PercentModuleStatusLabel(
                            stats: model.systemStats,
                            settings: model.settings,
                            metric: .cpu
                        )
                    )
                },
                makeDetail: { [weak self] in
                    self?.makeDetailContent(for: .cpu) ?? AnyView(EmptyView())
                }
            )
        )
    }

    private func makeMemoryController() -> MetricStatusItemController {
        let model = self.model
        return MetricStatusItemController(
            configuration: .init(
                autosaveName: "MacFan.module.memory",
                makeAccessibilityTitle: { "system.memory".localized },
                makeLabel: {
                    AnyView(
                        PercentModuleStatusLabel(
                            stats: model.systemStats,
                            settings: model.settings,
                            metric: .memory
                        )
                    )
                },
                makeDetail: { [weak self] in
                    self?.makeDetailContent(for: .memory) ?? AnyView(EmptyView())
                }
            )
        )
    }

    private func makeNetworkController() -> MetricStatusItemController {
        let model = self.model
        let networkInfoMonitor = self.networkInfoMonitor
        return MetricStatusItemController(
            configuration: .init(
                autosaveName: "MacFan.module.network",
                makeAccessibilityTitle: { "system.network".localized },
                makeLabel: {
                    AnyView(
                        NetworkModuleStatusLabel(
                            stats: model.systemStats,
                            settings: model.settings
                        )
                    )
                },
                makeDetail: { [weak self] in
                    self?.makeDetailContent(for: .network) ?? AnyView(EmptyView())
                },
                onPopoverOpen: {
                    networkInfoMonitor.refresh()
                }
            )
        )
    }
}
