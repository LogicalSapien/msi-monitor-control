import SwiftUI
import AppKit
@preconcurrency import MSIControl

// MARK: - Help window

/// In-app Help window (task #35). Four sections:
/// (a) Hotkey cheat-sheet — reads the LIVE config so it shows the user's current chords.
/// (b) Feature quick-start — short how-to per feature.
/// (c) Troubleshooting — monitor not detected, Gatekeeper, KVM note, debug log path.
/// (d) About / links — version, GitHub, MIT licence, supported-monitor note, RE disclaimer.
struct HelpView: View {

    @ObservedObject var settings: SettingsStore
    /// App bundle version string, e.g. "0.2.3".
    private let version: String

    init(settings: SettingsStore) {
        self.settings = settings
        self.version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Help — MSI Monitor Control")
                    .font(.title2).bold()

                cheatSheetSection
                Divider()
                quickStartSection
                Divider()
                troubleshootingSection
                Divider()
                aboutSection
            }
            .padding(20)
            .frame(width: 540, alignment: .leading)
        }
        .frame(width: 560, height: 640)
    }

    // MARK: (a) Hotkey cheat-sheet

    private var cheatSheetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Hotkey Cheat-Sheet")
            Text("These are your current hotkeys — they reflect any changes you've made in Settings and are fully rebindable.")
                .font(.caption).foregroundStyle(.secondary)

            let groups: [(String, [Command])] = [
                ("Inputs",  [.inputHDMI1, .inputHDMI2, .inputTypeC, .inputDP]),
                ("KVM",     [.kvmUSBC, .kvmUpstream, .kvmAuto]),
                ("Modes",   [.pbpOff, .pbpPIP, .pbpOn]),
                ("Launcher",[.showLauncher]),
            ]
            ForEach(groups, id: \.0) { title, commands in
                Text(title).font(.subheadline).bold().padding(.top, 4)
                VStack(spacing: 2) {
                    ForEach(commands, id: \.self) { command in
                        let chord = settings.primaryDisplay(for: command)
                        HStack {
                            Text(command.label)
                                .frame(width: 200, alignment: .leading)
                            Text(chord.isEmpty ? "No hotkey" : chord)
                                .foregroundStyle(chord.isEmpty ? .secondary : .primary)
                                .monospaced()
                            Spacer()
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 8)
            }
            Text("Hotkeys are rebindable in Settings → Hotkeys. Changes take effect immediately (no restart needed).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: (b) Feature quick-start

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Feature Quick-Start")

            quickStartItem(
                title: "Switching inputs",
                body: "Press a hotkey or click the action in the menu bar. The menu bar ticks the last input this app sent (best-effort — OSD changes are not reflected)."
            )
            quickStartItem(
                title: "KVM switching",
                body: "Three ports: USB-C (⌃⇧⌘K), Upstream (⌃⇧⌘U), Auto (⌃⇧⌘A). USB-C is the cable that carries both video and USB data; Upstream is the USB-B port used with DisplayPort cables."
            )
            quickStartItem(
                title: "PBP / PIP modes",
                body: "Off (⌃⇧⌘O), PIP (⌃⇧⌘I), PBP (⌃⇧⌘P). Use the PBP section in Settings to set the source for each window. Sub-window source is hardware-confirmed; main-window source is unverified."
            )
            quickStartItem(
                title: "Edge-switch KVM",
                body: "Enable in Settings → Edge-Switch KVM. When PBP is active, moving the cursor across the centre divider automatically switches the KVM. Requires Input Monitoring permission (only asked when you enable the toggle). Only applies to Type-C and DisplayPort windows — HDMI windows are not auto-switched."
            )
            quickStartItem(
                title: "Quick Launcher",
                body: "Press ⌃⇧⌘ Space (or click Quick Launcher… in the menu) to open a floating palette of all actions. Tab/Space/Return to navigate; Esc to dismiss. The chord is rebindable."
            )
            quickStartItem(
                title: "Rebinding hotkeys",
                body: "Open Settings, click a chord to start capturing, press your new combination, then release. Conflicts are surfaced immediately. You can add multiple hotkeys per action or remove existing ones."
            )
            quickStartItem(
                title: "Launch at login",
                body: "Toggle in Settings → Launch at login. Uses macOS SMAppService (modern, no helper required)."
            )
        }
    }

    @ViewBuilder
    private func quickStartItem(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).bold()
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }

    // MARK: (c) Troubleshooting

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Troubleshooting")

            troubleItem(
                title: "Monitor not detected",
                body: "The app uses raw USB HID (VID 0x1462, PID 0x3FA4). Ensure the USB cable (not just the video cable) is connected. Only the MD342CQP is tested. On first run, grant the app USB HID access if prompted."
            )
            troubleItem(
                title: "Gatekeeper blocks the app",
                body: "The app is unsigned (no Apple Developer certificate). Recommended fix: in Terminal, run:\n  xattr -dr com.apple.quarantine /Applications/MSIMonitorControl.app\nOr right-click the .app → Open → Open."
            )
            troubleItem(
                title: "Edge-switch KVM not working",
                body: "Check that the toggle is on in Settings → Edge-Switch KVM, and that Input Monitoring permission is granted (System Settings → Privacy & Security → Input Monitoring). The feature is inactive unless PBP mode was set via this app (OSD changes are not detected). Only Type-C and DisplayPort sources trigger a switch — HDMI sources are intentionally skipped."
            )
            troubleItem(
                title: "KVM mapping",
                body: "USB-C KVM port = the Type-C cable. Upstream KVM port = the USB-B cable used with DisplayPort. Auto = monitor decides. If your machines are on different ports, the KVM → Auto mode may work better."
            )
            troubleItem(
                title: "Input switching does nothing (KVM and PBP work)",
                body: "The monitor's firmware only honours input-switch commands that arrive over its USB-C upstream. A machine connected via the USB-B upstream can control KVM and PBP/PIP, but its input-switch commands are silently ignored — connect that machine via the monitor's USB-C port instead (hardware-verified on the MD342CQP)."
            )
            troubleItem(
                title: "Debug log",
                body: "If the app behaves unexpectedly, open the debug log for details: menu bar → Reveal Debug Log… The log is at:\n  ~/Library/Application Support/LogicalSapien/MSIMonitorControl/debug.log"
            )
            troubleItem(
                title: "Report a bug",
                body: "Open a GitHub issue at https://github.com/logicalsapien/msi-monitor-control and include the relevant debug.log lines."
            )

            Button("Reveal Debug Log…") {
                revealDebugLog()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func troubleItem(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).bold()
            Text(body)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
    }

    // MARK: (d) About / links

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("About")

            VStack(alignment: .leading, spacing: 4) {
                Text("MSI Monitor Control v\(version)")
                    .font(.subheadline).bold()
                Text("MIT licence © LogicalSapien")
                    .font(.caption)
                Text("Tested monitor: MSI MD342CQP. Other MSI monitors may work but are unverified.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("HID payloads obtained by reverse engineering. Use at your own risk.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider().padding(.vertical, 4)

                HStack(spacing: 12) {
                    Link("GitHub", destination: URL(string: "https://github.com/logicalsapien/msi-monitor-control")!)
                        .font(.caption)
                    Link("Releases", destination: URL(string: "https://github.com/logicalsapien/msi-monitor-control/releases")!)
                        .font(.caption)
                    Link("Issues", destination: URL(string: "https://github.com/logicalsapien/msi-monitor-control/issues")!)
                        .font(.caption)
                }
            }
            .padding(.leading, 8)
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func revealDebugLog() {
        guard let url = try? DebugLog.defaultURL() else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
