using System.Diagnostics;
using System.Text;
using System.Windows.Forms;

namespace MsiMonitorControl;

/// <summary>
/// Lightweight file logger for diagnosing switches and catching unexpected quits (v0.2.1).
///
/// Writes timestamped, structured lines to
/// <c>%APPDATA%\LogicalSapien\MSIMonitorControl\debug.log</c> (the same vendor directory as
/// <c>settings.json</c>). The log is truncated on each launch with a session-start marker, so a
/// run's log stays focused and bounded; a ~1&#160;MB size guard truncates as a backstop if a
/// single session ever grows large.
///
/// Logging is <b>best-effort</b> — every write is wrapped so a logging failure can never throw
/// into the app. <see cref="Init"/> also installs unhandled-exception handlers
/// (<see cref="AppDomain.UnhandledException"/> + <see cref="Application.ThreadException"/>) that
/// write a final <c>TERMINATING</c> line before the process dies, so a crash is distinguishable
/// from a normal user-initiated quit.
/// </summary>
internal static class DebugLog
{
    private static readonly object Gate = new();
    private const long MaxBytes = 1_000_000; // ~1 MB backstop

    /// <summary>The debug log file path (vendor-nested, beside settings.json).</summary>
    public static string LogPath => Path.Combine(HotkeyConfig.ConfigDirectory, "debug.log");

    /// <summary>
    /// Truncates the log, writes a session-start marker, and installs the unhandled-exception
    /// handlers. Call ONCE at startup, before <c>Application.Run</c>. Never throws.
    /// </summary>
    public static void Init()
    {
        try
        {
            Directory.CreateDirectory(HotkeyConfig.ConfigDirectory);
            // Truncate-on-launch: start each session with a fresh, focused log.
            File.WriteAllText(LogPath, "", new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[DebugLog] Could not initialise log file: {ex.Message}");
        }

        var version = typeof(DebugLog).Assembly.GetName().Version?.ToString() ?? "unknown";
        Info($"=== MSI Monitor Control session started (v{version}) ===");

        AppDomain.CurrentDomain.UnhandledException += OnUnhandledException;
        Application.ThreadException += OnThreadException;
    }

    public static void Info(string message)  => Write("INFO", message);
    public static void Warn(string message)  => Write("WARN", message);
    public static void Error(string message) => Write("ERROR", message);

    /// <summary>Logs an exception with a contextual prefix (message + stack trace).</summary>
    public static void Exception(string prefix, Exception ex) =>
        Write("ERROR", $"{prefix}: {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}");

    /// <summary>Logs the (expected) end of a session — distinguishes a clean quit from a crash.</summary>
    public static void SessionEnd(string reason) =>
        Info($"=== Session ended ({reason}) ===");

    /// <summary>
    /// Opens the folder containing the log in Explorer (selecting the file if present), for the
    /// tray "Reveal debug log" item. Never throws.
    /// </summary>
    public static void OpenLogFolder()
    {
        try
        {
            if (File.Exists(LogPath))
            {
                // /select, highlights the file within its folder.
                Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{LogPath}\"") { UseShellExecute = true });
            }
            else
            {
                Directory.CreateDirectory(HotkeyConfig.ConfigDirectory);
                Process.Start(new ProcessStartInfo(HotkeyConfig.ConfigDirectory) { UseShellExecute = true });
            }
        }
        catch (Exception ex)
        {
            Warn($"Could not open log folder: {ex.Message}");
        }
    }

    private static void Write(string level, string message)
    {
        var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{level}] {message}";
        Debug.WriteLine(line); // also surface in the IDE/debugger output

        lock (Gate)
        {
            try
            {
                // Size backstop: if a single session somehow exceeds the cap, start fresh.
                try
                {
                    var fi = new FileInfo(LogPath);
                    if (fi.Exists && fi.Length > MaxBytes)
                        File.WriteAllText(LogPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [INFO] (log truncated — exceeded {MaxBytes} bytes)\n",
                            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                }
                catch { /* size check is best-effort */ }

                File.AppendAllText(LogPath, line + "\n", new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[DebugLog] Write failed: {ex.Message}");
            }
        }
    }

    private static void OnUnhandledException(object sender, UnhandledExceptionEventArgs e)
    {
        var ex = e.ExceptionObject as Exception;
        Write("FATAL", ex is not null
            ? $"TERMINATING (unhandled): {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}"
            : $"TERMINATING (unhandled): {e.ExceptionObject}");
    }

    private static void OnThreadException(object sender, System.Threading.ThreadExceptionEventArgs e)
    {
        Write("FATAL", $"TERMINATING (UI thread): {e.Exception.GetType().Name}: {e.Exception.Message}\n{e.Exception.StackTrace}");
    }
}
