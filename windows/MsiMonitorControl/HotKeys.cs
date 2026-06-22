using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// Registers and manages Win32 global hotkeys via <c>RegisterHotKey</c>.
///
/// Hotkeys are registered <b>thread-level</b> (<c>hWnd = IntPtr.Zero</c>): Windows then
/// posts <c>WM_HOTKEY</c> to the message queue of the thread that called
/// <c>RegisterHotKey</c>. We catch it with an <see cref="IMessageFilter"/> attached via
/// <see cref="Application.AddMessageFilter"/>, so every message pumped by
/// <c>Application.Run</c> on the UI thread is inspected.
///
/// This replaces an earlier message-only window (<c>HWND_MESSAGE</c>) approach, which did
/// NOT reliably receive <c>WM_HOTKEY</c> — message-only windows are excluded from the
/// normal message pump used by the tray <see cref="ApplicationContext"/>, so the hotkeys
/// fired on macOS but did nothing on Windows. Thread-level hotkeys + a message filter
/// deliver the message to the same loop that runs the tray icon.
///
/// MUST be constructed on the UI (STA) thread that calls <c>Application.Run</c>.
///
/// Default hotkeys (Ctrl+Alt+*):
///   Ctrl+Alt+P = PBP On
///   Ctrl+Alt+O = PBP Off
///   Ctrl+Alt+U = KVM → USB-C
///   Ctrl+Alt+K = KVM → Upstream
///   Ctrl+Alt+T = Input → Type-C
///   Ctrl+Alt+D = Input → DP
/// </summary>
internal sealed class HotKeys : IMessageFilter, IDisposable
{
    private const int WmHotkey = 0x0312;

    // Win32 modifier flags
    private const uint ModAlt  = 0x0001;
    private const uint ModCtrl = 0x0002;

    // Virtual key codes
    private const uint VkP = 0x50;
    private const uint VkO = 0x4F;
    private const uint VkU = 0x55;
    private const uint VkK = 0x4B;
    private const uint VkT = 0x54;
    private const uint VkD = 0x44;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private readonly Action<CommandKind> _onCommand;
    private readonly List<int> _registeredIds = new();
    private bool _disposed;

    private static readonly (int Id, uint Vk, char Key, CommandKind Command)[] Bindings =
    {
        (1, VkP, 'P', CommandKind.PbpOn),
        (2, VkO, 'O', CommandKind.PbpOff),
        (3, VkU, 'U', CommandKind.KvmUsbC),
        (4, VkK, 'K', CommandKind.KvmUpstream),
        (5, VkT, 'T', CommandKind.InputTypeC),
        (6, VkD, 'D', CommandKind.InputDp),
    };

    /// <summary>
    /// Chords (e.g. "Ctrl+Alt+D") that failed to register, for the caller to surface
    /// to the user. Empty when all registrations succeeded.
    /// </summary>
    public IReadOnlyList<string> FailedChords { get; }

    /// <summary>
    /// Registers all hotkeys thread-level and installs the message filter.
    /// Call on the UI thread before/at <c>Application.Run</c>.
    /// </summary>
    /// <param name="onCommand">Callback invoked on the UI thread when a hotkey fires.</param>
    public HotKeys(Action<CommandKind> onCommand)
    {
        _onCommand = onCommand;

        var failed = new List<string>();
        foreach (var (id, vk, key, command) in Bindings)
        {
            // hWnd = IntPtr.Zero registers a thread-level hotkey: WM_HOTKEY is posted to
            // this thread's message queue and seen by the message filter below.
            if (RegisterHotKey(IntPtr.Zero, id, ModCtrl | ModAlt, vk))
            {
                _registeredIds.Add(id);
            }
            else
            {
                // Most common cause: the chord is already owned by another process.
                // Ctrl+Alt can also be swallowed where it maps to AltGr on some layouts.
                var err = Marshal.GetLastWin32Error();
                var chord = $"Ctrl+Alt+{key}";
                failed.Add(chord);
                Debug.WriteLine($"[HotKeys] Failed to register {chord} for {command} (Win32 error {err}).");
            }
        }

        FailedChords = failed;
        Application.AddMessageFilter(this);
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
            foreach (var (bindId, _, _, command) in Bindings)
            {
                if (bindId == id)
                {
                    _onCommand(command);
                    return true; // handled — don't propagate further
                }
            }
        }
        return false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        Application.RemoveMessageFilter(this);
        foreach (var id in _registeredIds)
            UnregisterHotKey(IntPtr.Zero, id);
        _registeredIds.Clear();
    }
}
