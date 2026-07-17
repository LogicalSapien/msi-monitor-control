using MsiMonitorControl;
using Xunit;

namespace MsiMonitorControl.Tests;

/// <summary>
/// Tests for <see cref="MsiDevice"/> that run in CI without a physical monitor attached.
/// </summary>
public class MsiDeviceTests
{
    [Fact]
    public void IsConnected_ReturnsFalse_WhenNoMonitorAttached()
    {
        // In CI (windows-latest runner) no MSI monitor is present.
        // MsiDevice must report not connected rather than throwing.
        var device = new MsiDevice();
        Assert.False(device.IsConnected);
    }

    [Theory]
    [InlineData(CommandKind.InputHdmi1)]
    [InlineData(CommandKind.InputHdmi2)]
    [InlineData(CommandKind.InputTypeC)]
    [InlineData(CommandKind.InputDp)]
    [InlineData(CommandKind.KvmUsbC)]
    [InlineData(CommandKind.KvmUpstream)]
    [InlineData(CommandKind.KvmAuto)]
    [InlineData(CommandKind.PbpOff)]
    [InlineData(CommandKind.PbpPip)]
    [InlineData(CommandKind.PbpOn)]
    public void Send_ReturnsDeviceNotFound_WhenNoMonitorAttached(CommandKind command)
    {
        var device = new MsiDevice();
        // In CI (windows-latest) no MD342CQP is attached, so no device matches VID/PID. Send
        // short-circuits on the null device → DeviceNotFound. All v0.2.2 monitor commands have
        // real payloads now, so none throw on the way (the payloads themselves are pinned by
        // CommandTests).
        var result = device.Send(command);
        Assert.Equal(MsiResult.DeviceNotFound, result);
    }

    [Fact]
    public void Send_ShowLauncher_ReturnsNotAMonitorCommand_NeverThrows()
    {
        // Defence-in-depth at the HID boundary: ShowLauncher is app-only (no HID payload). Send
        // must return NotAMonitorCommand WITHOUT throwing — and BEFORE any device/connectivity or
        // PayloadFor (which would throw for ShowLauncher). Holds regardless of monitor presence.
        var device = new MsiDevice();
        var result = device.Send(CommandKind.ShowLauncher);
        Assert.Equal(MsiResult.NotAMonitorCommand, result);
    }

    [Fact]
    public void SetPbpSource_ReturnsDeviceNotFound_WhenNoMonitorAttached()
    {
        // The parameterised PBP source-select must also short-circuit safely with no monitor.
        var device = new MsiDevice();
        var result = device.SetPbpSource(Command.PbpWindow.Sub, Command.PbpInput.Hdmi1);
        Assert.Equal(MsiResult.DeviceNotFound, result);
    }

    [Fact]
    public void EveryMonitorFrame_BeginsWithTheReportIdByte()
    {
        // The frame is written to HidSharp AS-IS: its first byte doubles as the report ID the
        // Windows HID stack consumes (hardware-confirmed via HidProbe 2026-07-17, variant B —
        // the device descriptor declares numbered reports, ID 1). Every monitor command's
        // payload must therefore begin 0x01 or the write would target the wrong report.
        foreach (CommandKind kind in Enum.GetValues<CommandKind>())
        {
            if (!Command.IsMonitorCommand(kind)) continue;
            Assert.Equal(0x01, Command.PayloadFor(kind)[0]);
        }
    }
}
