import SwiftUI

@main
struct VPNBypassApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: model.iconState))
        }
        .menuBarExtraStyle(.window)

        Window("VPN Bypass", id: "settings") {
            SettingsView()
                .environment(model)
                // Минимальная ширина 248; размер по умолчанию задан ниже (defaultSize).
                .frame(minWidth: 248, minHeight: 520)
        }
        // contentSize открывал бы окно в «идеальную» ширину формы (до 900): задаём размер явно.
        .defaultSize(width: 496, height: 520)
        .windowResizability(.contentMinSize)
    }
}
