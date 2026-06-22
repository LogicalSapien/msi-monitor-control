namespace MsiMonitorControl;

/// <summary>
/// The supported monitor commands for the MSI MD342CQP.
/// HID payloads are sourced byte-identically from docs/PROTOCOL.md.
///
/// Input switching (<see cref="InputTypeC"/>, <see cref="InputDp"/>) and KVM switching
/// (<see cref="KvmUsbC"/>, <see cref="KvmUpstream"/>) have confirmed payloads. PBP
/// (<see cref="PbpOn"/>, <see cref="PbpOff"/>) and the third KVM mode
/// (<see cref="KvmAuto"/>) have UNKNOWN payloads and surface as unavailable until they
/// are reverse-engineered on hardware — their bytes are never invented.
/// </summary>
public enum CommandKind
{
    PbpOn,
    PbpOff,
    KvmUsbC,
    KvmUpstream,
    KvmAuto,
    InputTypeC,
    InputDp,
}

public static class Command
{
    // -------------------------------------------------------------------------
    // Known payloads — sourced verbatim from docs/PROTOCOL.md.
    // Both Input payloads are 53 bytes (the length the reference implementation
    // sends; the report size field on the device is 64 but the reference uses
    // data.count = 53, so we match that exactly for byte-identical behaviour).
    // -------------------------------------------------------------------------

    private static readonly byte[] PayloadInputTypeC =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] PayloadInputDp =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    // -------------------------------------------------------------------------
    // KVM switching — feature 0x38 0x3E at indices [5],[6]. Source: kdar/msi-monitor-ctrl,
    // documented in docs/PROTOCOL.md §KVM switching. Byte-identical to the macOS
    // Command.swift kvm* cases. Only byte[10] differs (the position).
    //
    // byte[10] position→port mapping CONFIRMED on hardware (user-probed on the MD342CQP, v0.2.1):
    //   0x30 → Auto      (KvmAuto)
    //   0x31 → Upstream  (KvmUpstream)
    //   0x32 → USB-C     (KvmUsbC)
    //   (0x33 unused — there is no 4th position.)
    // NOTE: this CORRECTS the earlier provisional guess (0x30=USB-C, 0x31=Upstream) — 0x30 is
    // actually Auto, and USB-C is 0x32. All three are now live, confirmed values.
    // Transport: HID SetReport (stream.Write), matching the rest of the app. (kdar uses libusb
    // interrupt OUT; the 53-byte payload is identical — only the transport differs.)
    // -------------------------------------------------------------------------

    private static readonly byte[] PayloadKvmUsbC =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x32, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] PayloadKvmUpstream =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x31, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] PayloadKvmAuto =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    /// <summary>
    /// Returns the raw HID report bytes for <paramref name="command"/>.
    /// Bytes are byte-identical to the macOS app and sourced from docs/PROTOCOL.md.
    /// </summary>
    /// <exception cref="NotImplementedException">
    /// Thrown for commands whose payloads are still UNKNOWN in PROTOCOL.md (PBP On/Off). These
    /// require hardware reverse-engineering before they can be sent safely. Do not catch and
    /// swallow — surface as a Needs-decision to the human.
    /// </exception>
    public static byte[] PayloadFor(CommandKind command) => command switch
    {
        CommandKind.InputTypeC  => (byte[])PayloadInputTypeC.Clone(),
        CommandKind.InputDp     => (byte[])PayloadInputDp.Clone(),

        // KVM switching — all three confirmed on hardware (feature 0x38 0x3E; byte[10]:
        // USB-C=0x32, Upstream=0x31, Auto=0x30). See docs/PROTOCOL.md §KVM.
        CommandKind.KvmUsbC     => (byte[])PayloadKvmUsbC.Clone(),
        CommandKind.KvmUpstream => (byte[])PayloadKvmUpstream.Clone(),
        CommandKind.KvmAuto     => (byte[])PayloadKvmAuto.Clone(),

        // UNKNOWN payloads — see docs/PROTOCOL.md §"What is NOT known". PBP On/Off must be
        // discovered via USB HID capture on hardware before being filled in. Do NOT invent bytes.
        CommandKind.PbpOn       => throw new NotImplementedException("PbpOn payload UNKNOWN — see docs/PROTOCOL.md"),
        CommandKind.PbpOff      => throw new NotImplementedException("PbpOff payload UNKNOWN — see docs/PROTOCOL.md"),

        _ => throw new ArgumentOutOfRangeException(nameof(command), command, null),
    };

    /// <summary>
    /// Returns true if <paramref name="command"/> has a known payload sourced from PROTOCOL.md.
    /// Commands returning false will surface as unavailable in the UI.
    /// </summary>
    public static bool IsAvailable(CommandKind command) => command switch
    {
        CommandKind.InputTypeC  => true,
        CommandKind.InputDp     => true,
        CommandKind.KvmUsbC     => true,
        CommandKind.KvmUpstream => true,
        CommandKind.KvmAuto     => true,  // v0.2.1: byte[10]=0x30 confirmed on hardware — now live.
        // PbpOn, PbpOff — payloads UNKNOWN, unavailable until reverse-engineered.
        _                       => false,
    };

    /// <summary>All command kinds, in declaration order.</summary>
    public static IReadOnlyList<CommandKind> AllCases { get; } =
        Enum.GetValues<CommandKind>();

    // -------------------------------------------------------------------------
    // Data-driven identity (docs/SETTINGS.md §3.6, §5).
    //
    // v0.2.0: Command no longer hardcodes a key/modifier. The chord comes from the
    // loaded HotkeyConfig, keyed by the stable actionId below. Command keeps only its
    // intrinsic facts: actionId, label, payload, IsAvailable.
    // -------------------------------------------------------------------------

    /// <summary>
    /// The stable string id that maps this command 1:1 to a config binding (and to the
    /// macOS <c>Command</c> case). These ids are a public contract — <b>never rename one</b>
    /// (it would orphan a user's binding); only add new ones. See docs/SETTINGS.md §3.6.
    /// </summary>
    public static string ActionId(CommandKind command) => command switch
    {
        CommandKind.InputTypeC  => "inputTypeC",
        CommandKind.InputDp     => "inputDP",
        CommandKind.KvmUsbC     => "kvmUSBC",
        CommandKind.KvmUpstream => "kvmUpstream",
        CommandKind.KvmAuto     => "kvmAuto",
        CommandKind.PbpOn       => "pbpOn",
        CommandKind.PbpOff      => "pbpOff",
        _ => throw new ArgumentOutOfRangeException(nameof(command), command, null),
    };

    /// <summary>The reverse map: the <see cref="CommandKind"/> for a stable actionId, or null.</summary>
    public static CommandKind? KindForActionId(string actionId)
    {
        foreach (var kind in AllCases)
            if (ActionId(kind) == actionId)
                return kind;
        return null;
    }

    /// <summary>The human-readable menu/UI label for this command (British English).</summary>
    public static string Label(CommandKind command) => command switch
    {
        CommandKind.InputTypeC  => "Input → Type-C",
        CommandKind.InputDp     => "Input → DP",
        CommandKind.KvmUsbC     => "KVM → USB-C",
        CommandKind.KvmUpstream => "KVM → Upstream",
        CommandKind.KvmAuto     => "KVM → Auto",
        CommandKind.PbpOn       => "PBP On",
        CommandKind.PbpOff      => "PBP Off",
        _ => throw new ArgumentOutOfRangeException(nameof(command), command, null),
    };
}
