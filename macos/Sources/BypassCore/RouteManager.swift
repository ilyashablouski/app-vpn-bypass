import Foundation
import Darwin

/// Держит набор добавленных нами маршрутов и приводит его к желаемому через diff.
public final class RouteManager {
    public private(set) var owned = Set<IPv4Target>()
    public private(set) var gateway: UInt32?
    private let backend: RouteBackend

    public init(backend: RouteBackend) { self.backend = backend }

    /// Синхронизирует маршруты. Возвращает число ошибок добавления.
    @discardableResult
    public func sync(desired: Set<IPv4Target>, gateway newGateway: UInt32) -> Int {
        // Шлюз сменился (например, переключили Wi-Fi): старые маршруты ведут в никуда.
        if let old = gateway, old != newGateway { removeAll() }
        gateway = newGateway

        var wanted = desired
        wanted.remove(IPv4Target(address: newGateway)) // маршрут до самого шлюза не нужен
        let diff = RouteDiff.compute(desired: wanted, current: owned)

        for t in diff.remove {
            let e = backend.delete(t)
            if e == 0 || e == ESRCH { owned.remove(t) }
        }
        var failures = 0
        for t in diff.add {
            let e = backend.add(t, gateway: newGateway)
            if e == 0 {
                owned.insert(t)
            } else if e != EEXIST { // EEXIST: маршрут чужой, не трогаем и не удаляем
                failures += 1
            }
        }
        return failures
    }

    public func removeAll() {
        for t in owned { _ = backend.delete(t) }
        owned.removeAll()
        gateway = nil
    }

    /// Удаляет маршруты из файла состояния, оставшиеся после аварийного завершения.
    public static func cleanupLeftovers(at path: String, backend: RouteBackend) {
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                if let t = IPv4Target(String(line)) { _ = backend.delete(t) }
            }
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    public func persist(to path: String) {
        if owned.isEmpty {
            try? FileManager.default.removeItem(atPath: path)
        } else {
            try? owned.sorted().map(\.description).joined(separator: "\n").write(
                toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
