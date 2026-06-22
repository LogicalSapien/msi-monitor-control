using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// Pure, stateful divider-crossing logic for the PBP edge-switch KVM feature (v0.2.3, §5).
/// Separated from <see cref="EdgeSwitchTracker"/> so it can be unit-tested without a message
/// pump, Win32 hook, or real display. All operations are NOT thread-safe — call only from the
/// UI thread (or a test that owns the object exclusively).
/// </summary>
internal sealed class EdgeSwitchLogic
{
    private enum Side { Unknown, Left, Right }
    private Side _currentSide = Side.Unknown;
    private long _lastSwitchTick;

    private readonly int _deadZone;
    private readonly int _dwellMs;

    // Seam for tests: override Environment.TickCount64 with a fake clock.
    private Func<long>? _tickSource;
    internal void SetTickSource(Func<long> src) => _tickSource = src;
    private long Now => _tickSource?.Invoke() ?? Environment.TickCount64;

    /// <param name="deadZone">Dead-zone half-width in pixels (default: <see cref="EdgeSwitchTracker.DeadZonePixels"/>).</param>
    /// <param name="dwellMs">Minimum dwell time in ms (default: <see cref="EdgeSwitchTracker.DwellMs"/>).</param>
    public EdgeSwitchLogic(int deadZone = EdgeSwitchTracker.DeadZonePixels,
                           int dwellMs  = EdgeSwitchTracker.DwellMs)
    {
        _deadZone = deadZone;
        _dwellMs  = dwellMs;
    }

    /// <summary>Resets side state (call when PBP activates to avoid stale side).</summary>
    public void Reset() => _currentSide = Side.Unknown;

    /// <summary>
    /// Processes a cursor x-coordinate relative to the display divider.
    /// Returns the KVM command to send if a crossing is detected, or null if nothing should happen.
    /// </summary>
    /// <param name="cursorX">Cursor x in virtual-screen coordinates.</param>
    /// <param name="dividerX">The centre-divider x of the MSI display.</param>
    /// <param name="mainSource">Input shown in the right/main PBP window.</param>
    /// <param name="subSource">Input shown in the left/sub PBP window.</param>
    public CommandKind? Evaluate(int cursorX, int dividerX,
        Command.PbpInput mainSource, Command.PbpInput subSource)
    {
        // Determine which side, with dead-zone suppression (§5.1).
        Side newSide;
        if      (cursorX < dividerX - _deadZone) newSide = Side.Left;
        else if (cursorX > dividerX + _deadZone) newSide = Side.Right;
        else return null; // inside dead zone — no change

        if (newSide == _currentSide) return null; // same side — no event

        // First-time initialisation: set side without firing a switch.
        if (_currentSide == Side.Unknown)
        {
            _currentSide = newSide;
            return null;
        }

        // Dwell suppression (§5.2): suppress rapid back-and-forth.
        var now = Now;
        if ((now - _lastSwitchTick) < _dwellMs) return null;

        _currentSide   = newSide;
        _lastSwitchTick = now;

        // Map the target window's input to a KVM command (§4.2).
        var targetInput = newSide == Side.Left ? subSource : mainSource;
        return EdgeSwitchTracker.KvmCommandForInput(targetInput);
    }
}

/// <summary>
/// Tracks the cursor position via a low-level mouse hook (<c>WH_MOUSE_LL</c>) and
/// automatically sends a KVM switch command when the user moves the cursor across the
/// centre divider of the MSI MD342CQP in PBP (side-by-side) mode.
///
/// <para>
/// Feature is <b>opt-in, off by default</b> — enabled via <see cref="HotkeyConfig.EdgeSwitchEnabled"/>
/// and active only when PBP mode is on (v0.2.3 design §3). When disabled the hook is not
/// installed (<see cref="TrackerState.Idle"/>); when enabled but PBP is off the hook is
/// installed but the callback exits immediately (<see cref="TrackerState.Standby"/>); only
/// when PBP mode is on does the callback actually compare the cursor to the divider
/// (<see cref="TrackerState.Active"/>).
/// </para>
///
/// <para>
/// Hysteresis (§5): a 48-pixel dead zone suppresses jitter at the boundary; an 800 ms
/// minimum dwell time suppresses rapid back-and-forth. See <see cref="DeadZonePixels"/>
/// and <see cref="DwellMs"/>.
/// </para>
///
/// <para>
/// Display identification (§2.2): the MD342CQP is matched by 3440×1440 bounds in
/// <see cref="Screen.AllScreens"/>. If no match is found the tracker stays inactive and
/// logs a diagnostic. Re-scans on <see cref="Microsoft.Win32.SystemEvents.DisplaySettingsChanged"/>.
/// </para>
///
/// <para>
/// <b>Thread safety:</b> the hook proc runs on the WinForms UI thread (the thread that
/// called <see cref="SetEnabled"/>). KVM sends are dispatched via <see cref="Control.BeginInvoke"/>
/// so they go to the UI thread even if the callback fires synchronously on another pump
/// path. Must be constructed, enabled, and disabled on the UI thread.
/// </para>
/// </summary>
internal sealed class EdgeSwitchTracker : IDisposable
{
    // -------------------------------------------------------------------------
    // Hysteresis constants (§5) — not user-configurable in v0.2.3.
    // -------------------------------------------------------------------------

