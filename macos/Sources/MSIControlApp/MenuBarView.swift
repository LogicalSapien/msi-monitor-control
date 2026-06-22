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

        // Only show available commands
        ForEach(Command.allCases.filter(\.isAvailable), id: \.self) { command in
            Button(command.label) {
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

        Button("Quit MSI Monitor Control") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
