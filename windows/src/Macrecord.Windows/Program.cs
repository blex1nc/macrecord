namespace Macrecord.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var instance = new Mutex(initiallyOwned: true, "macrecord-windows-single-instance", out var first);
        if (!first)
        {
            MessageBox.Show("macrecord zaten çalışıyor.", "macrecord");
            return;
        }
        UpdateChecker.CleanUp();
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
    }
}
