using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace NexTerm.RdpHost
{
    internal sealed class MainForm : Form
    {
        private static readonly Color AppBg = Color.FromArgb(12, 15, 18);
        private static readonly Color Surface = Color.FromArgb(21, 26, 32);
        private static readonly Color SurfaceHigh = Color.FromArgb(30, 37, 45);
        private static readonly Color Border = Color.FromArgb(48, 59, 70);
        private static readonly Color TextPrimary = Color.FromArgb(232, 238, 242);
        private static readonly Color TextSecondary = Color.FromArgb(150, 162, 173);
        private static readonly Color Accent = Color.FromArgb(55, 214, 194);
        private static readonly Color Danger = Color.FromArgb(255, 91, 111);

        private readonly TextBox _hostText = new TextBox();
        private readonly NumericUpDown _portBox = new NumericUpDown();
        private readonly TextBox _userText = new TextBox();
        private readonly TextBox _domainText = new TextBox();
        private readonly TextBox _passwordText = new TextBox();
        private readonly CheckBox _clipboardBox = new CleanCheckBox();
        private readonly CheckBox _smartSizingBox = new CleanCheckBox();
        private readonly CheckBox _savePasswordBox = new CleanCheckBox();
        private readonly CheckBox _showPasswordBox = new CleanCheckBox();
        private readonly Button _connectButton = new CleanButton();
        private readonly Button _disconnectButton = new CleanButton();
        private readonly Button _testConnectionButton = new CleanButton();
        private readonly Button _newProfileButton = new CleanButton();
        private readonly Button _saveProfileButton = new CleanButton();
        private readonly Button _deleteProfileButton = new CleanButton();
        private readonly Button _openLogButton = new CleanButton();
        private readonly ListBox _profilesList = new CleanListBox();
        private readonly Label _profileSummaryLabel = new Label();
        private readonly Label _statusLabel = new Label();
        private readonly RdpSessionControl _rdpSession = new RdpSessionControl();
        private readonly ToolTip _toolTip = new ToolTip();
        private readonly RdpHostOptions _options;
        private readonly ConnectionStore _connectionStore = new ConnectionStore();
        private readonly List<ConnectionProfile> _profiles = new List<ConnectionProfile>();

        private bool _loadingProfile;
        private bool _connectionBusy;
        private bool _tcpTestBusy;
        private ConnectionProfile _selectedProfile;

        public MainForm(RdpHostOptions options)
        {
            _options = options ?? RdpHostOptions.FromArgs(null);
            Text = "NexTerm 远程桌面";
            BackColor = AppBg;
            ForeColor = TextPrimary;
            Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(980, 640);
            Size = new Size(1280, 820);
            KeyPreview = true;

            _rdpSession.StatusChanged += (_, e) => SetStatus(e.Message);
            _rdpSession.Connected += (_, __) => SetConnectionButtons(true);
            _rdpSession.Disconnected += (_, __) => SetConnectionButtons(false);
            _rdpSession.LoginCompleted += (_, __) => HandleLoginComplete();

            BuildLayout();
            WireInputShortcuts();
            LoadProfiles();
            ApplyOptions();
            UpdateActionState();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            Log("Closing window.");
            _rdpSession.Disconnect();
            base.OnFormClosing(e);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (_options.AutoConnect && !string.IsNullOrWhiteSpace(_hostText.Text) &&
                !string.IsNullOrWhiteSpace(_userText.Text))
            {
                BeginInvoke(new Action(ConnectRdp));
            }
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == (Keys.Control | Keys.S))
            {
                SaveCurrentProfile();
                return true;
            }

            if (keyData == Keys.F5)
            {
                ConnectRdp();
                return true;
            }

            if (keyData == Keys.F6)
            {
                TestCurrentEndpoint();
                return true;
            }

            if (keyData == Keys.Escape && (_connectionBusy || _rdpSession.IsConnected))
            {
                DisconnectRdp();
                return true;
            }

            return base.ProcessCmdKey(ref msg, keyData);
        }

        private void BuildLayout()
        {
            var shell = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                BackColor = AppBg,
                ColumnCount = 2,
                RowCount = 1,
            };
            shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 260));
            shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

            var root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                BackColor = AppBg,
                ColumnCount = 1,
                RowCount = 3,
            };
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 164));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));

            var headerShell = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                BackColor = Surface,
                Padding = new Padding(14, 10, 14, 10),
                ColumnCount = 1,
                RowCount = 2,
            };
            headerShell.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            headerShell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

            var titleRow = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 3,
                RowCount = 1,
            };
            titleRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 168));
            titleRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            titleRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 220));

            var title = new Label
            {
                Text = "NexTerm",
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleLeft,
                ForeColor = Accent,
                Font = new Font("Segoe UI Semibold", 15F, FontStyle.Bold, GraphicsUnit.Point),
            };
            var subtitle = new Label
            {
                Text = "Windows 远程桌面",
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleLeft,
                ForeColor = TextSecondary,
                Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point),
            };
            var phase = new Label
            {
                Text = "先连接，需要时再保存",
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleRight,
                ForeColor = TextSecondary,
            };
            titleRow.Controls.Add(title, 0, 0);
            titleRow.Controls.Add(subtitle, 1, 0);
            titleRow.Controls.Add(phase, 2, 0);

            var header = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 12,
                RowCount = 3,
            };

            for (var i = 0; i < 12; i++)
            {
                header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / 12f));
            }
            header.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
            header.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            header.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));

            AddLabel(header, "主机", 0, 0);
            AddLabel(header, "端口", 3, 0);
            AddLabel(header, "用户名", 4, 0);
            AddLabel(header, "域", 6, 0);
            AddLabel(header, "密码", 8, 0);

            _hostText.Dock = DockStyle.Fill;
            _hostText.PlaceholderTextCompat("服务器地址或 IP，可带端口");
            _hostText.TextChanged += (_, __) => UpdateActionState();
            _hostText.Leave += (_, __) => TryApplyPortFromHost(true);
            StyleTextBox(_hostText);
            header.Controls.Add(_hostText, 0, 1);
            header.SetColumnSpan(_hostText, 3);

            _portBox.Dock = DockStyle.Fill;
            _portBox.Minimum = 1;
            _portBox.Maximum = 65535;
            _portBox.Value = 3389;
            _portBox.BackColor = SurfaceHigh;
            _portBox.ForeColor = TextPrimary;
            _portBox.BorderStyle = BorderStyle.FixedSingle;
            _portBox.Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);
            _portBox.Margin = new Padding(0, 3, 8, 3);
            _portBox.ValueChanged += (_, __) => UpdateActionState();
            header.Controls.Add(_portBox, 3, 1);

            _userText.Dock = DockStyle.Fill;
            _userText.TextChanged += (_, __) => UpdateActionState();
            StyleTextBox(_userText);
            header.Controls.Add(_userText, 4, 1);
            header.SetColumnSpan(_userText, 2);

            _domainText.Dock = DockStyle.Fill;
            StyleTextBox(_domainText);
            header.Controls.Add(_domainText, 6, 1);
            header.SetColumnSpan(_domainText, 2);

            _passwordText.Dock = DockStyle.Fill;
            _passwordText.UseSystemPasswordChar = true;
            StyleTextBox(_passwordText);
            header.Controls.Add(_passwordText, 8, 1);
            header.SetColumnSpan(_passwordText, 2);

            var options = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                BackColor = Surface,
                Padding = new Padding(0, 4, 0, 0),
            };

            _clipboardBox.Text = "剪贴板";
            _clipboardBox.Checked = true;
            _clipboardBox.AutoSize = true;
            StyleCheckBox(_clipboardBox);
            _smartSizingBox.Text = "自适应窗口";
            _smartSizingBox.Checked = true;
            _smartSizingBox.AutoSize = true;
            _smartSizingBox.CheckedChanged += (_, __) =>
            {
                _rdpSession.SetFitToWindow(_smartSizingBox.Checked);
                UpdateActionState();
            };
            StyleCheckBox(_smartSizingBox);
            _savePasswordBox.Text = "保存密码";
            _savePasswordBox.AutoSize = true;
            _savePasswordBox.CheckedChanged += (_, __) => UpdateActionState();
            StyleCheckBox(_savePasswordBox);
            _showPasswordBox.Text = "显示密码";
            _showPasswordBox.AutoSize = true;
            _showPasswordBox.CheckedChanged += (_, __) => _passwordText.UseSystemPasswordChar = !_showPasswordBox.Checked;
            StyleCheckBox(_showPasswordBox);
            options.Controls.Add(_clipboardBox);
            options.Controls.Add(_smartSizingBox);
            options.Controls.Add(_savePasswordBox);
            options.Controls.Add(_showPasswordBox);
            header.Controls.Add(options, 0, 2);
            header.SetColumnSpan(options, 8);

            var buttons = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                BackColor = Surface,
                Padding = new Padding(0, 1, 0, 0),
            };

            _testConnectionButton.Text = "测试";
            _testConnectionButton.Width = 64;
            _testConnectionButton.Click += (_, __) => TestCurrentEndpoint();
            StyleButton(_testConnectionButton, false);
            _connectButton.Text = "连接";
            _connectButton.Width = 88;
            _connectButton.Click += (_, __) => ConnectRdp();
            StyleButton(_connectButton, true);
            _disconnectButton.Text = "断开";
            _disconnectButton.Width = 92;
            _disconnectButton.Enabled = false;
            _disconnectButton.Click += (_, __) => DisconnectRdp();
            StyleButton(_disconnectButton, false);
            buttons.Controls.Add(_testConnectionButton);
            buttons.Controls.Add(_connectButton);
            buttons.Controls.Add(_disconnectButton);
            header.Controls.Add(buttons, 8, 2);
            header.SetColumnSpan(buttons, 4);

            _rdpSession.Dock = DockStyle.Fill;
            _rdpSession.Margin = new Padding(10, 10, 10, 0);

            _statusLabel.Dock = DockStyle.Fill;
            _statusLabel.TextAlign = ContentAlignment.MiddleLeft;
            _statusLabel.Padding = new Padding(14, 0, 14, 0);
            _statusLabel.BackColor = Surface;
            _statusLabel.ForeColor = TextSecondary;
            _statusLabel.Font = new Font("Consolas", 9F, FontStyle.Regular, GraphicsUnit.Point);
            SetStatus("空闲");

            headerShell.Controls.Add(titleRow, 0, 0);
            headerShell.Controls.Add(header, 0, 1);
            root.Controls.Add(headerShell, 0, 0);
            root.Controls.Add(_rdpSession, 0, 1);
            root.Controls.Add(_statusLabel, 0, 2);
            shell.Controls.Add(BuildSidebar(), 0, 0);
            shell.Controls.Add(root, 1, 0);
            Controls.Add(shell);
        }

        private Control BuildSidebar()
        {
            var sidebar = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                BackColor = Surface,
                Padding = new Padding(12, 12, 12, 12),
                ColumnCount = 1,
                RowCount = 6,
            };
            sidebar.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
            sidebar.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
            sidebar.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            sidebar.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            sidebar.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            sidebar.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));

            var heading = new Label
            {
                Text = "已保存连接",
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleLeft,
                ForeColor = TextPrimary,
                Font = new Font("Segoe UI Semibold", 13F, FontStyle.Bold, GraphicsUnit.Point),
            };

            _profilesList.Dock = DockStyle.Fill;
            _profilesList.BackColor = SurfaceHigh;
            _profilesList.ForeColor = TextPrimary;
            _profilesList.BorderStyle = BorderStyle.FixedSingle;
            _profilesList.Font = new Font("Segoe UI", 9.5F, FontStyle.Regular, GraphicsUnit.Point);
            _profilesList.IntegralHeight = false;
            _profilesList.TabStop = false;
            _profilesList.SelectedIndexChanged += (_, __) => ApplySelectedProfile();
            _profilesList.DoubleClick += (_, __) => ConnectRdp();

            _newProfileButton.Text = "新建";
            _newProfileButton.Width = 56;
            _newProfileButton.Click += (_, __) => NewProfile();
            StyleButton(_newProfileButton, false);
            _saveProfileButton.Text = "保存";
            _saveProfileButton.Width = 64;
            _saveProfileButton.Click += (_, __) => SaveCurrentProfile();
            StyleButton(_saveProfileButton, true);
            _deleteProfileButton.Text = "删除";
            _deleteProfileButton.Width = 64;
            _deleteProfileButton.Click += (_, __) => DeleteSelectedProfile();
            StyleButton(_deleteProfileButton, false);

            var profileButtons = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                BackColor = Surface,
                Padding = new Padding(0, 2, 0, 0),
            };
            profileButtons.Controls.Add(_newProfileButton);
            profileButtons.Controls.Add(_saveProfileButton);
            profileButtons.Controls.Add(_deleteProfileButton);

            _profileSummaryLabel.Dock = DockStyle.Fill;
            _profileSummaryLabel.ForeColor = TextSecondary;
            _profileSummaryLabel.TextAlign = ContentAlignment.MiddleLeft;
            _profileSummaryLabel.Font = new Font("Segoe UI", 8.25F, FontStyle.Regular, GraphicsUnit.Point);

            var hint = new Label
            {
                Text = "双击连接。密码保存在凭据管理器。",
                Dock = DockStyle.Fill,
                ForeColor = TextSecondary,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Segoe UI", 8.25F, FontStyle.Regular, GraphicsUnit.Point),
            };

            _openLogButton.Text = "会话日志";
            _openLogButton.Dock = DockStyle.Fill;
            _openLogButton.Click += (_, __) => OpenSessionLog();
            StyleButton(_openLogButton, false);

            sidebar.Controls.Add(heading, 0, 0);
            sidebar.Controls.Add(_profileSummaryLabel, 0, 1);
            sidebar.Controls.Add(_profilesList, 0, 2);
            sidebar.Controls.Add(profileButtons, 0, 3);
            sidebar.Controls.Add(_openLogButton, 0, 4);
            sidebar.Controls.Add(hint, 0, 5);
            return sidebar;
        }

        private void WireInputShortcuts()
        {
            WireConnectOnEnter(_hostText);
            WireConnectOnEnter(_userText);
            WireConnectOnEnter(_domainText);
            WireConnectOnEnter(_passwordText);

            _toolTip.SetToolTip(_testConnectionButton, "连接前先检查主机和端口是否可达。快捷键：F6");
            _toolTip.SetToolTip(_connectButton, "开始远程桌面连接。快捷键：F5");
            _toolTip.SetToolTip(_saveProfileButton, "保存当前连接。快捷键：Ctrl+S");
            _toolTip.SetToolTip(_showPasswordBox, "临时显示密码。");
            _toolTip.SetToolTip(_savePasswordBox, "把该连接的密码保存到 Windows 凭据管理器。");
        }

        private void WireConnectOnEnter(TextBox textBox)
        {
            textBox.KeyDown += (_, e) =>
            {
                if (e.KeyCode == Keys.Enter)
                {
                    e.SuppressKeyPress = true;
                    ConnectRdp();
                }
            };
        }

        private void ApplyOptions()
        {
            if (!string.IsNullOrWhiteSpace(_options.Host))
            {
                _hostText.Text = _options.Host;
            }
            if (_options.Port >= 1 && _options.Port <= 65535)
            {
                _portBox.Value = _options.Port;
            }
            if (!string.IsNullOrWhiteSpace(_options.User))
            {
                _userText.Text = _options.User;
            }
            if (!string.IsNullOrWhiteSpace(_options.Domain))
            {
                _domainText.Text = _options.Domain;
            }
            _clipboardBox.Checked = _options.Clipboard;
            _smartSizingBox.Checked = _options.SmartSizing;
            TryApplyPortFromHost(false);
            UpdateActionState();
        }

        private void UpdateActionState()
        {
            var hasHost = !string.IsNullOrWhiteSpace(_hostText.Text);
            var hasUser = !string.IsNullOrWhiteSpace(_userText.Text);
            var canStart = hasHost && hasUser && !_connectionBusy && !_rdpSession.IsConnected;

            _testConnectionButton.Enabled = hasHost && !_tcpTestBusy;
            _connectButton.Enabled = canStart;
            _disconnectButton.Enabled = _connectionBusy || _rdpSession.IsConnected;
            _saveProfileButton.Enabled = hasHost && hasUser;
            _deleteProfileButton.Enabled = _selectedProfile != null;
        }

        private void TryApplyPortFromHost(bool notify)
        {
            var host = _hostText.Text.Trim();
            if (string.IsNullOrWhiteSpace(host))
            {
                return;
            }

            var firstColon = host.IndexOf(':');
            var lastColon = host.LastIndexOf(':');
            if (firstColon <= 0 || firstColon != lastColon || lastColon >= host.Length - 1)
            {
                return;
            }

            var portText = host.Substring(lastColon + 1);
            int port;
            if (!int.TryParse(portText, out port) || port < 1 || port > 65535)
            {
                return;
            }

            _hostText.Text = host.Substring(0, lastColon);
            _portBox.Value = port;
            if (notify)
            {
                SetStatus("已从主机栏识别端口：" + port);
            }
        }

        private void LoadProfiles()
        {
            _profiles.Clear();
            foreach (var profile in _connectionStore.Load())
            {
                _profiles.Add(profile);
            }

            RefreshProfileList(null);
            Log("Loaded connection profiles: " + _profiles.Count);
        }

        private void RefreshProfileList(string selectedId)
        {
            _loadingProfile = true;
            try
            {
                _profilesList.Items.Clear();
                ConnectionProfile selected = null;
                var visibleProfiles = new List<ConnectionProfile>(_profiles);
                visibleProfiles.Sort(CompareProfiles);
                var shown = 0;

                foreach (var profile in visibleProfiles)
                {
                    shown++;
                    _profilesList.Items.Add(profile);
                    if (!string.IsNullOrWhiteSpace(selectedId) &&
                        string.Equals(profile.Id, selectedId, StringComparison.OrdinalIgnoreCase))
                    {
                        selected = profile;
                    }
                }

                if (selected != null)
                {
                    _profilesList.SelectedItem = selected;
                }

                UpdateProfileSummary(shown, _profiles.Count);
            }
            finally
            {
                _loadingProfile = false;
            }

            if (_profilesList.SelectedItem == null)
            {
                _selectedProfile = null;
                RefreshProfileSummary();
            }
            UpdateActionState();
        }

        private string CurrentSelectedProfileId()
        {
            var profile = _selectedProfile ?? _profilesList.SelectedItem as ConnectionProfile;
            return profile == null ? null : profile.Id;
        }

        private void UpdateProfileSummary(int shown, int total)
        {
            if (total == 0)
            {
                _profileSummaryLabel.Text = "还没有保存的连接。";
                return;
            }

            if (shown == 0)
            {
                _profileSummaryLabel.Text = "没有可显示的连接。";
                return;
            }

            var text = shown == total
                ? "已保存 " + total + " 个"
                : "显示 " + shown + " / " + total + " 个";
            var last = SelectedLastConnectedText();
            _profileSummaryLabel.Text = string.IsNullOrWhiteSpace(last)
                ? text
                : text + " - " + last;
        }

        private void RefreshProfileSummary()
        {
            UpdateProfileSummary(_profilesList.Items.Count, _profiles.Count);
        }

        private string SelectedLastConnectedText()
        {
            if (_selectedProfile == null || string.IsNullOrWhiteSpace(_selectedProfile.LastConnectedAtUtc))
            {
                return "";
            }

            DateTime parsed;
            if (!DateTime.TryParse(_selectedProfile.LastConnectedAtUtc, out parsed))
            {
                return "";
            }

            return "上次 " + parsed.ToLocalTime().ToString("yyyy-MM-dd HH:mm");
        }

        private static int CompareProfiles(ConnectionProfile left, ConnectionProfile right)
        {
            if (left == null && right == null)
            {
                return 0;
            }
            if (left == null)
            {
                return 1;
            }
            if (right == null)
            {
                return -1;
            }

            var leftLast = ParseProfileTime(left.LastConnectedAtUtc);
            var rightLast = ParseProfileTime(right.LastConnectedAtUtc);
            var lastConnected = Nullable.Compare(rightLast, leftLast);
            if (lastConnected != 0)
            {
                return lastConnected;
            }

            return string.Compare(left.Name, right.Name, StringComparison.OrdinalIgnoreCase);
        }

        private static DateTime? ParseProfileTime(string value)
        {
            DateTime parsed;
            if (DateTime.TryParse(value, out parsed))
            {
                return parsed;
            }

            return null;
        }

        private void ApplySelectedProfile()
        {
            if (_loadingProfile)
            {
                return;
            }

            var profile = _profilesList.SelectedItem as ConnectionProfile;
            if (profile == null)
            {
                _selectedProfile = null;
                RefreshProfileSummary();
                UpdateActionState();
                return;
            }

            _loadingProfile = true;
            try
            {
                _selectedProfile = profile;
                _hostText.Text = profile.Host;
                _portBox.Value = Math.Min(Math.Max(profile.Port, 1), 65535);
                _userText.Text = profile.Username;
                _domainText.Text = profile.Domain ?? "";
                _clipboardBox.Checked = profile.Clipboard;
                _smartSizingBox.Checked = profile.SmartSizing;
                _savePasswordBox.Checked = CredentialVault.HasPassword(profile.CredentialTarget);
                _passwordText.Clear();
            }
            finally
            {
                _loadingProfile = false;
            }

            SetStatus("已选择连接：" + profile.Name +
                (_savePasswordBox.Checked ? "（已保存密码）" : ""));
            RefreshProfileSummary();
            UpdateActionState();
        }

        private void NewProfile()
        {
            _loadingProfile = true;
            try
            {
                _profilesList.ClearSelected();
                _selectedProfile = null;
                _hostText.Clear();
                _portBox.Value = 3389;
                _userText.Clear();
                _domainText.Clear();
                _passwordText.Clear();
                _clipboardBox.Checked = true;
                _smartSizingBox.Checked = true;
                _savePasswordBox.Checked = false;
            }
            finally
            {
                _loadingProfile = false;
            }

            SetStatus("新建连接");
            RefreshProfileSummary();
            UpdateActionState();
            _hostText.Focus();
        }

        private bool SaveCurrentProfile()
        {
            TryApplyPortFromHost(true);
            var host = _hostText.Text.Trim();
            if (string.IsNullOrWhiteSpace(host))
            {
                SetStatus("保存前需要填写主机。");
                _hostText.Focus();
                return false;
            }

            var user = _userText.Text.Trim();
            if (string.IsNullOrWhiteSpace(user))
            {
                SetStatus("保存前需要填写用户名。");
                _userText.Focus();
                return false;
            }

            try
            {
                var profile = _selectedProfile;
                var isNewProfile = profile == null;
                var previousHost = profile == null ? "" : profile.Host;
                var previousName = profile == null ? "" : profile.Name;
                if (profile == null)
                {
                    profile = new ConnectionProfile
                    {
                        Id = Guid.NewGuid().ToString("N"),
                        CreatedAtUtc = DateTime.UtcNow.ToString("O"),
                    };
                    _profiles.Add(profile);
                }

                if (ShouldUseDefaultProfileName(isNewProfile, previousName, previousHost))
                {
                    profile.Name = DefaultProfileName(host, user);
                }
                profile.Host = host;
                profile.Port = decimal.ToInt32(_portBox.Value);
                profile.Username = user;
                profile.Domain = _domainText.Text.Trim();
                profile.Group = profile.Group ?? "";
                profile.Notes = profile.Notes ?? "";
                profile.Clipboard = _clipboardBox.Checked;
                profile.SmartSizing = _smartSizingBox.Checked;
                profile.UpdatedAtUtc = DateTime.UtcNow.ToString("O");

                var credentialProtected = false;
                if (_savePasswordBox.Checked)
                {
                    if (!string.IsNullOrEmpty(_passwordText.Text))
                    {
                        CredentialVault.SavePassword(
                            profile.CredentialTarget,
                            _passwordText.Text,
                            profile.Name);
                    }
                    credentialProtected = CredentialVault.HasPassword(profile.CredentialTarget);
                }
                else
                {
                    CredentialVault.DeletePassword(profile.CredentialTarget);
                }

                _connectionStore.Save(_profiles);
                _selectedProfile = profile;
                RefreshProfileList(profile.Id);
                SetStatus("已保存连接：" + profile.Name +
                    (credentialProtected ? "（密码已保护）" : ""));
                UpdateActionState();
                return true;
            }
            catch (Exception ex)
            {
                Log("Save profile failed: " + ex);
                SetStatus("保存连接失败：" + ex.Message);
                UpdateActionState();
                return false;
            }
        }

        private static bool ShouldUseDefaultProfileName(bool isNewProfile, string previousName, string previousHost)
        {
            if (isNewProfile || string.IsNullOrWhiteSpace(previousName))
            {
                return true;
            }

            if (string.Equals(previousName, previousHost, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            return previousName.EndsWith(" @ " + previousHost, StringComparison.OrdinalIgnoreCase);
        }

        private static string DefaultProfileName(string host, string user)
        {
            return string.IsNullOrWhiteSpace(user) ? host : user + " @ " + host;
        }

        private void DeleteSelectedProfile()
        {
            var profile = _selectedProfile;
            if (profile == null)
            {
                SetStatus("没有选择连接。");
                return;
            }

            var result = MessageBox.Show(
                this,
                "删除连接“" + profile.Name + "”？",
                "NexTerm",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning);
            if (result != DialogResult.Yes)
            {
                return;
            }

            try
            {
                CredentialVault.DeletePassword(profile.CredentialTarget);
                _profiles.Remove(profile);
                _connectionStore.Save(_profiles);
                RefreshProfileList(null);
                NewProfile();
                SetStatus("已删除连接：" + profile.Name);
                UpdateActionState();
            }
            catch (Exception ex)
            {
                Log("Delete profile failed: " + ex);
                SetStatus("删除连接失败：" + ex.Message);
            }
        }

        private static string CurrentSessionLogPath()
        {
            return SessionLog.Path;
        }

        private void TestCurrentEndpoint()
        {
            TryApplyPortFromHost(true);
            var host = _hostText.Text.Trim();
            if (string.IsNullOrWhiteSpace(host))
            {
                SetStatus("测试前需要填写主机。");
                _hostText.Focus();
                return;
            }

            var port = decimal.ToInt32(_portBox.Value);
            _tcpTestBusy = true;
            UpdateActionState();
            SetStatus("正在测试 TCP " + host + ":" + port + "...");

            ThreadPool.QueueUserWorkItem(_ =>
            {
                var ok = RdpSessionControl.CanOpenTcpEndpoint(host, port, 3000);
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        _tcpTestBusy = false;
                        SetStatus(ok
                            ? "TCP 测试通过：" + host + ":" + port
                            : "TCP 测试失败：" + host + ":" + port);
                        UpdateActionState();
                    }));
                }
                catch (ObjectDisposedException)
                {
                }
                catch (InvalidOperationException)
                {
                }
            });
        }

        private void OpenSessionLog()
        {
            try
            {
                var path = CurrentSessionLogPath();
                if (!File.Exists(path))
                {
                    File.WriteAllText(path, "");
                }
                Process.Start("notepad.exe", path);
            }
            catch (Exception ex)
            {
                SetStatus("打开日志失败：" + ex.Message);
            }
        }

        private static void AddLabel(TableLayoutPanel panel, string text, int column, int row)
        {
            panel.Controls.Add(new Label
            {
                Text = text,
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.BottomLeft,
                ForeColor = TextSecondary,
                Font = new Font("Segoe UI", 8.5F, FontStyle.Regular, GraphicsUnit.Point),
            }, column, row);
        }

        private static void StyleTextBox(TextBox textBox)
        {
            textBox.BorderStyle = BorderStyle.FixedSingle;
            textBox.BackColor = SurfaceHigh;
            textBox.ForeColor = TextPrimary;
            textBox.Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);
            textBox.Margin = new Padding(0, 3, 8, 3);
        }

        private static void StyleCheckBox(CheckBox checkBox)
        {
            checkBox.ForeColor = TextSecondary;
            checkBox.FlatStyle = FlatStyle.Flat;
            checkBox.TabStop = false;
            checkBox.Margin = new Padding(0, 2, 14, 0);
        }

        private static void StyleButton(Button button, bool primary)
        {
            button.Height = 30;
            button.FlatStyle = FlatStyle.Flat;
            button.TabStop = false;
            button.FlatAppearance.BorderSize = 1;
            button.FlatAppearance.BorderColor = primary ? Accent : Border;
            button.BackColor = primary ? Accent : SurfaceHigh;
            button.ForeColor = primary ? Color.Black : TextPrimary;
            button.Font = new Font("Segoe UI Semibold", 9F, FontStyle.Bold, GraphicsUnit.Point);
            button.Margin = new Padding(0, 4, 8, 0);
            button.UseVisualStyleBackColor = false;
        }

        private void ConnectRdp()
        {
            if (_connectionBusy || _rdpSession.IsConnected)
            {
                return;
            }

            TryApplyPortFromHost(true);
            var host = _hostText.Text.Trim();
            var user = _userText.Text.Trim();
            var domain = _domainText.Text.Trim();
            var password = _passwordText.Text;
            if (string.IsNullOrEmpty(password) &&
                _selectedProfile != null &&
                _savePasswordBox.Checked)
            {
                password = CredentialVault.ReadPassword(_selectedProfile.CredentialTarget) ?? "";
                if (!string.IsNullOrEmpty(password))
                {
                    Log("Using saved credential for profile: " + _selectedProfile.Id);
                }
            }

            if (string.IsNullOrWhiteSpace(host))
            {
                SetStatus("需要填写主机。");
                _hostText.Focus();
                UpdateActionState();
                return;
            }
            if (string.IsNullOrWhiteSpace(user))
            {
                SetStatus("需要填写用户名。");
                _userText.Focus();
                UpdateActionState();
                return;
            }

            try
            {
                if (_savePasswordBox.Checked && !SaveCurrentProfile())
                {
                    return;
                }

                if (string.IsNullOrEmpty(password) &&
                    _selectedProfile != null &&
                    _savePasswordBox.Checked)
                {
                    password = CredentialVault.ReadPassword(_selectedProfile.CredentialTarget) ?? "";
                }

                var port = decimal.ToInt32(_portBox.Value);
                var request = new RdpConnectionRequest
                {
                    Host = host,
                    Port = port,
                    Username = user,
                    Domain = domain,
                    Password = password,
                    Clipboard = _clipboardBox.Checked,
                    SmartSizing = _smartSizingBox.Checked,
                };

                _connectionBusy = true;
                UpdateActionState();
                if (!_rdpSession.Connect(request))
                {
                    _connectionBusy = false;
                    MarkSelectedProfileResult("连接失败");
                    UpdateActionState();
                }
            }
            catch (Exception ex)
            {
                _connectionBusy = false;
                UpdateActionState();
                MarkSelectedProfileResult("连接失败");
                Log("Connect failed: " + ex);
                SetStatus("连接失败：" + ex.Message);
            }
        }

        private void DisconnectRdp()
        {
            _connectionBusy = false;
            _rdpSession.Disconnect();
            UpdateActionState();
        }

        private void SetConnectionButtons(bool connected)
        {
            _connectionBusy = false;
            UpdateActionState();
        }

        private void HandleLoginComplete()
        {
            if (_selectedProfile != null)
            {
                if (_savePasswordBox.Checked && !string.IsNullOrEmpty(_passwordText.Text))
                {
                    try
                    {
                        CredentialVault.SavePassword(
                            _selectedProfile.CredentialTarget,
                            _passwordText.Text,
                            _selectedProfile.Name);
                    }
                    catch (Exception ex)
                    {
                        Log("Save credential after login failed: " + ex.Message);
                    }
                }

                _selectedProfile.LastConnectedAtUtc = DateTime.UtcNow.ToString("O");
                _selectedProfile.LastResult = "已连接";
                _selectedProfile.UpdatedAtUtc = DateTime.UtcNow.ToString("O");
                _connectionStore.Save(_profiles);
                RefreshProfileList(_selectedProfile.Id);
                RefreshProfileSummary();
            }
        }

        private void MarkSelectedProfileResult(string result)
        {
            if (_selectedProfile == null)
            {
                return;
            }

            _selectedProfile.LastResult = result;
            _selectedProfile.UpdatedAtUtc = DateTime.UtcNow.ToString("O");
            _connectionStore.Save(_profiles);
            RefreshProfileList(_selectedProfile.Id);
        }

        private void SetStatus(string message)
        {
            _statusLabel.Text = DateTime.Now.ToString("HH:mm:ss") + "  " + message;
            Log("STATUS " + message);
        }

        private static void Log(string message)
        {
            SessionLog.Write(message);
        }

        private sealed class CleanButton : Button
        {
            public CleanButton()
            {
                TabStop = false;
            }

            protected override bool ShowFocusCues
            {
                get { return false; }
            }

            public override void NotifyDefault(bool value)
            {
                base.NotifyDefault(false);
            }
        }

        private sealed class CleanCheckBox : CheckBox
        {
            public CleanCheckBox()
            {
                TabStop = false;
            }

            protected override bool ShowFocusCues
            {
                get { return false; }
            }
        }

        private sealed class CleanListBox : ListBox
        {
            public CleanListBox()
            {
                DrawMode = DrawMode.OwnerDrawFixed;
                ItemHeight = 30;
                TabStop = false;
                SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            }

            protected override bool ShowFocusCues
            {
                get { return false; }
            }

            protected override void OnDrawItem(DrawItemEventArgs e)
            {
                if (e.Index < 0)
                {
                    return;
                }

                var selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
                using (var background = new SolidBrush(selected ? Color.FromArgb(43, 56, 66) : BackColor))
                {
                    e.Graphics.FillRectangle(background, e.Bounds);
                }

                var text = GetItemText(Items[e.Index]);
                var textBounds = new Rectangle(
                    e.Bounds.Left + 8,
                    e.Bounds.Top,
                    Math.Max(0, e.Bounds.Width - 16),
                    e.Bounds.Height);
                TextRenderer.DrawText(
                    e.Graphics,
                    text,
                    Font,
                    textBounds,
                    selected ? TextPrimary : ForeColor,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }

            protected override void OnGotFocus(EventArgs e)
            {
                base.OnGotFocus(e);
                Invalidate();
            }

            protected override void OnLostFocus(EventArgs e)
            {
                base.OnLostFocus(e);
                Invalidate();
            }
        }
    }

    internal static class TextBoxCompat
    {
        public static void PlaceholderTextCompat(this TextBox textBox, string text)
        {
            if (Environment.OSVersion.Version.Major < 10)
            {
                return;
            }

            NativeMethods.SendMessage(textBox.Handle, 0x1501, IntPtr.Zero, text);
        }
    }

    internal static class NativeMethods
    {
        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
    }
}
