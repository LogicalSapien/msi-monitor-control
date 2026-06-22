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
    private static readonly byte[] ExpectedKvmUsbC =
    {
        0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
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

    // -------------------------------------------------------------------------
    // Enum shape
    // -------------------------------------------------------------------------

    [Fact]
    public void AllCasesCoversEveryEnumMember()
    {
        // No hardcoded count — adding a CommandKind shouldn't silently break this; the
        // exhaustive membership test below pins down the exact set.
        Assert.Equal(Enum.GetValues<CommandKind>().Length, Command.AllCases.Count);
    }

    [Fact]
    public void AllCasesCoversAllSevenKinds()
    {
        var expected = new[]
        {
            CommandKind.PbpOn,
            CommandKind.PbpOff,
            CommandKind.KvmUsbC,
            CommandKind.KvmUpstream,
            CommandKind.KvmAuto,
            CommandKind.InputTypeC,
            CommandKind.InputDp,
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
    public void KvmPayloadsAre53Bytes()
    {
        Assert.Equal(53, Command.PayloadFor(CommandKind.KvmUsbC).Length);
        Assert.Equal(53, Command.PayloadFor(CommandKind.KvmUpstream).Length);
    }

    [Fact]
    public void KvmUsbCAndUpstreamDifferOnlyAtByte10()
    {
        var usbC     = Command.PayloadFor(CommandKind.KvmUsbC);
        var upstream = Command.PayloadFor(CommandKind.KvmUpstream);

        // Byte 10 is the KVM position: 0x30 = USB-C (pos 0), 0x31 = Upstream (pos 1).
        // TODO(verify-on-hardware): mapping unconfirmed — see docs/PROTOCOL.md §KVM.
        Assert.Equal(0x30, usbC[10]);
        Assert.Equal(0x31, upstream[10]);

        // The feature code lives at bytes[5],[6] and must be the KVM feature 0x38 0x3E
        // (the input feature uses 0x35 0x30 at those same two indices — note 0x35 also
        // appears at byte[1] as the fixed header, which is unrelated to the feature code).
        Assert.Equal(0x38, usbC[5]);
        Assert.Equal(0x3E, usbC[6]);

        // All other bytes must be identical.
        for (int i = 0; i < usbC.Length; i++)
        {
            if (i == 10) continue;
            Assert.Equal(usbC[i], upstream[i]);
        }
    }

    // -------------------------------------------------------------------------
    // UNKNOWN payloads — must throw, never invent bytes
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData(CommandKind.PbpOn)]
    [InlineData(CommandKind.PbpOff)]
    [InlineData(CommandKind.KvmAuto)]
    public void PayloadFor_ThrowsNotImplemented_ForUnknownPayloads(CommandKind command)
    {
        // PBP On/Off and the third KVM mode (Auto) are UNKNOWN — see docs/PROTOCOL.md
        // §"What is NOT known". The correct behaviour is to throw rather than send
        // invented bytes to the monitor.
        Assert.Throws<NotImplementedException>(() => Command.PayloadFor(command));
    }

    // -------------------------------------------------------------------------
    // IsAvailable
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData(CommandKind.InputTypeC,  true)]
    [InlineData(CommandKind.InputDp,     true)]
    [InlineData(CommandKind.KvmUsbC,     true)]
    [InlineData(CommandKind.KvmUpstream, true)]
    [InlineData(CommandKind.PbpOn,       false)]
    [InlineData(CommandKind.PbpOff,      false)]
    [InlineData(CommandKind.KvmAuto,     false)]
    public void IsAvailable_ReflectsProtocolMdKnowledge(CommandKind command, bool expected)
    {
        Assert.Equal(expected, Command.IsAvailable(command));
    }

    // -------------------------------------------------------------------------
    // Data-driven identity — stable actionIds (docs/SETTINGS.md §3.6) + labels.
    // These ids are a public contract with the config; renaming one orphans a
    // user's binding, so pin them down exactly.
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData(CommandKind.InputTypeC,  "inputTypeC")]
    [InlineData(CommandKind.InputDp,     "inputDP")]
    [InlineData(CommandKind.KvmUsbC,     "kvmUSBC")]
    [InlineData(CommandKind.KvmUpstream, "kvmUpstream")]
    [InlineData(CommandKind.KvmAuto,     "kvmAuto")]
    [InlineData(CommandKind.PbpOn,       "pbpOn")]
    [InlineData(CommandKind.PbpOff,      "pbpOff")]
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
    [InlineData(CommandKind.InputTypeC,  "Input → Type-C")]
    [InlineData(CommandKind.InputDp,     "Input → DP")]
    [InlineData(CommandKind.KvmUsbC,     "KVM → USB-C")]
    [InlineData(CommandKind.KvmUpstream, "KVM → Upstream")]
    [InlineData(CommandKind.KvmAuto,     "KVM → Auto")]
    [InlineData(CommandKind.PbpOn,       "PBP On")]
    [InlineData(CommandKind.PbpOff,      "PBP Off")]
    public void Label_IsBritishEnglishAndStable(CommandKind command, string expected)
    {
        Assert.Equal(expected, Command.Label(command));
    }
}
