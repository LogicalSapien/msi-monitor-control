using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// A small modal dialog that captures the next key chord the user presses. Used by the
/// settings window's click-to-rebind flow. The dialog reads the modifier state plus the base
/// key from a single <c>KeyDown</c>, builds a <see cref="Chord"/> in the canonical vocabulary,
/// and closes with <see cref="DialogResult.OK"/>. Escape cancels.
///
/// Only the v0.2.0 base-key set (A–Z, 0–9) is accepted; any other key is ignored so the
/// dialog keeps waiting. At least one supported modifier (Ctrl/Alt/Shift) is required — a
/// modifier-less global hotkey is rejected by the conflict rules anyway.
/// </summary>
internal sealed class ChordCaptureDialog : Form
{
    /// <summary>The captured chord, valid only when <see cref="Form.ShowDialog()"/> returns OK.</summary>
    public Chord? Captured { get; private set; }

    private readonly Label _prompt;

    public ChordCaptureDialog(string actionLabel)
    {
        Text            = "Press a shortcut";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition   = FormStartPosition.CenterParent;
        MinimizeBox     = false;
        MaximizeBox     = false;
        ShowInTaskbar   = false;
        ClientSize      = new Size(360, 90);
        KeyPreview      = true; // route key events to the form first

        _prompt = new Label
        {
            Text      = $"Press the new shortcut for “{actionLabel}”\n(Ctrl / Alt / Shift + a letter or digit). Esc to cancel.",
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
        };
        Controls.Add(_prompt);

        KeyDown += OnKeyDown;
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape)
        {
            DialogResult = DialogResult.Cancel;
            Close();
            return;
        }

        // Ignore pure-modifier key presses — wait for a base key.
        if (e.KeyCode is Keys.ControlKey or Keys.Menu or Keys.ShiftKey or Keys.LWin or Keys.RWin)
            return;

        if (!TryBaseKey(e.KeyCode, out string key))
            return; // unsupported base key — keep waiting

        var mods = new List<string>();
        if (e.Control) mods.Add(HotkeyConfig.ModControl);
        if (e.Alt)     mods.Add(HotkeyConfig.ModAlt);
        if (e.Shift)   mods.Add(HotkeyConfig.ModShift);

        if (mods.Count == 0)
        {
            // No modifier — not a valid global hotkey. Nudge and keep waiting.
            _prompt.Text = "Include at least one modifier (Ctrl / Alt / Shift). Esc to cancel.";
            e.SuppressKeyPress = true;
            return;
        }

        Captured = new Chord(HotkeyConfig.SortMods(mods), key);
        e.SuppressKeyPress = true;
        DialogResult = DialogResult.OK;
        Close();
    }

    /// <summary>Maps a <see cref="Keys"/> code to a single A–Z / 0–9 base key, or false.</summary>
    private static bool TryBaseKey(Keys code, out string key)
    {
        key = "";
        // Letters: Keys.A..Keys.Z map to ASCII 'A'..'Z'.
        if (code >= Keys.A && code <= Keys.Z)
        {
            key = ((char)code).ToString();
            return true;
        }
        // Top-row digits Keys.D0..Keys.D9.
        if (code >= Keys.D0 && code <= Keys.D9)
        {
            key = ((char)('0' + (code - Keys.D0))).ToString();
            return true;
        }
        // Numeric keypad digits.
        if (code >= Keys.NumPad0 && code <= Keys.NumPad9)
        {
            key = ((char)('0' + (code - Keys.NumPad0))).ToString();
            return true;
        }
        return false;
    }
}
