/// A command that can be sent to an MSI monitor via USB HID.
///
/// Seven cases are defined. Five actions have confirmed payloads sourced from
/// `docs/PROTOCOL.md`:
/// - `inputTypeC`, `inputDP` — from github.com/Phaseowner/MSI-Display-Switch
/// - `kvmUSBC`, `kvmUpstream`, `kvmAuto` — KVM feature 0x38 0x3E, byte[10] values
///   HARDWARE-CONFIRMED on the MD342CQP via `tools/kvm-probe` (USB-C=0x32,
///   Upstream=0x31, Auto=0x30).
///
/// Only `pbpOn` and `pbpOff` still have `payload == nil` because their HID bytes
/// are unknown. They are **never** shown in the menu or triggered by hotkeys until
/// confirmed payloads are added to PROTOCOL.md.
public enum Command: CaseIterable {
    case pbpOn
    case pbpOff
    case kvmUSBC
    case kvmUpstream
    case kvmAuto
    case inputTypeC
    case inputDP

    // MARK: - Payload

    /// The raw HID output report bytes for this command, or `nil` if the payload
    /// has not yet been reverse-engineered and confirmed on hardware.
    ///
    /// Byte layout (53 bytes, padded to report size 0x40 by `IOHIDDeviceSetReport`):
    /// - byte[0]  : report ID = `0x01`
    /// - byte[1]  : `0x35` (header)
    /// - byte[2]  : `0x62` (`'b'` = write)
    /// - bytes[3..4]  : `0x30 0x30`
    /// - bytes[5..6]  : feature code (`0x35 0x30` = input, `0x38 0x3E` = KVM)
    /// - bytes[7..9]  : `0x30 0x30 0x30`
    /// - byte[10] : value byte (`0x30` + position)
    /// - byte[11] : `0x0D` (carriage return — ASCII command terminator)
    /// - bytes[12..52]: `0x00`
    ///
    /// See `docs/PROTOCOL.md § Command grammar` for the full structure.
    public var payload: [UInt8]? {
        switch self {
        // Input switching — feature 0x35 0x30. Source: Phaseowner/MSI-Display-Switch.
        case .inputTypeC:   // value = 0x33 (position 3)
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        case .inputDP:      // value = 0x32 (position 2)
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        // KVM switching — feature 0x38 0x3E. byte[10] selects the port.
        // HARDWARE-CONFIRMED on the MD342CQP via tools/kvm-probe (2026-06-22):
        //   0x30 → Auto, 0x31 → Upstream, 0x32 → USB-C  (0x33 = no change).
        // This corrects the earlier reference-guessed mapping (USB-C was wrongly
        // 0x30, which is actually Auto) and supplies the previously-UNKNOWN Auto
        // value. See docs/PROTOCOL.md § KVM switching.
        case .kvmUSBC:      // value = 0x32 (USB-C) — hardware-confirmed
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x32, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        case .kvmUpstream:  // value = 0x31 (Upstream) — hardware-confirmed
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x31, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        case .kvmAuto:      // value = 0x30 (Auto) — hardware-confirmed (was UNKNOWN)
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        case .pbpOn, .pbpOff:
            // UNKNOWN — needs hardware reverse-engineering (sweep feature code at
            // [5],[6]). See docs/PROTOCOL.md § PBP (Picture-by-Picture).
            return nil
        }
    }

    // MARK: - Availability

    /// Whether the payload for this command is known and the command can be sent.
    public var isAvailable: Bool {
        payload != nil
    }

    // MARK: - Display label (British English)

    /// Human-readable label for use in the menu bar.
    public var label: String {
        switch self {
        case .pbpOn:       return "PBP On"
        case .pbpOff:      return "PBP Off"
        case .kvmUSBC:     return "KVM → USB-C"
        case .kvmUpstream: return "KVM → Upstream"
        case .kvmAuto:     return "KVM → Auto"
        case .inputTypeC:  return "Input → Type-C"
        case .inputDP:     return "Input → DisplayPort"
        }
    }

    // MARK: - Stable action id (config contract)

    /// The stable string id used as the key in the shared settings config
    /// (`docs/SETTINGS.md` §3.6). It maps 1:1 to a `Command` case and MUST match the
    /// Windows `CommandKind` id and the JSON `bindings` keys exactly. **Never rename
    /// an id** — it would orphan a user's saved binding. Add new ids only.
    public var actionId: String {
        switch self {
        case .pbpOn:       return "pbpOn"
        case .pbpOff:      return "pbpOff"
        case .kvmUSBC:     return "kvmUSBC"
        case .kvmUpstream: return "kvmUpstream"
        case .kvmAuto:     return "kvmAuto"
        case .inputTypeC:  return "inputTypeC"
        case .inputDP:     return "inputDP"
        }
    }

    /// Looks up a command by its stable `actionId` (the inverse of `actionId`),
    /// e.g. to resolve a config `bindings` key back to a `Command`.
    public static func from(actionId: String) -> Command? {
        allCases.first { $0.actionId == actionId }
    }

    // MARK: - Default hotkey key

    /// The default base key for this command's hotkey (SETTINGS.md §3.6). This is
    /// only a SEED for the built-in default config — at runtime the actual key and
    /// modifiers come from the loaded `HotkeyConfig`, never from here. The displayed
    /// chord is computed by `HotkeyChord.display`, so there is no stored
    /// shortcut string to drift.
    public var defaultKey: Character {
        switch self {
        case .inputTypeC:  return "C"
        case .inputDP:     return "D"
        case .kvmUSBC:     return "K"
        case .kvmUpstream: return "U"
        case .kvmAuto:     return "A"
        case .pbpOn:       return "P"
        case .pbpOff:      return "O"
        }
    }
}
