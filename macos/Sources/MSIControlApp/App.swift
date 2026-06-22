import SwiftUI
import AppKit
import MSIControl

@main
struct MSIControlApp: App {

    @StateObject private var deviceState: DeviceState

    /// Kept alive for the app lifetime — ARC would release it otherwise.
    private let hotKeyManager: HotKeyManager

    init() {
        // Hide the Dock icon — this is a menu-bar-only app.
        // LSUIElement cannot be set via Info.plist in SwiftPM executables,
        // so we apply it programmatically before the app activates.
        NSApp.setActivationPolicy(.accessory)

        let state = DeviceState()
        _deviceState = StateObject(wrappedValue: state)
        hotKeyManager = HotKeyManager(deviceState: state)
    }

    var body: some Scene {
        MenuBarExtra("MSI Monitor Control", systemImage: "display") {
            MenuBarView(deviceState: deviceState)
        }
        .menuBarExtraStyle(.menu)
    }
}
