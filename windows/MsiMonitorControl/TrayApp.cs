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
            Icon    = SystemIcons.Application,
            Visible = true,
        };

        _trayIcon.ContextMenuStrip = BuildMenu();

        _hotKeys = new HotKeys(OnCommand);

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

        menu.Items.Add(MakeItem("PBP On",         CommandKind.PbpOn));
        menu.Items.Add(MakeItem("PBP Off",         CommandKind.PbpOff));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(MakeItem("KVM → USB-C",    CommandKind.KvmUsbC));
        menu.Items.Add(MakeItem("KVM → Upstream", CommandKind.KvmUpstream));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(MakeItem("Input → Type-C", CommandKind.InputTypeC));
        menu.Items.Add(MakeItem("Input → DP",     CommandKind.InputDp));
        menu.Items.Add(new ToolStripSeparator());

        var exitItem = new ToolStripMenuItem("Exit");
        exitItem.Click += (_, _) => ExitApp();
        menu.Items.Add(exitItem);

        return menu;
    }

    private ToolStripMenuItem MakeItem(string label, CommandKind command)
    {
        var available = Command.IsAvailable(command);
        var item = new ToolStripMenuItem(label)
        {
            Enabled = available,
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
        _hotKeys.Dispose();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        Application.Exit();
    }
}
