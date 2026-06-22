using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// Registers and manages Win32 global hotkeys via <c>RegisterHotKey</c>, driven by a
/// <see cref="HotkeyConfig"/> (docs/SETTINGS.md §5) rather than a static table.
///
/// Hotkeys are registered <b>thread-level</b> (<c>hWnd = IntPtr.Zero</c>): Windows posts
/// <c>WM_HOTKEY</c> to the message queue of the thread that called <c>RegisterHotKey</c>. We
/// catch it with an <see cref="IMessageFilter"/> attached via
/// <see cref="Application.AddMessageFilter"/>, so every message pumped by
/// <c>Application.Run</c> on the UI thread is inspected.
///
/// This replaces an earlier message-only window (<c>HWND_MESSAGE</c>) approach, which did
/// NOT reliably receive <c>WM_HOTKEY</c>. Thread-level hotkeys + a message filter deliver the
/// message to the same loop that runs the tray icon.
///
/// MUST be constructed (and re-registered, and disposed) on the UI (STA) thread that calls
/// <c>Application.Run</c>: <c>RegisterHotKey</c>/<c>UnregisterHotKey</c> and the message-filter
/// list are all per-thread, so a cross-thread call would silently no-op.
///
/// Registration is data-driven from <see cref="HotkeyConfig.Bindings"/>:
/// <list type="bullet">
/// <item>Each chord becomes one Win32 registration (multiple chords per action supported).</item>
/// <item>Actions whose command is unavailable (<see cref="Command.IsAvailable"/>) or whose
///   binding array is empty register nothing — UNKNOWN-payload actions never claim a dead
///   chord (mirrors the macOS app's availability gating).</item>
/// </list>
/// </summary>
internal sealed class HotKeys : IMessageFilter, IDisposable
{
    private const int WmHotkey = 0x0312;

    // Win32 modifier flags (MOD_*).
    private const uint ModAlt   = 0x0001;
    private const uint ModCtrl  = 0x0002;
    private const uint ModShift = 0x0004;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    // Base offset for hotkey IDs. RegisterHotKey IDs are thread-global, so low values risk a
    // silent collision with another library that also registers thread-level hotkeys starting
    // at 1. An app-specific base makes a clash very unlikely. IDs are assigned sequentially as
    // bindings register, and reset on every re-registration pass.
    private const int HotkeyIdBase = 0x2000;

    private readonly Action<CommandKind> _onCommand;
    private readonly List<int> _registeredIds = new();
    private readonly Dictionary<int, CommandKind> _commandById = new();
    private int _nextId = HotkeyIdBase;
    private bool _disposed;

    /// <summary>The config whose bindings are currently registered — used to roll back a rejected re-register.</summary>
    private HotkeyConfig _appliedConfig;

    /// <summary>
    /// Chords (e.g. "Ctrl+Alt+D") from the most recent registration pass that failed to
    /// register — typically because the OS already owns them (OS-reserved, docs/SETTINGS.md
    /// §3.5 check 2). Empty when everything registered cleanly. Refreshed by each pass.
    /// </summary>
    public IReadOnlyList<string> FailedChords { get; private set; } = Array.Empty<string>();

    /// <summary>
    /// Registers all hotkeys from <paramref name="config"/> thread-level and installs the
    /// message filter. Call on the UI thread before/at <c>Application.Run</c>.
    /// </summary>
    /// <param name="onCommand">Callback invoked on the UI thread when a hotkey fires.</param>
    /// <param name="config">The current hotkey configuration.</param>
    public HotKeys(Action<CommandKind> onCommand, HotkeyConfig config)
    {
        _onCommand = onCommand;
        _appliedConfig = config;

        RegisterFrom(config);

        try
        {
            Application.AddMessageFilter(this);
        }
        catch
        {
            // Don't leave a partially-constructed instance with registered hotkeys behind.
            UnregisterAll();
            throw;
        }
    }

    /// <summary>
    /// Live re-registration with rollback (docs/SETTINGS.md §5 / §3.5 check 2): unregister the
    /// current hotkeys, then try to register the new set from <paramref name="config"/>. MUST be
    /// called on the UI/message-filter thread (the single message filter stays attached).
    /// <para>
    /// If EVERY chord registers, the new config becomes the applied config and this returns
    /// true. If ANY chord is rejected by the OS (e.g. OS-reserved), the whole new set is rolled
    /// back: the previously-applied config is re-registered so the user keeps the hotkeys that
    /// were working, the rejected chords are exposed in <see cref="FailedChords"/>, and this
    /// returns false. The caller should then NOT persist the new config.
    /// </para>
    /// </summary>
    /// <returns>true on full success; false if any chord was rejected (previous bindings restored).</returns>
    public bool TryReRegister(HotkeyConfig config)
    {
        if (_disposed) return false;

        UnregisterAll();
        RegisterFrom(config);

        if (FailedChords.Count == 0)
        {
            _appliedConfig = config;
            return true;
        }

        // Rejected — roll back to the previously-applied, known-good config. Preserve the
        // failed-chord list so the caller can surface exactly what was rejected.
        var rejected = FailedChords;
        UnregisterAll();
        RegisterFrom(_appliedConfig);
        FailedChords = rejected;
        return false;
    }

