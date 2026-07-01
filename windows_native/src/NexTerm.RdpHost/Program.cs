using System;
using System.IO;
using System.Windows.Forms;

namespace NexTerm.RdpHost
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (_, e) => LogException(e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (_, e) =>
                LogException(e.ExceptionObject as Exception);

            try
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(RdpHostOptions.FromArgs(args)));
            }
            catch (Exception ex)
            {
                LogException(ex);
                throw;
            }
        }

        private static void LogException(Exception exception)
        {
            if (exception == null)
            {
                return;
            }

            var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "NexTerm.RdpHost.crash.log");
            File.AppendAllText(
                path,
                DateTime.Now.ToString("O") + Environment.NewLine +
                exception + Environment.NewLine +
                new string('-', 80) + Environment.NewLine);
        }
    }
}
