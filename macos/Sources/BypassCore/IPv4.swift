import Foundation

/// IPv4-адрес или подсеть. Адрес хранится в host byte order и сразу маскируется.
public struct IPv4Target: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let address: UInt32
    public let prefix: UInt8

    public init(address: UInt32, prefix: UInt8 = 32) {
        let p = min(prefix, 32)
        self.prefix = p
        self.address = address & IPv4Target.mask(for: p)
    }

    /// Разбирает "a.b.c.d" или "a.b.c.d/n". Возвращает nil при любой ошибке.
    public init?(_ text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, let addr = IPv4Target.parseAddress(parts[0]) else { return nil }
        var prefix: UInt8 = 32
        if parts.count == 2 {
            guard let p = UInt8(parts[1]), p <= 32 else { return nil }
            prefix = p
        }
        self.init(address: addr, prefix: prefix)
    }

    public var mask: UInt32 { IPv4Target.mask(for: prefix) }
    public var isHost: Bool { prefix == 32 }

    public var description: String {
        let a = IPv4Target.format(address)
        return isHost ? a : "\(a)/\(prefix)"
    }

    public static func < (l: IPv4Target, r: IPv4Target) -> Bool {
        l.address != r.address ? l.address < r.address : l.prefix < r.prefix
    }

    public static func mask(for prefix: UInt8) -> UInt32 {
        prefix == 0 ? 0 : UInt32.max << UInt32(32 - min(prefix, 32))
    }

    public static func format(_ a: UInt32) -> String {
        "\(a >> 24 & 255).\(a >> 16 & 255).\(a >> 8 & 255).\(a & 255)"
    }

    static func parseAddress(_ s: Substring) -> UInt32? {
        let octets = s.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var result: UInt32 = 0
        for o in octets {
            guard !o.isEmpty, o.count <= 3, let v = UInt8(o) else { return nil }
            result = result << 8 | UInt32(v)
        }
        return result
    }
}