    /// <summary>
    /// Registers every chord in the config's bindings, skipping unavailable actions and empty
    /// arrays. Populates <see cref="FailedChords"/> for any chord the OS refused.
    /// </summary>
    private void RegisterFrom(HotkeyConfig config)
    {
        var failed = new List<string>();
        _nextId = HotkeyIdBase;

        foreach (var (actionId, chords) in config.Bindings)
        {
            var kind = Command.KindForActionId(actionId);
            if (kind is null)
            {
                Debug.WriteLine($"[HotKeys] Unknown actionId '{actionId}' in config — skipped.");
                continue;
            }

            // Skip unavailable commands (UNKNOWN payloads): they must not claim a chord.
            if (!Command.IsAvailable(kind.Value))
                continue;

            foreach (var chord in chords)
            {
                if (!TryMods(chord, out uint mods) || !TryVk(chord.Key, out uint vk))
                {
                    Debug.WriteLine($"[HotKeys] Skipping unmappable chord '{HotkeyConfig.DisplayString(chord)}' for {actionId}.");
                    continue;
                }

                int id = _nextId++;
                if (RegisterHotKey(IntPtr.Zero, id, mods, vk))
                {
                    _registeredIds.Add(id);
                    _commandById[id] = kind.Value;
                }
                else
                {
                    // Most common cause: the chord is already owned by another process
                    // (OS-reserved). On a re-register the previous binding is already gone for
                    // this action; the caller surfaces the conflict, the rest stay applied.
                    var err = Marshal.GetLastWin32Error();
                    var display = HotkeyConfig.DisplayString(chord);
                    failed.Add(display);
                    Debug.WriteLine($"[HotKeys] Failed to register {display} for {kind.Value} (Win32 error {err}).");
                }
            }
        }

        FailedChords = failed;
    }

    /// <summary>Maps a chord's canonical modifier set to the Win32 <c>MOD_*</c> flags.</summary>
    private static bool TryMods(Chord chord, out uint mods)
    {
        mods = 0;
        var set = chord.ModSet;
        if (set.Contains(HotkeyConfig.ModControl)) mods |= ModCtrl;
        if (set.Contains(HotkeyConfig.ModAlt))     mods |= ModAlt;
        if (set.Contains(HotkeyConfig.ModShift))   mods |= ModShift;
        // A "command" modifier is dropped on load, so it never reaches here.

        // A modifier-less global hotkey is rejected (too collision-prone — §3.3/§3.5).
        return mods != 0;
    }

    private const uint VkSpace = 0x20; // VK_SPACE

    /// <summary>
    /// Maps a base key to its Win32 virtual key code. For A–Z/0–9 the <c>VK_*</c> value equals the
    /// upper-case ASCII code (no table needed); named keys (v0.2.2: "Space") map explicitly.
    /// Returns false for anything outside the allowed set (§3.4).
    /// </summary>
    private static bool TryVk(string key, out uint vk)
    {
        vk = 0;
        if (string.IsNullOrEmpty(key)) return false;

        if (string.Equals(key, "Space", StringComparison.OrdinalIgnoreCase))
        {
            vk = VkSpace;
            return true;
        }

        if (key.Length != 1) return false;
        char c = char.ToUpperInvariant(key[0]);
        if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
        {
            vk = c; // VK_A..VK_Z and VK_0..VK_9 share the ASCII code points.
            return true;
        }
        return false;
    }

    /// <summary>
    /// Inspects every message pumped on the UI thread; fires the command on WM_HOTKEY.
    /// </summary>
    public bool PreFilterMessage(ref Message m)
    {
        if (m.Msg == WmHotkey)
        {
            var id = m.WParam.ToInt32();
            Debug.WriteLine($"[HotKeys] WM_HOTKEY received (id={id}).");
            if (_commandById.TryGetValue(id, out var command))
            {
                _onCommand(command);
                return true; // handled — don't propagate further
            }
        }
        return false;
    }

    /// <summary>Unregisters every live hotkey and clears the id maps (filter stays attached).</summary>
    private void UnregisterAll()
    {
        foreach (var id in _registeredIds)
            UnregisterHotKey(IntPtr.Zero, id);
        _registeredIds.Clear();
        _commandById.Clear();
    }

    /// <summary>
    /// Unregisters all hotkeys and removes the message filter.
    /// </summary>
    /// <remarks>
    /// MUST be called on the same UI (STA) thread that constructed this instance.
    /// <c>UnregisterHotKey</c> only affects hotkeys owned by the calling thread, and
    /// <c>Application.RemoveMessageFilter</c> operates on the calling thread's filter list, so
    /// disposing from another thread would silently fail to clean up. <see cref="TrayApp"/>
    /// disposes us during its own <c>Dispose</c> on the UI thread, which satisfies this.
    /// </remarks>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        Application.RemoveMessageFilter(this);
        UnregisterAll();
    }
}
