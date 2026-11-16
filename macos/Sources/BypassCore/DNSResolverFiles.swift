import Foundation

/// Файлы /etc/resolver/<домен>: macOS отправляет запросы к этому домену и его поддоменам на указанный DNS-сервер.
/// Так домены исключений резолвятся через DNS обычной сети, а не через DNS VPN (который может не отдавать
/// адреса нужных сайтов). Управляем только файлами с нашей меткой, чужие не трогаем.
public enum DNSResolverFiles {
    public static let directory = "/etc/resolver"
    static let marker = "# managed by VPN Bypass"

    public static func content(server: String) -> String {
        "\(marker)\nnameserver \(server)\n"
    }

    /// Имя файла равно домену, поэтому допускаем только безопасные имена (без `/`, `..`, пустых меток).
    static func isSafe(_ name: String) -> Bool {
        name.range(of: "^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", options: .regularExpression) != nil
    }

    /// Приводит каталог к виду «по файлу на домен». Возвращает true, если что-то изменилось.
    @discardableResult
    public static func sync(domains: Set<String>, server: String, directory dir: String = directory) -> Bool {
        let fm = FileManager.default
        var changed = false
        let wanted = Set(domains.map { $0.lowercased() }.filter(isSafe))

        if !wanted.isEmpty, !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o755])
        }
        let desired = content(server: server)
        for domain in wanted {
            let path = "\(dir)/\(domain)"
            if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
                guard existing.hasPrefix(marker) else { continue } // чужой файл
                if existing == desired { continue }
            }
            if (try? desired.write(toFile: path, atomically: true, encoding: .utf8)) != nil { changed = true }
        }
        if removeOwned(in: dir, keeping: wanted) { changed = true }
        return changed
    }

    /// Удаляет все наши файлы. Возвращает true, если что-то удалено.
    @discardableResult
    public static func removeAll(directory dir: String = directory) -> Bool {
        removeOwned(in: dir, keeping: [])
    }

    private static func removeOwned(in dir: String, keeping: Set<String>) -> Bool {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return false }
        var removed = false
        for name in names where !keeping.contains(name) {
            let path = "\(dir)/\(name)"
            guard let text = try? String(contentsOfFile: path, encoding: .utf8), text.hasPrefix(marker) else { continue }
            if (try? fm.removeItem(atPath: path)) != nil { removed = true }
        }
        return removed
    }
}
