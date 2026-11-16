import Foundation

/// Нормализация и проверка вводимых пользователем значений.
public enum Validation {
    /// Убирает схему, путь, порт и приводит к нижнему регистру ("https://Example.com/a" -> "example.com").
    public static func normalizeHost(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = t.range(of: "^[a-z][a-z0-9+.-]*://", options: .regularExpression) {
            t.removeSubrange(r)
        }
        let isCIDR = t.range(of: "^[0-9.]+/[0-9]+$", options: .regularExpression) != nil
        if !isCIDR, let slash = t.firstIndex(of: "/") {
            t = String(t[..<slash])
        }
        if let r = t.range(of: ":[0-9]+$", options: .regularExpression) {
            t.removeSubrange(r)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// IPv4, подсеть CIDR или доменное имя (допускается ведущий "*.").
    public static func isValidHost(_ text: String) -> Bool {
        if IPv4Target(text) != nil { return true }
        if text.range(of: "^[0-9.]+(/[0-9]+)?$", options: .regularExpression) != nil { return false }
        return text.range(
            of: "^(\\*\\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$",
            options: .regularExpression) != nil
    }

    /// Убирает ведущий "*." (поддомены нужно перечислять явно).
    public static func stripWildcard(_ host: String) -> String {
        host.hasPrefix("*.") ? String(host.dropFirst(2)) : host
    }

    /// Имя исполняемого файла из .app (то, что видно в списке процессов).
    public static func appProcessName(appURL: URL) -> String {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plist),
           let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = obj as? [String: Any],
           let name = dict["CFBundleExecutable"] as? String, !name.isEmpty {
            return name
        }
        return appURL.deletingPathExtension().lastPathComponent
    }
}
