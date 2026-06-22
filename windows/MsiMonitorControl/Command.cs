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
    // Command.swift kvmUSBC/kvmUpstream cases. Only byte[10] differs (the position).
    //
    // TODO(verify-on-hardware): the position→port mapping is UNCONFIRMED. We map
    // USB-C to position 0 (byte[10] = 0x30) and Upstream to position 1 (byte[10] = 0x31);
    // flip these two if hardware proves otherwise.
    // TODO(verify-on-hardware): kdar sends these bytes over libusb interrupt OUT; we send
    // over HID SetReport (stream.Write). The 12-byte payload is expected to be identical —
    // only the transport differs — but confirm on the real MD342CQP. Do not switch to libusb.
    // -------------------------------------------------------------------------

    private static readonly byte[] PayloadKvmUsbC =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
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

    /// <summary>
    /// Returns the raw HID report bytes for <paramref name="command"/>.
    /// Bytes are byte-identical to the macOS app and sourced from docs/PROTOCOL.md.
    /// </summary>
    /// <exception cref="NotImplementedException">
    /// Thrown for commands whose payloads are still UNKNOWN in PROTOCOL.md (PBP On/Off and
    /// the third KVM mode, KVM Auto). These require hardware reverse-engineering before they
    /// can be sent safely. Do not catch and swallow — surface as a Needs-decision to the human.
    /// </exception>
    public static byte[] PayloadFor(CommandKind command) => command switch
    {
        CommandKind.InputTypeC  => (byte[])PayloadInputTypeC.Clone(),
        CommandKind.InputDp     => (byte[])PayloadInputDp.Clone(),

        // KVM switching — confirmed payloads (feature 0x38 0x3E). See docs/PROTOCOL.md §KVM.
        CommandKind.KvmUsbC     => (byte[])PayloadKvmUsbC.Clone(),
        CommandKind.KvmUpstream => (byte[])PayloadKvmUpstream.Clone(),

        // UNKNOWN payloads — see docs/PROTOCOL.md §"What is NOT known".
        // PBP and the third KVM mode (Auto) must be discovered via USB HID capture on
        // hardware before being filled in here. Do NOT invent bytes. KvmAuto is a third
        // value of the KVM feature (0x38 0x3E) but its byte[10] value is not yet known.
        CommandKind.PbpOn       => throw new NotImplementedException("PbpOn payload UNKNOWN — see docs/PROTOCOL.md"),
        CommandKind.PbpOff      => throw new NotImplementedException("PbpOff payload UNKNOWN — see docs/PROTOCOL.md"),
        CommandKind.KvmAuto     => throw new NotImplementedException("KvmAuto payload UNKNOWN — see docs/PROTOCOL.md"),

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
        // PbpOn, PbpOff, KvmAuto — payloads UNKNOWN, unavailable until reverse-engineered.
        _                       => false,
    };

    /// <summary>All command kinds, in declaration order.</summary>
    public static IReadOnlyList<CommandKind> AllCases { get; } =
        Enum.GetValues<CommandKind>();
}
