using MsiMonitorControl;
using Xunit;

namespace MsiMonitorControl.Tests;

/// <summary>
/// Tests for <see cref="Command.PayloadFor"/> and <see cref="Command.IsAvailable"/>.
/// Expected byte arrays are copied verbatim from docs/PROTOCOL.md — do not modify
/// without updating PROTOCOL.md first (single source of truth).
/// </summary>
public class CommandTests
{
    // -------------------------------------------------------------------------
    // Expected payloads — verbatim from docs/PROTOCOL.md §Payloads.
    // 53 bytes each (the length the reference sends; see PROTOCOL.md notes).
    // -------------------------------------------------------------------------

    private static readonly byte[] ExpectedInputTypeC =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] ExpectedInputDp =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    // KVM switching — feature 0x38 0x3E. Byte-identical to macOS Command.swift.
    // byte[10] confirmed on hardware (v0.2.1): USB-C=0x32, Upstream=0x31, Auto=0x30.
    private static readonly byte[] ExpectedKvmUsbC =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x32, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] ExpectedKvmUpstream =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x31, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] ExpectedKvmAuto =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    // v0.2.2 — Input HDMI1/2 (feature 0x35 0x30; byte[10] 0x30/0x31). Byte-identical to macOS.
    private static readonly byte[] ExpectedInputHdmi1 =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x30, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] ExpectedInputHdmi2 =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x31, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    // v0.2.2 — PBP/PIP mode (feature 0x36 0x30; byte[10] Off=0x30, PIP=0x31, On=0x32). Byte-identical to macOS.
    private static readonly byte[] ExpectedPbpOff =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x30, 0x30, 0x30, 0x30, 0x30, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] ExpectedPbpPip =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x30, 0x30, 0x30, 0x30, 0x31, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    private static readonly byte[] ExpectedPbpOn =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    };

    // -------------------------------------------------------------------------
    // Enum shape
    // -------------------------------------------------------------------------

    [Fact]
    public void AllCasesCoversEveryEnumMember()
    {
        Assert.Equal(Enum.GetValues<CommandKind>().Length, Command.AllCases.Count);
    }

    [Fact]
    public void AllCasesCoversAllKinds_InContractOrder()
    {
        // v0.2.2: 11 kinds, declaration order = the §3.6 actionId contract order (ShowLauncher last).
        var expected = new[]
        {
            CommandKind.InputHdmi1,
            CommandKind.InputHdmi2,
            CommandKind.InputTypeC,
            CommandKind.InputDp,
            CommandKind.KvmUsbC,
            CommandKind.KvmUpstream,
            CommandKind.KvmAuto,
            CommandKind.PbpOff,
            CommandKind.PbpPip,
            CommandKind.PbpOn,
            CommandKind.ShowLauncher,
        };

        Assert.Equal(expected, Command.AllCases);
    }

    // -------------------------------------------------------------------------
    // Known payloads — byte-identical to docs/PROTOCOL.md and macOS Command.payload
    // -------------------------------------------------------------------------

    [Fact]
    public void InputTypeCPayloadMatchesProtocol()
    {
        Assert.Equal(ExpectedInputTypeC, Command.PayloadFor(CommandKind.InputTypeC));
    }

    [Fact]
    public void InputDpPayloadMatchesProtocol()
    {
        Assert.Equal(ExpectedInputDp, Command.PayloadFor(CommandKind.InputDp));
    }

    [Fact]
    public void InputTypeCPayloadIs53Bytes()
    {
        Assert.Equal(53, Command.PayloadFor(CommandKind.InputTypeC).Length);
    }

    [Fact]
    public void InputDpPayloadIs53Bytes()
    {
        Assert.Equal(53, Command.PayloadFor(CommandKind.InputDp).Length);
    }

    [Fact]
    public void InputTypeCAndDpDifferOnlyAtByte10()
    {
        var typeC = Command.PayloadFor(CommandKind.InputTypeC);
        var dp    = Command.PayloadFor(CommandKind.InputDp);

        // Byte 10 is the input selector: 0x33 = Type-C, 0x32 = DP (from PROTOCOL.md).
        Assert.Equal(0x33, typeC[10]);
        Assert.Equal(0x32, dp[10]);

        // All other bytes must be identical.
        for (int i = 0; i < typeC.Length; i++)
        {
            if (i == 10) continue;
            Assert.Equal(typeC[i], dp[i]);
        }
    }

    [Fact]
    public void PayloadFor_ReturnsDefensiveCopy()
    {
        // Mutating the returned array must not affect subsequent calls.
        var payload = Command.PayloadFor(CommandKind.InputTypeC);
        payload[0] = 0xFF;
        Assert.Equal(0x01, Command.PayloadFor(CommandKind.InputTypeC)[0]);
    }

    // -------------------------------------------------------------------------
    // KVM payloads — feature 0x38 0x3E, byte-identical to macOS Command.swift
    // -------------------------------------------------------------------------

    [Fact]
    public void KvmUsbCPayloadMatchesProtocol()
    {
        Assert.Equal(ExpectedKvmUsbC, Command.PayloadFor(CommandKind.KvmUsbC));
    }

    [Fact]
    public void KvmUpstreamPayloadMatchesProtocol()
    {
        Assert.Equal(ExpectedKvmUpstream, Command.PayloadFor(CommandKind.KvmUpstream));
    }

    [Fact]
    public void KvmAutoPayloadMatchesProtocol()
    {
        Assert.Equal(ExpectedKvmAuto, Command.PayloadFor(CommandKind.KvmAuto));
    }

    [Fact]
    public void KvmPayloadsAre53Bytes()
    {
        Assert.Equal(53, Command.PayloadFor(CommandKind.KvmUsbC).Length);
        Assert.Equal(53, Command.PayloadFor(CommandKind.KvmUpstream).Length);
        Assert.Equal(53, Command.PayloadFor(CommandKind.KvmAuto).Length);
    }

    [Fact]
    public void KvmPayloadsDifferOnlyAtByte10_WithConfirmedMapping()
    {
        var usbC     = Command.PayloadFor(CommandKind.KvmUsbC);
        var upstream = Command.PayloadFor(CommandKind.KvmUpstream);
        var auto     = Command.PayloadFor(CommandKind.KvmAuto);

        // Byte 10 is the KVM position — CONFIRMED on hardware (v0.2.1, MD342CQP):
        //   Auto = 0x30, Upstream = 0x31, USB-C = 0x32.
        Assert.Equal(0x32, usbC[10]);
        Assert.Equal(0x31, upstream[10]);
        Assert.Equal(0x30, auto[10]);

        // The feature code lives at bytes[5],[6] and must be the KVM feature 0x38 0x3E
        // (the input feature uses 0x35 0x30 at those same two indices — note 0x35 also
        // appears at byte[1] as the fixed header, which is unrelated to the feature code).
        Assert.Equal(0x38, usbC[5]);
        Assert.Equal(0x3E, usbC[6]);

        // All other bytes must be identical across all three KVM payloads.
        for (int i = 0; i < usbC.Length; i++)
        {
            if (i == 10) continue;
            Assert.Equal(usbC[i], upstream[i]);
            Assert.Equal(usbC[i], auto[i]);
        }
    }

    // -------------------------------------------------------------------------
    // HDMI inputs + PBP/PIP mode payloads (v0.2.2) — byte-identical to macOS
    // -------------------------------------------------------------------------

    [Fact]
    public void InputHdmi1PayloadMatchesProtocol() => Assert.Equal(ExpectedInputHdmi1, Command.PayloadFor(CommandKind.InputHdmi1));

    [Fact]
    public void InputHdmi2PayloadMatchesProtocol() => Assert.Equal(ExpectedInputHdmi2, Command.PayloadFor(CommandKind.InputHdmi2));

    [Fact]
    public void PbpOffPayloadMatchesProtocol() => Assert.Equal(ExpectedPbpOff, Command.PayloadFor(CommandKind.PbpOff));

    [Fact]
    public void PbpPipPayloadMatchesProtocol() => Assert.Equal(ExpectedPbpPip, Command.PayloadFor(CommandKind.PbpPip));

    [Fact]
    public void PbpOnPayloadMatchesProtocol() => Assert.Equal(ExpectedPbpOn, Command.PayloadFor(CommandKind.PbpOn));

    [Fact]
    public void AllInputsShareFeatureDifferOnlyAtByte10()
    {
        // Feature 0x35 0x30 at [5],[6]; byte[10]: HDMI1=0x30, HDMI2=0x31, DP=0x32, Type-C=0x33.
        var h1 = Command.PayloadFor(CommandKind.InputHdmi1);
        var h2 = Command.PayloadFor(CommandKind.InputHdmi2);
        var dp = Command.PayloadFor(CommandKind.InputDp);
        var tc = Command.PayloadFor(CommandKind.InputTypeC);
        Assert.Equal(0x30, h1[10]);
        Assert.Equal(0x31, h2[10]);
        Assert.Equal(0x32, dp[10]);
        Assert.Equal(0x33, tc[10]);
        Assert.Equal(0x35, h1[5]); Assert.Equal(0x30, h1[6]);
        for (int i = 0; i < h1.Length; i++)
        {
            if (i == 10) continue;
            Assert.Equal(h1[i], h2[i]); Assert.Equal(h1[i], dp[i]); Assert.Equal(h1[i], tc[i]);
        }
    }

    [Fact]
    public void PbpModePayloadsShareFeatureDifferOnlyAtByte10()
    {
        // Feature 0x36 0x30 at [5],[6]; byte[10]: Off=0x30, PIP=0x31, On(PBP)=0x32.
        var off = Command.PayloadFor(CommandKind.PbpOff);
        var pip = Command.PayloadFor(CommandKind.PbpPip);
        var on  = Command.PayloadFor(CommandKind.PbpOn);
        Assert.Equal(0x30, off[10]);
        Assert.Equal(0x31, pip[10]);
        Assert.Equal(0x32, on[10]);
        Assert.Equal(0x36, off[5]); Assert.Equal(0x30, off[6]);
        for (int i = 0; i < off.Length; i++)
        {
            if (i == 10) continue;
            Assert.Equal(off[i], pip[i]); Assert.Equal(off[i], on[i]);
        }
    }

    [Fact]
    public void AllMonitorPayloadsAre53Bytes()
    {
        foreach (var kind in Command.AllCases)
            if (Command.IsMonitorCommand(kind))
                Assert.Equal(53, Command.PayloadFor(kind).Length);
    }

    // -------------------------------------------------------------------------
    // PBP source-select — parameterised payload (v0.2.2)
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData(Command.PbpInput.Hdmi1, 0x30)]
    [InlineData(Command.PbpInput.Hdmi2, 0x31)]
    [InlineData(Command.PbpInput.Dp,    0x32)]
    [InlineData(Command.PbpInput.TypeC, 0x33)]
    public void PbpSourcePayload_SubWindow_FeatureAndValue(Command.PbpInput input, int expectedByte10)
    {
        var p = Command.PbpSourcePayload(Command.PbpWindow.Sub, input);
        Assert.Equal(53, p.Length);
        Assert.Equal(0x36, p[5]);          // PBP feature hi
        Assert.Equal(0x31, p[6]);          // sub-window
        Assert.Equal(expectedByte10, p[10]);
        Assert.Equal(0x01, p[0]);
        Assert.Equal(0x0D, p[11]);
    }

    [Fact]
    public void PbpSourcePayload_MainWindow_UsesFeature0x32()
    {
        // Main-window is UNVERIFIED on hardware but the byte form is fixed: feature 0x36 0x32.
        var p = Command.PbpSourcePayload(Command.PbpWindow.Main, Command.PbpInput.Hdmi1);
        Assert.Equal(0x36, p[5]);
        Assert.Equal(0x32, p[6]); // main-window (vs sub 0x31)
        Assert.Equal(0x30, p[10]);
    }

    [Fact]
    public void PbpSourcePayload_SubAndMainDifferOnlyAtFeatureLoByte()
    {
        var sub  = Command.PbpSourcePayload(Command.PbpWindow.Sub,  Command.PbpInput.Dp);
        var main = Command.PbpSourcePayload(Command.PbpWindow.Main, Command.PbpInput.Dp);
        for (int i = 0; i < sub.Length; i++)
        {
            if (i == 6) continue; // only the feature-lo byte differs
            Assert.Equal(sub[i], main[i]);
        }
        Assert.NotEqual(sub[6], main[6]);
    }

    // -------------------------------------------------------------------------
    // IsAvailable — v0.2.2: every kind is hardware-confirmed
    // -------------------------------------------------------------------------

    [Fact]
    public void IsAvailable_AllKindsLive()
    {
        foreach (var kind in Command.AllCases)
            Assert.True(Command.IsAvailable(kind), $"{kind} should be available in v0.2.2");
    }

    [Fact]
    public void PayloadFor_NeverThrows_ForMonitorCommands()
    {
        // v0.2.2: all MONITOR payloads are confirmed — none throw (PBP On/Off/PIP now have real bytes).
        foreach (var kind in Command.AllCases)
            if (Command.IsMonitorCommand(kind))
                _ = Command.PayloadFor(kind);
    }

    [Fact]
    public void ShowLauncher_IsAppOnly_NotAMonitorCommand()
    {
        Assert.False(Command.IsMonitorCommand(CommandKind.ShowLauncher));
        // Every other kind IS a monitor command.
        foreach (var kind in Command.AllCases)
            if (kind != CommandKind.ShowLauncher)
                Assert.True(Command.IsMonitorCommand(kind));
        // PayloadFor must NOT be called for ShowLauncher — it has no HID payload.
        Assert.Throws<InvalidOperationException>(() => Command.PayloadFor(CommandKind.ShowLauncher));
    }

    // -------------------------------------------------------------------------
    // Data-driven identity — stable actionIds (docs/SETTINGS.md §3.6) + labels.
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData(CommandKind.InputHdmi1,  "inputHDMI1")]
    [InlineData(CommandKind.InputHdmi2,  "inputHDMI2")]
    [InlineData(CommandKind.InputTypeC,  "inputTypeC")]
    [InlineData(CommandKind.InputDp,     "inputDP")]
    [InlineData(CommandKind.KvmUsbC,     "kvmUSBC")]
    [InlineData(CommandKind.KvmUpstream, "kvmUpstream")]
    [InlineData(CommandKind.KvmAuto,     "kvmAuto")]
    [InlineData(CommandKind.PbpOff,      "pbpOff")]
    [InlineData(CommandKind.PbpPip,      "pbpPIP")]
    [InlineData(CommandKind.PbpOn,       "pbpOn")]
    [InlineData(CommandKind.ShowLauncher, "showLauncher")]
    public void ActionId_MatchesSettingsContract(CommandKind command, string expected)
    {
        Assert.Equal(expected, Command.ActionId(command));
    }

    [Fact]
    public void KindForActionId_RoundTripsEveryCommand()
    {
        foreach (var kind in Command.AllCases)
            Assert.Equal(kind, Command.KindForActionId(Command.ActionId(kind)));
    }

    [Fact]
    public void KindForActionId_ReturnsNullForUnknownId()
    {
        Assert.Null(Command.KindForActionId("nope"));
    }

    [Theory]
    [InlineData(CommandKind.InputHdmi1,  "Input → HDMI 1")]
    [InlineData(CommandKind.InputHdmi2,  "Input → HDMI 2")]
    [InlineData(CommandKind.InputTypeC,  "Input → Type-C")]
    [InlineData(CommandKind.InputDp,     "Input → DP")]
    [InlineData(CommandKind.KvmUsbC,     "KVM → USB-C")]
    [InlineData(CommandKind.KvmUpstream, "KVM → Upstream")]
    [InlineData(CommandKind.KvmAuto,     "KVM → Auto")]
    [InlineData(CommandKind.PbpOff,      "PBP/PIP → Off")]
    [InlineData(CommandKind.PbpPip,      "PBP/PIP → Picture-in-Picture")]
    [InlineData(CommandKind.PbpOn,       "PBP/PIP → Picture-by-Picture")]
    [InlineData(CommandKind.ShowLauncher, "Quick Launcher")]
    public void Label_IsBritishEnglishAndStable(CommandKind command, string expected)
    {
        Assert.Equal(expected, Command.Label(command));
    }
}
