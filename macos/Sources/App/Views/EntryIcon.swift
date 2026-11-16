import SwiftUI
import AppKit
import BypassCore

/// Иконка записи в списке исключений: настоящая иконка приложения либо значок по типу записи.
struct EntryIcon: View {
    let entry: Entry
    private let size: CGFloat = 24

    var body: some View {
        Group {
            if entry.kind == .app, let icon = AppIconCache.icon(for: entry) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Значок по типу: приложение (когда иконку не удалось найти), домен, IP, подсеть.
    private var symbol: String {
        switch entry.kind {
        case .app: return "macwindow"
        case .host:
            guard let ip = IPv4Target(entry.value) else { return "globe" }
            return ip.isHost ? "number" : "point.3.connected.trianglepath.dotted"
        }
    }
}

/// Кэш иконок приложений: иконки читаются с диска один раз.
@MainActor
private enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for entry: Entry) -> NSImage? {
        guard let path = bundlePath(for: entry) else { return nil }
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 24, height: 24)
        cache[path] = icon
        return icon
    }

    /// Путь из записи; для импортированных из bypass.conf (без пути) ищем в стандартных папках.
    private static func bundlePath(for entry: Entry) -> String? {
        let fm = FileManager.default
        if let p = entry.path, fm.fileExists(atPath: p) { return p }
        for dir in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
            let candidate = "\(dir)/\(entry.value).app"
            if fm.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }
}
