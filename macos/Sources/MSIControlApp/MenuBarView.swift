import SwiftUI
import MSIControl

/// The menu shown when the user clicks the menu-bar icon.
struct MenuBarView: View {

    @ObservedObject var deviceState: DeviceState
    @ObservedObject var settings: SettingsStore
    /// Opens the settings window (wired from the App scene).
    var openSettings: () -> Void

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
        ForEach(Command.allCases.filter(\.isAvailable), id: \.self) { command in
            let chord = settings.primaryDisplay(for: command)
            Button(chord.isEmpty ? command.label : "\(command.label)  \(chord)") {
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
