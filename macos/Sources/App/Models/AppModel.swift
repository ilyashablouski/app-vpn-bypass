import Foundation
import Observation
import BypassCore

@MainActor
@Observable
final class AppModel {
    private(set) var settings: Settings
    private(set) var vpnActive = false
    /// Helper сейчас держит маршруты.
    private(set) var running = false
    private(set) var status: HelperStatus?
    private(set) var helperState: HelperState = .notInstalled
    private(set) var launchAtLogin = false
    private(set) var lastError: String?

    @ObservationIgnored private let helper = HelperClient()
    @ObservationIgnored private var monitor: VPNMonitor?
    @ObservationIgnored private var offTask: Task<Void, Never>?
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?

    init() {
        settings = SettingsStore.load()
        refreshSystemState()
        let m = VPNMonitor { [weak self] active in
            Task { @MainActor in self?.vpnChanged(active) }
        }
        monitor = m
        m.start()
    }

    // MARK: Состояние для UI

    var isBypassActive: Bool { settings.bypassEnabled && vpnActive && running }

    var iconName: String {
        if isBypassActive { return "checkmark.shield.fill" }
        return settings.bypassEnabled ? "shield.lefthalf.filled.slash" : "shield"
    }

    var summary: String {
        if !settings.bypassEnabled { return "Исключения выключены" }
        if !vpnActive { return "Ожидание VPN" }
        if running { return "Активны: маршрутов \(status?.routeCount ?? 0)" }
        return "Запуск..."
    }

    // MARK: VPN

    private func vpnChanged(_ active: Bool) {
        offTask?.cancel()
        if active {
            vpnActive = true
            reconcile()
        } else {
            // Небольшая пауза: VPN часто переподключается за секунды, незачем дёргать маршруты.
            offTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self else { return }
                vpnActive = false
                if !settings.autoResume, settings.bypassEnabled {
                    settings.bypassEnabled = false
                    save()
                }
                reconcile()
            }
        }
    }

    /// Приводит helper к желаемому состоянию: исключения включены и VPN активен -> работают, иначе остановлены.
    private func reconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { [self] in
            if settings.bypassEnabled && vpnActive {
                refreshSystemState()
                guard helperState == .enabled else {
                    running = false
                    lastError = "Helper не установлен или не подтверждён в Системных настройках"
                    return
                }
                let req = StartRequest(entries: settings.entries, interval: settings.interval,
                                       gateway: settings.gatewayOverride)
                lastError = await helper.start(req)
                running = lastError == nil
            } else if running {
                lastError = await helper.stop()
                running = false
            }
            await refreshStatus()
        }
    }

    func refreshStatus() async {
        status = running ? await helper.status() : nil
        if let e = status?.lastError { lastError = e }
    }

    func refreshSystemState() {
        helperState = helper.state
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: Действия

    func setBypassEnabled(_ on: Bool) {
        settings.bypassEnabled = on
        save()
        reconcile()
    }

    func setAutoResume(_ on: Bool) {
        settings.autoResume = on
        save()
    }

    func setInterval(_ seconds: Int) {
        settings.interval = max(5, seconds)
        save()
        if running { reconcile() }
    }

    func setGatewayOverride(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        settings.gatewayOverride = t.isEmpty ? nil : t
        save()
        if running { reconcile() }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do { try LoginItem.set(on) } catch { lastError = error.localizedDescription }
        launchAtLogin = LoginItem.isEnabled
    }

    func installHelper() {
        do { try helper.install(); lastError = nil } catch { lastError = error.localizedDescription }
        refreshSystemState()
        reconcile()
    }

    func uninstallHelper() {
        Task {
            do { try await helper.uninstall(); lastError = nil } catch { lastError = error.localizedDescription }
            running = false
            status = nil
            refreshSystemState()
        }
    }

    /// Остановка перед выходом из приложения.
    func shutdown() async {
        monitor?.stop()
        if running { _ = await helper.stop() }
    }

    // MARK: Список исключений

    /// Возвращает текст ошибки или nil.
    @discardableResult
    func addHost(_ text: String) -> String? {
        let host = Validation.normalizeHost(text)
        guard Validation.isValidHost(host) else { return "Не похоже на домен, IP или подсеть" }
        return add(Entry(kind: .host, value: host))
    }

    func addApp(_ url: URL) {
        add(Entry(kind: .app, value: Validation.appProcessName(appURL: url), path: url.path))
    }

    @discardableResult
    private func add(_ entry: Entry) -> String? {
        guard !settings.entries.contains(where: { $0.id == entry.id }) else { return "Уже есть в списке" }
        settings.entries.append(entry)
        entriesChanged()
        return nil
    }

    func remove(_ entry: Entry) {
        settings.entries.removeAll { $0.id == entry.id }
        entriesChanged()
    }

    /// Импорт старого bypass.conf. Возвращает число добавленных записей.
    func importLegacy(_ url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let existing = Set(settings.entries.map(\.id))
        let new = LegacyConfig.parse(text).filter { !existing.contains($0.id) }
        settings.entries += new
        entriesChanged()
        return new.count
    }

    private func entriesChanged() {
        save()
        if settings.bypassEnabled && vpnActive { reconcile() }
    }

    private func save() {
        do { try SettingsStore.save(settings) } catch { lastError = error.localizedDescription }
    }
}
