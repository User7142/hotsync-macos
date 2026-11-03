import CoreWLAN
import Foundation

/// Die IPv4-Adressen dieses Macs, für den Netzwerk-HotSync: der Palm
/// braucht die Adresse des "primären PCs". WLAN und Ethernet zuerst,
/// Loopback und Link-Local nie.
enum LocalAddress {
    /// The name the Palm shows for this Mac: the computer name from Sharing.
    static var computerName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// The Wi-Fi interface's name ("en1"), where the Palm is.
    static var wifiInterface: String? { CWWiFiClient.shared().interface()?.interfaceName }

    static func address(ofInterface name: String) -> Address? {
        ipv4().first { $0.interface == name }
    }

    struct Address: Equatable {
        let interface: String
        let ip: String
        let netmask: String
    }

    static func ipv4() -> [Address] {
        var list: [Address] = []
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0, entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buffer)
            if ip.hasPrefix("169.254.") { continue }
            var netmask = "255.255.255.0"
            if let mask = entry.pointee.ifa_netmask,
               getnameinfo(mask, socklen_t(mask.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                netmask = String(cString: buffer)
            }
            list.append(Address(interface: String(cString: entry.pointee.ifa_name), ip: ip, netmask: netmask))
        }
        // WLAN zuerst (dort ist der Palm), dann Ethernet, dann VPN- und
        // Bridge-Schnittstellen
        let wifi = CWWiFiClient.shared().interface()?.interfaceName
        func rank(_ a: Address) -> Int {
            if a.interface == wifi { return 0 }
            return a.interface.hasPrefix("en") ? 1 : 2
        }
        return list.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            return ra != rb ? ra < rb : a.interface < b.interface
        }
    }
}
