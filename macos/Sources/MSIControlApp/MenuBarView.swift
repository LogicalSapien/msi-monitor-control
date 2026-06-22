import SwiftUI
import MSIControl

/// The menu shown when the user clicks the menu-bar icon.
struct MenuBarView: View {

    @ObservedObject var deviceState: DeviceState

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

        // Only show available commands. Each row shows its global hotkey chord
        // (⌃⌥⌘ + key) next to the label so newcomers can see and learn them.
        // The chord text comes from `command.shortcutDisplay`, the same source
        // the Carbon hotkey registration uses, so the hint always matches.
        ForEach(Command.allCases.filter(\.isAvailable), id: \.self) { command in
            Button {
                deviceState.send(command)
            } label: {
                HStack {
                    Text(command.label)
                    Spacer()
                    Text(command.shortcutDisplay)
                        .foregroundStyle(.secondary)
                }
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

        Button("Quit MSI Monitor Control") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
