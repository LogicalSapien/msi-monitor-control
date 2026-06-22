using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// The settings window (docs/SETTINGS.md §8(b).4) — the Windows counterpart of the macOS
/// SwiftUI settings surface. Provides:
/// <list type="bullet">
/// <item>a preset dropdown (Default / Ctrl+Shift / Legacy / Custom);</item>
/// <item>one row per available action with its current chord(s), click-to-rebind, and
///   add/remove for extra hotkeys;</item>
/// <item>inline conflict (duplicate / OS-reserved) and AltGr advisory surfacing;</item>
/// <item>a launch-at-login checkbox.</item>
/// </list>
///
/// The form edits a working copy of the <see cref="HotkeyConfig"/>. On Save it commits the
/// copy back to the caller, which persists it, live-re-registers the hotkeys, and reconciles
/// launch-at-login. Cancel discards. v0.2.2: a "Picture-by-Picture" section drives PBP/PIP mode
/// + per-window source-select (live device sends, not config edits; main-window unverified).
/// All actions are available (hardware-confirmed payloads).
/// </summary>
internal sealed class SettingsForm : Form
{
    private readonly HotkeyConfig _config; // working copy
    private readonly ComboBox _presetBox;
    private readonly CheckBox _launchAtLogin;
    private readonly FlowLayoutPanel _rows;
    private readonly Label _advisory;

    // v0.2.2 live actions — invoked immediately (these are device sends, not config edits).
    private readonly Action<CommandKind> _sendCommand;                          // PBP mode buttons
    private readonly Action<Command.PbpWindow, Command.PbpInput> _setPbpSource; // PBP source dropdowns

    /// <summary>The committed config — valid only when <see cref="Form.ShowDialog()"/> returns OK.</summary>
    public HotkeyConfig Result => _config;

    private static readonly (HotkeyPreset Preset, string Label)[] PresetChoices =
    {
        (HotkeyPreset.CmdShiftCtrl, "Default (Ctrl+Alt+Shift)"),
        (HotkeyPreset.CtrlShift,    "Ctrl+Shift"),
        (HotkeyPreset.Legacy,       "Legacy (Ctrl+Alt)"),
        (HotkeyPreset.Custom,       "Custom"),
    };

