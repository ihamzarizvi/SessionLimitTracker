import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService for the "launch at login" toggle.
/// No-ops gracefully when run without a proper app bundle (e.g. `swift run`).
enum LaunchAtLogin {

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        guard Bundle.main.bundleIdentifier != nil else {
            // Running as a bare SwiftPM binary — nothing to register.
            return
        }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("%@", "LaunchAtLogin toggle failed: \(error.localizedDescription)")
        }
    }
}
