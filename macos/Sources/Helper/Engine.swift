import Foundation
import BypassCore
import os

/// Периодически приводит маршруты к желаемому состоянию.
///
/// Экономия ресурсов: цикл работает с низким приоритетом и допуском таймера (пробуждения объединяются
/// системой), интервал растёт, пока ничего не меняется, смена сети ловится событием PF_ROUTE, а в простое
/// (исключения остановлены) процесс завершается и освобождает память.
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
    /// Сколько циклов подряд маршруты не менялись (для адаптивного интервала).
    private var unchanged = 0
    private var lastSyncEnd = Date.distantPast

    /// Цепочки CNAME доменов (системе нужны resolver-файлы и для их звеньев).
    private var cnameTargets: [String: [String]] = [:]
    /// Есть ли у нас файлы в /etc/resolver (чтобы убрать их, если режим выключили).
    private var managesResolverFiles = false
    private var watcher: RouteChangeWatcher?
    private var idleExit: Task<Void, Never>?
    private let idleTimeout: UInt64 = 60

    private var observers: [UUID: (HelperStatus) -> Void] = [:]
    private var lastPublished: HelperStatus?

    init(backend: RouteBackend) {
        manager = RouteManager(backend: backend)
    }

    /// Вызывается один раз при запуске демона: если им никто не пользуется, он завершится.
    func begin() { scheduleIdleExit() }

    // MARK: Управление

    /// Применяет запрос и возвращается после первой синхронизации, чтобы статус сразу был точным.
    func start(_ req: StartRequest) async {
        idleExit?.cancel()
        idleExit = nil
        request = req
        generation += 1
        loop?.cancel()
        loop = nil
        unchanged = 0
        let gen = generation

        if watcher == nil {
            let w = RouteChangeWatcher(debounce: 1.5) { [weak self] in
                Task { await self?.networkChanged() }
            }
            w.start()
            watcher = w
        }

        await sync(generation: gen)
        guard gen == generation else { return } // за время синхронизации пришёл новый запрос или stop()
        startLoop(generation: gen)
    }

    func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
        watcher?.stop()
        watcher = nil
        request = nil
        resolved.removeAll()
        appSeen.removeAll()
        cnameTargets.removeAll()
        unchanged = 0
        manager.removeAll()
        manager.persist(to: Constants.routesStatePath)
        removeResolverFiles()
        lastError = nil
        publish()
        scheduleIdleExit()
    }

    func status() -> HelperStatus {
        HelperStatus(running: request != nil, routeCount: manager.owned.count,
                     gateway: manager.gateway.map(IPv4Target.format), lastError: lastError)
    }

    func subscribe(_ id: UUID, _ callback: @escaping (HelperStatus) -> Void) { observers[id] = callback }
    func unsubscribe(_ id: UUID) { observers[id] = nil }

    // MARK: Цикл

    private func startLoop(generation gen: Int) {
        loop?.cancel()
        loop = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let seconds = await self?.nextDelay() else { return }
                // Допуск 20%: система объединяет пробуждения и экономит энергию.
                try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(max(1, seconds / 5)))
                guard !Task.isCancelled else { return }
                await self?.sync(generation: gen)
            }
        }
    }

    private func nextDelay() -> Int {
        guard let req = request else { return Constants.defaultInterval }
        return SyncSchedule.delay(base: max(5, req.interval), unchanged: unchanged,
                                  hasApps: req.entries.contains { $0.kind == .app })
    }

    /// Сеть изменилась (смена Wi-Fi, шлюза, VPN): синхронизируемся сразу и сбрасываем растянутый интервал.
    /// События от наших собственных маршрутов игнорируются.
    private func networkChanged() async {
        guard request != nil, Date().timeIntervalSince(lastSyncEnd) > 3 else { return }
        unchanged = 0
        let gen = generation
        await sync(generation: gen)
        guard gen == generation else { return }
        startLoop(generation: gen)
    }

    private func sync(generation gen: Int) async {
        guard gen == generation, let req = request else { return }
        defer { lastSyncEnd = Date() }

        let routes = RouteTable.current()
        let gateway: UInt32
        if let manual = req.gateway, let ip = IPv4Target(manual) {
            gateway = ip.address
        } else if let detected = NetworkState.physicalGateway(routes) {
            gateway = detected.gateway
        } else {
            lastError = "Не удалось определить шлюз физического интерфейса"
            log.error("gateway not found")
            publish()
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

        // Домены резолвим через DNS обычной сети: DNS VPN может не отдавать адреса нужных сайтов.
        if req.useDirectDNS {
            let server = IPv4Target(req.dnsServer ?? "")?.address ?? gateway
            // Система запрашивает цели CNAME отдельно и через DNS VPN, поэтому звенья цепочки
            // (например ir.ozone.ru -> mmedia.ozone.ru -> edge-mmedia-lb.ozone.ru) тоже нужно направить на DNS обычной сети.
            let chains = await DNSClient.cnameChains(for: Array(Set(hostNames)), server: server)
            guard gen == generation else { return }
            for (host, chain) in chains { cnameTargets[host] = chain }
            let activeNames = Set(hostNames)
            cnameTargets = cnameTargets.filter { activeNames.contains($0.key) }
            let resolverDomains = activeNames.union(cnameTargets.values.flatMap { $0 })
            if DNSResolverFiles.sync(domains: resolverDomains, server: IPv4Target.format(server)) {
                flushDNSCache()
                try? await Task.sleep(for: .milliseconds(400)) // дать системе подхватить новые резолверы
            }
            managesResolverFiles = !hostNames.isEmpty
            // Публичный DNS-сервер должен идти мимо VPN; локальные адреса достижимы напрямую.
            if !Engine.isPrivate(server) { staticTargets.insert(IPv4Target(address: server)) }
        } else if managesResolverFiles {
            removeResolverFiles()
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

        let before = manager.owned
        let failures = manager.sync(desired: desired, gateway: gateway)
        if manager.owned != before || failures > 0 { unchanged = 0 } else { unchanged += 1 }
        manager.persist(to: Constants.routesStatePath)
        lastError = failures > 0 ? "Не удалось добавить маршрутов: \(failures)" : nil
        log.info("routes=\(self.manager.owned.count) failures=\(failures)")
        publish()
    }

    // MARK: Уведомления и выход по простою

    private func publish() {
        let s = status()
        guard s != lastPublished else { return }
        lastPublished = s
        for callback in observers.values { callback(s) }
    }

    private func scheduleIdleExit() {
        idleExit?.cancel()
        let timeout = idleTimeout
        idleExit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.exitIfIdle()
        }
    }

    /// launchd поднимет демон заново при следующем обращении (Mach-сервис по требованию).
    private func exitIfIdle() {
        guard request == nil else { return }
        log.info("idle, exiting")
        exit(0)
    }

    // MARK: DNS

    private func removeResolverFiles() {
        if DNSResolverFiles.removeAll() { flushDNSCache() }
        managesResolverFiles = false
    }

    /// Сбрасывает кэш DNS (в том числе отрицательные ответы), чтобы новые резолверы подействовали сразу.
    private func flushDNSCache() {
        for (tool, args) in [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            try? p.run()
            p.waitUntilExit()
        }
    }

    /// Частные адреса (10/8, 172.16/12, 192.168/16, 169.254/16): маршрут через шлюз для них не нужен.
    private static func isPrivate(_ a: UInt32) -> Bool {
        a >> 24 == 10 || a >> 20 == 0xAC1 || a >> 16 == 0xC0A8 || a >> 16 == 0xA9FE
    }
}
