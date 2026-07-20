using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// The in-app help window (v0.2.3, task #35). Opens from the tray menu ("Help…") or from
/// the Settings form ("Help…" button). Contains four sections:
/// <list type="bullet">
/// <item>(a) Hotkey cheat-sheet — from the live config, shows rebindable chords.</item>
/// <item>(b) Feature quick-start — brief walkthrough of all features.</item>
/// <item>(c) Troubleshooting — monitor not detected, SmartScreen, KVM notes, debug log.</item>
/// <item>(d) About/Links — version, GitHub, MIT licence, supported monitor.</item>
/// </list>
/// Content is structured to match the macOS SwiftUI Help view so both platforms read consistently.
/// </summary>
internal sealed class HelpForm : Form
{
    private const string GithubUrl = "https://github.com/LogicalSapien/msi-monitor-control";

    private readonly HotkeyConfig _config;

    public HelpForm(HotkeyConfig config)
    {
        _config = config;

        Text            = "MSI Monitor Control — Help";
        FormBorderStyle = FormBorderStyle.Sizable;
        StartPosition   = FormStartPosition.CenterScreen;
        MinimizeBox     = true;
        MaximizeBox     = true;
        ShowInTaskbar   = true;
        ClientSize      = new Size(560, 500);
        MinimumSize     = new Size(460, 400);

        var tabs = new TabControl { Dock = DockStyle.Fill };

        tabs.TabPages.Add(BuildCheatSheetTab());
        tabs.TabPages.Add(BuildQuickStartTab());
        tabs.TabPages.Add(BuildTroubleshootingTab());
        tabs.TabPages.Add(BuildAboutTab());

        Controls.Add(tabs);
    }

    // -------------------------------------------------------------------------
    // (a) Hotkey cheat-sheet — from the live config
    // -------------------------------------------------------------------------

    private TabPage BuildCheatSheetTab()
    {
        var page = new TabPage("Hotkey Cheat-Sheet");

        var rtb = new RichTextBox
        {
            Dock      = DockStyle.Fill,
            ReadOnly  = true,
            BackColor = SystemColors.Window,
            BorderStyle = BorderStyle.None,
            Font      = new Font("Segoe UI", 9.5f),
            ScrollBars = RichTextBoxScrollBars.Vertical,
        };

        var sb = new System.Text.StringBuilder();
        sb.AppendLine("Hotkeys are rebindable in Settings. All use Ctrl+Alt+Shift by default.");
        sb.AppendLine();

        // Group commands by category.
        AppendCheatSheetGroup(sb, "Inputs",
            CommandKind.InputHdmi1, CommandKind.InputHdmi2,
            CommandKind.InputTypeC, CommandKind.InputDp);

        AppendCheatSheetGroup(sb, "KVM",
            CommandKind.KvmUsbC, CommandKind.KvmUpstream, CommandKind.KvmAuto);

        AppendCheatSheetGroup(sb, "PBP / PIP Mode",
            CommandKind.PbpOff, CommandKind.PbpPip, CommandKind.PbpOn);

        AppendCheatSheetGroup(sb, "App",
            CommandKind.ShowLauncher);

        sb.AppendLine();
        sb.AppendLine("To rebind: open Settings → click the chord button for any action.");

        rtb.Text = sb.ToString();
        page.Controls.Add(rtb);
        return page;
    }

    private void AppendCheatSheetGroup(System.Text.StringBuilder sb, string heading, params CommandKind[] kinds)
    {
        sb.AppendLine($"── {heading} ──");
        foreach (var kind in kinds)
        {
            var actionId = Command.ActionId(kind);
            var label    = Command.Label(kind);
            var chord    = _config.PrimaryDisplay(actionId);
            var chordStr = chord.Length > 0 ? chord : "(no shortcut)";
            sb.AppendLine($"  {label,-38} {chordStr}");
        }
        sb.AppendLine();
    }

    // -------------------------------------------------------------------------
    // (b) Feature quick-start
    // -------------------------------------------------------------------------

