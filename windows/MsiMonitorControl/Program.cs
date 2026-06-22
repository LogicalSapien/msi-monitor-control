using System.Windows.Forms;

namespace MsiMonitorControl;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Initialise the debug log + crash capture FIRST so a failure anywhere below is recorded.
        DebugLog.Init();

        // Route unhandled UI-thread exceptions to our handler (and the debug log) instead of the
        // default WinForms dialog, so a crash is captured to debug.log before the process dies.
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            Application.Run(new TrayApp());
            DebugLog.SessionEnd("Application.Run returned");
        }
        catch (Exception ex)
        {
            DebugLog.Exception("TERMINATING (Main)", ex);
            throw;
        }
    }
}
