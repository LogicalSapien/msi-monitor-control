using System.Diagnostics;
using Microsoft.Win32;

namespace MsiMonitorControl;

/// <summary>
/// Launch-at-login via the HKCU <c>Run</c> key (docs/SETTINGS.md §6).
///
/// The registry <b>value name</b> is the FLAT app name <c>MSIMonitorControl</c> — NOT nested
/// under the vendor folder. (The vendor nesting applies only to the config file path; a
/// <c>Run</c> value name is a label, not a path.) The value <b>data</b> is the quoted full
/// path to the executable.
///
/// The config's <c>launchAtLogin</c> bool is the source of truth: on toggle we write/delete
/// the registry value and persist the bool; on launch we reconcile (config wins).
/// </summary>
internal static class LaunchAtLogin
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    /// <summary>FLAT registry value name (NOT vendor-nested). See docs/SETTINGS.md §6.</summary>
    private const string ValueName = "MSIMonitorControl";

    /// <summary>The quoted path to the running executable, suitable as the <c>Run</c> value data.</summary>
    private static string? ExecutableCommand
    {
        get
        {
            var exe = Environment.ProcessPath;
            return string.IsNullOrEmpty(exe) ? null : $"\"{exe}\"";
        }
    }

    /// <summary>True when the HKCU Run value exists (regardless of whether it points at this exe).</summary>
    public static bool IsEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            return key?.GetValue(ValueName) is not null;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[LaunchAtLogin] Could not read Run key: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// The current value data, or null when absent/unreadable. Used to detect a stale path (the
    /// exe moved since the value was written) so reconcile can repair it.
    /// </summary>
    private static string? CurrentValueData()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            return key?.GetValue(ValueName) as string;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[LaunchAtLogin] Could not read Run value data: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Writes (enable) or deletes (disable) the HKCU Run value. Returns true on success.
    /// On failure the caller should revert the UI toggle and not persist the bool.
    /// </summary>
    public static bool SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
                            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (key is null)
            {
                Debug.WriteLine("[LaunchAtLogin] Could not open/create the Run key.");
                return false;
            }

            if (enabled)
            {
                var cmd = ExecutableCommand;
                if (cmd is null)
                {
                    Debug.WriteLine("[LaunchAtLogin] Cannot enable — executable path unavailable.");
                    return false;
                }
                key.SetValue(ValueName, cmd, RegistryValueKind.String);
            }
            else
            {
                if (key.GetValue(ValueName) is not null)
                    key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
            return true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[LaunchAtLogin] Could not {(enabled ? "enable" : "disable")} launch-at-login: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Reconciles the OS state with the config on launch — the config wins (docs/SETTINGS.md §6).
    /// If they already agree, this is a no-op. Failures are logged and ignored (non-fatal).
    /// </summary>
    public static void Reconcile(HotkeyConfig config)
    {
        try
        {
            if (IsEnabled() != config.LaunchAtLogin)
            {
                SetEnabled(config.LaunchAtLogin);
                return;
            }

            // Already in the desired on/off state — but if enabled, the stored path may be stale
            // (the exe moved/updated since it was written). Repair it so login still launches the
            // right binary. Comparing DATA, not just existence.
            if (config.LaunchAtLogin)
            {
                var current = CurrentValueData();
                var wanted  = ExecutableCommand;
                if (wanted is not null && !string.Equals(current, wanted, StringComparison.OrdinalIgnoreCase))
                {
                    Debug.WriteLine($"[LaunchAtLogin] Repairing stale Run path: '{current}' → '{wanted}'.");
                    SetEnabled(true);
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[LaunchAtLogin] Reconcile failed: {ex.Message}");
        }
    }
}
