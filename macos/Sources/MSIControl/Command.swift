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
    case pbpOn        // PBP/PIP mode = PBP (feature 0x36 0x30, value 0x32)
    case pbpOff       // PBP/PIP mode = Off (feature 0x36 0x30, value 0x30)
    case pbpPIP       // PBP/PIP mode = PIP (feature 0x36 0x30, value 0x31)
    case kvmUSBC
    case kvmUpstream
    case kvmAuto
    case inputHDMI1
    case inputHDMI2
    case inputTypeC
    case inputDP
    case showLauncher   // UI action (opens the quick-launcher palette) — NOT a HID command

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
        // Input switching — feature 0x35 0x30; byte[10] = input enum.
        // HARDWARE-CONFIRMED: HDMI1=0x30, HDMI2=0x31, DP=0x32, Type-C=0x33.
        case .inputHDMI1:  return Command.makePayload(featHi: 0x35, featLo: 0x30, value: 0x30)
        case .inputHDMI2:  return Command.makePayload(featHi: 0x35, featLo: 0x30, value: 0x31)
        case .inputDP:     return Command.makePayload(featHi: 0x35, featLo: 0x30, value: 0x32)
        case .inputTypeC:  return Command.makePayload(featHi: 0x35, featLo: 0x30, value: 0x33)

        // KVM switching — feature 0x38 0x3E; HARDWARE-CONFIRMED via tools/kvm-probe:
        // Auto=0x30, Upstream=0x31, USB-C=0x32 (0x33 no-op). See docs/PROTOCOL.md § KVM.
        case .kvmAuto:     return Command.makePayload(featHi: 0x38, featLo: 0x3E, value: 0x30)
        case .kvmUpstream: return Command.makePayload(featHi: 0x38, featLo: 0x3E, value: 0x31)
        case .kvmUSBC:     return Command.makePayload(featHi: 0x38, featLo: 0x3E, value: 0x32)

        // PBP/PIP mode — feature 0x36 0x30; HARDWARE-CONFIRMED: Off=0x30, PIP=0x31,
        // PBP=0x32. Replaces the old nil-payload PBP stubs. See docs/PROTOCOL.md § PBP.
        case .pbpOff:      return Command.makePayload(featHi: 0x36, featLo: 0x30, value: 0x30)
        case .pbpPIP:      return Command.makePayload(featHi: 0x36, featLo: 0x30, value: 0x31)
        case .pbpOn:       return Command.makePayload(featHi: 0x36, featLo: 0x30, value: 0x32)

        // UI action — opens the quick-launcher palette; no HID payload.
        case .showLauncher: return nil
        }
    }

    /// Whether this action sends a HID report to the monitor. `showLauncher` is a
    /// UI action (opens the launcher window) and is NOT a monitor command, so the
    /// dispatch must NOT call `MSIDevice.send` for it.
    public var isMonitorCommand: Bool {
        self != .showLauncher
    }

    /// Builds a 53-byte HID output report for the ASCII command grammar
    /// `01 35 62 30 30 <featHi> <featLo> 30 30 30 <value> 0D` zero-padded to 53.
    /// byte[0]=0x01 report ID; feature at [5],[6]; value at [10]. See PROTOCOL.md.
    static func makePayload(featHi: UInt8, featLo: UInt8, value: UInt8) -> [UInt8] {
        var p = [UInt8](repeating: 0x00, count: 53)
        p[0]  = 0x01; p[1] = 0x35; p[2] = 0x62
        p[3]  = 0x30; p[4] = 0x30
        p[5]  = featHi; p[6] = featLo
        p[7]  = 0x30; p[8] = 0x30; p[9] = 0x30
        p[10] = value
        p[11] = 0x0D
        return p
    }

    // MARK: - Availability

    /// Whether this action is available (registrable / shown). Monitor commands are
    /// available iff they have a known payload; the `showLauncher` UI action is
    /// always available (it needs no payload).
    public var isAvailable: Bool {
        isMonitorCommand ? payload != nil : true
    }

    // MARK: - Display label (British English)

    /// Human-readable label for use in the menu bar.
    public var label: String {
        switch self {
        case .pbpOn:       return "PBP/PIP → PBP"
        case .pbpOff:      return "PBP/PIP → Off"
        case .pbpPIP:      return "PBP/PIP → PIP"
        case .kvmUSBC:     return "KVM → USB-C"
        case .kvmUpstream: return "KVM → Upstream"
        case .kvmAuto:     return "KVM → Auto"
        case .inputHDMI1:  return "Input → HDMI 1"
        case .inputHDMI2:  return "Input → HDMI 2"
        case .inputTypeC:  return "Input → Type-C"
        case .inputDP:     return "Input → DisplayPort"
        case .showLauncher: return "Quick Launcher…"
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
        case .pbpPIP:      return "pbpPIP"
        case .kvmUSBC:     return "kvmUSBC"
        case .kvmUpstream: return "kvmUpstream"
        case .kvmAuto:     return "kvmAuto"
        case .inputHDMI1:  return "inputHDMI1"
        case .inputHDMI2:  return "inputHDMI2"
        case .inputTypeC:  return "inputTypeC"
        case .inputDP:     return "inputDP"
        case .showLauncher: return "showLauncher"
        }
    }

    /// Looks up a command by its stable `actionId` (the inverse of `actionId`),
    /// e.g. to resolve a config `bindings` key back to a `Command`.
    public static func from(actionId: String) -> Command? {
        allCases.first { $0.actionId == actionId }
    }

    // MARK: - Mutually-exclusive group (for last-sent "current" tracking)

    /// The mutually-exclusive group this command belongs to. The monitor cannot
    /// report its state, so the app tracks the LAST successfully-sent command per
    /// group to show a "current" highlight (SETTINGS.md / PROTOCOL.md § no read-back).
    public enum Group: Sendable { case input, kvm, pbpMode }

    /// The mutually-exclusive monitor-state group, or `nil` for non-monitor actions
    /// (`showLauncher`) which have no "current" state to track.
    public var group: Group? {
        switch self {
        case .inputHDMI1, .inputHDMI2, .inputTypeC, .inputDP: return .input
        case .kvmUSBC, .kvmUpstream, .kvmAuto:                return .kvm
        case .pbpOn, .pbpOff, .pbpPIP:                        return .pbpMode
        case .showLauncher:                                  return nil
        }
    }

    // MARK: - Default hotkey key

    /// The default base key for this command's hotkey (SETTINGS.md §3.6). This is
    /// only a SEED for the built-in default config — at runtime the actual key and
    /// modifiers come from the loaded `HotkeyConfig`. (The property is optional to
    /// allow future menu-only commands, but in v0.2.2 every command seeds a chord.)
    /// Returns a key TOKEN string (a single `A`–`Z`/`0`–`9` char, or a named key
    /// like `"Space"`) so named keys are representable, or `nil` for no default chord.
    public var defaultKey: String? {
        switch self {
        case .inputHDMI1:   return "H"
        case .inputHDMI2:   return "J"
        case .inputTypeC:   return "C"
        case .inputDP:      return "D"
        case .kvmUSBC:      return "K"
        case .kvmUpstream:  return "U"
        case .kvmAuto:      return "A"
        case .pbpOn:        return "P"
        case .pbpPIP:       return "I"
        case .pbpOff:       return "O"
        case .showLauncher: return "Space"   // ⌃⇧⌘Space by default
        }
    }
}

