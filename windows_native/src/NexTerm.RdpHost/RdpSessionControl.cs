using System;
using System.Drawing;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Windows.Forms;
using AxMSTSCLib;

namespace NexTerm.RdpHost
{
    internal sealed class RdpSessionControl : UserControl
    {
        private const int MinimumDesktopWidth = 320;
        private const int MinimumDesktopHeight = 240;

        private readonly Panel _hostPanel = new Panel();
        private readonly Label _emptyStateLabel = new Label();
        private readonly Timer _displayUpdateTimer = new Timer();

        private Control _rdpControl;
        private object _rdp;
        private bool _connected;
        private bool _fitToWindow;
        private bool _displayUpdateUnsupported;
        private Size _lastDisplaySize = Size.Empty;
        private string _activeControlName = "";

        public event EventHandler<RdpSessionStatusEventArgs> StatusChanged;
        public event EventHandler Connected;
        public event EventHandler LoginCompleted;
        public event EventHandler Disconnected;

        public RdpSessionControl()
        {
            Dock = DockStyle.Fill;
            BackColor = Color.Black;

            _hostPanel.Dock = DockStyle.Fill;
            _hostPanel.BackColor = Color.Black;
            _hostPanel.Resize += (_, __) => QueueDisplayUpdate();

            _displayUpdateTimer.Interval = 250;
            _displayUpdateTimer.Tick += (_, __) =>
            {
                _displayUpdateTimer.Stop();
                ApplyDisplayUpdate();
            };

            _emptyStateLabel.Dock = DockStyle.Fill;
            _emptyStateLabel.TextAlign = ContentAlignment.MiddleCenter;
            _emptyStateLabel.Text = "填写连接信息后点击连接";
            _emptyStateLabel.ForeColor = Color.FromArgb(92, 104, 116);
            _emptyStateLabel.Font = new Font("Segoe UI", 13F, FontStyle.Regular, GraphicsUnit.Point);
            _hostPanel.Controls.Add(_emptyStateLabel);

            Controls.Add(_hostPanel);
            RecreateRdpControl();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _displayUpdateTimer.Dispose();
            }

            base.Dispose(disposing);
        }

        public bool IsConnected
        {
            get { return _connected; }
        }

        public string ActiveControlName
        {
            get { return _activeControlName; }
        }

        public bool Connect(RdpConnectionRequest request)
        {
            if (request == null)
            {
                SetStatus("缺少连接请求。");
                return false;
            }

            if (!CanOpenTcpEndpoint(request.Host, request.Port, 3000))
            {
                SetStatus("TCP 测试失败：" + request.Host + ":" + request.Port);
                return false;
            }

            try
            {
                Disconnect();
                RecreateRdpControl();
                _fitToWindow = request.SmartSizing;
                _displayUpdateUnsupported = false;
                _lastDisplaySize = Size.Empty;

                var desktopSize = CurrentDesktopSize();

                SetIfExists(_rdp, "Server", request.Host);
                SetIfExists(_rdp, "UserName", request.Username);
                SetIfExists(_rdp, "Domain", request.Domain ?? "");
                SetIfExists(_rdp, "DesktopWidth", desktopSize.Width);
                SetIfExists(_rdp, "DesktopHeight", desktopSize.Height);
                SetIfExists(_rdp, "ColorDepth", 32);

                var advanced = GetAdvancedSettings(_rdp);
                SessionLog.Write("Connecting host=" + request.Host +
                    " port=" + request.Port +
                    " user=" + request.Username +
                    " domain=" + (request.Domain ?? "") +
                    " control=" + _activeControlName +
                    " clipboard=" + request.Clipboard +
                    " smartSizing=" + request.SmartSizing);
                ConfigureAdvancedSettings(
                    advanced,
                    request.Port,
                    request.Password ?? "",
                    request.Clipboard,
                    request.SmartSizing);

                SetStatus("正在连接 " + request.Host + ":" + request.Port + "...");
                _emptyStateLabel.Visible = false;
                _rdpControl.Visible = true;
                _rdpControl.BringToFront();
                Call(_rdp, "Connect");
                return true;
            }
            catch (Exception ex)
            {
                SessionLog.Write("Connect failed: " + ex);
                SetStatus("连接失败：" + ex.Message);
                return false;
            }
        }

