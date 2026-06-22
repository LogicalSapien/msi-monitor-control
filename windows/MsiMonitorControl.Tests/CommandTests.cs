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

    // -------------------------------------------------------------------------
    // Enum shape
    // -------------------------------------------------------------------------

    [Fact]
    public void AllSixCommandsExist()
    {
        Assert.Equal(6, Command.AllCases.Count);
    }

    [Fact]
    public void AllCasesCoversAllSixKinds()
    {
        var expected = new[]
        {
            CommandKind.PbpOn,
            CommandKind.PbpOff,
            CommandKind.KvmUsbC,
            CommandKind.KvmUpstream,
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
    // UNKNOWN payloads — must throw, never invent bytes
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData(CommandKind.PbpOn)]
    [InlineData(CommandKind.PbpOff)]
    [InlineData(CommandKind.KvmUsbC)]
    [InlineData(CommandKind.KvmUpstream)]
    public void PayloadFor_ThrowsNotImplemented_ForUnknownPayloads(CommandKind command)
    {
        // Payloads for PBP and KVM are UNKNOWN — see docs/PROTOCOL.md §"What is NOT known".
        // The correct behaviour is to throw rather than send invented bytes to the monitor.
        Assert.Throws<NotImplementedException>(() => Command.PayloadFor(command));
    }

    // -------------------------------------------------------------------------
    // IsAvailable
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData(CommandKind.InputTypeC, true)]
    [InlineData(CommandKind.InputDp,    true)]
    [InlineData(CommandKind.PbpOn,      false)]
    [InlineData(CommandKind.PbpOff,     false)]
    [InlineData(CommandKind.KvmUsbC,    false)]
    [InlineData(CommandKind.KvmUpstream, false)]
    public void IsAvailable_ReflectsProtocolMdKnowledge(CommandKind command, bool expected)
    {
        Assert.Equal(expected, Command.IsAvailable(command));
    }
}
