import AppKit
import Combine
import SwiftUI

/// Creates and tears down the optional CPU/RAM/network menu bar items as the
/// Display settings toggles change. Owns the shared detail-data monitors.
@MainActor
final class MenuBarModulesCoordinator {
    private let model: AppModel
    private let processMonitor = ProcessStatsMonitor()
    private let networkInfoMonitor = NetworkInfoMonitor()

    private var cpuController: MetricStatusItemController?
    private var memoryController: MetricStatusItemController?
    private var networkController: MetricStatusItemController?
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model

        Publishers.CombineLatest3(
            model.settings.$showsCPUModule.removeDuplicates(),
            model.settings.$showsMemoryModule.removeDuplicates(),
            model.settings.$showsNetworkModule.removeDuplicates()
        )
        .sink { [weak self] showsCPU, showsMemory, showsNetwork in
            self?.sync(showsCPU: showsCPU, showsMemory: showsMemory, showsNetwork: showsNetwork)
        }
        .store(in: &cancellables)
    }

    private func sync(showsCPU: Bool, showsMemory: Bool, showsNetwork: Bool) {
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
                            title: "system.cpu".localized,
                            metric: \.cpuPercent,
                            history: \.cpuHistory,
                            color: Theme.accent,
                            tickSeconds: model.settings.controlTickSeconds
                        )
                    )
                },
                makeDetail: {
                    AnyView(
                        CPUModuleDetailView(
                            stats: model.systemStats,
                            processes: processMonitor,
                            tickSeconds: model.settings.controlTickSeconds
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
                            title: "system.memory".localized,
                            metric: \.memoryPercent,
                            history: \.memoryHistory,
                            color: .indigo,
                            tickSeconds: model.settings.controlTickSeconds
                        )
                    )
                },
                makeDetail: {
                    AnyView(
                        MemoryModuleDetailView(
                            stats: model.systemStats,
                            processes: processMonitor,
                            tickSeconds: model.settings.controlTickSeconds
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
                    AnyView(NetworkModuleStatusLabel(stats: model.systemStats))
                },
                makeDetail: {
                    AnyView(
                        NetworkModuleDetailView(
                            stats: model.systemStats,
                            info: networkInfoMonitor,
                            tickSeconds: model.settings.controlTickSeconds
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
