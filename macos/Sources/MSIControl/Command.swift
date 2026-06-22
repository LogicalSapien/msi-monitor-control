/// A command that can be sent to an MSI monitor via USB HID.
///
/// Six cases are defined as per the plan. Four actions have confirmed payloads
/// sourced from `docs/PROTOCOL.md`:
/// - `inputTypeC`, `inputDP` — from github.com/Phaseowner/MSI-Display-Switch
/// - `kvmUSBC`, `kvmUpstream` — from github.com/kdar/msi-monitor-ctrl
///
/// `pbpOn` and `pbpOff` still have `payload == nil` because their HID bytes are
/// unknown; they are **never** shown in the menu or triggered by hotkeys until
/// confirmed payloads are added to PROTOCOL.md.
public enum Command: CaseIterable {
    case pbpOn
    case pbpOff
    case kvmUSBC
    case kvmUpstream
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

        // KVM switching — feature 0x38 0x3E. Source: kdar/msi-monitor-ctrl.
        // TODO(verify-on-hardware): position→port mapping is UNCONFIRMED. We map
        // USB-C to position 0 and Upstream to position 1; flip if hardware proves
        // otherwise. Also TODO(verify-on-hardware): kdar sends over libusb
        // interrupt OUT; we send over HID SetReport — bytes expected identical.
        // See docs/PROTOCOL.md § KVM switching.
        case .kvmUSBC:      // value = 0x30 (position 0)
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        case .kvmUpstream:  // value = 0x31 (position 1)
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x31, 0x0D,
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
        case .inputTypeC:  return "Input → Type-C"
        case .inputDP:     return "Input → DisplayPort"
        }
    }
}
