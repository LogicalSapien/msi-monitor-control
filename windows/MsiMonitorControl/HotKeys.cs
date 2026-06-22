using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// Registers and manages Win32 global hotkeys via <c>RegisterHotKey</c>.
///
/// Default hotkeys (Ctrl+Alt+*):
///   Ctrl+Alt+P = PBP On
///   Ctrl+Alt+O = PBP Off
///   Ctrl+Alt+U = KVM → USB-C
///   Ctrl+Alt+K = KVM → Upstream
///   Ctrl+Alt+T = Input → Type-C
///   Ctrl+Alt+D = Input → DP
/// </summary>
internal sealed class HotKeys : NativeWindow, IDisposable
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
    private bool _disposed;

    private static readonly (int Id, uint Vk, CommandKind Command)[] Bindings =
    {
        (1, VkP, CommandKind.PbpOn),
        (2, VkO, CommandKind.PbpOff),
        (3, VkU, CommandKind.KvmUsbC),
        (4, VkK, CommandKind.KvmUpstream),
        (5, VkT, CommandKind.InputTypeC),
        (6, VkD, CommandKind.InputDp),
    };

    /// <summary>
    /// Initialises and registers all hotkeys.
    /// </summary>
    /// <param name="hwnd">The HWND to associate hotkey messages with (tray icon handle).</param>
    /// <param name="onCommand">Callback invoked on the UI thread when a hotkey fires.</param>
    public HotKeys(IntPtr hwnd, Action<CommandKind> onCommand)
    {
        _onCommand = onCommand;

        // Attach to the provided window handle so WM_HOTKEY messages are routed here.
        AssignHandle(hwnd);

        foreach (var (id, vk, _) in Bindings)
            RegisterHotKey(Handle, id, ModCtrl | ModAlt, vk);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey)
        {
            var id = m.WParam.ToInt32();
            foreach (var (bindId, _, command) in Bindings)
            {
                if (bindId == id)
                {
                    _onCommand(command);
                    break;
                }
            }
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        foreach (var (id, _, _) in Bindings)
            UnregisterHotKey(Handle, id);

        ReleaseHandle();
    }
}
