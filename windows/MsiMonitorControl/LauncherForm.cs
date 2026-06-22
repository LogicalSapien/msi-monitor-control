using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// The quick-launcher palette (v0.2.2): a centred, top-most floating window showing a grid of
/// every monitor command, grouped (Inputs / KVM / Modes). Open it with the <c>showLauncher</c>
/// hotkey (default Ctrl+Alt+Shift+Space). Click a button — or focus it with Tab and press
/// Space/Enter — to run that command and close; Esc closes without running.
///
/// Each button shows the command label plus its current hotkey chord (derived from the config).
/// This is an app-only surface: it dispatches through the same command handler as the tray menu,
/// so a launched command records last-sent + ticks the menu like any other.
/// </summary>
internal sealed class LauncherForm : Form
{
    private readonly Action<CommandKind> _run;

    private static readonly (string Heading, CommandKind[] Commands)[] Groups =
    {
        ("Inputs", new[] { CommandKind.InputHdmi1, CommandKind.InputHdmi2, CommandKind.InputTypeC, CommandKind.InputDp }),
        ("KVM",    new[] { CommandKind.KvmUsbC, CommandKind.KvmUpstream, CommandKind.KvmAuto }),
        ("Modes",  new[] { CommandKind.PbpOff, CommandKind.PbpPip, CommandKind.PbpOn }),
    };

    /// <param name="config">Current config — for the per-button chord display.</param>
    /// <param name="run">Dispatches the chosen command (same path as the tray menu).</param>
    /// <param name="isConnected">Whether the monitor is connected (buttons grey out when not).</param>
    /// <param name="lastSent">
    /// The last-sent command in each group (input / KVM / PBP mode) — its button gets a ✓. These
    /// are "last sent by this app", not a true device state (the monitor can't report state).
    /// </param>
    public LauncherForm(HotkeyConfig config, Action<CommandKind> run, bool isConnected, IReadOnlySet<CommandKind> lastSent)
    {
        _run = run;

        Text            = "MSI Monitor Control";
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        StartPosition   = FormStartPosition.CenterScreen;
        TopMost         = true;
        ShowInTaskbar   = false;
        MinimizeBox     = false;
        MaximizeBox     = false;
        KeyPreview      = true; // so Esc closes regardless of focus
        AutoScaleMode   = AutoScaleMode.Dpi;

        var layout = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = Groups.Length,
            RowCount    = 2, // headings row + buttons row
            Padding     = new Padding(12),
            AutoSize    = true,
        };
        Controls.Add(layout);

        int tab = 0;
        for (int col = 0; col < Groups.Length; col++)
        {
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            var (heading, commands) = Groups[col];

            layout.Controls.Add(new Label
            {
                Text      = heading,
                AutoSize  = true,
                Font      = new Font(Font, FontStyle.Bold),
                Margin    = new Padding(6, 0, 6, 4),
            }, col, 0);

            var stack = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
            foreach (var command in commands)
            {
                // Buttons are enabled only when the monitor is connected (a launcher action sends
                // HID); the action's own availability is always true for the 10 monitor commands.
                var enabled = isConnected && Command.IsAvailable(command);
                var chord   = config.PrimaryDisplay(Command.ActionId(command));
                var tick    = lastSent.Contains(command) ? "✓ " : "    ";
                var label   = Command.Label(command);
                var btn = new Button
                {
                    Text      = chord.Length > 0 ? $"{tick}{label}   ({chord})" : $"{tick}{label}",
                    AutoSize   = true,
                    Width      = 250,
                    Height     = 32,
                    Margin     = new Padding(6, 2, 6, 2),
                    Enabled    = enabled,
                    TabStop    = enabled,
                    TabIndex   = tab++,
                    TextAlign  = ContentAlignment.MiddleLeft,
                };
                if (enabled)
                {
                    var captured = command;
                    btn.Click += (_, _) => RunAndClose(captured);
                }
                stack.Controls.Add(btn);
            }
            layout.Controls.Add(stack, col, 1);
        }

        ClientSize = layout.PreferredSize;
    }

    /// <summary>Runs the chosen command then closes the launcher.</summary>
    private void RunAndClose(CommandKind command)
    {
        Close();
        _run(command);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape)
        {
            e.Handled = true;
            Close();
            return;
        }
        base.OnKeyDown(e);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        Activate(); // bring to front + focus the first button so Tab/Space/Enter work immediately
        if (Controls.Count > 0) SelectNextControl(null, forward: true, tabStopOnly: true, nested: true, wrap: true);
    }
}
