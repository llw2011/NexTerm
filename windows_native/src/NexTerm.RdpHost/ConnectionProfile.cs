using System;
using System.Collections.Generic;
using System.IO;
using System.Xml.Serialization;

namespace NexTerm.RdpHost
{
    public sealed class ConnectionProfile
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Host { get; set; }
        public int Port { get; set; }
        public string Username { get; set; }
        public string Domain { get; set; }
        public string Group { get; set; }
        public string Notes { get; set; }
        public bool Favorite { get; set; }
        public bool Clipboard { get; set; }
        public bool SmartSizing { get; set; }
        public string LastConnectedAtUtc { get; set; }
        public string LastResult { get; set; }
        public string CreatedAtUtc { get; set; }
        public string UpdatedAtUtc { get; set; }

        [XmlIgnore]
        public string CredentialTarget
        {
            get { return "NexTerm/RDP/" + Id; }
        }

        public override string ToString()
        {
            var name = string.IsNullOrWhiteSpace(Name) ? Host : Name;
            if (string.IsNullOrWhiteSpace(Host))
            {
                return name;
            }

            var endpoint = Host + ":" + Port;
            if (string.Equals(name, Host, StringComparison.OrdinalIgnoreCase))
            {
                return endpoint;
            }

            return name + "  " + endpoint;
        }
    }

    [XmlRoot("connections")]
    public sealed class ConnectionProfileList
    {
        [XmlElement("connection")]
        public List<ConnectionProfile> Items { get; set; }

        public ConnectionProfileList()
        {
            Items = new List<ConnectionProfile>();
        }
    }

    internal sealed class ConnectionStore
    {
        private readonly string _path;

        public ConnectionStore()
            : this(DefaultPath())
        {
        }

        public ConnectionStore(string path)
        {
            _path = path;
        }

        public IList<ConnectionProfile> Load()
        {
            if (!File.Exists(_path))
            {
                return new List<ConnectionProfile>();
            }

            try
            {
                var serializer = new XmlSerializer(typeof(ConnectionProfileList));
                using (var stream = File.OpenRead(_path))
                {
                    var list = (ConnectionProfileList)serializer.Deserialize(stream);
                    return Normalize(list == null ? null : list.Items);
                }
            }
            catch
            {
                var brokenPath = _path + ".broken-" + DateTime.Now.ToString("yyyyMMddHHmmss");
                File.Move(_path, brokenPath);
                return new List<ConnectionProfile>();
            }
        }

        public void Save(IEnumerable<ConnectionProfile> profiles)
        {
            var directory = Path.GetDirectoryName(_path);
            if (!Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var list = new ConnectionProfileList();
            foreach (var profile in profiles)
            {
                if (profile == null)
                {
                    continue;
                }

                EnsureIdentity(profile);
                list.Items.Add(profile);
            }

            var serializer = new XmlSerializer(typeof(ConnectionProfileList));
            using (var stream = File.Create(_path))
            {
                serializer.Serialize(stream, list);
            }
        }

        private static IList<ConnectionProfile> Normalize(IEnumerable<ConnectionProfile> profiles)
        {
            var result = new List<ConnectionProfile>();
            if (profiles == null)
            {
                return result;
            }

            foreach (var profile in profiles)
            {
                if (profile == null)
                {
                    continue;
                }

                EnsureIdentity(profile);
                if (profile.Port <= 0 || profile.Port > 65535)
                {
                    profile.Port = 3389;
                }
                if (string.IsNullOrWhiteSpace(profile.Name))
                {
                    profile.Name = profile.Host;
                }
                if (profile.Port <= 0)
                {
                    profile.Port = 3389;
                }
                result.Add(profile);
            }

            return result;
        }

        private static void EnsureIdentity(ConnectionProfile profile)
        {
            if (string.IsNullOrWhiteSpace(profile.Id))
            {
                profile.Id = Guid.NewGuid().ToString("N");
            }
            if (string.IsNullOrWhiteSpace(profile.CreatedAtUtc))
            {
                profile.CreatedAtUtc = DateTime.UtcNow.ToString("O");
            }
            profile.UpdatedAtUtc = string.IsNullOrWhiteSpace(profile.UpdatedAtUtc)
                ? profile.CreatedAtUtc
                : profile.UpdatedAtUtc;
        }

        private static string DefaultPath()
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "NexTerm",
                "Windows",
                "connections.xml");
        }
    }
}
