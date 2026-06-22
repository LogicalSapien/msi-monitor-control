import Carbon
import MSIControl

// MARK: - Carbon key codes

private enum KeyCode {
    static let c: UInt32 = 8
    static let d: UInt32 = 2
    static let k: UInt32 = 40
    static let u: UInt32 = 32
    static let p: UInt32 = 35
    static let o: UInt32 = 31
}

// MARK: - Modifier mask

/// ⌃⌥⌘ (Control + Option + Command)
private let kHotKeyModifiers: UInt32 = UInt32(
    controlKey | optionKey | cmdKey
)

// MARK: - HotKeyManager

/// Registers global hotkeys via Carbon `RegisterEventHotKey`.
///
/// Default bindings (⌃⌥⌘ + key):
///
/// | Key | Action                |
/// |-----|-----------------------|
/// | C   | Input → Type-C        |
/// | D   | Input → DisplayPort   |
/// | K   | KVM → USB-C           |
/// | U   | KVM → Upstream        |
/// | P   | PBP On                |
/// | O   | PBP Off               |
final class HotKeyManager {

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private weak var deviceState: DeviceState?

    /// Mapping from hotkey ID to Command.
    private static let bindings: [(id: UInt32, keyCode: UInt32, command: Command)] = [
        (1, KeyCode.c, .inputTypeC),
        (2, KeyCode.d, .inputDP),
        (3, KeyCode.k, .kvmUSBC),
        (4, KeyCode.u, .kvmUpstream),
        (5, KeyCode.p, .pbpOn),
        (6, KeyCode.o, .pbpOff),
    ]

    /// Map from hotkey ID → Command, used in the event handler.
    private static let commandMap: [UInt32: Command] = {
        Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0.command) })
    }()

    init(deviceState: DeviceState) {
        self.deviceState = deviceState
        registerAll()
    }

    deinit {
        if let ref = handlerRef {
            RemoveEventHandler(ref)
        }
        for ref in hotKeyRefs {
            if let r = ref { UnregisterEventHotKey(r) }
        }
    }

    // MARK: - Registration

    private func registerAll() {
        // Install a Carbon event handler for hotkey events.
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )

        // C closure passed to Carbon — must be @convention(c).
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

        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        // InstallApplicationEventHandler is a C macro; call InstallEventHandler directly.
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )

        // Use a simple 4-byte OSType literal instead of the deprecated UTGetOSTypeFromString.
        let sig: OSType = 0x4D534931  // 'MSI1' in big-endian ASCII

        for binding in Self.bindings {
            var ref: EventHotKeyRef?
            let keyID = EventHotKeyID(signature: sig, id: binding.id)
            RegisterEventHotKey(
                binding.keyCode,
                kHotKeyModifiers,
                keyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            hotKeyRefs.append(ref)
        }
    }

    // MARK: - Handler

    private func handleHotKey(id: UInt32) {
        guard let command = Self.commandMap[id] else { return }
        DispatchQueue.main.async {
            self.deviceState?.send(command)
        }
    }
}
