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
        .sink { [weak self] showsCPU, showsMemory, showsNetwork, fused in
            self?.sync(showsCPU: showsCPU, showsMemory: showsMemory, showsNetwork: showsNetwork, fused: fused)
        }
        .store(in: &cancellables)
    }

    private func sync(showsCPU: Bool, showsMemory: Bool, showsNetwork: Bool, fused: Bool) {
        guard !fused else {
            cpuController = nil
            memoryController = nil
            networkController = nil
            syncFused(showsCPU: showsCPU, showsMemory: showsMemory, showsNetwork: showsNetwork)
            return
        }
        fusedController = nil

        // Creation order fixes the default left-to-right order to
        // CPU · RAM · NET, always left of the fan item.
        if showsNetwork, networkController == nil {
            networkController = makeNetworkController()
        } else if !showsNetwork {
            networkController = nil
        }

        if showsMemory, memoryController == nil {
            memoryController = makeMemoryController()
        } else if !showsMemory {
            memoryController = nil
        }

        if showsCPU, cpuController == nil {
            cpuController = makeCPUController()
        } else if !showsCPU {
            cpuController = nil
        }
    }

    private func syncFused(showsCPU: Bool, showsMemory: Bool, showsNetwork: Bool) {
        var modules: [SystemModuleKind] = []
        if showsCPU { modules.append(.cpu) }
        if showsMemory { modules.append(.memory) }
        if showsNetwork { modules.append(.network) }

        guard !modules.isEmpty else {
            fusedController = nil
            return
        }

        if let fusedController {
            fusedController.setModules(modules)
        } else {
            fusedController = FusedModulesStatusItemController(
                model: model,
                processMonitor: processMonitor,
                networkInfoMonitor: networkInfoMonitor,
                modules: modules
            )
        }
    }

    private func makeCPUController() -> MetricStatusItemController {
        let model = self.model
        let processMonitor = self.processMonitor
        return MetricStatusItemController(
            configuration: .init(
                autosaveName: "MacFan.module.cpu",
                accessibilityTitle: "system.cpu".localized,
                makeLabel: {
                    AnyView(
                        PercentModuleStatusLabel(
                            stats: model.systemStats,
                            settings: model.settings,
                            metric: .cpu
                        )
                    )
                },
                makeDetail: {
                    AnyView(
                        CPUModuleDetailView(
                            stats: model.systemStats,
                            processes: processMonitor,
                            tickSeconds: model.settings.controlTickSeconds,
                            animated: model.settings.performanceMode == .full
                        )
                    )
                }
            )
        )
    }

    private func makeMemoryController() -> MetricStatusItemController {
        let model = self.model
        let processMonitor = self.processMonitor
        return MetricStatusItemController(
            configuration: .init(
                autosaveName: "MacFan.module.memory",
                accessibilityTitle: "system.memory".localized,
                makeLabel: {
                    AnyView(
                        PercentModuleStatusLabel(
                            stats: model.systemStats,
                            settings: model.settings,
                            metric: .memory
                        )
                    )
                },
                makeDetail: {
                    AnyView(
                        MemoryModuleDetailView(
                            stats: model.systemStats,
                            processes: processMonitor,
                            tickSeconds: model.settings.controlTickSeconds,
                            animated: model.settings.performanceMode == .full
                        )
                    )
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
                accessibilityTitle: "system.network".localized,
                makeLabel: {
                    AnyView(
                        NetworkModuleStatusLabel(
                            stats: model.systemStats,
                            settings: model.settings
                        )
                    )
                },
                makeDetail: {
                    AnyView(
                        NetworkModuleDetailView(
                            stats: model.systemStats,
                            info: networkInfoMonitor,
                            tickSeconds: model.settings.controlTickSeconds,
                            animated: model.settings.performanceMode == .full
                        )
                    )
                },
                onPopoverOpen: {
                    networkInfoMonitor.refresh()
                }
            )
        )
    }
}
