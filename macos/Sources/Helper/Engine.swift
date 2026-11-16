import Foundation
import BypassCore
import os

/// Периодически приводит маршруты к желаемому состоянию.
actor Engine {
    private let log = Logger(subsystem: Constants.helperLabel, category: "engine")
    private let manager: RouteManager
    private var request: StartRequest?
    private var loop: Task<Void, Never>?
    private var generation = 0

    /// Последний удачный резолв доменов (при сбое DNS остаётся прошлый результат).
    private var resolved: [String: [IPv4Target]] = [:]
    /// IP соединений приложений с временем последнего появления.
    private var appSeen: [IPv4Target: Date] = [:]
    private let appRetention: TimeInterval = 600

    private var lastError: String?

    init(backend: RouteBackend) {
        manager = RouteManager(backend: backend)
    }

    func start(_ req: StartRequest) {
        request = req
        generation += 1
        loop?.cancel()
        let gen = generation
        let interval = UInt64(max(5, req.interval)) * 1_000_000_000
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync(generation: gen)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
        request = nil
        resolved.removeAll()
        appSeen.removeAll()
        manager.removeAll()
        manager.persist(to: Constants.routesStatePath)
        lastError = nil
    }

    func status() -> HelperStatus {
        HelperStatus(running: loop != nil, routeCount: manager.owned.count,
                     gateway: manager.gateway.map(IPv4Target.format), lastError: lastError)
    }

    private func sync(generation gen: Int) async {
        guard gen == generation, let req = request else { return }

        let routes = RouteTable.current()
        let gateway: UInt32
        if let manual = req.gateway, let ip = IPv4Target(manual) {
            gateway = ip.address
        } else if let detected = NetworkState.physicalGateway(routes) {
            gateway = detected.gateway
        } else {
            lastError = "Не удалось определить шлюз физического интерфейса"
            log.error("gateway not found")
            return
        }

        var staticTargets = Set<IPv4Target>()
        var hostNames: [String] = []
        var apps: [Entry] = []
        for e in req.entries {
            switch e.kind {
            case .app: apps.append(e)
            case .host:
                if let t = IPv4Target(e.value) { staticTargets.insert(t) }
                else { hostNames.append(Validation.stripWildcard(e.value)) }
            }
        }

        let names = Array(Set(hostNames))
        let appEntries = apps
        async let dns = Resolver.resolveAll(names)
        async let live = Task.detached(priority: .utility) { AppConnections.remoteAddresses(for: appEntries) }.value
        let (dnsResult, liveIPs) = await (dns, live)
        guard gen == generation else { return } // запрос обновили, пока резолвили

        for (host, ips) in dnsResult { resolved[host] = ips }
        let activeHosts = Set(hostNames)
        resolved = resolved.filter { activeHosts.contains($0.key) }
        for h in activeHosts where resolved[h] == nil { log.notice("no IPs for \(h, privacy: .public)") }

        let now = Date()
        for ip in liveIPs { appSeen[ip] = now }
        appSeen = appSeen.filter { now.timeIntervalSince($0.value) < appRetention }

        var desired = staticTargets
        for ips in resolved.values { desired.formUnion(ips) }
        desired.formUnion(appSeen.keys)

        let failures = manager.sync(desired: desired, gateway: gateway)
        manager.persist(to: Constants.routesStatePath)
        lastError = failures > 0 ? "Не удалось добавить маршрутов: \(failures)" : nil
        log.info("routes=\(self.manager.owned.count) failures=\(failures)")
    }
}
