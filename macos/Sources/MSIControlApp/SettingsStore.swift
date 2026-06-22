import Foundation
import Combine
import MSIControl

/// The app's observable settings hub. Owns the loaded `HotkeyConfig`, persists every
/// change atomically, and drives live hotkey re-registration and launch-at-login.
/// SwiftUI views observe this; they never touch `HotkeyConfig` or `HotKeyManager`
/// directly.
@MainActor
final class SettingsStore: ObservableObject {

    /// The live config. Mutated only through the methods below so persistence and
    /// re-registration stay coupled to every change.
    @Published private(set) var config: HotkeyConfig

    /// Action ids whose chord the OS most recently refused to register
    /// (reserved/in-use). Surfaced in the UI as a conflict (SETTINGS.md §3.5).
    @Published private(set) var osRejectedActions: [String] = []

    /// Current Input Monitoring permission status (cached; updated when the user
    /// enables the edge-switch toggle). The Settings UI observes this to show the
    /// permission row (v0.2.3 design §1.1, §7.1).
    @Published private(set) var inputMonitoringStatus: InputMonitoringStatus = .unknown

    /// The edge-switch KVM tracker. Created lazily when first needed; retained here
    /// for the app lifetime once created.
    var edgeSwitchTracker: EdgeSwitchTracker?

    private let hotKeyManager: HotkeyRegistering
    private let fileURL: URL?

    /// - Parameter fileURL: override for tests; `nil` uses the default vendor path.
    init(hotKeyManager: HotkeyRegistering, fileURL: URL? = nil) {
        self.hotKeyManager = hotKeyManager
        self.fileURL = fileURL
        let (loaded, _) = HotkeyConfig.load(from: fileURL)
        self.config = loaded
        // Apply the loaded hotkeys, and make the OS launch-at-login state match the
        // config (config wins, §6).
        self.osRejectedActions = hotKeyManager.apply(config: loaded)
        LaunchAtLogin.reconcile(desired: loaded.launchAtLogin)
    }

    // MARK: - Mutations (each persists + re-applies)

    /// Applies a preset (apply-and-bake: rewrites all binding mods), persists, and
    /// re-registers the hotkeys live.
    func applyPreset(_ preset: HotkeyPreset) {
        var c = config
        c.applyPreset(preset)
        commit(c)
    }

    /// Validates and sets the chord at `index` for an action. Returns the validation
    /// issues; on a BLOCKING `.duplicate` the change is NOT applied. AltGr warnings
    /// are advisory and do not block.
    @discardableResult
    func rebind(action actionId: String, index: Int, to chord: HotkeyChord) -> [HotkeyConfig.ValidationIssue] {
        let issues = config.validate(chord: chord, forAction: actionId)
        if issues.contains(where: { if case .duplicate = $0 { return true }; return false }) {
            return issues   // blocked — keep existing binding
        }
        var c = config
        var chords = c.bindings[actionId] ?? []
        if index >= 0 && index < chords.count {
            chords[index] = chord
        } else {
            chords.append(chord)
        }
        c.bindings[actionId] = chords
        c.preset = c.inferredPreset()   // keep the label honest after a hand-edit
        commit(c)
        return issues
    }

    /// Adds an extra chord to an action (the add-hotkey feature). Blocked on duplicate.
    @discardableResult
    func addBinding(action actionId: String, chord: HotkeyChord) -> [HotkeyConfig.ValidationIssue] {
        rebind(action: actionId, index: Int.max, to: chord)
    }

    /// Removes the chord at `index` for an action.
    func removeBinding(action actionId: String, index: Int) {
        var c = config
        guard var chords = c.bindings[actionId], index >= 0, index < chords.count else { return }
        chords.remove(at: index)
        c.bindings[actionId] = chords
        c.preset = c.inferredPreset()
        commit(c)
    }

    /// Enables or disables the edge-switch KVM feature (v0.2.3 design §1.1).
    ///
    /// On enable: probes Input Monitoring permission. If denied, does NOT apply the
    /// setting — leaves the toggle off and updates `inputMonitoringStatus` so the UI
    /// shows the advisory + System Settings button. If granted, saves and notifies the
    /// tracker (per design §3.1).
    func setEdgeSwitchEnabled(_ enabled: Bool) {
        if enabled {
            let status = probeInputMonitoringPermission()
            inputMonitoringStatus = status
            guard status == .granted else {
                DebugLog.shared.warn("edge-switch toggle on — Input Monitoring denied; not enabling")
                // Ensure the config stays false (the UI binding read will stay false).
                return
            }
        }
        var c = config
        c.edgeSwitchEnabled = enabled
        persist(c)
        config = c
        edgeSwitchTracker?.setEnabled(enabled)
        DebugLog.shared.info("edge-switch \(enabled ? "enabled" : "disabled")")
    }

    /// Toggles launch-at-login. Calls the OS first; only persists on success so the
    /// config never claims a state the OS rejected (§6).
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            var c = config
            c.launchAtLogin = enabled
            persist(c)
            config = c
        } catch {
            print("[Settings] launch-at-login \(enabled) failed: \(error); reverting.")
            // Force a publish so the UI toggle snaps back to the real state.
            objectWillChange.send()
        }
    }

    // MARK: - Helpers

    /// Tries to apply `newConfig` to the OS FIRST; only persists + publishes if the
    /// OS accepted every chord. On any OS rejection (reserved/in-use) the change is
    /// rolled back: the PREVIOUS config is re-registered (so the user keeps working
    /// hotkeys), nothing is persisted, and `osRejectedActions` surfaces the conflict
    /// (SETTINGS.md §3.5/§5). Returns true if committed, false if rolled back.
    @discardableResult
    private func commit(_ newConfig: HotkeyConfig) -> Bool {
        // The register-first / persist-on-success / rollback-and-re-register policy
        // lives in the library `HotkeyCommitter` so it is unit-testable with a spy
        // registrar (SETTINGS.md §3.5/§5).
        let result = HotkeyCommitter.commit(previous: config,
                                            candidate: newConfig,
                                            registrar: hotKeyManager,
                                            persist: { [weak self] in self?.persist($0) })
        config = result.liveConfig
        osRejectedActions = result.rejectedActions
        if result.committed {
            DebugLog.shared.info("settings committed (preset \(result.liveConfig.preset.rawValue))")
        } else {
            DebugLog.shared.warn("settings change rolled back — OS rejected: \(result.rejectedActions.joined(separator: ","))")
            objectWillChange.send()   // refresh UI to show the conflict + reverted state
        }
        return result.committed
    }

    private func persist(_ c: HotkeyConfig) {
        do {
            try c.save(to: fileURL)
        } catch {
            DebugLog.shared.error("settings save failed: \(error.localizedDescription)")
        }
    }

    /// The derived display string for an action's first chord, for the menu
    /// (SETTINGS.md §3.7). Empty if the action has no chord.
    func primaryDisplay(for command: Command) -> String {
        config.bindings[command.actionId]?.first?.display ?? ""
    }
}
