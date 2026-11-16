import Foundation

public enum Constants {
    public static let appID = "com.vpnbypass.app"
    public static let helperLabel = "com.vpnbypass.helper"
    public static let helperPlist = "com.vpnbypass.helper.plist"
    /// Требование к подписи клиента XPC. Для строгой привязки добавьте
    /// `and certificate leaf[subject.OU] = "TEAMID"`.
    public static let clientRequirement = "identifier \"\(appID)\" and anchor apple generic"
    public static let routesStatePath = "/var/run/com.vpnbypass.helper.routes"
    public static let defaultInterval = 30
}

public struct Entry: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case host, app }

    public var kind: Kind
    /// Домен / IP / CIDR либо имя процесса приложения.
    public var value: String
    /// Путь к .app (для приложений): по нему находятся и вспомогательные процессы.
    public var path: String?
    /// Необязательное описание для адреса (на маршруты не влияет).
    public var note: String?

    public var id: String { "\(kind.rawValue):\(value)" }

    public init(kind: Kind, value: String, path: String? = nil, note: String? = nil) {
        self.kind = kind
        self.value = value
        self.path = path
        self.note = Entry.cleanNote(note)
    }

    /// Обрезает пробелы и длину; пустое описание превращается в nil.
    public static func cleanNote(_ text: String?, maxLength: Int = 200) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(maxLength))
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var entries: [Entry] = []
    public var bypassEnabled = false
    /// Возобновлять исключения при повторном подключении VPN.
    public var autoResume = true
    public var interval = Constants.defaultInterval
    /// Ручной шлюз вместо автоопределения.
    public var gatewayOverride: String?
    /// Резолвить домены исключений через DNS обычной сети (файлы /etc/resolver), а не через DNS VPN.
    public var resolveViaPhysicalDNS = true
    /// DNS-сервер для этого режима; по умолчанию шлюз (роутер).
    public var dnsServer: String?

    public init() {}

    // Ручной декодер: поля, которых нет в старых config.json, берут значения по умолчанию.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        bypassEnabled = try c.decodeIfPresent(Bool.self, forKey: .bypassEnabled) ?? false
        autoResume = try c.decodeIfPresent(Bool.self, forKey: .autoResume) ?? true
        interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? Constants.defaultInterval
        gatewayOverride = try c.decodeIfPresent(String.self, forKey: .gatewayOverride)
        resolveViaPhysicalDNS = try c.decodeIfPresent(Bool.self, forKey: .resolveViaPhysicalDNS) ?? true
        dnsServer = try c.decodeIfPresent(String.self, forKey: .dnsServer)
    }
}

public enum SettingsStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VPNBypass/config.json")
    }

    public static func load(from url: URL = defaultURL) -> Settings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    public static func save(_ settings: Settings, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(settings).write(to: url, options: .atomic)
    }
}

/// Импорт старого формата `bypass.conf`.
public enum LegacyConfig {
    public static func parse(_ text: String) -> [Entry] {
        var result: [Entry] = []
        var seen = Set<String>()
        for raw in text.split(whereSeparator: \.isNewline) {
            let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let line = parts[0].trimmingCharacters(in: .whitespaces)
            // Комментарий в конце строки становится описанием записи.
            let comment = parts.count > 1 ? String(parts[1]) : nil
            guard !line.isEmpty else { continue }
            let entry: Entry
            if line.hasPrefix("app:") {
                let name = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                entry = Entry(kind: .app, value: name)
            } else {
                let host = Validation.normalizeHost(line)
                guard Validation.isValidHost(host) else { continue }
                entry = Entry(kind: .host, value: host, note: comment)
            }
            if seen.insert(entry.id).inserted { result.append(entry) }
        }
        return result
    }
}

/// Запрос приложения к helper.
public struct StartRequest: Codable, Sendable {
    public var entries: [Entry]
    public var interval: Int
    public var gateway: String?
    /// Управлять файлами /etc/resolver для доменов (резолв через DNS обычной сети).
    public var useDirectDNS: Bool
    /// DNS-сервер для этого режима; nil означает шлюз.
    public var dnsServer: String?

    public init(entries: [Entry], interval: Int, gateway: String?,
                useDirectDNS: Bool = false, dnsServer: String? = nil) {
        self.entries = entries
        self.interval = interval
        self.gateway = gateway
        self.useDirectDNS = useDirectDNS
        self.dnsServer = dnsServer
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode([Entry].self, forKey: .entries)
        interval = try c.decode(Int.self, forKey: .interval)
        gateway = try c.decodeIfPresent(String.self, forKey: .gateway)
        useDirectDNS = try c.decodeIfPresent(Bool.self, forKey: .useDirectDNS) ?? false
        dnsServer = try c.decodeIfPresent(String.self, forKey: .dnsServer)
    }
}

public struct HelperStatus: Codable, Equatable, Sendable {
    public var running: Bool
    public var routeCount: Int
    public var gateway: String?
    public var lastError: String?

    public init(running: Bool, routeCount: Int, gateway: String?, lastError: String?) {
        self.running = running
        self.routeCount = routeCount
        self.gateway = gateway
        self.lastError = lastError
    }
}

@objc public protocol HelperProtocol {
    /// Запускает (или обновляет) синхронизацию маршрутов. reply: текст ошибки или nil.
    func start(_ request: Data, reply: @escaping (String?) -> Void)
    func stop(reply: @escaping (String?) -> Void)
    /// JSON `HelperStatus`.
    func status(reply: @escaping (Data) -> Void)
}

/// Обратный канал helper -> приложение: статус приходит по событиям, без опроса.
@objc public protocol ClientProtocol {
    /// JSON `HelperStatus`.
    func statusChanged(_ status: Data)
}
