/// A command that can be sent to an MSI monitor via USB HID.
///
/// Six cases are defined as per the plan. Only `inputTypeC` and `inputDP` have
/// confirmed payloads (sourced from `docs/PROTOCOL.md` via reverse engineering of
/// github.com/Phaseowner/MSI-Display-Switch). The remaining four actions —
/// `pbpOn`, `pbpOff`, `kvmUSBC`, `kvmUpstream` — have `payload == nil` because
/// their HID bytes are unknown; they are **never** shown in the menu or triggered
/// by hotkeys until confirmed payloads are added to PROTOCOL.md.
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
    /// - byte[1]  : `0x35`
    /// - byte[2]  : `0x62`
    /// - bytes[3..9]  : `0x30 0x30 0x35 0x30 0x30 0x30 0x30`
    /// - byte[10] : input selector (`0x32` = DP, `0x33` = Type-C)
    /// - byte[11] : `0x0D` (carriage return — ASCII command terminator)
    /// - bytes[12..52]: `0x00`
    ///
    /// Source: docs/PROTOCOL.md
    public var payload: [UInt8]? {
        switch self {
        case .inputTypeC:
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        case .inputDP:
            return [
                0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00
            ]

        case .pbpOn, .pbpOff, .kvmUSBC, .kvmUpstream:
            // UNKNOWN — needs hardware reverse-engineering.
            // See docs/PROTOCOL.md § "Reverse-engineering notes".
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
