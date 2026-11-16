import Foundation
import Darwin

public struct RouteInfo: Equatable, Sendable {
    public var destination: UInt32
    public var mask: UInt32
    /// IPv4-шлюз (nil для link-маршрутов).
    public var gateway: UInt32?
    public var flags: Int32
    public var interface: String

    public init(destination: UInt32, mask: UInt32, gateway: UInt32?, flags: Int32, interface: String) {
        self.destination = destination
        self.mask = mask
        self.gateway = gateway
        self.flags = flags
        self.interface = interface
    }

    public var isDefault: Bool { destination == 0 && mask == 0 }
    public var isScoped: Bool { flags & RouteFlag.ifscope != 0 }
}

enum RouteFlag {
    static let up: Int32 = 0x1
    static let gateway: Int32 = 0x2
    static let host: Int32 = 0x4
    static let staticRoute: Int32 = 0x800
    static let ifscope: Int32 = 0x1000000
}

/// Разбор и чтение таблицы маршрутов ядра (sysctl NET_RT_DUMP) без запуска `netstat`.
public enum RouteTable {
    /// sizeof(struct rt_msghdr) на macOS.
    static let headerSize = 92

    /// Разбирает буфер NET_RT_DUMP. `ifName` превращает индекс интерфейса в имя.
    public static func parse(_ buf: [UInt8], ifName: (UInt16) -> String) -> [RouteInfo] {
        var routes: [RouteInfo] = []
        var off = 0
        while off + headerSize <= buf.count {
            let msgLen = Int(u16(buf, off))
            guard msgLen >= headerSize, off + msgLen <= buf.count else { break }
            let index = u16(buf, off + 4)
            let flags = Int32(bitPattern: u32(buf, off + 8))
            let addrs = Int(u32(buf, off + 12))
            let end = off + msgLen

            var p = off + headerSize
            var dst: UInt32?
            var gw: UInt32?
            var mask: UInt32?
            var bit = 0
            while bit < 8, p < end {
                if addrs & (1 << bit) != 0 {
                    let saLen = Int(buf[p])
                    let family = p + 1 < end ? buf[p + 1] : 0
                    // Адрес лежит в байтах 4..<8; укороченные sockaddr дополняются нулями.
                    var v: UInt32 = 0
                    for i in 4..<8 {
                        v = v << 8 | (i < saLen && p + i < end ? UInt32(buf[p + i]) : 0)
                    }
                    switch bit {
                    case 0: if family == UInt8(AF_INET) { dst = v }
                    case 1: if family == UInt8(AF_INET) { gw = v }
                    case 2: mask = v
                    default: break
                    }
                    p += saLen == 0 ? 4 : (saLen + 3) & ~3
                }
                bit += 1
            }
            if let dst {
                let m = mask ?? UInt32.max
                routes.append(RouteInfo(destination: dst, mask: m, gateway: gw,
                                        flags: flags, interface: ifName(index)))
            }
            off = end
        }
        return routes
    }

    /// Читает текущую таблицу IPv4-маршрутов.
    public static func current() -> [RouteInfo] {
        parse(dump(), ifName: interfaceName)
    }

    static func dump() -> [UInt8] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, 1 /* NET_RT_DUMP */, 0]
        for _ in 0..<4 {
            var len = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return [] }
            len += len / 8 // таблица может вырасти между вызовами
            var buf = [UInt8](repeating: 0, count: len)
            if sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 {
                return Array(buf[0..<len])
            }
            if errno != ENOMEM { break }
        }
        return []
    }

    private static func interfaceName(_ index: UInt16) -> String {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        return if_indextoname(UInt32(index), &name) != nil ? String(cString: name) : ""
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}

/// Выводы по таблице маршрутов: активен ли VPN и какой шлюз у физического интерфейса.
public enum NetworkState {
    /// VPN активен, если default-маршрут (или 0/1, 128.0/1) идёт через utun*.
    public static func isVPNActive(_ routes: [RouteInfo]) -> Bool {
        routes.contains { r in
            guard r.flags & RouteFlag.up != 0, !r.isScoped, r.interface.hasPrefix("utun") else { return false }
            return r.isDefault
                || (r.mask == 0x8000_0000 && (r.destination == 0 || r.destination == 0x8000_0000))
        }
    }

    /// Default-маршрут физического интерфейса (en*), включая scoped: при активном VPN
    /// системный default часто становится scoped.
    public static func physicalGateway(_ routes: [RouteInfo]) -> (gateway: UInt32, interface: String)? {
        let candidates = routes.filter { r in
            r.isDefault && r.gateway != nil && r.interface.hasPrefix("en")
                && r.interface.dropFirst(2).allSatisfy(\.isNumber)
        }
        let best = candidates.first { !$0.isScoped } ?? candidates.first
        guard let best, let gw = best.gateway else { return nil }
        return (gw, best.interface)
    }
}
