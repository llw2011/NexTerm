namespace NexTerm.RdpHost
{
    internal sealed class RdpConnectionRequest
    {
        public string Host { get; set; }
        public int Port { get; set; }
        public string Username { get; set; }
        public string Domain { get; set; }
        public string Password { get; set; }
        public bool Clipboard { get; set; }
        public bool SmartSizing { get; set; }
    }
}
