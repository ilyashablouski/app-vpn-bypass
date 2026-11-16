import Foundation
import ServiceManagement
import BypassCore

enum HelperState: Equatable {
    case notInstalled, requiresApproval, enabled
}

/// XPC-клиент helper-демона и управление его регистрацией (SMAppService).
@MainActor
final class HelperClient {
    private var connection: NSXPCConnection?
    private let service = SMAppService.daemon(plistName: Constants.helperPlist)

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
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            guard let p = proxy({ cont.resume(returning: $0.localizedDescription) }) else {
                return cont.resume(returning: "Нет связи с helper")
            }
            p.start(data) { cont.resume(returning: $0) }
        }
    }

    func stop() async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            guard let p = proxy({ cont.resume(returning: $0.localizedDescription) }) else {
                return cont.resume(returning: "Нет связи с helper")
            }
            p.stop { cont.resume(returning: $0) }
        }
    }

    func status() async -> HelperStatus? {
        await withCheckedContinuation { (cont: CheckedContinuation<HelperStatus?, Never>) in
            guard let p = proxy({ _ in cont.resume(returning: nil) }) else { return cont.resume(returning: nil) }
            p.status { cont.resume(returning: try? JSONDecoder().decode(HelperStatus.self, from: $0)) }
        }
    }

    private func proxy(_ onError: @escaping (Error) -> Void) -> HelperProtocol? {
        let c = connection ?? makeConnection()
        connection = c
        return c.remoteObjectProxyWithErrorHandler(onError) as? HelperProtocol
    }

    private func makeConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: Constants.helperLabel, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        c.setCodeSigningRequirement("identifier \"\(Constants.helperLabel)\" and anchor apple generic")
        c.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        c.resume()
        return c
    }
}