    public SettingsForm(HotkeyConfig config,
                        Action<CommandKind> sendCommand,
                        Action<Command.PbpWindow, Command.PbpInput> setPbpSource)
    {
        // Deep-copy so Cancel truly discards. A round-trip through the model is the simplest
        // faithful clone and reuses the same (sanitising) load path.
        _config = CloneConfig(config);
        _sendCommand = sendCommand;
        _setPbpSource = setPbpSource;

        Text            = "MSI Monitor Control — Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition   = FormStartPosition.CenterScreen;
        MinimizeBox     = false;
        MaximizeBox     = false;
        ShowInTaskbar   = true;
        ClientSize      = new Size(460, 520);

        var layout = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 1,
            RowCount    = 6,
            Padding     = new Padding(12),
        };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));   // preset
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); // hotkey rows
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));   // advisory
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));   // PBP/PIP section
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));   // launch
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));   // buttons
        Controls.Add(layout);

        // -- Preset row ------------------------------------------------------
        var presetPanel = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        presetPanel.Controls.Add(new Label { Text = "Scheme:", AutoSize = true, TextAlign = ContentAlignment.MiddleLeft, Margin = new Padding(0, 6, 6, 0) });
        _presetBox = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
        foreach (var (_, label) in PresetChoices) _presetBox.Items.Add(label);
        _presetBox.SelectedIndex = IndexOfPreset(_config.Preset);
        _presetBox.SelectedIndexChanged += OnPresetChanged;
        presetPanel.Controls.Add(_presetBox);
        layout.Controls.Add(presetPanel, 0, 0);

        // -- Action rows -----------------------------------------------------
        _rows = new FlowLayoutPanel
        {
            Dock          = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents  = false,
            AutoScroll    = true,
        };
        layout.Controls.Add(_rows, 0, 1);
        RebuildRows();

        // -- Advisory --------------------------------------------------------
        _advisory = new Label { AutoSize = true, ForeColor = Color.DarkGoldenrod, MaximumSize = new Size(430, 0) };
        layout.Controls.Add(_advisory, 0, 2);

        // -- Picture-by-Picture section (v0.2.2) -----------------------------
        layout.Controls.Add(BuildPbpSection(), 0, 3);

        // -- Launch-at-login -------------------------------------------------
        _launchAtLogin = new CheckBox { Text = "Launch at login", AutoSize = true, Checked = _config.LaunchAtLogin };
        layout.Controls.Add(_launchAtLogin, 0, 4);

        // -- Buttons ---------------------------------------------------------
        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft, Dock = DockStyle.Fill };
        var save   = new Button { Text = "Save",   DialogResult = DialogResult.OK,     AutoSize = true };
        var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, AutoSize = true };
        save.Click += (_, _) => { _config.LaunchAtLogin = _launchAtLogin.Checked; };
        buttons.Controls.Add(save);
        buttons.Controls.Add(cancel);
        layout.Controls.Add(buttons, 0, 5);

        AcceptButton = save;
        CancelButton = cancel;
    }

    private static int IndexOfPreset(HotkeyPreset preset)
    {
        for (int i = 0; i < PresetChoices.Length; i++)
            if (PresetChoices[i].Preset == preset) return i;
        return 0;
    }

    private void OnPresetChanged(object? sender, EventArgs e)
    {
        var chosen = PresetChoices[_presetBox.SelectedIndex].Preset;
        if (chosen == HotkeyPreset.Custom) return; // not directly applicable
        _config.ApplyPreset(chosen);
        RebuildRows();
        RefreshAdvisory();
    }

    /// <summary>
    /// The "Picture-by-Picture" section (v0.2.2): a mode picker (Off / PIP / PBP) plus two
    /// source-select dropdowns (sub-window + main-window). Main-window is flagged "(unverified)"
    /// — its feature code (0x36 0x32) is not confirmed on hardware. These are LIVE device sends
    /// (not config edits): selecting a mode/source dispatches immediately via the callbacks.
    /// </summary>
    private Control BuildPbpSection()
    {
        var group = new GroupBox
        {
            Text     = "Picture-by-Picture",
            AutoSize = true,
            Dock     = DockStyle.Fill,
            Padding  = new Padding(8),
        };

        var grid = new TableLayoutPanel
        {
            AutoSize    = true,
            ColumnCount = 2,
            Dock        = DockStyle.Fill,
        };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        group.Controls.Add(grid);

        // Mode picker (Off / PIP / PBP) — sends the corresponding mode command immediately.
        grid.Controls.Add(new Label { Text = "Mode:", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 6, 8, 0) }, 0, 0);
        var modeBox = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240, Anchor = AnchorStyles.Left };
        var modes = new (string Label, CommandKind Cmd)[]
        {
            ("Off",                  CommandKind.PbpOff),
            ("Picture-in-Picture",   CommandKind.PbpPip),
            ("Picture-by-Picture",   CommandKind.PbpOn),
        };
        foreach (var (label, _) in modes) modeBox.Items.Add(label);
        modeBox.SelectedIndexChanged += (_, _) =>
        {
            if (modeBox.SelectedIndex >= 0) _sendCommand(modes[modeBox.SelectedIndex].Cmd);
        };
        grid.Controls.Add(modeBox, 1, 0);

        // Sub-window source (verified).
        grid.Controls.Add(new Label { Text = "Sub-window source:", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 6, 8, 0) }, 0, 1);
        grid.Controls.Add(BuildSourceCombo(Command.PbpWindow.Sub), 1, 1);

        // Main-window source (UNVERIFIED — feature 0x36 0x32 not hardware-confirmed).
        grid.Controls.Add(new Label { Text = "Main-window source (unverified):", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 6, 8, 0) }, 0, 2);
        grid.Controls.Add(BuildSourceCombo(Command.PbpWindow.Main), 1, 2);

        return group;
    }

    private ComboBox BuildSourceCombo(Command.PbpWindow window)
    {
        var box = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240, Anchor = AnchorStyles.Left };
        var inputs = new[] { Command.PbpInput.Hdmi1, Command.PbpInput.Hdmi2, Command.PbpInput.Dp, Command.PbpInput.TypeC };
        foreach (var input in inputs) box.Items.Add(Command.Label(input));
        if (window == Command.PbpWindow.Main)
            box.AccessibleDescription = "Unverified on hardware";
        box.SelectedIndexChanged += (_, _) =>
        {
            if (box.SelectedIndex >= 0) _setPbpSource(window, inputs[box.SelectedIndex]);
        };
        return box;
    }

    /// <summary>Rebuilds the per-action rows from the working config. Only available actions appear.</summary>
    private void RebuildRows()
    {
        _rows.SuspendLayout();

        // Dispose the controls we're about to discard (and their children) so re-rendering the
        // rows on every edit doesn't leak window handles.
        var old = _rows.Controls.Cast<Control>().ToList();
        _rows.Controls.Clear();
        foreach (var c in old) c.Dispose();

        foreach (var kind in Command.AllCases)
        {
            if (!Command.IsAvailable(kind)) continue;
            var actionId = Command.ActionId(kind);
            if (!_config.Bindings.TryGetValue(actionId, out var chords))
            {
                chords = new List<Chord>();
                _config.Bindings[actionId] = chords;
            }

            _rows.Controls.Add(BuildActionRow(kind, actionId, chords));
        }

        _rows.ResumeLayout();
    }

    // Fixed label-column width so the chord controls line up in a tidy column across every row
    // (the macOS bug was the chip wrapping below the label; this keeps label + chords on ONE row
    // with a stable column boundary regardless of label length).
    private const int LabelColumnWidth = 200;
    private const int RowHeight = 30;

    private Control BuildActionRow(CommandKind kind, string actionId, List<Chord> chords)
    {
        // Row = [fixed-width label] [chords flow…] on a single line, vertically centred.
        var panel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents  = false,
            AutoSize      = true,
            Height        = RowHeight,
            Margin        = new Padding(0, 0, 0, 4),
        };

        panel.Controls.Add(new Label
        {
            Text         = Command.Label(kind),
            Width        = LabelColumnWidth,
            Height       = RowHeight,
            TextAlign    = ContentAlignment.MiddleLeft,
            AutoEllipsis = true,             // long labels truncate rather than push the column
            Margin       = new Padding(0, 0, 8, 0),
        });

        // One "chord button" per bound chord — click to rebind that slot; plus a remove (×).
        for (int i = 0; i < chords.Count; i++)
        {
            int slot = i;
            var display = HotkeyConfig.DisplayString(chords[i]);

            var rebind = new Button { Text = display, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 2, 2, 2) };
            rebind.Click += (_, _) => Rebind(actionId, slot);
            panel.Controls.Add(rebind);

            var remove = new Button { Text = "×", Width = 24, Anchor = AnchorStyles.Left, Margin = new Padding(0, 2, 8, 2) };
            remove.Click += (_, _) => RemoveChord(actionId, slot);
            panel.Controls.Add(remove);
        }

        var add = new Button { Text = chords.Count == 0 ? "Set shortcut" : "+ Add", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 2, 0, 2) };
        add.Click += (_, _) => Rebind(actionId, -1);
        panel.Controls.Add(add);

        return panel;
    }

    /// <summary>
    /// Captures a new chord for an action. <paramref name="slot"/> = -1 adds a new chord;
    /// otherwise it replaces the chord at that index. Validation (§3.5) runs before commit:
    /// duplicate is BLOCKING (rejected with a message); AltGr is a non-blocking advisory.
    /// </summary>
    private void Rebind(string actionId, int slot)
    {
        using var dialog = new ChordCaptureDialog(Command.Label(Command.KindForActionId(actionId)!.Value));
        if (dialog.ShowDialog(this) != DialogResult.OK || dialog.Captured is null)
            return;

        var chord = dialog.Captured;
        var validation = _config.ValidateChord(actionId, chord, excludeChordIndex: slot);

        if (!validation.IsValid)
        {
            var clashKind = Command.KindForActionId(validation.DuplicateActionId!);
            var clashLabel = clashKind is null ? validation.DuplicateActionId : Command.Label(clashKind.Value);
            MessageBox.Show(this,
                $"{HotkeyConfig.DisplayString(chord)} is already assigned to “{clashLabel}”. "
                    + "Choose a different shortcut.",
                "Shortcut already in use", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var chords = _config.Bindings[actionId];
        if (slot >= 0 && slot < chords.Count)
            chords[slot] = chord;
        else
            chords.Add(chord);

        // Any hand-edit may move us off the named preset → re-derive the label.
        _config.Preset = _config.DerivePreset();
        _presetBox.SelectedIndexChanged -= OnPresetChanged;
        _presetBox.SelectedIndex = IndexOfPreset(_config.Preset);
        _presetBox.SelectedIndexChanged += OnPresetChanged;

        RebuildRows();
        RefreshAdvisory();
    }

    private void RemoveChord(string actionId, int slot)
    {
        var chords = _config.Bindings[actionId];
        if (slot >= 0 && slot < chords.Count)
            chords.RemoveAt(slot);

        _config.Preset = _config.DerivePreset();
        _presetBox.SelectedIndexChanged -= OnPresetChanged;
        _presetBox.SelectedIndex = IndexOfPreset(_config.Preset);
        _presetBox.SelectedIndexChanged += OnPresetChanged;

        RebuildRows();
        RefreshAdvisory();
    }

    /// <summary>Surfaces a non-blocking AltGr advisory listing any at-risk chords (§3.5).</summary>
    private void RefreshAdvisory()
    {
        var risky = new List<string>();
        foreach (var (actionId, chords) in _config.Bindings)
        {
            foreach (var chord in chords)
                if (_config.IsAltGrRisk(chord))
                    risky.Add(HotkeyConfig.DisplayString(chord));
        }

        _advisory.Text = risky.Count == 0
            ? ""
            : "Note: " + string.Join(", ", risky)
              + " may clash with an AltGr character on some EU keyboard layouts. You can still use it.";
    }

    /// <summary>Deep-clones a config via a serialise/parse round-trip (faithful, sanitising).</summary>
    private static HotkeyConfig CloneConfig(HotkeyConfig source)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(source, CloneOptions);
        return HotkeyConfig.Parse(json, overwriteOnRepair: false, repaired: out _);
    }

    private static readonly System.Text.Json.JsonSerializerOptions CloneOptions = new()
    {
        Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter(System.Text.Json.JsonNamingPolicy.CamelCase) },
    };

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        RefreshAdvisory();
    }
}
