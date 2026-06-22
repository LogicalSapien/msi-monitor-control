import SwiftUI
import AppKit
import MSIControl

// MARK: - Settings window

/// The settings surface (SETTINGS.md §1): preset dropdown, per-action rebinding
/// rows with add/remove, conflict + AltGr surfacing, and the launch-at-login toggle.
struct SettingsView: View {

    @ObservedObject var settings: SettingsStore
    @ObservedObject var deviceState: DeviceState
    /// Opens the Help window (injected from App.swift scene).
    var openHelp: (() -> Void)? = nil

    /// Which (action, index) is currently capturing a new chord, if any.
    @State private var capturing: CaptureTarget?
    /// Transient advisory shown after an AltGr-flagged rebind.
    @State private var advisory: String?

    private struct CaptureTarget: Equatable {
        let actionId: String
        let index: Int   // Int.max == appending a new chord
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2).bold()

            presetSection
            Divider()
            bindingsSection
            Divider()
            pbpSection
            Divider()
            edgeSwitchSection
            Divider()
            launchSection

            if let advisory {
                Text(advisory)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let openHelp {
                Divider()
                HStack {
                    Spacer()
                    Button("Help…", action: openHelp)
                        .buttonStyle(.link)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: Preset

    private var presetSection: some View {
        HStack {
            Text("Scheme")
            Picker("Scheme", selection: presetBinding) {
                // Labels are DERIVED from each preset's macOS modifiers
                // (`macDisplayName`) so the displayed chord stays honest, e.g.
                // "Default (⌃⇧⌘)". Windows builds its own labels from its mods.
                Text(HotkeyPreset.cmdShiftCtrl.macDisplayName).tag(HotkeyPreset.cmdShiftCtrl)
                Text(HotkeyPreset.ctrlShift.macDisplayName).tag(HotkeyPreset.ctrlShift)
                Text(HotkeyPreset.legacy.macDisplayName).tag(HotkeyPreset.legacy)
                if settings.config.preset == .custom {
                    Text(HotkeyPreset.custom.macDisplayName).tag(HotkeyPreset.custom)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 220)
            Spacer()
        }
    }

    /// `.custom` is display-only — selecting a named preset applies-and-bakes it.
    private var presetBinding: Binding<HotkeyPreset> {
        Binding(
            get: { settings.config.preset },
            set: { newValue in
                guard newValue != .custom else { return }
                settings.applyPreset(newValue)
            }
        )
    }

    // MARK: Bindings

    private var bindingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkeys").font(.headline)
            // Only commands with a known payload can take a hotkey.
            ForEach(Command.allCases.filter(\.isAvailable), id: \.self) { command in
                actionRows(for: command)
            }
        }
    }

    // Column widths for a tidy aligned grid: [label] … [chord] [＋][－].
    private let labelColumn: CGFloat = 170
    private let chordColumn: CGFloat = 120

    @ViewBuilder
    private func actionRows(for command: Command) -> some View {
        let chords = settings.config.bindings[command.actionId] ?? []
        VStack(alignment: .leading, spacing: 4) {
            if chords.isEmpty && !isAppending(command) {
                // Single row: label + "No hotkey" placeholder + add button, all on
                // ONE line in the same columns as bound rows.
                gridRow(label: command.label, command: command) {
                    Text("No hotkey")
                        .frame(width: chordColumn, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }

            // One row per chord — label shown only on the first row so extra chords
            // align under it without repeating the name.
            ForEach(Array(chords.enumerated()), id: \.offset) { index, chord in
                chordRow(command: command,
                         index: index,
                         chord: chord,
                         showLabel: index == 0)
            }

            // Active "add another hotkey" capture row (index == Int.max).
            if isAppending(command) {
                appendCaptureRow(command: command, showLabel: chords.isEmpty)
            }
        }
    }

    private func isAppending(_ command: Command) -> Bool {
        capturing == CaptureTarget(actionId: command.actionId, index: Int.max)
    }

    /// A single aligned row: [label column][trailing content][＋ add]. The trailing
    /// closure supplies the chord/placeholder/capture field (right-aligned).
    @ViewBuilder
    private func gridRow<Trailing: View>(label: String,
                                         command: Command,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: labelColumn, alignment: .leading)
            trailing()
            Button {
                capturing = CaptureTarget(actionId: command.actionId, index: Int.max)
            } label: {
                Image(systemName: "plus.circle").help("Add another hotkey")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func appendCaptureRow(command: Command, showLabel: Bool) -> some View {
        HStack(spacing: 8) {
            Text(showLabel ? command.label : "")
                .frame(width: labelColumn, alignment: .leading)
            Text("Press a chord…")
                .frame(width: chordColumn, alignment: .trailing)
                .foregroundStyle(.secondary)
                .background(
                    ChordCaptureView(isActive: true) { captured in
                        handleCapture(command: command, index: Int.max, chord: captured)
                    } onCancel: {
                        capturing = nil
                    }
                )
            Button("Cancel") { capturing = nil }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func chordRow(command: Command, index: Int, chord: HotkeyChord, showLabel: Bool) -> some View {
        let isCapturing = capturing == CaptureTarget(actionId: command.actionId, index: index)
        let conflicted = settings.osRejectedActions.contains(command.actionId)
        HStack(spacing: 8) {
            Text(showLabel ? command.label : "")
                .frame(width: labelColumn, alignment: .leading)
            Button {
                capturing = CaptureTarget(actionId: command.actionId, index: index)
            } label: {
                Text(isCapturing ? "Press a chord…" : chord.display)
                    .frame(width: chordColumn, alignment: .trailing)
            }
            .background(
                ChordCaptureView(isActive: isCapturing) { captured in
                    handleCapture(command: command, index: index, chord: captured)
                } onCancel: {
                    capturing = nil
                }
            )
            if conflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("This chord is reserved or already in use system-wide — choose another.")
            }
            Button {
                settings.removeBinding(action: command.actionId, index: index)
            } label: {
                Image(systemName: "minus.circle").help("Remove this hotkey")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
    }

    private func handleCapture(command: Command, index: Int, chord: HotkeyChord) {
        capturing = nil
        let issues = settings.rebind(action: command.actionId, index: index, to: chord)
        advisory = nil
        for issue in issues {
            switch issue {
            case .duplicate(let existing):
                let label = Command.from(actionId: existing)?.label ?? existing
                advisory = "\(chord.display) is already used by “\(label)”. Binding unchanged."
            case .altGrWarning(let key):
                advisory = "Note: ‘\(key)’ with ⌥ may clash with an AltGr character on some EU keyboard layouts."
            }
        }
    }

    // MARK: Picture-by-Picture

    private var pbpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Picture-by-Picture").font(.headline)

            // Mode — drives the pbpOff/pbpPIP/pbpOn commands and reflects the tracked
            // "current" mode (best-effort; monitor can't report state).
            HStack(spacing: 8) {
                Text("Mode").frame(width: labelColumn, alignment: .leading)
                Picker("Mode", selection: pbpModeBinding) {
                    Text("Off").tag(Command.pbpOff)
                    Text("PIP").tag(Command.pbpPIP)
                    Text("PBP").tag(Command.pbpOn)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!deviceState.isConnected)
            }

            // Sub-window source (feature 0x36 0x31 — hardware-confirmed).
            // Binding writes back to DeviceState.pbpSubSource so EdgeSwitchTracker
            // can read the current selection (v0.2.3 design §4.3).
            sourceRow(title: "Right / inset source", window: .sub,
                      selection: Binding(
                          get: { deviceState.pbpSubSource },
                          set: { deviceState.pbpSubSource = $0 }
                      ))

            // Main-window source (feature 0x36 0x32 — ASSUMED, not verified).
            sourceRow(title: "Left / main source", window: .main,
                      selection: Binding(
                          get: { deviceState.pbpMainSource },
                          set: { deviceState.pbpMainSource = $0 }
                      ),
                      footnote: "Unverified — the main-window source command isn’t hardware-confirmed yet.")
        }
    }

    /// Two-way binding: get reflects the tracked current PBP mode (default Off);
    /// set sends the corresponding command.
    private var pbpModeBinding: Binding<Command> {
        Binding(
            get: { deviceState.currentByGroup[.pbpMode] ?? .pbpOff },
            set: { deviceState.send($0) }
        )
    }

    @ViewBuilder
    private func sourceRow(title: String,
                           window: PBPWindow,
                           selection: Binding<InputEnum>,
                           footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title).frame(width: labelColumn, alignment: .leading)
                Picker(title, selection: selection) {
                    ForEach(InputEnum.allCases, id: \.self) { input in
                        Text(input.label).tag(input)
                    }
                }
                .labelsHidden()
                .frame(width: chordColumn + 60)
                .disabled(!deviceState.isConnected)
                // Single-arg onChange for macOS 13 compatibility (the two-arg form
                // is macOS 14+).
                .onChange(of: selection.wrappedValue) { newValue in
                    deviceState.setPBPSource(window: window, input: newValue)
                }
            }
            if let footnote {
                Text(footnote)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, labelColumn)
            }
        }
    }

    // MARK: Edge-Switch KVM (v0.2.3)

    /// The "Edge-Switch KVM" settings section. Layout per design §7.1.
    private var edgeSwitchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edge-Switch KVM").font(.headline)

            Toggle(isOn: Binding(
                get: { settings.config.edgeSwitchEnabled },
                set: { settings.setEdgeSwitchEnabled($0) }
            )) {
                Text("Auto-switch KVM at PBP divider")
            }

            Group {
                Text("When enabled and PBP mode is active, moving the cursor across the centre divider automatically switches the KVM to the source in that window.")
                Text("Only applies to Type-C and DisplayPort windows. HDMI sources are not auto-switched (ambiguous port mapping).")
                Text("⚠ Privacy: cursor position is read locally, used only for divider detection, and never stored or transmitted.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)

            // Input Monitoring permission status (always shown so the user understands
            // the dependency; deep-link button appears only when denied, per §7.1).
            inputMonitoringStatusRow
        }
    }

    @ViewBuilder
    private var inputMonitoringStatusRow: some View {
        let status = settings.inputMonitoringStatus
        HStack(spacing: 8) {
            Image(systemName: status == .granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(status == .granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility — Input Monitoring")
                    .font(.caption).bold()
                Text(status.statusText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status == .denied {
                Button("Open System Settings…") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
    }

    // MARK: Launch at login

    private var launchSection: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { settings.config.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        ))
    }
}

// MARK: - Chord capture (AppKit key monitor)

/// An invisible NSView-backed helper that, while `isActive`, installs a local key
/// monitor and reports the next chord (modifiers + base key) the user presses.
/// Escape cancels. Used by the rebinding rows to capture a new hotkey.
private struct ChordCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (HotkeyChord) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.onCancel = onCancel
        context.coordinator.setActive(isActive)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onCapture: ((HotkeyChord) -> Void)?
        var onCancel: (() -> Void)?
        private var monitor: Any?

        func setActive(_ active: Bool) {
            if active && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handle(event)
                    return nil   // swallow the event while capturing
                }
            } else if !active, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            // Escape cancels capture without binding — and tells SwiftUI to clear the
            // capturing state so the row doesn't get stuck on "Press a chord…".
            if event.keyCode == 53 {
                stop()
                onCancel?()
                return
            }

            var mods: Set<HotkeyModifier> = []
            if event.modifierFlags.contains(.control) { mods.insert(.control) }
            if event.modifierFlags.contains(.option)  { mods.insert(.option) }
            if event.modifierFlags.contains(.shift)   { mods.insert(.shift) }
            if event.modifierFlags.contains(.command) { mods.insert(.command) }
            guard !mods.isEmpty else { return }   // need at least one modifier

            // Resolve the base key: Space (keyCode 49) maps to the named "Space" key;
            // otherwise the typed A–Z / 0–9 character.
            let key: String
            if event.keyCode == 49 {
                key = "Space"
            } else if let ch = event.charactersIgnoringModifiers?.uppercased().first {
                key = String(ch)
            } else {
                return
            }
            guard HotkeyChord.isValidKey(key) else {
                return   // ignore until a valid chord is pressed
            }
            onCapture?(HotkeyChord(mods: mods, key: key))
            stop()
        }

        private func stop() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        deinit { stop() }
    }
}
