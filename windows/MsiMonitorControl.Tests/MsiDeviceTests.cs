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
    [InlineData(CommandKind.PbpOn)]
    [InlineData(CommandKind.PbpOff)]
    [InlineData(CommandKind.KvmUsbC)]
    [InlineData(CommandKind.KvmUpstream)]
    [InlineData(CommandKind.InputTypeC)]
    [InlineData(CommandKind.InputDp)]
    public void Send_ReturnsDeviceNotFound_WhenNoMonitorAttached(CommandKind command)
    {
        var device = new MsiDevice();
        // In CI (windows-latest) no MD342CQP is attached, so no device matches VID/PID.
        // Send short-circuits on the null device before PayloadFor is reached, so commands
        // with UNKNOWN payloads (PBP On/Off) still return DeviceNotFound here — the throwing
        // path itself is covered by CommandTests.PayloadFor_ThrowsNotImplemented_ForUnknownPayloads.
        var result = device.Send(command);
        Assert.Equal(MsiResult.DeviceNotFound, result);
    }
}
