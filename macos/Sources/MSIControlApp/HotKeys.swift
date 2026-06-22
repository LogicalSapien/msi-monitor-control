import Carbon
import MSIControl

// MARK: - Carbon key-code table (A–Z, 0–9)

/// Maps a base key character (upper-case `A`–`Z` / `0`–`9`) to its Carbon virtual
/// key code. These ANSI positions are an implementation detail of the macOS app —
/// NOT part of the shared config (see `docs/SETTINGS.md` §3.4). Keys outside this
/// table are out of scope for v0.2.0 and cannot be registered.
private enum CarbonKeyCode {
    static let table: [Character: UInt32] = [
        "A": 0,  "B": 11, "C": 8,  "D": 2,  "E": 14, "F": 3,  "G": 5,
        "H": 4,  "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45,
        "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1,  "T": 17, "U": 32,
        "V": 9,  "W": 13, "X": 7,  "Y": 16, "Z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25,
    ]

    static func code(for key: String) -> UInt32? {
        guard let ch = key.uppercased().first else { return nil }
        return table[ch]
    }
}

/// Translates a set of canonical modifiers into the Carbon modifier mask.
private func carbonModifierMask(_ mods: Set<HotkeyModifier>) -> UInt32 {
    var mask: UInt32 = 0
    if mods.contains(.control) { mask |= UInt32(controlKey) }
    if mods.contains(.option)  { mask |= UInt32(optionKey) }
    if mods.contains(.shift)   { mask |= UInt32(shiftKey) }
    if mods.contains(.command) { mask |= UInt32(cmdKey) }
    return mask
}

// MARK: - HotKeyManager

/// Registers global hotkeys via Carbon `RegisterEventHotKey`, driven entirely by a
/// `HotkeyConfig` (the shared settings contract). The single Carbon event handler
/// is installed once; `apply(config:)` (re)registers the chords and can be called
/// live — on a preset change or rebind — without an app restart (SETTINGS.md §5).
///
/// Only chords for available commands are registered; UNKNOWN-payload actions have
/// an empty bindings array, so they are skipped automatically.
///
/// Conforms to `HotkeyRegistering` (library seam) so the commit/rollback policy is
/// unit-testable with a spy.
final class HotKeyManager: HotkeyRegistering {

    /// A live registration: the Carbon ref plus which command it fires.
    private struct Registration {
        let ref: EventHotKeyRef
        let command: Command
    }

    private var registrations: [UInt32: Registration] = [:]   // hotkey id → registration
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private var selfPtr: UnsafeMutableRawPointer?
    private weak var deviceState: DeviceState?

    private static let signature: OSType = 0x4D534931  // 'MSI1'

    init(deviceState: DeviceState) {
        self.deviceState = deviceState
        installHandler()
    }

    deinit {
        // Carbon lifecycle must be torn down on the main thread; deinit of an
        // app-lifetime, main-thread-owned object runs there.
        unregisterAll()
        if let ref = handlerRef {
            RemoveEventHandler(ref)
        }
    }

    // MARK: - Handler install (once)

    private func installHandler() {
        assertMainThread()
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }
            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKey(id: hotkeyID.id)
            return noErr
        }

        // Pass `self` UNRETAINED: this manager is owned for the whole app lifetime by
        // `MSIControlApp`, so the pointer cannot dangle, and not retaining avoids a
        // self-retain cycle that would prevent `deinit` from ever running. The
        // matching `RemoveEventHandler` in `deinit` stops any further callbacks.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        self.selfPtr = selfPtr
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
        if installStatus != noErr {
            print("[HotKeys] InstallEventHandler failed: OSStatus \(installStatus)")
        }
    }

    /// Carbon hotkey APIs are not thread-safe; all (re)registration must happen on
    /// the main thread. We assert rather than hop, so a mis-call surfaces in debug.
    private func assertMainThread() {
        assert(Thread.isMainThread, "HotKeyManager must be used on the main thread (Carbon requirement)")
    }

    // MARK: - Live (re)registration (SETTINGS.md §5)

    /// Replaces the entire live registration set with the chords from `config`.
    /// Safe to call repeatedly (preset change, rebind). Returns the action ids whose
    /// chords the OS REFUSED to register (reserved/already-in-use) so the UI can
    /// surface a conflict — per the contract, the OS register call is the authority.
    @discardableResult
    func apply(config: HotkeyConfig) -> [String] {
        assertMainThread()
        unregisterAll()
        var failedActions: [String] = []

        for command in Command.allCases {
            // Skip unavailable commands defensively; their bindings should be empty
            // anyway, but this guarantees no UNKNOWN-payload chord is ever live.
            guard command.isAvailable else { continue }
            guard let chords = config.bindings[command.actionId] else { continue }

            for chord in chords {
                guard let keyCode = CarbonKeyCode.code(for: chord.key) else {
                    print("[HotKeys] No Carbon key code for '\(chord.key)' (\(command.actionId)); skipping.")
                    continue
                }
                let id = nextID; nextID += 1
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    keyCode,
                    carbonModifierMask(chord.mods),
                    EventHotKeyID(signature: Self.signature, id: id),
                    GetApplicationEventTarget(),
                    0,
                    &ref
                )
                if status == noErr, let ref = ref {
                    registrations[id] = Registration(ref: ref, command: command)
                } else {
                    // Reserved or already taken — surface for conflict handling.
                    print("[HotKeys] RegisterEventHotKey failed for \(command.actionId) (\(chord.display)): OSStatus \(status)")
                    if !failedActions.contains(command.actionId) {
                        failedActions.append(command.actionId)
                    }
                }
            }
        }
        return failedActions
    }

    private func unregisterAll() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }

    // MARK: - Handler dispatch

    private func handleHotKey(id: UInt32) {
        guard let command = registrations[id]?.command else { return }
        DispatchQueue.main.async { [weak self] in
            self?.deviceState?.send(command)
        }
    }
}
