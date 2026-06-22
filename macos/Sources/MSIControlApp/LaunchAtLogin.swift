import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` for the launch-at-login toggle (SETTINGS.md §6).
///
/// `SMAppService` is the modern (macOS 13+) replacement for the deprecated
/// `SMLoginItemSetEnabled`; macOS 13 is already our minimum target, so no fallback
/// path is needed. The persisted config's `launchAtLogin` flag is the source of
/// truth; `reconcile(desired:)` makes the OS match it on launch (config wins).
enum LaunchAtLogin {

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the main app. Throws on failure so the caller can
    /// revert the UI toggle and avoid persisting a state the OS rejected.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    /// Makes the OS state match the config (config wins, §6). Best-effort: a failure
    /// is logged, not fatal — the app still runs.
    static func reconcile(desired: Bool) {
        guard isEnabled != desired else { return }
        do {
            try setEnabled(desired)
        } catch {
            print("[LaunchAtLogin] reconcile to \(desired) failed: \(error)")
        }
    }
}
