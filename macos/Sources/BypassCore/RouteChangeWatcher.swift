import Foundation
import Darwin

/// Событийное слежение за изменениями сети: слушает PF_ROUTE сокет (любые изменения маршрутов
/// и интерфейсов) и после паузы вызывает `onChange`. Без таймеров, в простое процесс спит.
public final class RouteChangeWatcher {
    public let queue = DispatchQueue(label: "vpnbypass.routewatcher", qos: .utility)
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private var source: DispatchSourceRead?
    private var pending: DispatchWorkItem?

    public init(debounce: TimeInterval, onChange: @escaping () -> Void) {
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
        }
    }

    public func stop() {
        queue.async { [self] in
            source?.cancel()
            source = nil
            pending?.cancel()
            pending = nil
        }
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
