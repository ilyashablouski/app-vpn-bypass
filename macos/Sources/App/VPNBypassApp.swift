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
                .frame(minWidth: 460, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
