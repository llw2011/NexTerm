using System;
using System.Runtime.InteropServices;
using System.Text;

namespace NexTerm.RdpHost
{
    internal static class CredentialVault
    {
        private const uint CredTypeGeneric = 1;
        private const uint CredPersistLocalMachine = 2;

        public static void SavePassword(string target, string password, string username)
        {
            if (string.IsNullOrWhiteSpace(target))
            {
                throw new ArgumentException("Credential target is required.", "target");
            }
            if (password == null)
            {
                password = "";
            }

            var blob = Marshal.StringToCoTaskMemUni(password);
            try
            {
                var credential = new NativeCredential
                {
                    Type = CredTypeGeneric,
                    TargetName = target,
                    CredentialBlob = blob,
                    CredentialBlobSize = (uint)Encoding.Unicode.GetByteCount(password),
                    Persist = CredPersistLocalMachine,
                    UserName = string.IsNullOrWhiteSpace(username)
                        ? Environment.UserName
                        : username,
                };

                if (!CredWrite(ref credential, 0))
                {
                    throw new InvalidOperationException(
                        "CredWrite failed with Win32 error " + Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                Marshal.ZeroFreeCoTaskMemUnicode(blob);
            }
        }

        public static string ReadPassword(string target)
        {
            IntPtr credentialPtr;
            if (!CredRead(target, CredTypeGeneric, 0, out credentialPtr))
            {
                return null;
            }

            try
            {
                var credential = (NativeCredential)Marshal.PtrToStructure(
                    credentialPtr,
                    typeof(NativeCredential));
                if (credential.CredentialBlob == IntPtr.Zero ||
                    credential.CredentialBlobSize == 0)
                {
                    return "";
                }

                var bytes = new byte[credential.CredentialBlobSize];
                Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
                return Encoding.Unicode.GetString(bytes);
            }
            finally
            {
                CredFree(credentialPtr);
            }
        }

        public static bool HasPassword(string target)
        {
            IntPtr credentialPtr;
            if (!CredRead(target, CredTypeGeneric, 0, out credentialPtr))
            {
                return false;
            }

            CredFree(credentialPtr);
            return true;
        }

        public static void DeletePassword(string target)
        {
            if (string.IsNullOrWhiteSpace(target))
            {
                return;
            }

            CredDelete(target, CredTypeGeneric, 0);
        }

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(ref NativeCredential userCredential, uint flags);

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, uint type, uint reservedFlag, out IntPtr credentialPtr);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(string target, uint type, uint flags);

        [DllImport("advapi32.dll", SetLastError = false)]
        private static extern void CredFree(IntPtr buffer);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NativeCredential
        {
            public uint Flags;
            public uint Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }
    }
}