        public void SetFitToWindow(bool enabled)
        {
            _fitToWindow = enabled;
            var advanced = GetAdvancedSettings(_rdp);
            ConfigureSmartSizing(advanced, enabled);
            SetIfExists(_rdp, "SmartSizing", enabled);

            if (enabled)
            {
                QueueDisplayUpdate();
            }
            else
            {
                _displayUpdateTimer.Stop();
            }
        }

        public void Disconnect()
        {
            if (_rdp == null)
            {
                return;
            }

            try
            {
                if (_connected || (_rdpControl != null && _rdpControl.Visible))
                {
                    SessionLog.Write("Disconnecting.");
                    Call(_rdp, "Disconnect");
                }
            }
            catch (Exception ex)
            {
                SessionLog.Write("Disconnect failed: " + ex);
                SetStatus("断开失败：" + ex.Message);
            }
            finally
            {
                _connected = false;
                if (_rdpControl != null)
                {
                    _rdpControl.Visible = false;
                    _emptyStateLabel.Visible = true;
                }
            }
        }

        private void RecreateRdpControl()
        {
            if (_rdpControl != null)
            {
                _hostPanel.Controls.Remove(_rdpControl);
                _rdpControl.Dispose();
                _rdpControl = null;
                _rdp = null;
            }

            var errors = new StringBuilder();
            foreach (var type in RdpControlCandidates())
            {
                Control control = null;
                try
                {
                    control = (Control)Activator.CreateInstance(type);
                    ((System.ComponentModel.ISupportInitialize)control).BeginInit();
                    control.Dock = DockStyle.Fill;
                    control.Enabled = true;
                    control.Visible = false;
                    _hostPanel.Controls.Add(control);
                    ((System.ComponentModel.ISupportInitialize)control).EndInit();
                    control.SendToBack();

                    _rdpControl = control;
                    _rdp = control;
                    _activeControlName = type.Name;
                    SubscribeRdpEvents(_rdp);
                    SetStatus("使用 " + type.Name);
                    SessionLog.Write("Created RDP control: " + type.FullName);
                    return;
                }
                catch (Exception ex)
                {
                    if (control != null)
                    {
                        _hostPanel.Controls.Remove(control);
                        control.Dispose();
                    }
                    errors.AppendLine(type.Name + ": " + ex.Message);
                    SessionLog.Write("RDP control candidate failed: " + type.Name + " :: " + ex.Message);
                }
            }

            throw new InvalidOperationException(
                "无法创建 MSTSCAX ActiveX 控件。" + Environment.NewLine + errors);
        }

        private static Type[] RdpControlCandidates()
        {
            return new[]
            {
                typeof(AxMsRdpClient12NotSafeForScripting),
                typeof(AxMsRdpClient11NotSafeForScripting),
                typeof(AxMsRdpClient10NotSafeForScripting),
                typeof(AxMsRdpClient9NotSafeForScripting),
                typeof(AxMsRdpClient8NotSafeForScripting),
                typeof(AxMsRdpClient7NotSafeForScripting),
                typeof(AxMsRdpClient6NotSafeForScripting),
                typeof(AxMsRdpClient5NotSafeForScripting),
                typeof(AxMsRdpClient4NotSafeForScripting),
                typeof(AxMsRdpClient3NotSafeForScripting),
                typeof(AxMsRdpClient2NotSafeForScripting),
                typeof(AxMsRdpClientNotSafeForScripting),
                typeof(AxMsTscAxNotSafeForScripting),
            };
        }

        private void SubscribeRdpEvents(object target)
        {
            Subscribe(target, "OnConnecting", "OnRdpConnecting");
            Subscribe(target, "OnConnected", "OnRdpConnected");
            Subscribe(target, "OnLoginComplete", "OnRdpLoginComplete");
            Subscribe(target, "OnDisconnected", "OnRdpDisconnected");
            Subscribe(target, "OnFatalError", "OnRdpFatalError");
            Subscribe(target, "OnWarning", "OnRdpWarning");
        }

