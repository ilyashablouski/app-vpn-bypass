import SwiftUI
import AppKit

struct MenuContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    /// Белый текст в тёмной теме, чёрный в светлой.
    private var textColor: Color { scheme == .dark ? .white : .black }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(model.vpnActive ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.vpnActive ? "VPN подключён" : "VPN не подключён")
                    .font(.headline)
                    .foregroundStyle(textColor)
            }

            Toggle(isOn: Binding(get: { model.settings.bypassEnabled },
                                 set: { model.setBypassEnabled($0) })) {
                VStack(alignment: .leading) {
                    Text("Исключения из VPN").foregroundStyle(textColor)
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
                        .buttonStyle(MenuButtonStyle())
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
                .buttonStyle(MenuButtonStyle())
                Spacer()
                Button("Выйти") {
                    Task {
                        await model.shutdown()
                        NSApp.terminate(nil)
                    }
                }
                .buttonStyle(MenuButtonStyle())
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

/// Кнопки меню: контрастный текст (белый в тёмной теме, чёрный в светлой);
/// стандартный стиль в окне меню выглядит блёклым.
struct MenuButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let ink: Color = scheme == .dark ? .white : .black
        return configuration.label
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ink.opacity(configuration.isPressed ? 0.22 : 0.10))
            )
    }
}
