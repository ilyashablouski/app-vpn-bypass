import Foundation
import Darwin

public protocol RouteBackend {
    /// Возвращает errno (0 при успехе).
    func add(_ target: IPv4Target, gateway: UInt32) -> Int32
    func delete(_ target: IPv4Target) -> Int32
}

/// Построение сообщений RTM_ADD / RTM_DELETE для PF_ROUTE сокета.
public enum RouteMessage {
    static let rtmAdd: UInt8 = 1
    static let rtmDelete: UInt8 = 2
    static let version: UInt8 = 5
    static let rtaDst: UInt32 = 1, rtaGateway: UInt32 = 2, rtaNetmask: UInt32 = 4

    public static func add(_ t: IPv4Target, gateway: UInt32, seq: UInt32) -> [UInt8] {
        var flags = RouteFlag.up | RouteFlag.gateway | RouteFlag.staticRoute
        var addrs = rtaDst | rtaGateway
        if t.isHost { flags |= RouteFlag.host } else { addrs |= rtaNetmask }
        var sockaddrs = sockaddrIn(t.address) + sockaddrIn(gateway)
        if !t.isHost { sockaddrs += sockaddrIn(t.mask) }
        return build(type: rtmAdd, flags: flags, addrs: addrs, seq: seq, body: sockaddrs)
    }

    public static func delete(_ t: IPv4Target, seq: UInt32) -> [UInt8] {
        var flags = RouteFlag.up | RouteFlag.staticRoute
        var addrs = rtaDst
        var sockaddrs = sockaddrIn(t.address)
        if t.isHost { flags |= RouteFlag.host } else {
            addrs |= rtaNetmask
            sockaddrs += sockaddrIn(t.mask)
        }
        return build(type: rtmDelete, flags: flags, addrs: addrs, seq: seq, body: sockaddrs)
    }

    /// struct sockaddr_in (16 байт): len, family, port, addr (сетевой порядок), zero[8].
    static func sockaddrIn(_ hostOrder: UInt32) -> [UInt8] {
        [16, UInt8(AF_INET), 0, 0,
         UInt8(hostOrder >> 24 & 255), UInt8(hostOrder >> 16 & 255),
         UInt8(hostOrder >> 8 & 255), UInt8(hostOrder & 255),
         0, 0, 0, 0, 0, 0, 0, 0]
    }

    static func build(type: UInt8, flags: Int32, addrs: UInt32, seq: UInt32, body: [UInt8]) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: RouteTable.headerSize)
        let total = UInt16(RouteTable.headerSize + body.count)
        put16(&m, 0, total)
        m[2] = version
        m[3] = type
        put32(&m, 8, UInt32(bitPattern: flags))
        put32(&m, 12, addrs)
        put32(&m, 20, seq)
        return m + body
    }

    private static func put16(_ b: inout [UInt8], _ o: Int, _ v: UInt16) {
        b[o] = UInt8(v & 255); b[o + 1] = UInt8(v >> 8)
    }

    private static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for i in 0..<4 { b[o + i] = UInt8(v >> UInt32(8 * i) & 255) }
    }
}

/// Один PF_ROUTE сокет на всё время жизни: без fork/exec `/sbin/route`.
public final class RouteSocket: RouteBackend {
    private let fd: Int32
    private var seq: UInt32 = 0

    public init?() {
        fd = socket(PF_ROUTE, SOCK_RAW, 0)
        guard fd >= 0 else { return nil }
        shutdown(fd, SHUT_RD) // ответы ядра нам не нужны, ошибки приходят из write()
    }

    deinit { close(fd) }

    public func add(_ t: IPv4Target, gateway: UInt32) -> Int32 {
        seq &+= 1
        return send(RouteMessage.add(t, gateway: gateway, seq: seq))
    }

    public func delete(_ t: IPv4Target) -> Int32 {
        seq &+= 1
        return send(RouteMessage.delete(t, seq: seq))
    }

    private func send(_ msg: [UInt8]) -> Int32 {
        let n = msg.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        return n == msg.count ? 0 : (errno == 0 ? EIO : errno)
    }
}

/// Разница между желаемым и текущим набором маршрутов.
public struct RouteDiff: Equatable {
    public var add: [IPv4Target]
    public var remove: [IPv4Target]

    public static func compute(desired: Set<IPv4Target>, current: Set<IPv4Target>) -> RouteDiff {
        RouteDiff(add: desired.subtracting(current).sorted(),
                  remove: current.subtracting(desired).sorted())
    }
}