        private void Subscribe(object target, string eventName, string methodName)
        {
            var eventInfo = target.GetType().GetEvent(eventName);
            if (eventInfo == null)
            {
                return;
            }

            var handler = Delegate.CreateDelegate(
                eventInfo.EventHandlerType,
                this,
                GetType().GetMethod(methodName, BindingFlags.Instance | BindingFlags.NonPublic));
            eventInfo.AddEventHandler(target, handler);
        }

        private void OnRdpConnecting(object sender, EventArgs e)
        {
            SetStatus("正在连接...");
        }

        private void OnRdpConnected(object sender, EventArgs e)
        {
            _connected = true;
            SetStatus("已连接：" + _activeControlName);
            QueueDisplayUpdate();
            var handler = Connected;
            if (handler != null)
            {
                handler(this, EventArgs.Empty);
            }
        }

        private void OnRdpLoginComplete(object sender, EventArgs e)
        {
            SetStatus("登录完成");
            QueueDisplayUpdate();
            var handler = LoginCompleted;
            if (handler != null)
            {
                handler(this, EventArgs.Empty);
            }
        }

        private void OnRdpDisconnected(object sender, object e)
        {
            _connected = false;
            if (_rdpControl != null)
            {
                _rdpControl.Visible = false;
                _emptyStateLabel.Visible = true;
            }

            var reason = ReadEventValue(e, "discReason");
            var extended = GetProperty(_rdp, "ExtendedDisconnectReason");
            var description = GetErrorDescription(reason, extended);
            SetStatus("已断开。reason=" + reason +
                " extended=" + (extended ?? "") +
                (string.IsNullOrWhiteSpace(description) ? "" : " " + description));

            var handler = Disconnected;
            if (handler != null)
            {
                handler(this, EventArgs.Empty);
            }
        }

        private void OnRdpFatalError(object sender, object e)
        {
            SetStatus("严重错误。code=" + ReadEventValue(e, "errorCode"));
        }

        private void OnRdpWarning(object sender, object e)
        {
            SetStatus("警告。code=" + ReadEventValue(e, "warningCode"));
        }

        private Size CurrentDesktopSize()
        {
            return new Size(
                Math.Max(MinimumDesktopWidth, _hostPanel.ClientSize.Width),
                Math.Max(MinimumDesktopHeight, _hostPanel.ClientSize.Height));
        }

        private void QueueDisplayUpdate()
        {
            if (!_fitToWindow || !_connected || _displayUpdateUnsupported)
            {
                return;
            }

            _displayUpdateTimer.Stop();
            _displayUpdateTimer.Start();
        }

        private void ApplyDisplayUpdate()
        {
            if (!_fitToWindow || !_connected || _rdp == null || _displayUpdateUnsupported)
            {
                return;
            }

            var size = CurrentDesktopSize();
            if (size == _lastDisplaySize)
            {
                return;
            }

            if (TryUpdateSessionDisplaySettings(size.Width, size.Height))
            {
                _lastDisplaySize = size;
            }
        }

        private bool TryUpdateSessionDisplaySettings(int width, int height)
        {
            var args = new object[] { (uint)width, (uint)height, (uint)width, (uint)height, 0U, 100U, 100U };
            if (TryInvoke(_rdp, "UpdateSessionDisplaySettings", args))
            {
                SessionLog.Write("Updated session display settings: " + width + "x" + height);
                return true;
            }

            args = new object[] { width, height, width, height, 0, 100, 100 };
            if (TryInvoke(_rdp, "UpdateSessionDisplaySettings", args))
            {
                SessionLog.Write("Updated session display settings: " + width + "x" + height);
                return true;
            }

            _displayUpdateUnsupported = true;
            SessionLog.Write("UpdateSessionDisplaySettings is unavailable; SmartSizing fallback remains enabled.");
            return false;
        }

