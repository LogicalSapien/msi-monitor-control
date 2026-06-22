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
///
/// <para>
/// <b>v0.2.4 re-detect:</b> the monitor's USB HID interface is routed away from the host
/// during a KVM switch, so the cached <see cref="HidDevice"/> becomes stale.
/// <see cref="Refresh"/> re-enumerates synchronously and fires <see cref="ConnectionChanged"/>
/// when the state changes. <see cref="TrayApp"/> calls <see cref="Refresh"/> on a 5-second
/// timer so the tray menu un-greys automatically when the KVM routes the monitor back.
/// On any HID write failure, <see cref="WriteReport"/> refreshes + retries once (mirrors the
/// macOS reopen-on-stale-handle fix).
/// </para>
/// </summary>
public sealed class MsiDevice
{
    // Sourced verbatim from docs/PROTOCOL.md §Device (VID/PID).
    private const int VendorId  = 0x1462; // MSI (Micro-Star International)
    private const int ProductId = 0x3FA4; // MD342CQP — tested

    private HidDevice? _device;

    /// <summary>
    /// Raised (on the caller's thread) when the connection state changes — i.e. the monitor
    /// appeared or disappeared. The bool argument is <c>true</c> when connected, false when gone.
    /// <see cref="TrayApp"/> subscribes to this to rebuild the menu live.
    /// </summary>
    public event Action<bool>? ConnectionChanged;

    public MsiDevice()
    {
        Refresh();
    }

    /// <summary>
    /// True if the monitor HID device is currently visible on the USB bus (as of the last
    /// <see cref="Refresh"/> call or failed send that triggered an auto-refresh).
    /// </summary>
    public bool IsConnected => _device is not null;

    /// <summary>
    /// Re-queries the HID device list and updates <see cref="IsConnected"/>. Fires
    /// <see cref="ConnectionChanged"/> when the state changes. Safe to call from any thread,
    /// but must be marshalled to the UI thread before touching any WinForms state.
    /// </summary>
    public void Refresh()
    {
        bool wasConnected = _device is not null;
        _device = DeviceList.Local
            .GetHidDevices(VendorId, ProductId)
            .FirstOrDefault();

        bool nowConnected = _device is not null;
        // Log + notify only on a real transition — Refresh() runs every 5s, so logging
        // the unchanged state would flood debug.log.
        if (nowConnected != wasConnected)
        {
            DebugLog.Info(nowConnected
                ? $"Monitor connected (VID=0x{VendorId:X4} PID=0x{ProductId:X4})."
                : "Monitor disconnected.");
            ConnectionChanged?.Invoke(nowConnected);
        }
    }

    /// <summary>
    /// Sends <paramref name="command"/> to the monitor as an HID Output report.
    /// Returns <see cref="MsiResult.NotAMonitorCommand"/> for an app-only command (no HID payload),
    /// <see cref="MsiResult.DeviceNotFound"/> when the monitor is not connected (after a re-check),
    /// or <see cref="MsiResult.SendFailed"/> on I/O error. Never throws.
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
            // v0.2.4: try a re-enumerate before giving up — the device may have reconnected since
            // the last periodic refresh (e.g. KVM just switched back).
            DebugLog.Info($"Send {command}: device null — re-enumerating before send.");
            Refresh();
            if (_device is null)
            {
                DebugLog.Warn($"Send {command}: monitor not found after re-enumerate.");
                return MsiResult.DeviceNotFound;
            }
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
            DebugLog.Info($"SetPbpSource {window}←{input}: device null — re-enumerating.");
            Refresh();
            if (_device is null)
            {
                DebugLog.Warn($"SetPbpSource {window}←{input}: monitor not found after re-enumerate.");
                return MsiResult.DeviceNotFound;
            }
        }

        var payload = Command.PbpSourcePayload(window, input);
        var note = window == Command.PbpWindow.Main ? " [main: UNVERIFIED]" : "";
        return WriteReport(payload, $"PBP source {window}←{Command.Label(input)}{note}");
    }

    /// <summary>
    /// Opens the device and writes a single HID Output report, with logging. Shared by
    /// <see cref="Send"/> and <see cref="SetPbpSource"/>. On first failure, re-enumerates and
    /// retries once — handles the KVM-stale-handle case (v0.2.4, mirrors macOS reopen fix).
    /// </summary>
    private MsiResult WriteReport(byte[] payload, string label)
    {
        if (TryWrite(payload, label, out var result))
            return result;

        // First write failed — the HidDevice object may be stale (KVM switched USB away).
        // Re-enumerate and try once more before giving up.
        DebugLog.Info($"Send {label}: first write failed — re-enumerating and retrying.");
        Refresh();
        if (_device is null)
        {
            DebugLog.Warn($"Send {label}: monitor gone after re-enumerate — cannot retry.");
            return MsiResult.DeviceNotFound;
        }

        TryWrite(payload, label, out var retryResult);
        return retryResult;
    }

    /// <summary>
    /// Attempts one HID Output report write. Returns true and sets <paramref name="result"/> to
    /// <see cref="MsiResult.Success"/> on success; returns false and sets it to
    /// <see cref="MsiResult.SendFailed"/> on any exception.
    /// </summary>
    private bool TryWrite(byte[] payload, string label, out MsiResult result)
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
            result = MsiResult.Success;
            return true;
        }
        catch (Exception ex)
        {
            DebugLog.Exception($"Send {label}: HID write failed", ex);
            result = MsiResult.SendFailed;
            return false;
        }
    }
}
