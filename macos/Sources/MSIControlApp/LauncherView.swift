import SwiftUI
import MSIControl

/// The quick-launcher palette (⌃⇧⌘Space): a centered floating window showing every
/// available monitor action as a grouped grid of clickable buttons, for when the
/// user can't recall the shortcuts. Click (or Tab→Space/Enter) runs the command and
/// closes the window; Esc dismisses. Each button shows its label + its current chord.
struct LauncherView: View {

    @ObservedObject var deviceState: DeviceState
    @ObservedObject var settings: SettingsStore
    /// Closes the launcher window.
    var dismiss: () -> Void

    /// Groups in display order. Only monitor commands (not `showLauncher`) appear.
    private var groups: [(title: String, commands: [Command])] {
        [
            ("Inputs", [.inputTypeC, .inputDP, .inputHDMI1, .inputHDMI2]),
            ("KVM",    [.kvmUSBC, .kvmUpstream, .kvmAuto]),
            ("Modes",  [.pbpOn, .pbpPIP, .pbpOff]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Launcher")
                .font(.title3).bold()

            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        ForEach(group.commands.filter(\.isAvailable), id: \.self) { command in
                            button(for: command)
                        }
                    }
                }
            }

            Text("Tab to move · Space/Return to run · Esc to close")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 420)
        // Esc dismisses. A hidden default-less button captures the Escape key.
        .background(
            Button("", action: dismiss).keyboardShortcut(.cancelAction).hidden()
        )
    }

    @ViewBuilder
    private func button(for command: Command) -> some View {
        let chord = settings.primaryDisplay(for: command)
        let isCurrent = deviceState.isCurrent(command)
        Button {
            deviceState.send(command)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.label).lineLimit(1)
                    if !chord.isEmpty {
                        Text(chord).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(!deviceState.isConnected)
    }
}
