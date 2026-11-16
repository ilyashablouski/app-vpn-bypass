import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BypassCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newHost = ""
    @State private var message: String?
    @State private var intervalText = ""
    @State private var gatewayText = ""

    var body: some View {
        Form {
            Section("Исключения") {
                HStack {
                    TextField("Домен, IP или подсеть", text: $newHost)
                        .onSubmit(addHost)
                    Button("Добавить", action: addHost)
                        .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Button("Добавить приложение…", action: pickApp)
                    Button("Импорт bypass.conf…", action: importConfig)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if model.settings.entries.isEmpty {
                    Text("Список пуст").foregroundStyle(.secondary)
                } else {
                    ForEach(model.settings.entries) { entry in
                        HStack {
                            Image(systemName: entry.kind == .app ? "app" : "globe")
                                .foregroundStyle(.secondary)
                            Text(entry.value)
                            Spacer()
                            Button(role: .destructive) { model.remove(entry) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Поведение") {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Возобновлять при повторном подключении VPN", isOn: Binding(
                    get: { model.settings.autoResume }, set: { model.setAutoResume($0) }))
                Text("При отключении VPN исключения останавливаются автоматически.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Дополнительно") {
                HStack {
                    Text("Интервал обновления, с")
                    Spacer()
                    TextField("", text: $intervalText)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { if let v = Int(intervalText) { model.setInterval(v) } }
                }
                TextField("Шлюз вручную (необязательно)", text: $gatewayText)
                    .onSubmit { model.setGatewayOverride(gatewayText) }
            }

            Section("Helper") {
                HStack {
                    Text(helperText)
                    Spacer()
                    if model.helperState == .enabled {
                        Button("Удалить", role: .destructive) { model.uninstallHelper() }
                    } else {
                        Button("Установить") { model.installHelper() }
                    }
                }
                if let error = model.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshSystemState()
            intervalText = String(model.settings.interval)
            gatewayText = model.settings.gatewayOverride ?? ""
        }
    }

    private var helperText: String {
        switch model.helperState {
        case .enabled: return "Helper установлен"
        case .requiresApproval: return "Ожидает подтверждения в Системных настройках"
        case .notInstalled: return "Helper не установлен"
        }
    }

    private func addHost() {
        message = model.addHost(newHost)
        if message == nil { newHost = "" }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(model.addApp) }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = "Импортировано записей: \(model.importLegacy(url))"
    }
}
