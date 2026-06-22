import SwiftUI
import AppKit
import MSIControl

// MARK: - Settings window

/// The settings surface (SETTINGS.md §1): preset dropdown, per-action rebinding
/// rows with add/remove, conflict + AltGr surfacing, and the launch-at-login toggle.
struct SettingsView: View {

    @ObservedObject var settings: SettingsStore

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
            launchSection

            if let advisory {
                Text(advisory)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text("Hyper (⌃⌥⇧)").tag(HotkeyPreset.hyper)
                Text("Control + Shift (⌃⇧)").tag(HotkeyPreset.ctrlShift)
                Text("Legacy (⌃⌥⌘)").tag(HotkeyPreset.legacy)
                if settings.config.preset == .custom {
                    Text("Custom").tag(HotkeyPreset.custom)
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

    @ViewBuilder
    private func actionRows(for command: Command) -> some View {
        let chords = settings.config.bindings[command.actionId] ?? []
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(command.label).frame(width: 160, alignment: .leading)
                Spacer()
                Button {
                    capturing = CaptureTarget(actionId: command.actionId, index: Int.max)
                } label: {
                    Image(systemName: "plus.circle").help("Add another hotkey")
                }
                .buttonStyle(.borderless)
            }

            if chords.isEmpty && !isAppending(command) {
                Text("No hotkey")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 160)
            }

            ForEach(Array(chords.enumerated()), id: \.offset) { index, chord in
                chordRow(command: command, index: index, chord: chord)
            }

            // Active "add another hotkey" capture row (index == Int.max). Without
            // this the plus button armed capture but rendered no capture view, so
            // nothing could be appended.
            if isAppending(command) {
                appendCaptureRow(command: command)
            }
        }
    }

    private func isAppending(_ command: Command) -> Bool {
        capturing == CaptureTarget(actionId: command.actionId, index: Int.max)
    }

    @ViewBuilder
    private func appendCaptureRow(command: Command) -> some View {
        HStack {
            Spacer().frame(width: 160)
            Text("Press a chord…")
                .frame(minWidth: 110)
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
            Spacer()
        }
    }

    @ViewBuilder
    private func chordRow(command: Command, index: Int, chord: HotkeyChord) -> some View {
        let isCapturing = capturing == CaptureTarget(actionId: command.actionId, index: index)
        let conflicted = settings.osRejectedActions.contains(command.actionId)
        HStack {
            Spacer().frame(width: 160)
            Button {
                capturing = CaptureTarget(actionId: command.actionId, index: index)
            } label: {
                Text(isCapturing ? "Press a chord…" : chord.display)
                    .frame(minWidth: 110)
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

            // Require at least one modifier and exactly one valid base A–Z / 0–9 key.
            guard !mods.isEmpty,
                  let chars = event.charactersIgnoringModifiers?.uppercased(),
                  let ch = chars.first,
                  HotkeyChord.isValidKey(String(ch)) else {
                return   // ignore until a valid chord is pressed
            }
            onCapture?(HotkeyChord(mods: mods, key: String(ch)))
            stop()
        }

        private func stop() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        deinit { stop() }
    }
}