    private static TabPage BuildQuickStartTab()
    {
        var page = new TabPage("Quick Start");
        page.Controls.Add(MakeRtb(
@"MSI Monitor Control — Feature Quick Start
─────────────────────────────────────────

INPUT SWITCHING
  Switch the monitor's active input source with a hotkey.
  Supported inputs: HDMI 1, HDMI 2, DisplayPort, Type-C.
  Default chords: Ctrl+Alt+Shift + H / J / D / C.

KVM SWITCHING
  Route USB peripherals (keyboard, mouse, etc.) to a different host.
  Three modes: USB-C, Upstream, Auto.
  Default chords: Ctrl+Alt+Shift + K / U / A.

PBP / PIP MODES
  Picture-by-Picture (PBP) splits the screen side-by-side.
  Picture-in-Picture (PIP) shows a small overlay window.
  Default chords: Ctrl+Alt+Shift + O (off) / I (PIP) / P (PBP).

EDGE-SWITCH KVM (opt-in — Settings → Edge-Switch KVM)
  When PBP is active, automatically switches the KVM as the cursor
  crosses the centre divider. Works for Type-C and DisplayPort sources.
  HDMI sources are not auto-switched (ambiguous port mapping).
  Enable the toggle in Settings; no special permissions needed on Windows.

QUICK LAUNCHER (Ctrl+Alt+Shift+Space)
  Opens a floating grid of all monitor commands. Click or press
  Tab/Space/Enter to activate; Esc closes.

SOURCE SELECT (PBP)
  In Settings → Picture-by-Picture, choose which input feeds each
  PBP window. Sub-window is hardware-confirmed; main-window is marked
  '(unverified)' until confirmed on hardware.

REBINDING HOTKEYS
  Open Settings → click any chord button → press the new chord.
  Use 'Set shortcut' to add a chord to an action that has none.
  Duplicate chords are blocked; OS-reserved chords are reported.

LAUNCH AT LOGIN
  Tick 'Launch at login' in Settings to start automatically on sign-in.
  Untick to disable.
"));
        return page;
    }

    // -------------------------------------------------------------------------
    // (c) Troubleshooting
    // -------------------------------------------------------------------------

    private TabPage BuildTroubleshootingTab()
    {
        var page = new TabPage("Troubleshooting");

        var layout = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 1,
            RowCount    = 2,
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        layout.Controls.Add(MakeRtb(
@"MONITOR NOT DETECTED
  • Ensure the USB-A cable (from the monitor's USB-B upstream port) is
    connected to your PC. The app controls the monitor over USB HID —
    HDMI/DP cables alone are not enough.
  • If the app is running but commands do nothing, try unplugging and
    re-plugging the USB cable. Double-click the tray icon to refresh.
  • Model supported: MSI MD342CQP. Other MSI models may work but are
    unverified.

SMARTSCREEN WARNING ON FIRST LAUNCH
  The app is unsigned (open-source utility). Windows may show a
  'Windows protected your PC' SmartScreen warning.
  Click 'More info' → 'Run anyway' to proceed.
  Source code is at github.com/LogicalSapien/msi-monitor-control.

KVM MAPPING NOTE
  The KVM has two host ports: USB-C and Upstream (USB-B).
  Type-C input → USB-C KVM port (direct hardware pairing).
  DisplayPort input → Upstream KVM port (best-effort assumption).
  HDMI inputs do not auto-switch KVM (ambiguous — no fixed pairing).

INPUT SWITCHING DOES NOTHING (KVM AND PBP WORK)
  The monitor's firmware only honours INPUT-SWITCH commands that arrive
  over its USB-C upstream. If this PC is connected via the USB-B
  upstream (typical for HDMI/DisplayPort + USB-A cable setups), KVM and
  PBP/PIP commands work but input switching is silently ignored.
  Fix: connect this PC to the monitor's USB-C port (hardware-verified
  on the MD342CQP).

EDGE-SWITCH NOT WORKING
  • Confirm PBP mode is active (set via the app, not the OSD buttons).
    Edge-switch only tracks PBP state set through the app — OSD changes
    are not detected.
  • Confirm the toggle is enabled in Settings → Edge-Switch KVM.
  • Check that the monitor is showing as 3440×1440 in Windows display
    settings (native resolution required for display detection).

DEBUG LOG
  The app writes a session log to:
    %APPDATA%\LogicalSapien\MSIMonitorControl\debug.log
  Use 'Reveal debug log' from the tray menu to open the folder.
  Include the log when reporting issues.

REPORTING ISSUES
  Please report bugs and feature requests via GitHub Issues:
"), 0, 0);

        var linkPanel = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(6, 0, 6, 6) };
        var link = new LinkLabel { Text = GithubUrl + "/issues", AutoSize = true };
        link.LinkClicked += (_, _) => OpenUrl(GithubUrl + "/issues");
        linkPanel.Controls.Add(link);
        layout.Controls.Add(linkPanel, 0, 1);

        page.Controls.Add(layout);
        return page;
    }

    // -------------------------------------------------------------------------
    // (d) About / Links
    // -------------------------------------------------------------------------

    private static TabPage BuildAboutTab()
    {
        var page = new TabPage("About");

        var version = Assembly.GetExecutingAssembly()
                              .GetName().Version?.ToString(3) ?? "0.2.3";

        var layout = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 1,
            RowCount    = 3,
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        layout.Controls.Add(MakeRtb(
$@"MSI Monitor Control v{version}
© LogicalSapien — MIT Licence

A dual-platform (macOS + Windows) utility for controlling the MSI MD342CQP
34-inch ultrawide monitor over raw USB HID. Not an official MSI product.

Supported monitor: MSI MD342CQP (3440×1440).
Other MSI models may work but are unverified.

Protocol note: this app reverse-engineered HID payloads from the MD342CQP.
Bytes are never invented — unknown payloads are flagged rather than guessed.
See docs/PROTOCOL.md in the source repository for full details.

Licence: MIT (free to use, modify, and distribute with attribution).
"), 0, 0);

        var linkPanel = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(6, 0, 6, 0) };
        var repoLink = new LinkLabel { Text = "GitHub repository: " + GithubUrl, AutoSize = true };
        repoLink.LinkClicked += (_, _) => OpenUrl(GithubUrl);
        linkPanel.Controls.Add(repoLink);
        layout.Controls.Add(linkPanel, 0, 1);

        var issuePanel = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(6, 0, 6, 6) };
        var issueLink = new LinkLabel { Text = "Report an issue: " + GithubUrl + "/issues", AutoSize = true };
        issueLink.LinkClicked += (_, _) => OpenUrl(GithubUrl + "/issues");
        issuePanel.Controls.Add(issueLink);
        layout.Controls.Add(issuePanel, 0, 2);

        page.Controls.Add(layout);
        return page;
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// <summary>Creates a read-only, word-wrapped RichTextBox suitable for help content.</summary>
    private static RichTextBox MakeRtb(string text)
    {
        return new RichTextBox
        {
            Dock        = DockStyle.Fill,
            ReadOnly    = true,
            BackColor   = SystemColors.Window,
            BorderStyle = BorderStyle.None,
            Font        = new Font("Segoe UI", 9.5f),
            ScrollBars  = RichTextBoxScrollBars.Vertical,
            Text        = text,
            WordWrap    = true,
        };
    }

    private static void OpenUrl(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            DebugLog.Warn($"HelpForm: could not open URL '{url}': {ex.Message}");
        }
    }
}
