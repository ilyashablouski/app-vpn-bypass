import Foundation

/// Следит за VPN без опроса: по событиям PF_ROUTE перечитывает таблицу маршрутов
/// и сообщает о смене состояния (активен ли VPN).
public final class VPNMonitor {
    private var watcher: RouteChangeWatcher!
    private let onChange: (Bool) -> Void
    private var last: Bool?

    public init(debounce: TimeInterval = 0.8, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        watcher = RouteChangeWatcher(debounce: debounce) { [weak self] in self?.evaluate() }
    }

    public func start() {
        watcher.start()
        watcher.queue.async { [weak self] in self?.evaluate() }
    }

    public func stop() { watcher.stop() }

    /// Вызывается только на очереди watcher, поэтому `last` не требует блокировок.
    private func evaluate() {
        let active = NetworkState.isVPNActive(RouteTable.current())
        guard active != last else { return }
        last = active
        onChange(active)
    }
}
