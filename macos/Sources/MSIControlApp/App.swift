import SwiftUI
import AppKit
import MSIControl

/// App delegate — applies the menu-bar-only activation policy once the app has
/// finished launching (`NSApp` is guaranteed to exist here, unlike in `App.init`).
///
/// When run from the `.app` bundle, `LSUIElement = true` in Info.plist already
/// hides the Dock icon; this is a belt-and-braces fallback that also covers
/// running the bare SwiftPM binary directly (`.build/release/MSIControlApp`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct MSIControlApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var deviceState: DeviceState

    /// Kept alive for the app lifetime — ARC would release it otherwise.
    private let hotKeyManager: HotKeyManager

    init() {
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
