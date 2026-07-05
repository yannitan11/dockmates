import ServiceManagement

/// Wraps SMAppService so Dockmates can register/unregister itself as a
/// login item (launch automatically when you log in). This is the modern
/// replacement for the old Login Items list and needs no separate helper
/// app or entitlement beyond the app being properly signed.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            return false
        }
    }
}
