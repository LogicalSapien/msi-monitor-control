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
    /// <summary>
    /// The command is an app-only action (e.g. <see cref="CommandKind.ShowLauncher"/>) with no HID
    /// payload — it must not be sent to the monitor. Returned (never thrown) as a defence-in-depth
    /// guard at the device boundary; the dispatcher already routes such commands elsewhere.
    /// </summary>
    NotAMonitorCommand,
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
    /// Returns <see cref="MsiResult.NotAMonitorCommand"/> for an app-only command (no HID payload),
    /// <see cref="MsiResult.DeviceNotFound"/> when the monitor is not connected, or
    /// <see cref="MsiResult.SendFailed"/> on I/O error. Never throws.
    /// </summary>
    public MsiResult Send(CommandKind command)
    {
        // Defence-in-depth at the HID boundary: an app-only command (e.g. ShowLauncher) has no
        // payload and must never reach Command.PayloadFor (which would throw). The dispatcher
        // already routes these elsewhere; this guard means a direct/future Send() call is safe too.
        if (!Command.IsMonitorCommand(command))
        {
            DebugLog.Warn($"Send {command}: not a monitor command (app-only) — ignored.");
            return MsiResult.NotAMonitorCommand;
        }

        if (_device is null)
        {
            DebugLog.Warn($"Send {command}: monitor not found (device not connected).");
            return MsiResult.DeviceNotFound;
        }

        // All v0.2.2 monitor commands have hardware-confirmed payloads. This catch is a defensive
        // backstop: if a future monitor command is added without a payload (PayloadFor throws),
        // fail safely with a diagnostic rather than crashing or sending invented bytes.
        byte[] payload;
        try
        {
            payload = Command.PayloadFor(command);
        }
        catch (Exception ex) when (ex is NotImplementedException or InvalidOperationException)
        {
            DebugLog.Warn($"Send {command}: no payload available — not sent ({ex.GetType().Name}).");
            return MsiResult.SendFailed;
        }

        return WriteReport(payload, command.ToString());
    }

    /// <summary>
    /// Sets which physical input feeds a PBP/PIP window (v0.2.2). A parameterised operation
    /// rather than a fixed <see cref="CommandKind"/>: <paramref name="window"/> selects the
    /// feature code (sub 0x36 0x31 / main 0x36 0x32) and <paramref name="input"/> selects the
    /// byte[10] value. <b>Main-window is UNVERIFIED on hardware</b> — surfaced as such in the UI.
    /// </summary>
    public MsiResult SetPbpSource(Command.PbpWindow window, Command.PbpInput input)
    {
        if (_device is null)
        {
            DebugLog.Warn($"SetPbpSource {window}←{input}: monitor not found (device not connected).");
            return MsiResult.DeviceNotFound;
        }

        var payload = Command.PbpSourcePayload(window, input);
        var note = window == Command.PbpWindow.Main ? " [main: UNVERIFIED]" : "";
        return WriteReport(payload, $"PBP source {window}←{Command.Label(input)}{note}");
    }

    /// <summary>
    /// Opens the device and writes a single HID Output report, with logging. Shared by
    /// <see cref="Send"/> and <see cref="SetPbpSource"/>. Caller must have checked connectivity.
    /// </summary>
    private MsiResult WriteReport(byte[] payload, string label)
    {
        try
        {
            // Per docs/PROTOCOL.md §HID interface: report type is Output.
            // HidSharp's HidStream.Write() sends an Output report — correct here.
            using var stream = _device!.Open();
            // Don't block indefinitely if the device stalls or stops responding.
            stream.WriteTimeout = 1000; // milliseconds
            stream.Write(payload);
            DebugLog.Info($"Send {label}: OK ({payload.Length}-byte HID Output report).");
            return MsiResult.Success;
        }
        catch (Exception ex)
        {
            DebugLog.Exception($"Send {label}: HID write FAILED", ex);
            return MsiResult.SendFailed;
        }
    }
}