    /// <summary>
    /// Dead zone half-width in physical pixels (§5.1). The cursor must travel at least
    /// this many pixels past the divider on the NEW side before a KVM switch fires.
    /// 48 px ≈ 1.4 % of the 3440 px panel width — wide enough to suppress jitter.
    /// </summary>
    public const int DeadZonePixels = 48;

    /// <summary>
    /// Minimum time between KVM switches in milliseconds (§5.2). After a switch fires,
    /// the next switch is suppressed for this long so a quick reversal does not re-trigger.
    /// </summary>
    public const int DwellMs = 800;

    // -------------------------------------------------------------------------
    // State machine (§3)
    // -------------------------------------------------------------------------

    /// <summary>Operating state of the tracker (§3).</summary>
    public enum TrackerState
    {
        /// <summary>Feature disabled — hook not installed.</summary>
        Idle,
        /// <summary>Feature enabled but PBP mode is off — hook installed, callback exits immediately.</summary>
        Standby,
        /// <summary>Feature enabled and PBP mode is on — divider comparison is live.</summary>
        Active,
    }

    private TrackerState _state = TrackerState.Idle;

    /// <summary>Current operating state of the tracker (read-only; updated by SetEnabled/NotifyPbpMode).</summary>
    public TrackerState State => _state;

    // -------------------------------------------------------------------------
    // Input→KVM mapping (§4.2)
    // -------------------------------------------------------------------------

    /// <summary>
    /// Maps a PBP window input to the KVM command to send when the cursor enters that window.
    /// Returns null for HDMI inputs (no guaranteed KVM pairing — §4.1).
    /// </summary>
    public static CommandKind? KvmCommandForInput(Command.PbpInput input) => input switch
    {
        Command.PbpInput.TypeC => CommandKind.KvmUsbC,      // USB-C input → USB-C KVM port
        Command.PbpInput.Dp    => CommandKind.KvmUpstream,  // DP → Upstream (best-effort)
        Command.PbpInput.Hdmi1 => null,                     // HDMI — ambiguous, no switch
        Command.PbpInput.Hdmi2 => null,                     // HDMI — ambiguous, no switch
        _                      => null,
    };

    // -------------------------------------------------------------------------
    // Win32 WH_MOUSE_LL
    // -------------------------------------------------------------------------

