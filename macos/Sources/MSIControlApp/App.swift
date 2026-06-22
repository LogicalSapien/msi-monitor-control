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

// MARK: - Menu-bar icon

/// Loads the custom menu-bar template icon (`menubar-icon.pdf`) from the bundle.
///
/// The PDF is a monochrome silhouette on a transparent background; marking it
/// `isTemplate` lets macOS tint it automatically for light and dark menu bars.
/// If the resource is missing for any reason, the caller falls back to an SF
/// Symbol so the app always has a usable icon.
private func loadMenuBarIcon() -> NSImage? {
    // Look in the assembled .app's Contents/Resources first (Bundle.main), then in
    // the SwiftPM resource bundle (Bundle.module) for `swift run` during dev. The
    // two locations differ because build-app.sh places the PDF directly in
    // Contents/Resources — a code-signable location — rather than relying on the
    // SwiftPM bundle layout, which codesign cannot seal inside an app bundle.
    let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "pdf")
        ?? Bundle.module.url(forResource: "menubar-icon", withExtension: "pdf")
    guard let url, let image = NSImage(contentsOf: url) else {
        return nil
    }
    // ~18pt tall is the conventional menu-bar icon size; width follows the
    // square artwork. Template rendering ignores the artwork's own colours.
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
}

@main
struct MSIControlApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var deviceState: DeviceState
    @StateObject private var settings: SettingsStore

    /// Kept alive for the app lifetime — ARC would release it otherwise.
    private let hotKeyManager: HotKeyManager

    @Environment(\.openWindow) private var openWindow

    init() {
        let state = DeviceState()
        let manager = HotKeyManager(deviceState: state)
        _deviceState = StateObject(wrappedValue: state)
        // SettingsStore loads the config and applies hotkeys + launch-at-login.
        _settings = StateObject(wrappedValue: SettingsStore(hotKeyManager: manager))
        hotKeyManager = manager
    }

    /// The custom template icon, loaded once. `nil` falls back to an SF Symbol.
    private let menuBarIcon: NSImage? = loadMenuBarIcon()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(deviceState: deviceState, settings: settings) {
                // Bring the app forward, then open the settings window.
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
        } label: {
            if let icon = menuBarIcon {
                Image(nsImage: icon)
            } else {
                // Fallback if the bundled template PDF could not be loaded.
                Image(systemName: "display")
            }
        }
        .menuBarExtraStyle(.menu)

        // Settings window, opened on demand from the menu. Accessory-policy apps
        // have no standard Settings menu, so we use a plain Window we open by id.
        Window("MSI Monitor Control Settings", id: "settings") {
            SettingsView(settings: settings)
        }
        .windowResizability(.contentSize)
    }
}
