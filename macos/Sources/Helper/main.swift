import Foundation
import BypassCore

/// XPC-сервис: тонкая обёртка над Engine. Один экземпляр на подключение.
final class Service: NSObject, HelperProtocol {
    private let engine: Engine
    private let id = UUID()

    init(engine: Engine, client: ClientProtocol?) {
        self.engine = engine
        super.init()
        // Подписываем клиента на изменения статуса (push вместо опроса).
        if let client {
            let id = id
            Task {
                await engine.subscribe(id) { status in
                    if let data = try? JSONEncoder().encode(status) { client.statusChanged(data) }
                }
            }
        }
    }

    func detach() {
        let id = id
        Task { await engine.unsubscribe(id) }
    }

    func start(_ request: Data, reply: @escaping (String?) -> Void) {
        guard let req = try? JSONDecoder().decode(StartRequest.self, from: request) else {
            return reply("Некорректный запрос")
        }
        // Принимаем только валидные значения: helper работает от root.
        guard req.entries.allSatisfy({ $0.kind == .app || Validation.isValidHost($0.value) }) else {
            return reply("Недопустимое значение в списке исключений")
        }
        Task { await engine.start(req); reply(nil) }
    }

    func stop(reply: @escaping (String?) -> Void) {
        Task { await engine.stop(); reply(nil) }
    }

    func status(reply: @escaping (Data) -> Void) {
        Task { reply((try? JSONEncoder().encode(await engine.status())) ?? Data()) }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let engine: Engine
    private let lock = NSLock()
    private var connections = 0

    init(engine: Engine) { self.engine = engine }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        // Принимаем только подписанное нашим идентификатором приложение.
        c.setCodeSigningRequirement(Constants.clientRequirement)
        c.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        c.remoteObjectInterface = NSXPCInterface(with: ClientProtocol.self)

        let client = c.remoteObjectProxyWithErrorHandler { _ in } as? ClientProtocol
        let service = Service(engine: engine, client: client)
        c.exportedObject = service

        lock.lock(); connections += 1; lock.unlock()
        // Когда приложение закрылось или упало, убираем маршруты.
        c.invalidationHandler = { [self] in
            service.detach()
            lock.lock(); connections -= 1; let left = connections; lock.unlock()
            if left == 0 { Task { await engine.stop() } }
        }
        c.resume()
        return true
    }
}

guard let backend = RouteSocket() else {
    FileHandle.standardError.write(Data("cannot open PF_ROUTE socket\n".utf8))
    exit(1)
}
// Маршруты, оставшиеся после аварийного завершения прошлого запуска.
RouteManager.cleanupLeftovers(at: Constants.routesStatePath, backend: backend)
DNSResolverFiles.removeAll() // файлы /etc/resolver, оставшиеся после аварийного завершения

let engine = Engine(backend: backend)
let delegate = ListenerDelegate(engine: engine)
let listener = NSXPCListener(machServiceName: Constants.helperLabel)
listener.delegate = delegate
listener.resume()
Task { await engine.begin() }

// При остановке демона (SIGTERM от launchd) убираем маршруты.
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    Task { await engine.stop(); exit(0) }
}
termSource.resume()

RunLoop.main.run()