    private const int WH_MOUSE_LL = 14;
    private const int WM_MOUSEMOVE = 0x0200;

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData, flags, time;
        public IntPtr dwExtraInfo;
    }

    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    // Strong reference to the delegate — MUST be a field for the GC lifetime of the hook.
    // A delegate passed to SetWindowsHookEx that is only referenced by unmanaged code is invisible
    // to the GC; if it were a local or a closure captured inline, the GC could collect it and the
    // hook would call into freed memory → crash. Storing it here keeps it rooted for the hook's
    // entire lifetime (until RemoveHook sets it to null, which only happens after UnhookWindowsHookEx).
    private LowLevelMouseProc? _proc;
    private IntPtr _hookHandle = IntPtr.Zero;

    // -------------------------------------------------------------------------
    // Runtime state — read/written on the UI thread only
    // -------------------------------------------------------------------------

    /// <summary>Sources in the two PBP windows (written by TrayApp on each source-select).</summary>
    private Command.PbpInput _mainSource = Command.PbpInput.TypeC;
    private Command.PbpInput _subSource  = Command.PbpInput.Dp;

    private readonly EdgeSwitchLogic _logic = new();

    // Display info — updated by RefreshDisplay().
    private System.Drawing.Rectangle? _msiScreenBounds;
    private int _dividerX;

    /// <summary>The callback to invoke when a KVM switch should be sent (typically TrayApp.OnCommand).</summary>
    private readonly Action<CommandKind> _sendKvm;

    /// <summary>A control on the UI thread used for BeginInvoke.</summary>
    private readonly Control _uiContext;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// <summary>
    /// Initialises the tracker in <see cref="TrackerState.Idle"/> state.
    /// Must be called on the UI (message-pump) thread.
    /// </summary>
    /// <param name="sendKvm">Callback invoked on the UI thread to dispatch a KVM command.</param>
    /// <param name="uiContext">Any live control on the UI thread (used for BeginInvoke).</param>
    public EdgeSwitchTracker(Action<CommandKind> sendKvm, Control uiContext)
    {
        _sendKvm   = sendKvm;
        _uiContext = uiContext;

        RefreshDisplay();

        // Re-scan when the user changes display configuration.
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
    }

    // -------------------------------------------------------------------------
    // Public API — called by TrayApp on the UI thread
    // -------------------------------------------------------------------------

    /// <summary>
    /// Enables or disables the tracker in response to the <see cref="HotkeyConfig.EdgeSwitchEnabled"/>
    /// toggle. When enabled, installs the hook and transitions to Standby or Active depending on
    /// whether PBP mode is currently on. If the hook fails to install, stays Idle (no false
    /// Active/Standby state). When disabled, removes the hook (→ Idle).
    ///
    /// <para>Must be called on the UI (message-pump) thread.</para>
    /// </summary>
    public void SetEnabled(bool enabled, CommandKind? currentPbpMode)
    {
        if (enabled)
        {
            if (_state == TrackerState.Idle)
            {
                InstallHook();
                // Only transition if the hook actually installed — don't lie about state.
                if (_hookHandle == IntPtr.Zero)
                {
                    DebugLog.Warn("EdgeSwitchTracker: hook install failed — staying Idle; edge-switch inactive.");
                    return;
                }
            }

            UpdatePbpMode(currentPbpMode);
        }
        else
        {
            RemoveHook();
            _state = TrackerState.Idle;
            DebugLog.Info("EdgeSwitchTracker: disabled → Idle.");
        }
    }

    /// <summary>
    /// Called by TrayApp after a successful PBP-mode command send so the tracker can transition
    /// between Standby and Active. Has no effect when the tracker is Idle.
    /// </summary>
    public void NotifyPbpMode(CommandKind pbpCommand)
    {
        if (_state == TrackerState.Idle) return;
        UpdatePbpMode(pbpCommand);
    }

    /// <summary>Updates the PBP source configuration so the tracker can map cursor-side → KVM command.</summary>
    public void SetSources(Command.PbpInput mainSource, Command.PbpInput subSource)
    {
        _mainSource = mainSource;
        _subSource  = subSource;
    }

    // -------------------------------------------------------------------------
    // State machine internals
    // -------------------------------------------------------------------------

    private void UpdatePbpMode(CommandKind? pbpCommand)
    {
        bool pbpOn = pbpCommand == CommandKind.PbpOn;
        var newState = pbpOn ? TrackerState.Active : TrackerState.Standby;
        if (_state != newState)
        {
            _state = newState;
            if (newState == TrackerState.Active)
                _logic.Reset(); // reset hysteresis on PBP activation
            DebugLog.Info($"EdgeSwitchTracker: → {_state} (PBP command = {pbpCommand}).");
        }
    }

    // -------------------------------------------------------------------------
    // Display detection (§2.2)
    // -------------------------------------------------------------------------

    private void RefreshDisplay()
    {
        _msiScreenBounds = null;
        foreach (var screen in Screen.AllScreens)
        {
            if (screen.Bounds.Width == 3440 && screen.Bounds.Height == 1440)
            {
                _msiScreenBounds = screen.Bounds;
                _dividerX = screen.Bounds.Left + screen.Bounds.Width / 2;
                DebugLog.Info($"EdgeSwitchTracker: MSI display found at {screen.Bounds}, divider x={_dividerX}.");
                return;
            }
        }
        DebugLog.Info("EdgeSwitchTracker: no 3440×1440 display found — tracker will stay inactive.");
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
    {
        // The event may fire on a system thread; BeginInvoke to the UI thread.
        if (_uiContext.IsHandleCreated && !_uiContext.IsDisposed)
            _uiContext.BeginInvoke(RefreshDisplay);
    }

    // -------------------------------------------------------------------------
    // Hook install / remove
    // -------------------------------------------------------------------------

    // InstallHook/RemoveHook MUST be called on the UI (message-pump) thread.
    // WH_MOUSE_LL requires an active message loop on the installing thread; WinForms provides
    // this on the UI thread. The hook proc (MouseProc) will also fire on that thread.
    private void InstallHook()
    {
        if (_hookHandle != IntPtr.Zero) return; // already installed

        // Assign _proc to a field BEFORE calling SetWindowsHookEx so the delegate is rooted
        // in managed memory before unmanaged code takes a function pointer to it.
        _proc = MouseProc;

        // Thread ID 0 = system-wide hook. WH_MOUSE_LL fires on the thread that installed it,
        // which must be pumping messages — the WinForms UI thread qualifies.
        _hookHandle = SetWindowsHookEx(WH_MOUSE_LL, _proc, IntPtr.Zero, 0);

        if (_hookHandle == IntPtr.Zero)
        {
            var err = Marshal.GetLastWin32Error();
            DebugLog.Warn($"EdgeSwitchTracker: SetWindowsHookEx failed (Win32 error {err}) — tracker inactive.");
            _proc = null; // clear the delegate since the hook never installed
        }
        else
        {
            DebugLog.Info("EdgeSwitchTracker: WH_MOUSE_LL hook installed.");
        }
    }

    private void RemoveHook()
    {
        if (_hookHandle == IntPtr.Zero) return;
        if (!UnhookWindowsHookEx(_hookHandle))
        {
            var err = Marshal.GetLastWin32Error();
            DebugLog.Warn($"EdgeSwitchTracker: UnhookWindowsHookEx failed (Win32 error {err}) — hook may be leaked.");
        }
        else
        {
            DebugLog.Info("EdgeSwitchTracker: WH_MOUSE_LL hook removed.");
        }
        // Clear regardless — the handle is no longer meaningful even on failure.
        _hookHandle = IntPtr.Zero;
        _proc       = null;
    }

    // -------------------------------------------------------------------------
    // Mouse proc (runs on the message-pump / UI thread)
    // -------------------------------------------------------------------------

    // MouseProc runs on the message-pump (UI) thread — same thread that called SetWindowsHookEx.
    // All field reads here (_state, _msiScreenBounds, _dividerX, _mainSource, _subSource) are
    // safe because SetEnabled/NotifyPbpMode/SetSources are also required on the UI thread.
    // BeginInvoke dispatches back to the same UI thread so SendKvm is serialised.
    private IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && (int)wParam == WM_MOUSEMOVE && _state == TrackerState.Active
            && _msiScreenBounds.HasValue)
        {
            var data = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            var pt   = data.pt;
            var bounds = _msiScreenBounds.Value;

            // Only process events inside the MSI display bounds (multi-monitor — §2.2).
            if (pt.X >= bounds.Left && pt.X < bounds.Right &&
                pt.Y >= bounds.Top  && pt.Y < bounds.Bottom)
            {
                var kvm = _logic.Evaluate(pt.X, _dividerX, _mainSource, _subSource);
                if (kvm.HasValue)
                {
                    // Log only on the actual switch (rare) — not on every WM_MOUSEMOVE (hot path).
                    DebugLog.Info($"EdgeSwitchTracker: cursor crossed divider → sending {kvm.Value}.");

                    // Guard against a race where the control is disposed between the
                    // IsHandleCreated/IsDisposed check and the BeginInvoke call (e.g. app shutdown).
                    if (_uiContext.IsHandleCreated && !_uiContext.IsDisposed)
                    {
                        var cmd = kvm.Value;
                        try
                        {
                            _uiContext.BeginInvoke(() => _sendKvm(cmd));
                        }
                        catch (ObjectDisposedException)
                        {
                            // Control was disposed between the check and the call — app is shutting
                            // down. Safe to ignore; the KVM switch is a best-effort UI action.
                        }
                        catch (InvalidOperationException)
                        {
                            // Handle not yet created or already destroyed. Also safe to ignore.
                        }
                    }
                }
            }
        }
        return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    // -------------------------------------------------------------------------
    // IDisposable
    // -------------------------------------------------------------------------

    private bool _disposed;

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        RemoveHook();
    }
}
