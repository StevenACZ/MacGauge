import Darwin
import Foundation
import SystemConfiguration

/// Resolves the primary interface, local/router IPs, and (on demand) the
/// public IP for the network detail popover. Refreshed when the popover opens.
@MainActor
final class NetworkInfoMonitor: ObservableObject {
    @Published private(set) var interfaceDisplayName: String?
    @Published private(set) var interfaceBSDName: String?
    @Published private(set) var localIPAddress: String?
    @Published private(set) var routerAddress: String?
    @Published private(set) var publicIPAddress: String?
    @Published private(set) var isFetchingPublicIP = false
    @Published private(set) var publicIPFetchFailed = false

    private var publicIPTask: Task<Void, Never>?

    func refresh() {
        readPrimaryInterface()
        if publicIPAddress == nil {
            fetchPublicIP()
        }
    }

    func fetchPublicIP() {
        publicIPTask?.cancel()
        isFetchingPublicIP = true
        publicIPFetchFailed = false
        publicIPTask = Task { [weak self] in
            let address = await Self.requestPublicIP()
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.isFetchingPublicIP = false
            if let address {
                self.publicIPAddress = address
                self.publicIPFetchFailed = false
            } else {
                self.publicIPFetchFailed = true
            }
        }
    }

    private func readPrimaryInterface() {
        let previousNetwork = (interfaceBSDName, localIPAddress, routerAddress)

        // IPv6-only networks have no IPv4 global state; fall back to the v6
        // primary so the popover still names the interface and router.
        let store = SCDynamicStoreCreate(nil, "MacFan" as CFString, nil, nil)
        let global = store.flatMap { store in
            (SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any])
                ?? (SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any])
        }

        if let global, let primary = global["PrimaryInterface"] as? String {
            interfaceBSDName = primary
            routerAddress = global["Router"] as? String
            interfaceDisplayName = Self.displayName(forBSDName: primary)
            localIPAddress =
                Self.ipAddress(forInterface: primary, family: AF_INET)
                ?? Self.ipAddress(forInterface: primary, family: AF_INET6)
        } else {
            interfaceDisplayName = nil
            interfaceBSDName = nil
            localIPAddress = nil
            routerAddress = nil
        }

        // A different network usually means a different public IP; drop the
        // cache so the fetch-on-open logic refetches instead of going stale.
        if (interfaceBSDName, localIPAddress, routerAddress) != previousNetwork {
            publicIPAddress = nil
        }
    }

    private static func displayName(forBSDName bsdName: String) -> String? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in interfaces {
            if SCNetworkInterfaceGetBSDName(interface) as String? == bsdName {
                return SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            }
        }
        return nil
    }

    private static func ipAddress(forInterface name: String, family: Int32) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }

        var cursor = addresses
        while let entry = cursor {
            let interface = entry.pointee
            cursor = interface.ifa_next

            guard String(cString: interface.ifa_name) == name,
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(family)
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    address, socklen_t(address.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0,
                    NI_NUMERICHOST
                ) == 0
            else { continue }
            let text = String(cString: host)
            // Link-local v6 addresses say nothing useful about the network.
            if family == AF_INET6, text.hasPrefix("fe80") { continue }
            return text
        }
        return nil
    }

    private static func requestPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty, text.count <= 45,
            text.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == ":" })
        else {
            return nil
        }
        return text
    }
}
