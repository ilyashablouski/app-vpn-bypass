import Foundation
import ServiceManagement

/// Автозапуск приложения при входе в систему.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        let s = SMAppService.mainApp
        if on {
            if s.status != .enabled { try s.register() }
        } else if s.status == .enabled || s.status == .requiresApproval {
            try s.unregister()
        }
    }
}
