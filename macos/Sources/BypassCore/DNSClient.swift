import Foundation
import Darwin

/// Минимальный DNS-клиент (A-запрос по UDP к заданному серверу). Нужен, чтобы узнать цепочку CNAME у DNS обычной сети:
/// система запрашивает цели CNAME отдельно и через DNS VPN, поэтому для них тоже нужны файлы /etc/resolver.
public enum DNSClient {
    public struct Answer: Equatable {
        /// Цели CNAME по порядку цепочки (без завершающей точки, в нижнем регистре).
        public var cnames: [String]
        public var addresses: [IPv4Target]
    }

    public static func buildQuery(name: String, id: UInt16) -> [UInt8] {
        // Заголовок: id, флаги (RD), QDCOUNT = 1; затем вопрос (имя, тип A, класс IN).
        var packet: [UInt8] = [UInt8(id >> 8), UInt8(id & 255), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            packet.append(UInt8(min(label.utf8.count, 63)))
            packet += Array(label.utf8.prefix(63))
        }
        packet += [0, 0, 1, 0, 1]
        return packet
    }

    /// Разбирает ответ: записи CNAME и A (с поддержкой сжатия имён).
    public static func parse(_ d: [UInt8], expectedID: UInt16? = nil) -> Answer? {
        guard d.count >= 12, d[2] & 0x80 != 0 else { return nil }
        if let expectedID, (UInt16(d[0]) << 8 | UInt16(d[1])) != expectedID { return nil }
        let questions = Int(d[4]) << 8 | Int(d[5])
        let answers = Int(d[6]) << 8 | Int(d[7])

        var pos = 12
        for _ in 0..<questions {
            guard let (_, next) = readName(d, pos), next + 4 <= d.count else { return nil }
            pos = next + 4
        }
        var cnames: [String] = []
        var addresses: [IPv4Target] = []
        for _ in 0..<answers {
            guard let (_, afterName) = readName(d, pos), afterName + 10 <= d.count else { return nil }
            let type = Int(d[afterName]) << 8 | Int(d[afterName + 1])
            let length = Int(d[afterName + 8]) << 8 | Int(d[afterName + 9])
            let data = afterName + 10
            guard data + length <= d.count else { return nil }
            if type == 5, let (target, _) = readName(d, data) {
                cnames.append(target)
            } else if type == 1, length == 4 {
                let value = UInt32(d[data]) << 24 | UInt32(d[data + 1]) << 16 | UInt32(d[data + 2]) << 8 | UInt32(d[data + 3])
                addresses.append(IPv4Target(address: value))
            }
            pos = data + length
        }
        return Answer(cnames: cnames, addresses: addresses)
    }

    /// Читает имя (в том числе со ссылками сжатия). Возвращает имя и позицию после него.
    static func readName(_ d: [UInt8], _ start: Int) -> (String, Int)? {
        var labels: [String] = []
        var pos = start
        var after: Int?
        var jumps = 0
        while true {
            guard pos < d.count else { return nil }
            let length = Int(d[pos])
            if length == 0 { pos += 1; break }
            if length & 0xC0 == 0xC0 {
                guard pos + 1 < d.count else { return nil }
                if after == nil { after = pos + 2 }
                pos = (length & 0x3F) << 8 | Int(d[pos + 1])
                jumps += 1
                if jumps > 10 { return nil }
                continue
            }
            guard length <= 63, pos + 1 + length <= d.count else { return nil }
            labels.append(String(decoding: d[(pos + 1)..<(pos + 1 + length)], as: UTF8.self).lowercased())
            pos += 1 + length
        }
        return (labels.joined(separator: "."), after ?? pos)
    }

    /// Блокирующий запрос A к серверу `server` (порт 53). nil при таймауте или ошибке.
    public static func query(_ name: String, server: UInt32, timeout: TimeInterval = 1.5) -> Answer? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(53).bigEndian
        addr.sin_addr.s_addr = server.bigEndian

        let id = UInt16.random(in: 1...UInt16.max)
        let packet = buildQuery(name: name, id: id)
        let sent = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else { return nil }

        var buffer = [UInt8](repeating: 0, count: 1500)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received > 0 else { return nil }
        return parse(Array(buffer[0..<received]), expectedID: id)
    }

    /// Параллельно узнаёт цепочки CNAME. В результате только имена с непустой цепочкой.
    public static func cnameChains(for hosts: [String], server: UInt32) async -> [String: [String]] {
        await withTaskGroup(of: (String, [String]?).self) { group in
            for host in hosts {
                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<(String, [String]?), Never>) in
                        DispatchQueue.global(qos: .utility).async {
                            cont.resume(returning: (host, query(host, server: server)?.cnames))
                        }
                    }
                }
            }
            var result: [String: [String]] = [:]
            for await (host, chain) in group {
                if let chain, !chain.isEmpty { result[host] = chain }
            }
            return result
        }
    }
}
