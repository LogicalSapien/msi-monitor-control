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
        // Start the debug logger FIRST so launch + any early error is captured, and
        // the crash/signal handlers are installed before anything can go wrong.
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        DebugLog.shared.start(version: version)
        DebugLog.shared.info("applicationDidFinishLaunching — activation policy .accessory")
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Distinguishes a clean quit from a crash/silent-vanish in the log.
        DebugLog.shared.info("applicationWillTerminate — clean shutdown")
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

/// Tiny holder so the Carbon hotkey handler (built in `App.init`, before SwiftUI's
/// `openWindow` is available) can trigger the launcher window once the scene has
/// wired up the actual opener.
final class LauncherOpener { var open: () -> Void = {} }

@main
struct MSIControlApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var deviceState: DeviceState
    @StateObject private var settings: SettingsStore

    /// Kept alive for the app lifetime — ARC would release it otherwise.
    private let hotKeyManager: HotKeyManager
    private let launcherOpener: LauncherOpener

    @Environment(\.openWindow) private var openWindow

    private func openHelp() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "help")
    }

    init() {
        let state = DeviceState()
        let opener = LauncherOpener()
        let manager = HotKeyManager(deviceState: state,
                                    onShowLauncher: { [opener] in opener.open() })
        _deviceState = StateObject(wrappedValue: state)
        // SettingsStore loads the config and applies hotkeys + launch-at-login.
        let store = SettingsStore(hotKeyManager: manager)
        // Create the edge-switch tracker, passing a KVM-send closure that dispatches
        // to DeviceState.send on the main thread (the tracker's onKvmSwitch contract,
        // design §1.1 / M5).
        store.edgeSwitchTracker = EdgeSwitchTracker(
            deviceState: state,
            onKvmSwitch: { [state] command in state.send(command) }
        )
        // If the config already had edge-switch enabled (e.g. relaunched after save),
        // apply it now (permission will be re-probed by setEnabled if needed).
        if store.config.edgeSwitchEnabled {
            store.edgeSwitchTracker?.setEnabled(true)
        }
        // Wire PBP mode change notifications → tracker Standby/Active transitions.
        let tracker = store.edgeSwitchTracker
        state.onPBPModeChanged = { [tracker] in tracker?.notifyPBPModeChanged() }
        _settings = StateObject(wrappedValue: store)
        hotKeyManager = manager
        launcherOpener = opener
    }

    /// The custom template icon, loaded once. `nil` falls back to an SF Symbol.
    private let menuBarIcon: NSImage? = loadMenuBarIcon()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(deviceState: deviceState, settings: settings,
                        openSettings: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "settings")
                        },
                        openLauncher: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "launcher")
                        },
                        openHelp: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "help")
                        })
                .onAppear { wireLauncherOpener() }
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
            SettingsView(settings: settings, deviceState: deviceState,
                         openHelp: {
                             NSApp.activate(ignoringOtherApps: true)
                             openWindow(id: "help")
                         })
        }
        .windowResizability(.contentSize)

        // Quick-launcher palette, opened by the ⌃⇧⌘Space hotkey (or the menu). We
        // wire `launcherOpener` here, where `openWindow` is available, so the Carbon
        // handler (built in init) can trigger it. The window centres + becomes key.
        Window("Quick Launcher", id: "launcher") {
            LauncherView(deviceState: deviceState, settings: settings) {
                // Close via AppKit (Environment.dismissWindow is macOS 14+). The
                // launcher is the key window while shown.
                closeLauncherWindow()
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // In-app Help window (task #35).
        Window("MSI Monitor Control Help", id: "help") {
            HelpView(settings: settings)
        }
        .windowResizability(.contentSize)
    }

    /// Closes the launcher window by title (macOS 13-safe — no `dismissWindow`).
    private func closeLauncherWindow() {
        NSApp.windows.first { $0.title == "Quick Launcher" && $0.isVisible }?.close()
    }

    /// Wires `launcherOpener.open` to actually open the window. Called from the
    /// always-present MenuBarExtra content so it's set before the hotkey can fire
    /// (the `.onAppear` of the launcher window itself would be too late — it only
    /// runs once the window is already shown).
    private func wireLauncherOpener() {
        launcherOpener.open = {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "launcher")
        }
    }
}
