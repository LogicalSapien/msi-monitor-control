import SwiftUI
import MSIControl

/// The menu shown when the user clicks the menu-bar icon.
struct MenuBarView: View {

    @ObservedObject var deviceState: DeviceState
    @ObservedObject var settings: SettingsStore
    /// Opens the settings window (wired from the App scene).
    var openSettings: () -> Void
    /// Opens the quick-launcher palette (wired from the App scene).
    var openLauncher: () -> Void

    var body: some View {
        // Connection status indicator
        HStack {
            Circle()
                .fill(deviceState.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(deviceState.isConnected ? "Monitor connected" : "Monitor not detected")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)

        Divider()

        // Non-clickable header so the chords below are obviously shortcuts.
        Text("Actions (global shortcuts)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)

        // Only show available commands. Each row's chord is folded into the label
        // text (native NSMenu drops a trailing custom Text) and is now DATA-DRIVEN
        // from the loaded config via `settings.primaryDisplay` — not hardcoded —
        // so it always reflects the user's current binding (SETTINGS.md §3.7).
        // A leading "✓ " marks the last command this app sent in each group (the
        // best-effort "current" highlight — folded into the label text because the
        // native NSMenu drops custom marker views, same reason the chord is folded).
        // Monitor commands only (exclude the showLauncher UI action, which is not a
        // HID send and gets its own menu item below).
        ForEach(Command.allCases.filter { $0.isAvailable && $0.isMonitorCommand }, id: \.self) { command in
            let chord = settings.primaryDisplay(for: command)
            let tick = deviceState.isCurrent(command) ? "✓ " : "   "
            let base = chord.isEmpty ? command.label : "\(command.label)  \(chord)"
            Button("\(tick)\(base)") {
                deviceState.send(command)
            }
            .disabled(!deviceState.isConnected)
        }

        if let error = deviceState.lastError {
            Divider()
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
                .padding(.horizontal)
        }

        Divider()

        Button(launcherLabel) {
            openLauncher()
        }

        Button("Settings…") {
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Reveal Debug Log…") {
            revealDebugLog()
        }

        Button("Quit MSI Monitor Control") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// "Quick Launcher…" with its current chord folded in (e.g. "Quick Launcher…  ⌃⇧⌘ Space").
    private var launcherLabel: String {
        let chord = settings.primaryDisplay(for: .showLauncher)
        return chord.isEmpty ? "Quick Launcher…" : "Quick Launcher…  \(chord)"
    }

    /// Reveals `debug.log` in Finder so the user can grab it after an unexpected
    /// quit. Falls back to opening the containing folder if the file isn't there yet.
    private func revealDebugLog() {
        guard let url = try? DebugLog.defaultURL() else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
