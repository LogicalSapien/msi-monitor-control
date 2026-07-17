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
    public void ToWireReport_PrependsReportId_KeepingTheWholeFrameAsData()
    {
        // Windows' HID stack consumes buffer[0] as the report ID, so the PROTOCOL.md frame —
        // including its own leading 0x01 — must sit AFTER a prepended report-ID byte. Without
        // the prepend the frame arrives shifted one byte left and the monitor silently ignores
        // it (the v0.2.5 "Send OK but nothing switches" bug).
        var frame = Command.PayloadFor(CommandKind.InputTypeC);
        var wire = MsiDevice.ToWireReport(frame);

        Assert.Equal(frame.Length + 1, wire.Length);
        Assert.Equal(0x01, wire[0]);                  // prepended report ID
        Assert.Equal(frame, wire.Skip(1).ToArray()); // frame intact, still starting 0x01 0x35
        Assert.Equal(0x01, wire[1]);
        Assert.Equal(0x35, wire[2]);
    }
}
