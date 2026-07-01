using System;

namespace NexTerm.RdpHost
{
    internal sealed class RdpHostOptions
    {
        public string Host { get; private set; }
        public int Port { get; private set; }
        public string User { get; private set; }
        public string Domain { get; private set; }
        public bool AutoConnect { get; private set; }
        public bool Clipboard { get; private set; }
        public bool SmartSizing { get; private set; }

        private RdpHostOptions()
        {
            Port = 3389;
            Clipboard = true;
            SmartSizing = true;
        }

        public static RdpHostOptions FromArgs(string[] args)
        {
            var options = new RdpHostOptions();
            if (args == null)
            {
                return options;
            }

            foreach (var raw in args)
            {
                if (string.IsNullOrWhiteSpace(raw))
                {
                    continue;
                }

                var arg = raw.Trim();
                if (arg.Equals("/connect", StringComparison.OrdinalIgnoreCase) ||
                    arg.Equals("--connect", StringComparison.OrdinalIgnoreCase))
                {
                    options.AutoConnect = true;
                    continue;
                }

                var split = arg.IndexOf(':');
                if (split <= 0)
                {
                    split = arg.IndexOf('=');
                }
                if (split <= 0)
                {
                    continue;
                }

                var key = arg.Substring(0, split).TrimStart('/', '-').ToLowerInvariant();
                var value = arg.Substring(split + 1);

                switch (key)
                {
                    case "host":
                    case "server":
                        options.Host = value;
                        break;
                    case "port":
                        int port;
                        if (int.TryParse(value, out port) && port >= 1 && port <= 65535)
                        {
                            options.Port = port;
                        }
                        break;
                    case "user":
                    case "username":
                        options.User = value;
                        break;
                    case "domain":
                        options.Domain = value;
                        break;
                    case "clipboard":
                        options.Clipboard = ParseBool(value, true);
                        break;
                    case "smartsizing":
                    case "smart-sizing":
                        options.SmartSizing = ParseBool(value, true);
                        break;
                }
            }

            return options;
        }

        private static bool ParseBool(string value, bool defaultValue)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return defaultValue;
            }

            if (value.Equals("1") ||
                value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("yes", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("on", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            if (value.Equals("0") ||
                value.Equals("false", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("no", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("off", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return defaultValue;
        }
    }
}
