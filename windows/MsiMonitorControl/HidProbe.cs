using System.Runtime.InteropServices;
using HidSharp;
using Microsoft.Win32.SafeHandles;

namespace MsiMonitorControl;

/// <summary>
/// Field diagnostic (v0.2.7): the monitor silently ignores commands sent from Windows even
/// though every write succeeds (v0.2.5 bare frame AND v0.2.6 report-ID-prefixed frame), while
/// the identical frame works from macOS. This probe gathers the evidence needed to pin down
/// the working Windows wire format in ONE session on the real MD342CQP:
///
///   1. Dumps every matching HID device's path, report-length caps and RAW report descriptor
///      to debug.log — the descriptor is ground truth for how reports must be framed.
///   2. Tries each plausible transport/framing variant in turn, using PBP→PIP as the test
///      signal (visible on screen, but does not switch the input away or move the KVM).
///      The user confirms per variant whether PIP appeared; the answer is logged.
///
/// Temporary tooling — remove (and bake the confirmed variant into MsiDevice) once the
/// working format is known.
/// </summary>
internal static class HidProbe
{
    // Same device identity as MsiDevice (docs/PROTOCOL.md §Device).
    private const int VendorId  = 0x1462;
    private const int ProductId = 0x3FA4;

    public static void Run()
    {
        DebugLog.Info("HidProbe: === starting send-path probe ===");

        var devices = DeviceList.Local.GetHidDevices(VendorId, ProductId).ToList();
        if (devices.Count == 0)
        {
            DebugLog.Warn("HidProbe: no matching HID device — is the monitor's USB routed here?");
            MessageBox.Show("No matching HID device found — is the monitor's USB routed to this machine?",
                "MSI HID probe", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        DebugLog.Info($"HidProbe: {devices.Count} matching HID device(s).");
        foreach (var d in devices)
            DumpDevice(d);

        // Probe against the same device the app uses (first match — mirrors MsiDevice.Refresh).
        var device = devices[0];
        var pipOn  = Command.PayloadFor(CommandKind.PbpPip);
        var pbpOff = Command.PayloadFor(CommandKind.PbpOff);

        var intro = MessageBox.Show(
            "This probe sends the PBP→Picture-in-Picture command using six different HID wire " +
            "formats, one at a time.\n\n" +
            "Watch the monitor: after each attempt you'll be asked whether PIP appeared. " +
            "It is switched back off between attempts. Your input and the KVM are not touched.\n\n" +
            "Results are written to debug.log. Continue?",
            "MSI HID probe", MessageBoxButtons.OKCancel, MessageBoxIcon.Information);
        if (intro != DialogResult.OK)
        {
            DebugLog.Info("HidProbe: cancelled before any send.");
            return;
        }

        var variants = new (string Label, Action<HidDevice, byte[]> Send)[]
        {
            ("A — WriteFile, 0x01 prepended (v0.2.6 behaviour)",        (d, f) => StreamWrite(d, Prefix(0x01, f))),
            ("B — WriteFile, bare frame (v0.2.5 behaviour)",           (d, f) => StreamWrite(d, f)),
            ("C — WriteFile, 0x00 prepended (unnumbered descriptor)",  (d, f) => StreamWrite(d, Prefix(0x00, f))),
            ("D — HidD_SetOutputReport, 0x01 prepended",               (d, f) => SetOutputReport(d, Prefix(0x01, f))),
            ("E — HidD_SetOutputReport, 0x00 prepended",               (d, f) => SetOutputReport(d, Prefix(0x00, f))),
            ("F — HidD_SetFeature, 0x01 prepended",                    (d, f) => SetFeature(d, Prefix(0x01, f))),
        };

        foreach (var (label, send) in variants)
        {
            DebugLog.Info($"HidProbe: variant {label} — sending PBP→PIP.");
            var error = TrySend(send, device, pipOn);
            if (error is not null)
            {
                DebugLog.Warn($"HidProbe: variant {label} failed to send: {error}");
                var carryOn = MessageBox.Show(
                    $"Variant {label} failed to send:\n{error}\n\nContinue with the next variant?",
                    "MSI HID probe", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (carryOn == DialogResult.No) break;
                continue;
            }

            var answer = MessageBox.Show(
                $"Variant {label} sent.\n\nDid Picture-in-Picture appear on the monitor?\n\n" +
                "Yes = it worked · No = try the next variant · Cancel = abort the probe",
                "MSI HID probe", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            DebugLog.Info($"HidProbe: variant {label} — user reports PIP appeared = {answer}.");

            // Switch PIP back off via the same variant regardless of the answer (harmless no-op
            // if PIP never actually appeared).
            var offError = TrySend(send, device, pbpOff);
            if (offError is not null)
                DebugLog.Warn($"HidProbe: variant {label} — PBP-off send failed: {offError}");

            if (answer == DialogResult.Yes)
            {
                DebugLog.Info($"HidProbe: === WORKING VARIANT: {label} ===");
                MessageBox.Show(
                    $"Variant {label} works — recorded in debug.log.\n\nPBP has been switched back off. " +
                    "Please send the debug log to the developer.",
                    "MSI HID probe", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (answer == DialogResult.Cancel) break;
        }

        DebugLog.Info("HidProbe: === probe finished — no working variant confirmed ===");
        MessageBox.Show(
            "Probe finished — no variant visibly worked. Please send debug.log to the developer; " +
            "the report-descriptor dump it now contains is the next clue.",
            "MSI HID probe", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    // -------------------------------------------------------------------------
    // Evidence dump
    // -------------------------------------------------------------------------

    private static void DumpDevice(HidDevice d)
    {
        try { DebugLog.Info($"HidProbe: device path = {d.DevicePath}"); }
        catch (Exception ex) { DebugLog.Warn($"HidProbe: device path unavailable: {ex.Message}"); }

        try
        {
            DebugLog.Info(
                $"HidProbe: report lengths (bytes, incl. report-ID byte) — " +
                $"input={d.GetMaxInputReportLength()} output={d.GetMaxOutputReportLength()} " +
                $"feature={d.GetMaxFeatureReportLength()}");
        }
        catch (Exception ex) { DebugLog.Warn($"HidProbe: report lengths unavailable: {ex.Message}"); }

        try
        {
            var desc = d.GetRawReportDescriptor();
            DebugLog.Info($"HidProbe: raw report descriptor ({desc.Length} bytes): {Convert.ToHexString(desc)}");
        }
        catch (Exception ex) { DebugLog.Warn($"HidProbe: report descriptor unavailable: {ex.Message}"); }
    }

    // -------------------------------------------------------------------------
    // Send variants
    // -------------------------------------------------------------------------

    private static byte[] Prefix(byte reportId, byte[] frame)
    {
        var buffer = new byte[frame.Length + 1];
        buffer[0] = reportId;
        Array.Copy(frame, 0, buffer, 1, frame.Length);
        return buffer;
    }

    /// <summary>Runs one send, returning null on success or the failure text (never throws).</summary>
    private static string? TrySend(Action<HidDevice, byte[]> send, HidDevice device, byte[] buffer)
    {
        try
        {
            send(device, buffer);
            return null;
        }
        catch (Exception ex)
        {
            return $"{ex.GetType().Name}: {ex.Message}";
        }
    }

    /// <summary>The app's normal transport: HidSharp HidStream.Write (WriteFile under the hood).</summary>
    private static void StreamWrite(HidDevice device, byte[] buffer)
    {
        using var stream = device.Open();
        stream.WriteTimeout = 1000;
        stream.Write(buffer);
        DebugLog.Info($"HidProbe: WriteFile OK ({buffer.Length} bytes handed to HidSharp, first byte 0x{buffer[0]:X2}).");
    }

    /// <summary>Control-pipe SET_REPORT(Output) via hid.dll — bypasses the interrupt-OUT path.</summary>
    private static void SetOutputReport(HidDevice device, byte[] buffer)
    {
        var padded = PadTo(buffer, device.GetMaxOutputReportLength(), "output");
        using var handle = OpenRaw(device);
        if (!HidD_SetOutputReport(handle, padded, (uint)padded.Length))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        DebugLog.Info($"HidProbe: HidD_SetOutputReport OK ({padded.Length} bytes, first byte 0x{padded[0]:X2}).");
    }

    /// <summary>Feature-report transport via HidSharp (HidD_SetFeature under the hood).</summary>
    private static void SetFeature(HidDevice device, byte[] buffer)
    {
        var padded = PadTo(buffer, device.GetMaxFeatureReportLength(), "feature");
        using var stream = device.Open();
        stream.SetFeature(padded);
        DebugLog.Info($"HidProbe: HidD_SetFeature OK ({padded.Length} bytes, first byte 0x{padded[0]:X2}).");
    }

    private static byte[] PadTo(byte[] buffer, int reportLength, string kind)
    {
        if (reportLength <= 0)
            throw new InvalidOperationException($"device reports no {kind} reports (caps length {reportLength})");
        if (buffer.Length >= reportLength)
            return buffer;
        var padded = new byte[reportLength];
        Array.Copy(buffer, padded, buffer.Length);
        return padded;
    }

    private static SafeFileHandle OpenRaw(HidDevice device)
    {
        const uint GENERIC_READ    = 0x80000000;
        const uint GENERIC_WRITE   = 0x40000000;
        const uint FILE_SHARE_READ  = 0x1;
        const uint FILE_SHARE_WRITE = 0x2;
        const uint OPEN_EXISTING    = 3;

        var handle = CreateFileW(device.DevicePath,
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (handle.IsInvalid)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return handle;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFileW(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes,
        uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("hid.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.U1)]
    private static extern bool HidD_SetOutputReport(SafeFileHandle hidDeviceObject, byte[] report, uint reportBufferLength);
}
