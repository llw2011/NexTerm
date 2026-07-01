using System;

namespace NexTerm.RdpHost
{
    internal sealed class RdpSessionStatusEventArgs : EventArgs
    {
        public RdpSessionStatusEventArgs(string message)
        {
            Message = message;
        }

        public string Message { get; private set; }
    }
}
