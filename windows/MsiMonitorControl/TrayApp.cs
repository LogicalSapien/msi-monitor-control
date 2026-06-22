using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// System-tray application shell. Hosts a <see cref="NotifyIcon"/> with a context menu for
/// all monitor actions, wires up Win32 global hotkeys via <see cref="HotKeys"/>, and exposes a
/// settings window for rebinding hotkeys and toggling launch-at-login (docs/SETTINGS.md §8(b)).
///
/// Hotkeys and menu shortcuts are driven by a loaded <see cref="HotkeyConfig"/> rather than a
/// static table. Actions with UNKNOWN payloads (PBP On/Off and KVM Auto — see PROTOCOL.md)
/// appear greyed out and are excluded from hotkey registration until their payloads are
/// confirmed via hardware reverse-engineering. Input switching and KVM USB-C/Upstream have
/// confirmed payloads and are live.
/// </summary>
internal sealed class TrayApp : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private readonly MsiDevice _device;
    private readonly HotKeys _hotKeys;
    private HotkeyConfig _config;

    public TrayApp()
    {
        _device = new MsiDevice();

        // Load (or create) the shared config, then reconcile launch-at-login (config wins).
        _config = HotkeyConfig.Load();
        LaunchAtLogin.Reconcile(_config);

        _trayIcon = new NotifyIcon
        {
            Text    = "MSI Monitor Control",
            Icon    = LoadAppIcon(),
            Visible = true,
        };

        _trayIcon.ContextMenuStrip = BuildMenu();

        _hotKeys = new HotKeys(OnCommand, _config);
        WarnOnFailedChords();

        DebugLog.Info($"Tray ready (config preset={_config.Preset}, monitor {(_device.IsConnected ? "connected" : "not found")}).");

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

        menu.Items.Add(MakeItem(CommandKind.PbpOn));
        menu.Items.Add(MakeItem(CommandKind.PbpOff));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(MakeItem(CommandKind.KvmUsbC));
        menu.Items.Add(MakeItem(CommandKind.KvmUpstream));
        menu.Items.Add(MakeItem(CommandKind.KvmAuto));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(MakeItem(CommandKind.InputTypeC));
        menu.Items.Add(MakeItem(CommandKind.InputDp));
        menu.Items.Add(new ToolStripSeparator());

        var settingsItem = new ToolStripMenuItem("Settings…");
        settingsItem.Click += (_, _) => OpenSettings();
        menu.Items.Add(settingsItem);

        var logItem = new ToolStripMenuItem("Reveal debug log");
        logItem.Click += (_, _) => DebugLog.OpenLogFolder();
        menu.Items.Add(logItem);

        var exitItem = new ToolStripMenuItem("Exit");
        exitItem.Click += (_, _) => ExitApp();
        menu.Items.Add(exitItem);

        return menu;
    }

    private ToolStripMenuItem MakeItem(CommandKind command)
    {
        var available = Command.IsAvailable(command);
        var shortcut  = _config.PrimaryDisplay(Command.ActionId(command));
        var item = new ToolStripMenuItem(Command.Label(command))
        {
            Enabled = available,
            // Shows the global hotkey right-aligned, derived from the config (e.g.
            // "Input → DP   Ctrl+Alt+Shift+D"). Display-only — actual binding is in HotKeys.
            ShowShortcutKeys = shortcut.Length > 0,
            ShortcutKeyDisplayString = shortcut.Length > 0 ? shortcut : null,
            ToolTipText = available
                ? null
                : "Payload unknown — see docs/PROTOCOL.md for reverse-engineering steps",
        };
        if (available)
            item.Click += (_, _) => OnCommand(command);
        return item;
    }

    /// <summary>
    /// Opens the settings window modally. On Save: persist the config, live-re-register the
    /// hotkeys, reconcile launch-at-login, and rebuild the menu so the derived shortcuts update.
    /// </summary>
    private void OpenSettings()
    {
        using var form = new SettingsForm(_config);
        if (form.ShowDialog() != DialogResult.OK)
            return;

        var updated = form.Result;

        // Register FIRST, persist only on success (docs/SETTINGS.md §3.5/§5). If the OS rejects
        // any new chord, HotKeys rolls back to the previously-applied config so the user keeps
        // their working hotkeys — and we must NOT write the rejected config to disk.
        if (!_hotKeys.TryReRegister(updated))
        {
            DebugLog.Warn($"Settings: re-register rejected (conflicts: {string.Join(", ", _hotKeys.FailedChords)}) — kept previous config, not saved.");
            WarnOnFailedChords(); // names the rejected chord(s); previous bindings stay live
            return;
        }

        // Registration succeeded — the file is now the source of truth, so persist it.
        try
        {
            updated.Save();
            DebugLog.Info($"Settings saved (preset={updated.Preset}, launchAtLogin={updated.LaunchAtLogin}).");
        }
        catch (Exception ex)
        {
            // Persist failed but the new hotkeys are live and match the in-memory config; the
            // file is simply stale. Surface it; keep the live state (reverting registration to a
            // config we couldn't save would be worse).
            DebugLog.Exception("Settings: applied but save FAILED", ex);
            ShowBalloon($"Settings applied but could not be saved: {ex.Message}", ToolTipIcon.Warning);
        }

        // Launch-at-login: write/delete the Run value; on failure revert the bool + warn.
        if (updated.LaunchAtLogin != LaunchAtLogin.IsEnabled())
        {
            if (!LaunchAtLogin.SetEnabled(updated.LaunchAtLogin))
            {
                updated.LaunchAtLogin = LaunchAtLogin.IsEnabled();
                try { updated.Save(); } catch { /* best-effort revert persist */ }
                ShowBalloon("Could not change the launch-at-login setting.", ToolTipIcon.Warning);
            }
        }

        _config = updated;

        var oldMenu = _trayIcon.ContextMenuStrip;
        _trayIcon.ContextMenuStrip = BuildMenu();
        oldMenu?.Dispose(); // non-blocking #1: dispose the replaced menu (no handle leak)
    }

    /// <summary>
    /// If any hotkey could not be bound (e.g. already owned by another app / OS-reserved), tell
    /// the user rather than letting that chord fail silently.
    /// </summary>
    private void WarnOnFailedChords()
    {
        if (_hotKeys.FailedChords.Count > 0)
        {
            ShowBalloon(
                $"Some shortcuts could not be registered: {string.Join(", ", _hotKeys.FailedChords)}. "
                    + "Another app may already use them.",
                ToolTipIcon.Warning);
        }
    }

    private void OnCommand(CommandKind command)
    {
        DebugLog.Info($"Command invoked: {command} ({Command.Label(command)}).");
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
    /// <c>&lt;ApplicationIcon&gt;</c>) so the tray shows the brand mark rather than a generic
    /// icon — which also helps the unsigned build look less like malware. Falls back to the
    /// system application icon if extraction fails.
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
        DebugLog.SessionEnd("user quit");
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
