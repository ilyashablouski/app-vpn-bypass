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
                    Text("Домен/IP:")
                    // В Form заголовок TextField становится подписью слева, а само поле
                    // без рамки не видно: поэтому своя рамка, подсказка и скрытая подпись.
                    TextField("Домен, IP или подсеть", text: $newHost,
                              prompt: Text("example.com, 1.2.3.4 или 10.0.0.0/8"))
                        .labelsHidden()
                        .bordered()
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
                            EntryIcon(entry: entry)
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
                    TextField("", text: $intervalText, prompt: Text("30"))
                        .labelsHidden()
                        .bordered()
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { if let v = Int(intervalText) { model.setInterval(v) } }
                }
                LabeledContent("Шлюз вручную") {
                    TextField("", text: $gatewayText, prompt: Text("авто, напр. 192.168.0.1"))
                        .labelsHidden()
                        .bordered()
                        .frame(width: 220)
                        .onSubmit { model.setGatewayOverride(gatewayText) }
                }
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

/// Поле ввода с тонкой рамкой (1 pt): серая в покое, цвета акцента при фокусе.
private struct BorderedField: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Color.accentColor : Color.secondary.opacity(0.45), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

private extension View {
    func bordered() -> some View { modifier(BorderedField()) }
}
