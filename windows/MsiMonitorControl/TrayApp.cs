using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// System-tray application shell. Hosts a <see cref="NotifyIcon"/> with a context
/// menu for all monitor actions and wires up Win32 global hotkeys via <see cref="HotKeys"/>.
///
/// Actions with UNKNOWN payloads (PBP, KVM — see docs/PROTOCOL.md) appear greyed
/// out in the menu and are excluded from hotkey registration until their payloads
/// are confirmed via hardware reverse-engineering.
/// </summary>
internal sealed class TrayApp : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private readonly MsiDevice _device;
    private readonly HotKeys _hotKeys;

    public TrayApp()
    {
        _device = new MsiDevice();

        _trayIcon = new NotifyIcon
        {
            Text    = "MSI Monitor Control",
            Icon    = LoadAppIcon(),
            Visible = true,
        };

        _trayIcon.ContextMenuStrip = BuildMenu();

        _hotKeys = new HotKeys(OnCommand);

        // If any hotkey could not be bound (e.g. already owned by another app), tell the
        // user on startup rather than letting that chord fail silently.
        if (_hotKeys.FailedChords.Count > 0)
        {
            ShowBalloon(
                $"Some shortcuts could not be registered: {string.Join(", ", _hotKeys.FailedChords)}. "
                    + "Another app may already use them.",
                ToolTipIcon.Warning);
        }

        // Refresh device list on tray icon double-click.
        _trayIcon.DoubleClick += (_, _) =>
        {
            _device.Refresh();
            UpdateConnectedState();
        };
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();

        menu.Items.Add(MakeItem("PBP On",         CommandKind.PbpOn,     "Ctrl+Alt+P"));
        menu.Items.Add(MakeItem("PBP Off",         CommandKind.PbpOff,    "Ctrl+Alt+O"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(MakeItem("KVM → USB-C",    CommandKind.KvmUsbC,   "Ctrl+Alt+U"));
        menu.Items.Add(MakeItem("KVM → Upstream", CommandKind.KvmUpstream, "Ctrl+Alt+K"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(MakeItem("Input → Type-C", CommandKind.InputTypeC, "Ctrl+Alt+T"));
        menu.Items.Add(MakeItem("Input → DP",     CommandKind.InputDp,    "Ctrl+Alt+D"));
        menu.Items.Add(new ToolStripSeparator());

        var exitItem = new ToolStripMenuItem("Exit");
        exitItem.Click += (_, _) => ExitApp();
        menu.Items.Add(exitItem);

        return menu;
    }

    private ToolStripMenuItem MakeItem(string label, CommandKind command, string shortcut)
    {
        var available = Command.IsAvailable(command);
        var item = new ToolStripMenuItem(label)
        {
            Enabled = available,
            // Shows the global hotkey right-aligned in grey, e.g. "Input → DP   Ctrl+Alt+D".
            // This is display-only — the actual binding is done by HotKeys.
            ShowShortcutKeys = true,
            ShortcutKeyDisplayString = shortcut,
            ToolTipText = available
                ? null
                : "Payload unknown — see docs/PROTOCOL.md for reverse-engineering steps",
        };
        if (available)
            item.Click += (_, _) => OnCommand(command);
        return item;
    }

    private void OnCommand(CommandKind command)
    {
        var result = _device.Send(command);
        if (result == MsiResult.DeviceNotFound)
        {
            ShowBalloon("Monitor not found. Is the USB cable connected?", ToolTipIcon.Warning);
        }
        else if (result == MsiResult.SendFailed)
        {
            ShowBalloon("Failed to send command to monitor.", ToolTipIcon.Error);
        }
        // On success: silent — no notification is the expected behaviour.
    }

    /// <summary>
    /// Returns the application's own icon (the custom logo embedded via the csproj
    /// <c>&lt;ApplicationIcon&gt;</c>) so the tray shows the brand mark rather than a
    /// generic icon — which also helps the unsigned build look less like malware.
    /// Falls back to the system application icon if extraction fails.
    /// </summary>
    private static Icon LoadAppIcon()
    {
        try
        {
            var exePath = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(exePath))
            {
                var icon = Icon.ExtractAssociatedIcon(exePath);
                if (icon is not null)
                    return icon;
            }
        }
        catch
        {
            // Fall through to the system icon below.
        }
        return SystemIcons.Application;
    }

    private void ShowBalloon(string message, ToolTipIcon icon)
    {
        _trayIcon.BalloonTipTitle = "MSI Monitor Control";
        _trayIcon.BalloonTipText  = message;
        _trayIcon.BalloonTipIcon  = icon;
        _trayIcon.ShowBalloonTip(3000);
    }

    private void UpdateConnectedState()
    {
        _trayIcon.Text = _device.IsConnected
            ? "MSI Monitor Control — Connected"
            : "MSI Monitor Control — Not connected";
    }

    private void ExitApp()
    {
        // ExitThread disposes this ApplicationContext, which routes through
        // Dispose(bool) below for cleanup.
        ExitThread();
    }

    private bool _disposed;

    protected override void Dispose(bool disposing)
    {
        if (disposing && !_disposed)
        {
            _disposed = true;
            // Ensures cleanup happens even if Application.Run returns by another path,
            // not only via the Exit menu item.
            _hotKeys.Dispose();
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
        }

        base.Dispose(disposing);
    }
}
