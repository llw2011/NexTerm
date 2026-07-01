using System;
using System.IO;

namespace NexTerm.RdpHost
{
    internal static class SessionLog
    {
        public static string Path
        {
            get
            {
                return System.IO.Path.Combine(
                    AppDomain.CurrentDomain.BaseDirectory,
                    "NexTerm.RdpHost.session.log");
            }
        }

        public static void Write(string message)
        {
            File.AppendAllText(
                Path,
                DateTime.Now.ToString("O") + " " + message + Environment.NewLine);
        }
    }
}
