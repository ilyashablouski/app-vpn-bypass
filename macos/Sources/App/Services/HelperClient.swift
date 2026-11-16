import Foundation
import ServiceManagement
import BypassCore

enum HelperState: Equatable {
    case notInstalled, requiresApproval, enabled
}

/// Приёмник статуса, который helper присылает по событиям (вместо опроса).
private final class StatusReceiver: NSObject, ClientProtocol {
    private let handler: (HelperStatus) -> Void
    init(handler: @escaping (HelperStatus) -> Void) { self.handler = handler }

    func statusChanged(_ status: Data) {
        if let s = try? JSONDecoder().decode(HelperStatus.self, from: status) { handler(s) }
    }
}

/// XPC-клиент helper-демона и управление его регистрацией (SMAppService).
@MainActor
final class HelperClient {
    private var connection: NSXPCConnection?
    private let service = SMAppService.daemon(plistName: Constants.helperPlist)

    /// Вызывается, когда helper присылает новый статус.
    var onStatus: ((HelperStatus) -> Void)?

    // MARK: Регистрация

    var state: HelperState {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .notInstalled
        }
    }

    func install() throws {
        try service.register()
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func uninstall() async throws {
        _ = await stop()
        connection?.invalidate()
        connection = nil
        try await service.unregister()
    }

    // MARK: XPC

    func start(_ request: StartRequest) async -> String? {
        guard let data = try? JSONEncoder().encode(request) else { return "Не удалось сформировать запрос" }
        return await call { proxy, reply in proxy.start(data, reply: reply) }
    }

    func stop() async -> String? {
        await call { proxy, reply in proxy.stop(reply: reply) }
    }

    func status() async -> HelperStatus? {
        await withCheckedContinuation { (cont: CheckedContinuation<HelperStatus?, Never>) in
            guard let p = proxy({ _ in cont.resume(returning: nil) }) else { return cont.resume(returning: nil) }
            p.status { cont.resume(returning: try? JSONDecoder().decode(HelperStatus.self, from: $0)) }
        }
    }

    private enum Outcome { case reply(String?), failure(String) }

    /// Вызов с одной повторной попыткой: helper завершается в простое, и первая отправка
    /// после его выхода может вернуть ошибку соединения.
    private func call(_ body: @escaping (HelperProtocol, @escaping (String?) -> Void) -> Void) async -> String? {
        for attemptNumber in 0..<2 {
            let outcome = await withCheckedContinuation { (cont: CheckedContinuation<Outcome, Never>) in
                guard let p = proxy({ cont.resume(returning: .failure($0.localizedDescription)) }) else {
                    return cont.resume(returning: .failure("Нет связи с helper"))
                }
                body(p) { cont.resume(returning: .reply($0)) }
            }
            switch outcome {
            case .reply(let error):
                return error
            case .failure(let message):
                connection?.invalidate()
                connection = nil
                if attemptNumber == 1 { return message }
            }
        }
        return nil
    }

    private func proxy(_ onError: @escaping (Error) -> Void) -> HelperProtocol? {
        let c = connection ?? makeConnection()
        connection = c
        return c.remoteObjectProxyWithErrorHandler(onError) as? HelperProtocol
    }

    private func makeConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: Constants.helperLabel, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        c.exportedInterface = NSXPCInterface(with: ClientProtocol.self)
        c.exportedObject = StatusReceiver { [weak self] status in
            Task { @MainActor in self?.onStatus?(status) }
        }
        c.setCodeSigningRequirement("identifier \"\(Constants.helperLabel)\" and anchor apple generic")
        c.invalidationHandler = { [weak self, weak c] in
            Task { @MainActor in
                // Обнуляем только своё соединение, а не новое, созданное при повторной попытке.
                if let self, self.connection === c { self.connection = nil }
            }
        }
        c.resume()
        return c
    }
}
