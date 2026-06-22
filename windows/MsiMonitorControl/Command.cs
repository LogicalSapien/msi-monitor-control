namespace MsiMonitorControl;

/// <summary>
/// The six supported monitor commands for the MSI MD342CQP.
/// HID payloads are sourced byte-identically from docs/PROTOCOL.md.
/// </summary>
public enum CommandKind
{
    PbpOn,
    PbpOff,
    KvmUsbC,
    KvmUpstream,
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

    /// <summary>
    /// Returns the raw HID report bytes for <paramref name="command"/>.
    /// Bytes are byte-identical to the macOS app and sourced from docs/PROTOCOL.md.
    /// </summary>
    /// <exception cref="NotImplementedException">
    /// Thrown for commands whose payloads are UNKNOWN in PROTOCOL.md (PBP, KVM).
    /// These require hardware reverse-engineering before they can be sent safely.
    /// Do not catch and swallow — surface as a Needs-decision to the human.
    /// </exception>
    public static byte[] PayloadFor(CommandKind command) => command switch
    {
        CommandKind.InputTypeC  => (byte[])PayloadInputTypeC.Clone(),
        CommandKind.InputDp     => (byte[])PayloadInputDp.Clone(),

        // UNKNOWN payloads — see docs/PROTOCOL.md §"What is NOT known".
        // PBP and KVM payloads must be discovered via USB HID capture on hardware
        // before being filled in here. Do NOT invent bytes.
        CommandKind.PbpOn       => throw new NotImplementedException("PbpOn payload UNKNOWN — see docs/PROTOCOL.md"),
        CommandKind.PbpOff      => throw new NotImplementedException("PbpOff payload UNKNOWN — see docs/PROTOCOL.md"),
        CommandKind.KvmUsbC     => throw new NotImplementedException("KvmUsbC payload UNKNOWN — see docs/PROTOCOL.md"),
        CommandKind.KvmUpstream => throw new NotImplementedException("KvmUpstream payload UNKNOWN — see docs/PROTOCOL.md"),

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
        _                       => false,
    };

    /// <summary>All six command kinds, in declaration order.</summary>
    public static IReadOnlyList<CommandKind> AllCases { get; } =
        Enum.GetValues<CommandKind>();
}
