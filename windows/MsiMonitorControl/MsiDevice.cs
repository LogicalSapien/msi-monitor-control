using HidSharp;

namespace MsiMonitorControl;

/// <summary>
/// Result returned by <see cref="MsiDevice.Send"/>.
/// </summary>
public enum MsiResult
{
    Success,
    DeviceNotFound,
    SendFailed,
}

/// <summary>
/// Sends HID Output reports to an MSI MD342CQP monitor via HidSharp.
/// VID/PID and report type are sourced from docs/PROTOCOL.md.
/// </summary>
public sealed class MsiDevice
{
    // Sourced verbatim from docs/PROTOCOL.md §Device (VID/PID).
    private const int VendorId  = 0x1462; // MSI (Micro-Star International)
    private const int ProductId = 0x3FA4; // MD342CQP — tested

    private HidDevice? _device;

    public MsiDevice()
    {
        Refresh();
    }

    /// <summary>
    /// True if the monitor HID device is currently visible on the USB bus.
    /// </summary>
    public bool IsConnected => _device is not null;

    /// <summary>
    /// Re-queries the HID device list. Call after a USB reconnect event.
    /// </summary>
    public void Refresh()
    {
        bool wasConnected = _device is not null;
        _device = DeviceList.Local
            .GetHidDevices(VendorId, ProductId)
            .FirstOrDefault();

        bool nowConnected = _device is not null;
        if (nowConnected != wasConnected)
            DebugLog.Info(nowConnected
                ? $"Monitor connected (VID=0x{VendorId:X4} PID=0x{ProductId:X4})."
                : "Monitor disconnected.");
        else
            DebugLog.Info($"Device refresh — {(nowConnected ? "connected" : "not found")}.");
    }

    /// <summary>
    /// Sends <paramref name="command"/> to the monitor as an HID Output report.
    /// Returns <see cref="MsiResult.DeviceNotFound"/> when the monitor is not connected.
    /// Returns <see cref="MsiResult.SendFailed"/> on unknown payload or I/O error.
    /// </summary>
    public MsiResult Send(CommandKind command)
    {
        if (_device is null)
        {
            DebugLog.Warn($"Send {command}: monitor not found (device not connected).");
            return MsiResult.DeviceNotFound;
        }

        byte[] payload;
        try
        {
            payload = Command.PayloadFor(command);
        }
        catch (NotImplementedException)
        {
            // Payload not yet known (PBP — see docs/PROTOCOL.md §"What is NOT known").
            // Return SendFailed so the tray app can show a diagnostic rather than silently
            // doing nothing. Do NOT invent bytes.
            DebugLog.Warn($"Send {command}: payload UNKNOWN (not reverse-engineered) — not sent.");
            return MsiResult.SendFailed;
        }

        try
        {
            // Per docs/PROTOCOL.md §HID interface: report type is Output.
            // HidSharp's HidStream.Write() sends an Output report — correct here.
            using var stream = _device.Open();
            // Don't block indefinitely if the device stalls or stops responding.
            stream.WriteTimeout = 1000; // milliseconds
            stream.Write(payload);
            DebugLog.Info($"Send {command}: OK ({payload.Length}-byte HID Output report).");
            return MsiResult.Success;
        }
        catch (Exception ex)
        {
            DebugLog.Exception($"Send {command}: HID write FAILED", ex);
            return MsiResult.SendFailed;
        }
    }
}