// MARK: - PBP source-select (parameterised, not a fixed Command)

/// A monitor input, used both for main-input switching and as the value for the
/// PBP per-window source-select features (SETTINGS.md / PROTOCOL.md). The raw value
/// is byte[10] in the 53-byte report.
public enum InputEnum: UInt8, CaseIterable, Sendable {
    case hdmi1 = 0x30
    case hdmi2 = 0x31
    case displayPort = 0x32
    case typeC = 0x33

    public var label: String {
        switch self {
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .displayPort: return "DisplayPort"
        case .typeC: return "Type-C"
        }
    }
}

/// Which PBP/PIP window a source-select targets.
public enum PBPWindow: Sendable {
    /// Right / inset window. Feature `0x36 0x31` — HARDWARE-CONFIRMED.
    case sub
    /// Left / main window. Feature `0x36 0x32` — **ASSUMED, not hardware-verified**
    /// (the KVM/USB-C control connection is on the main window, so it couldn't be
    /// probed safely). See docs/PROTOCOL.md § PBP.
    case main

    /// The 2-byte feature code at indices [5],[6] for this window's source-select.
    var feature: (hi: UInt8, lo: UInt8) {
        switch self {
        case .sub:  return (0x36, 0x31)
        case .main: return (0x36, 0x32)
        }
    }

    /// Whether this window's source feature is hardware-verified.
    public var isVerified: Bool {
        switch self {
        case .sub:  return true
        case .main: return false
        }
    }
}
