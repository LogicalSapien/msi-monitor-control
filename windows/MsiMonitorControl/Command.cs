namespace MsiMonitorControl;

/// <summary>
/// The supported monitor commands for the MSI MD342CQP.
/// HID payloads are sourced byte-identically from docs/PROTOCOL.md.
///
/// v0.2.2: all input, KVM and PBP/PIP-mode commands now have hardware-confirmed payloads.
/// Only the PBP source-select operation is a parameterised device API (not a fixed command) —
/// see <see cref="MsiDevice.SetPbpSource"/>. Declaration order follows the §3.6 actionId
/// contract order (shared with macOS).
/// </summary>
public enum CommandKind
{
    InputHdmi1,
    InputHdmi2,
    InputTypeC,
    InputDp,
    KvmUsbC,
    KvmUpstream,
    KvmAuto,
    PbpOff,
    PbpPip,
    PbpOn,
    // v0.2.2: not a monitor command — opens the quick-launcher window (no HID payload).
    ShowLauncher,
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

    // v0.2.2: HDMI inputs — same Input feature (0x35 0x30); byte[10] 0x30=HDMI1, 0x31=HDMI2.
    // (DP=0x32, Type-C=0x33.) Byte-identical to the macOS Command.swift inputHDMI1/2 cases.
    private static readonly byte[] PayloadInputHdmi1 =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x30, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] PayloadInputHdmi2 =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x31, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    // v0.2.2: PBP/PIP mode — feature 0x36 0x30 at indices [5],[6]; byte[10] selects the mode:
    // 0x30=Off, 0x31=PIP (picture-in-picture), 0x32=PBP (picture-by-picture, side-by-side).
    // Hardware-confirmed; byte-identical to the macOS Command.swift pbpOff/pbpPIP/pbpOn cases.
    private static readonly byte[] PayloadPbpOff =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x30, 0x30, 0x30, 0x30, 0x30, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] PayloadPbpPip =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x30, 0x30, 0x30, 0x30, 0x31, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] PayloadPbpOn =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
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
    /// <remarks>
    /// v0.2.2: every <see cref="CommandKind"/> now has a hardware-confirmed payload (inputs incl.
    /// HDMI1/2, KVM incl. Auto, and PBP/PIP mode Off/PIP/On). PBP <b>source-select</b> is a
    /// separate parameterised operation — see <see cref="MsiDevice.SetPbpSource"/>.
    /// </remarks>
    public static byte[] PayloadFor(CommandKind command) => command switch
    {
        // Input switching — feature 0x35 0x30; byte[10]: HDMI1=0x30, HDMI2=0x31, DP=0x32, Type-C=0x33.
        CommandKind.InputHdmi1  => (byte[])PayloadInputHdmi1.Clone(),
        CommandKind.InputHdmi2  => (byte[])PayloadInputHdmi2.Clone(),
        CommandKind.InputTypeC  => (byte[])PayloadInputTypeC.Clone(),
        CommandKind.InputDp     => (byte[])PayloadInputDp.Clone(),

        // KVM switching — feature 0x38 0x3E; byte[10]: USB-C=0x32, Upstream=0x31, Auto=0x30.
        CommandKind.KvmUsbC     => (byte[])PayloadKvmUsbC.Clone(),
        CommandKind.KvmUpstream => (byte[])PayloadKvmUpstream.Clone(),
        CommandKind.KvmAuto     => (byte[])PayloadKvmAuto.Clone(),

        // PBP/PIP mode — feature 0x36 0x30; byte[10]: Off=0x30, PIP=0x31, On(PBP)=0x32 (v0.2.2).
        CommandKind.PbpOff      => (byte[])PayloadPbpOff.Clone(),
        CommandKind.PbpPip      => (byte[])PayloadPbpPip.Clone(),
        CommandKind.PbpOn       => (byte[])PayloadPbpOn.Clone(),

        // ShowLauncher is NOT a monitor command — it has no HID payload. Callers must gate on
        // IsMonitorCommand and never reach here for it.
        CommandKind.ShowLauncher => throw new InvalidOperationException(
            "ShowLauncher is not a monitor command — it has no HID payload (check IsMonitorCommand)."),

        _ => throw new ArgumentOutOfRangeException(nameof(command), command, null),
    };

    /// <summary>
    /// True when <paramref name="command"/> sends a HID report to the monitor. False for app-only
    /// actions like <see cref="CommandKind.ShowLauncher"/> (which open UI instead). Dispatch must
    /// route non-monitor commands to their handler rather than <see cref="MsiDevice.Send"/>.
    /// </summary>
    public static bool IsMonitorCommand(CommandKind command) => command != CommandKind.ShowLauncher;

    /// <summary>
    /// Returns true if <paramref name="command"/> is a usable action. v0.2.2: all monitor commands
    /// are hardware-confirmed, and ShowLauncher (app-only) is always available.
    /// </summary>
    public static bool IsAvailable(CommandKind command) => command switch
    {
        CommandKind.InputHdmi1   => true,
        CommandKind.InputHdmi2   => true,
        CommandKind.InputTypeC   => true,
        CommandKind.InputDp      => true,
        CommandKind.KvmUsbC      => true,
        CommandKind.KvmUpstream  => true,
        CommandKind.KvmAuto      => true,
        CommandKind.PbpOff       => true,
        CommandKind.PbpPip       => true,
        CommandKind.PbpOn        => true,
        CommandKind.ShowLauncher => true, // app-only (opens the quick-launcher)
        _                        => false,
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
        CommandKind.InputHdmi1  => "inputHDMI1",
        CommandKind.InputHdmi2  => "inputHDMI2",
        CommandKind.InputTypeC  => "inputTypeC",
        CommandKind.InputDp     => "inputDP",
        CommandKind.KvmUsbC     => "kvmUSBC",
        CommandKind.KvmUpstream => "kvmUpstream",
        CommandKind.KvmAuto     => "kvmAuto",
        CommandKind.PbpOff      => "pbpOff",
        CommandKind.PbpPip      => "pbpPIP",
        CommandKind.PbpOn       => "pbpOn",
        CommandKind.ShowLauncher => "showLauncher",
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
        CommandKind.InputHdmi1  => "Input → HDMI 1",
        CommandKind.InputHdmi2  => "Input → HDMI 2",
        CommandKind.InputTypeC  => "Input → Type-C",
        CommandKind.InputDp     => "Input → DP",
        CommandKind.KvmUsbC     => "KVM → USB-C",
        CommandKind.KvmUpstream => "KVM → Upstream",
        CommandKind.KvmAuto     => "KVM → Auto",
        CommandKind.PbpOff      => "PBP/PIP → Off",
        CommandKind.PbpPip      => "PBP/PIP → Picture-in-Picture",
        CommandKind.PbpOn       => "PBP/PIP → Picture-by-Picture",
        CommandKind.ShowLauncher => "Quick Launcher",
        _ => throw new ArgumentOutOfRangeException(nameof(command), command, null),
    };

    // -------------------------------------------------------------------------
    // PBP source-select — parameterised (NOT a fixed CommandKind). v0.2.2.
    //
    // Sets which physical input feeds a PBP/PIP window. Two windows, each its own feature code:
    //   sub-window  = feature 0x36 0x31
    //   main-window = feature 0x36 0x32   ← UNVERIFIED on hardware (flagged in UI + here)
    // byte[10] = the input enum value (HDMI1=0, HDMI2=1, DP=2, Type-C=3) offset onto the 0x30 base
    // (so 0x30/0x31/0x32/0x33), matching the input-feature value convention. Byte-identical to
    // the macOS device API. 53-byte report, byte[0]=0x01.
    // -------------------------------------------------------------------------

    /// <summary>Which PBP/PIP window a source-select targets.</summary>
    public enum PbpWindow
    {
        Sub,   // feature 0x36 0x31 — verified
        Main,  // feature 0x36 0x32 — UNVERIFIED on hardware
    }

    /// <summary>The input a PBP window can be fed from. Enum value = the on-the-wire offset.</summary>
    public enum PbpInput
    {
        Hdmi1 = 0,
        Hdmi2 = 1,
        Dp    = 2,
        TypeC = 3,
    }

    /// <summary>Human-readable label for a <see cref="PbpInput"/> (British English).</summary>
    public static string Label(PbpInput input) => input switch
    {
        PbpInput.Hdmi1 => "HDMI 1",
        PbpInput.Hdmi2 => "HDMI 2",
        PbpInput.Dp    => "DP",
        PbpInput.TypeC => "Type-C",
        _ => throw new ArgumentOutOfRangeException(nameof(input), input, null),
    };

    /// <summary>
    /// Builds the 53-byte PBP source-select report for <paramref name="window"/> ←
    /// <paramref name="input"/>. The window picks the feature code (sub 0x36 0x31 / main 0x36 0x32);
    /// the input picks byte[10] (0x30 + enum value). Byte-identical to the macOS device API.
    /// </summary>
    public static byte[] PbpSourcePayload(PbpWindow window, PbpInput input)
    {
        byte featLo = window == PbpWindow.Sub ? (byte)0x31 : (byte)0x32;
        byte value  = (byte)(0x30 + (int)input);

        var p = new byte[53];
        p[0]  = 0x01;
        p[1]  = 0x35;
        p[2]  = 0x62;
        p[3]  = 0x30;
        p[4]  = 0x30;
        p[5]  = 0x36;     // PBP feature hi
        p[6]  = featLo;   // sub=0x31 / main=0x32
        p[7]  = 0x30;
        p[8]  = 0x30;
        p[9]  = 0x30;
        p[10] = value;    // input: 0x30=HDMI1 … 0x33=Type-C
        p[11] = 0x0D;
        // p[12..] remain 0x00.
        return p;
    }
}
