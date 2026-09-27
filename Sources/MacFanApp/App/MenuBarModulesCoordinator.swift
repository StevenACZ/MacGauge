import AppKit
import Combine
import SwiftUI

/// Creates and tears down the optional CPU/RAM/network menu bar items as the
/// Display settings toggles change. Owns the shared detail-data monitors.
/// At Together spacing the modules join the fan's own status item; every
/// other level keeps one independent item per module. The remaining style settings
/// (padding, graph length, colors) apply live through the label views.
@MainActor
final class MenuBarModulesCoordinator {
    private let model: AppModel
    private let fanItem: StatusItemController
    private let processMonitor = ProcessStatsMonitor()
    private let networkInfoMonitor = NetworkInfoMonitor()

    private var cpuController: MetricStatusItemController?
    private var memoryController: MetricStatusItemController?
    private var networkController: MetricStatusItemController?
    private var fusedStrip: FusedModulesStrip?
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, fanItem: StatusItemController) {
        self.model = model
        self.fanItem = fanItem

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
        dropFusedStrip()

        if modules.contains(.memory), memoryController == nil {
            placeNextToFan("MacFan.module.memory", rank: 1)
            memoryController = makeMemoryController()
        } else if !modules.contains(.memory) {
            memoryController = nil
        }

        if modules.contains(.cpu), cpuController == nil {
            placeNextToFan("MacFan.module.cpu", rank: 2)
            cpuController = makeCPUController()
        } else if !modules.contains(.cpu) {
            cpuController = nil
        }

        if modules.contains(.network), networkController == nil {
            placeNextToFan("MacFan.module.network", rank: 3)
            networkController = makeNetworkController()
        } else if !modules.contains(.network) {
            networkController = nil
        }
    }

    private func syncFused(modules: [SystemModuleKind]) {
        guard !modules.isEmpty else {
            dropFusedStrip()
            return
        }

        if let fusedStrip {
            fusedStrip.setModules(modules)
        } else {
            let strip = FusedModulesStrip(
                model: model,
                networkInfoMonitor: networkInfoMonitor,
                modules: modules,
                host: fanItem,
                makeDetail: { [weak self] module in
                    self?.makeDetailContent(for: module) ?? AnyView(EmptyView())
                }
            )
            fanItem.attachLeadingContent(strip)
            fusedStrip = strip
        }
    }

    private func dropFusedStrip() {
        guard fusedStrip != nil else { return }
        fanItem.detachLeadingContent()
        fusedStrip = nil
    }

    /// macOS forgets a status item's position once the item is removed, so a
    /// recreated module item would land left of every other app's item. A
    /// missing position is seeded just left of the fan, higher rank further
    /// left, keeping NET · CPU · RAM · fan together until the user moves them.
    private func placeNextToFan(_ autosaveName: String, rank: Double) {
        let defaults = UserDefaults.standard
        let key = Self.positionKey(autosaveName)
        let fanKey = Self.positionKey(fanItem.autosaveName)
        guard defaults.object(forKey: key) == nil, defaults.object(forKey: fanKey) != nil else { return }
        defaults.set(defaults.double(forKey: fanKey) + rank, forKey: key)
    }

    private static func positionKey(_ autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    private func rebuildModuleViews() {
        cpuController?.rebuildViews()
        memoryController?.rebuildViews()
        networkController?.rebuildViews()
        fusedStrip?.rebuildViews()
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
