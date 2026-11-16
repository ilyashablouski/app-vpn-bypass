import SwiftUI
import AppKit

struct MenuContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(model.vpnActive ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.vpnActive ? "VPN подключён" : "VPN не подключён")
                    .font(.headline)
            }

            Toggle(isOn: Binding(get: { model.settings.bypassEnabled },
                                 set: { model.setBypassEnabled($0) })) {
                VStack(alignment: .leading) {
                    Text("Исключения из VPN")
                    Text(model.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if model.helperState != .enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.helperState == .requiresApproval
                         ? "Подтвердите helper в Системных настройках"
                         : "Для изменения маршрутов нужен helper")
                        .font(.caption)
                    Button("Установить helper") { model.installHelper() }
                }
            }

            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Настройки…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Выйти") {
                    Task {
                        await model.shutdown()
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .task {
            model.refreshSystemState()
            await model.refreshStatus()
        }
    }
}