        private void SetStatus(string message)
        {
            SessionLog.Write("STATUS " + message);
            var handler = StatusChanged;
            if (handler != null)
            {
                handler(this, new RdpSessionStatusEventArgs(message));
            }
        }

        public static bool CanOpenTcpEndpoint(string host, int port, int timeoutMs)
        {
            try
            {
                using (var client = new TcpClient())
                {
                    var result = client.BeginConnect(host, port, null, null);
                    var connected = result.AsyncWaitHandle.WaitOne(timeoutMs);
                    if (!connected)
                    {
                        return false;
                    }

                    client.EndConnect(result);
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }

        private static void SetIfExists(object target, string propertyName, object value)
        {
            if (target == null)
            {
                return;
            }

            var property = target.GetType().GetProperty(
                propertyName,
                BindingFlags.Instance | BindingFlags.Public);
            if (property == null || !property.CanWrite)
            {
                try
                {
                    target.GetType().InvokeMember(
                        propertyName,
                        BindingFlags.Instance | BindingFlags.Public | BindingFlags.SetProperty,
                        null,
                        target,
                        new[] { value });
                    if (!propertyName.ToLowerInvariant().Contains("password"))
                    {
                        SessionLog.Write("Set COM property: " + propertyName + "=" + value);
                    }
                    return;
                }
                catch (Exception ex)
                {
                    SessionLog.Write("Skipped unsupported property: " + propertyName +
                        " on " + target.GetType().FullName + " :: " + ex.Message);
                    return;
                }
            }

            property.SetValue(target, value, null);
            if (!propertyName.ToLowerInvariant().Contains("password"))
            {
                SessionLog.Write("Set property: " + propertyName + "=" + value);
            }
        }

        private static void ConfigureAdvancedSettings(
            object advanced,
            int port,
            string password,
            bool clipboard,
            bool smartSizing)
        {
            if (advanced == null)
            {
                SessionLog.Write("Advanced RDP settings are unavailable.");
                return;
            }

            SessionLog.Write("Advanced settings object: " + advanced.GetType().FullName);

            var advanced8 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings8;
            if (advanced8 != null)
            {
                advanced8.RDPPort = port;
                advanced8.ClearTextPassword = password;
                advanced8.EnableCredSspSupport = true;
                advanced8.RedirectClipboard = clipboard;
                ConfigureSmartSizing(advanced8, smartSizing);
                SessionLog.Write("Configured advanced settings via IMsRdpClientAdvancedSettings8.");
                return;
            }

            var advanced7 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings7;
            if (advanced7 != null)
            {
                advanced7.RDPPort = port;
                advanced7.ClearTextPassword = password;
                advanced7.EnableCredSspSupport = true;
                advanced7.RedirectClipboard = clipboard;
                ConfigureSmartSizing(advanced7, smartSizing);
                SessionLog.Write("Configured advanced settings via IMsRdpClientAdvancedSettings7.");
                return;
            }

            var advanced6 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings6;
            if (advanced6 != null)
            {
                advanced6.RDPPort = port;
                advanced6.ClearTextPassword = password;
                advanced6.EnableCredSspSupport = true;
                advanced6.RedirectClipboard = clipboard;
                ConfigureSmartSizing(advanced6, smartSizing);
                SessionLog.Write("Configured advanced settings via IMsRdpClientAdvancedSettings6.");
                return;
            }

            var advanced5 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings5;
            if (advanced5 != null)
            {
                advanced5.RDPPort = port;
                advanced5.ClearTextPassword = password;
                advanced5.RedirectClipboard = clipboard;
                ConfigureSmartSizing(advanced5, smartSizing);
                SessionLog.Write("Configured advanced settings via IMsRdpClientAdvancedSettings5.");
                return;
            }

            var advancedBase = advanced as MSTSCLib.IMsRdpClientAdvancedSettings;
            if (advancedBase != null)
            {
                advancedBase.RDPPort = port;
                advancedBase.ClearTextPassword = password;
                ConfigureSmartSizing(advancedBase, smartSizing);
                SessionLog.Write("Configured advanced settings via IMsRdpClientAdvancedSettings.");
                return;
            }

            SetIfExists(advanced, "RDPPort", port);
            SetIfExists(advanced, "ClearTextPassword", password);
            SetIfExists(advanced, "EnableCredSspSupport", true);
            SetIfExists(advanced, "RedirectClipboard", clipboard);
            SetIfExists(advanced, "SmartSizing", smartSizing);
            SessionLog.Write("Configured advanced settings through COM dispatch fallback.");
        }

        private static void ConfigureSmartSizing(object advanced, bool smartSizing)
        {
            if (advanced == null)
            {
                return;
            }

            var advanced8 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings8;
            if (advanced8 != null)
            {
                advanced8.SmartSizing = smartSizing;
                return;
            }

            var advanced7 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings7;
            if (advanced7 != null)
            {
                advanced7.SmartSizing = smartSizing;
                return;
            }

            var advanced6 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings6;
            if (advanced6 != null)
            {
                advanced6.SmartSizing = smartSizing;
                return;
            }

            var advanced5 = advanced as MSTSCLib.IMsRdpClientAdvancedSettings5;
            if (advanced5 != null)
            {
                advanced5.SmartSizing = smartSizing;
                return;
            }

            var advancedBase = advanced as MSTSCLib.IMsRdpClientAdvancedSettings;
            if (advancedBase != null)
            {
                advancedBase.SmartSizing = smartSizing;
                return;
            }

            SetIfExists(advanced, "SmartSizing", smartSizing);
        }

        private static object GetAdvancedSettings(object target)
        {
            for (var i = 9; i >= 2; i--)
            {
                var value = GetProperty(target, "AdvancedSettings" + i);
                if (value != null)
                {
                    return value;
                }
            }

            return GetProperty(target, "AdvancedSettings");
        }

        private static object GetProperty(object target, string propertyName)
        {
            if (target == null)
            {
                return null;
            }

            var property = target.GetType().GetProperty(
                propertyName,
                BindingFlags.Instance | BindingFlags.Public);
            return property != null && property.CanRead ? property.GetValue(target, null) : null;
        }

        private static void Call(object target, string methodName)
        {
            target.GetType().InvokeMember(
                methodName,
                BindingFlags.Instance | BindingFlags.Public | BindingFlags.InvokeMethod,
                null,
                target,
                null);
        }

        private static bool TryInvoke(object target, string methodName, object[] args)
        {
            if (target == null)
            {
                return false;
            }

            try
            {
                target.GetType().InvokeMember(
                    methodName,
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.InvokeMethod,
                    null,
                    target,
                    args);
                return true;
            }
            catch (MissingMethodException)
            {
                return false;
            }
            catch (TargetInvocationException ex)
            {
                var message = ex.InnerException == null ? ex.Message : ex.InnerException.Message;
                SessionLog.Write(methodName + " failed: " + message);
                return false;
            }
            catch (Exception ex)
            {
                SessionLog.Write(methodName + " failed: " + ex.Message);
                return false;
            }
        }

        private string GetErrorDescription(object reason, object extended)
        {
            if (reason == null)
            {
                return "";
            }

            try
            {
                var reasonNumber = Convert.ToUInt32(reason);
                var extendedNumber = extended == null ? 0U : Convert.ToUInt32(extended);
                var value = _rdp.GetType().InvokeMember(
                    "GetErrorDescription",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.InvokeMethod,
                    null,
                    _rdp,
                    new object[] { reasonNumber, extendedNumber });
                return value == null ? "" : value.ToString();
            }
            catch
            {
                return "";
            }
        }

        private static object ReadEventValue(object eventArgs, string name)
        {
            if (eventArgs == null)
            {
                return "";
            }

            var field = eventArgs.GetType().GetField(
                name,
                BindingFlags.Instance | BindingFlags.Public);
            if (field != null)
            {
                return field.GetValue(eventArgs);
            }

            var property = eventArgs.GetType().GetProperty(
                name,
                BindingFlags.Instance | BindingFlags.Public);
            return property != null ? property.GetValue(eventArgs, null) : "";
        }
    }
}
