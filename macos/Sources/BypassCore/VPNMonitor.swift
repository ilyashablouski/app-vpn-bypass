import Foundation
import Darwin

/// Следит за VPN без опроса: слушает PF_ROUTE сокет (любое изменение маршрутов/интерфейсов),
/// после небольшой паузы перечитывает таблицу и сообщает о смене состояния.
public final class VPNMonitor {
    private let queue = DispatchQueue(label: "vpnbypass.vpnmonitor", qos: .utility)
    private let debounce: TimeInterval
    private let onChange: (Bool) -> Void
    private var source: DispatchSourceRead?
    private var pending: DispatchWorkItem?
    private var last: Bool?

    public init(debounce: TimeInterval = 0.8, onChange: @escaping (Bool) -> Void) {
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        queue.async { [self] in
            guard source == nil else { return }
            let fd = socket(PF_ROUTE, SOCK_RAW, 0)
            guard fd >= 0 else { return }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in
                var scratch = [UInt8](repeating: 0, count: 4096)
                while read(fd, &scratch, scratch.count) > 0 {} // сообщения нужны лишь как сигнал
                self?.schedule()
            }
            src.setCancelHandler { close(fd) }
            source = src
            src.resume()
            evaluate()
        }
    }

    public func stop() {
        queue.async { [self] in
            source?.cancel()
            source = nil
            pending?.cancel()
        }
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.evaluate() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func evaluate() {
        let active = NetworkState.isVPNActive(RouteTable.current())
        guard active != last else { return }
        last = active
        onChange(active)
    }
}
