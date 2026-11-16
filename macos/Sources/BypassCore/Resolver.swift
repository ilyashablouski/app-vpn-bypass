import Foundation
import Darwin

public enum Resolver {
    /// Блокирующий резолв IPv4. nil при ошибке (чтобы не затирать прошлый результат).
    public static func resolveIPv4(_ host: String) -> [IPv4Target]? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(first) }

        var out = Set<IPv4Target>()
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let ai = p {
            if ai.pointee.ai_family == AF_INET, let sa = ai.pointee.ai_addr {
                let addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                out.insert(IPv4Target(address: addr))
            }
            p = ai.pointee.ai_next
        }
        return out.sorted()
    }

    /// Параллельный резолв. В результате отсутствуют домены, которые не удалось разрешить.
    public static func resolveAll(_ hosts: [String]) async -> [String: [IPv4Target]] {
        await withTaskGroup(of: (String, [IPv4Target]?).self) { group in
            for host in hosts {
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<(String, [IPv4Target]?), Never>) in
                        DispatchQueue.global(qos: .utility).async {
                            cont.resume(returning: (host, resolveIPv4(host)))
                        }
                    }
                }
            }
            var result: [String: [IPv4Target]] = [:]
            for await (host, ips) in group {
                if let ips { result[host] = ips }
            }
            return result
        }
    }
}
