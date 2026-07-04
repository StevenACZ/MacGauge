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
        guard let store = SCDynamicStoreCreate(nil, "MacFan" as CFString, nil, nil),
            let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
            let primary = global["PrimaryInterface"] as? String
        else {
            interfaceDisplayName = nil
            interfaceBSDName = nil
            localIPAddress = nil
            routerAddress = nil
            return
        }

        interfaceBSDName = primary
        routerAddress = global["Router"] as? String
        interfaceDisplayName = Self.displayName(forBSDName: primary)
        localIPAddress = Self.ipv4Address(forInterface: primary)
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

    private static func ipv4Address(forInterface name: String) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }

        var cursor = addresses
        while let entry = cursor {
            let interface = entry.pointee
            cursor = interface.ifa_next

            guard String(cString: interface.ifa_name) == name,
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
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
            return String(cString: host)
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
