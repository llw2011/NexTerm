import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../i18n/app_localizations.dart';
import '../../models/connection.dart';
import '../../providers/connections_provider.dart';
import '../../utils/secure_storage.dart';
import '../../utils/ssh_connection_service.dart';
import '../../utils/ssh_host_key_prompt.dart';
import '../../utils/ssh_tunnel_service.dart';
import '../sftp/sftp_screen.dart';

class SshScreen extends StatefulWidget {
  final Connection connection;
  final bool embedded;
  const SshScreen({super.key, required this.connection, this.embedded = false});

  @override
  State<SshScreen> createState() => _SshScreenState();
}

class _SshScreenState extends State<SshScreen> {
  SSHSession? _session;
  SSHClient? _client;
  SSHSocket? _socket;
  SSHClient? _jumpClient;
  SSHSocket? _jumpSocket;
  late final Terminal _terminal;
  TerminalController? _terminalController;
  late final FocusNode _terminalFocusNode;

  String _status = '';
  bool _hasError = false;
  bool _closing = false;
  bool _connected = false;
  bool _toolbarVisible = true;
  bool _shortcutBarVisible = true;
  bool _ctrlArmed = false;
  bool _altArmed = false;
  final List<SshTunnelRuntime> _tunnelRuntimes = [];
  final Map<String, SshTunnelStatus> _tunnelStatuses = {};

  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[SSH] $msg');
  }

  @override
  void initState() {
    super.initState();
    _log('initState - creating terminal');
    _terminal = Terminal(maxLines: 10000);
    _terminalController = TerminalController();
    _terminalFocusNode = FocusNode();
    _log('initState - calling _connect');
    _connect();
  }

  Future<void> _connect() async {
    _log('_connect started');
    if (!mounted || _closing) {
      _log('_connect early exit - not mounted or closing');
      return;
    }

    setState(() {
      _hasError = false;
      _status = '正在连接 ${widget.connection.host}:${widget.connection.port}...';
    });

    try {
      final password = await loadPassword(widget.connection.id);
      final privateKey = await loadPrivateKey(widget.connection.id);
      final passphrase = await loadKeyPassphrase(widget.connection.id);
      final authType = widget.connection.sshAuthType ?? SshAuthType.password;

      if (!mounted || _closing) return;

      setState(() {
        _status = '正在连接...';
      });

      // Connect to host
      _log('Connecting to ${widget.connection.host}:${widget.connection.port}');
      _log('Auth type: $authType, username: ${widget.connection.username}');

      // Debug callbacks for dartssh2
      void handleDebug(String? msg) {
        if (msg != null) _log('[dartssh2] $msg');
      }

      void handleTrace(String? msg) {
        if (msg != null) _log('[dartssh2 trace] $msg');
      }

      _socket = await _openSshSocket(
        widget.connection.host,
        widget.connection.port,
        timeout: const Duration(seconds: 15),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('连接超时 (20秒)');
        },
      );

      _log('Socket connected');

      if (!mounted || _closing) {
        _closeSshTransport();
        return;
      }

      setState(() {
        _status = '正在认证...';
      });

      // Build client based on auth type
      if (authType == SshAuthType.privateKey &&
          privateKey != null &&
          privateKey.isNotEmpty) {
        _log('Using private key authentication');

        final keyPairs = SSHKeyPair.fromPem(
          privateKey,
          passphrase?.isNotEmpty == true ? passphrase : null,
        );

        _client = SSHClient(
          _socket!,
          username: widget.connection.username,
          identities: keyPairs,
          onPasswordRequest: () {
            _log('Password callback triggered');
            return password;
          },
          onVerifyHostKey: _verifyHostKey,
          printDebug: handleDebug,
          printTrace: handleTrace,
        );
      } else {
        _log('Using password authentication');

        _client = SSHClient(
          _socket!,
          username: widget.connection.username,
          onPasswordRequest: () {
            _log('Password callback triggered - returning password');
            return password;
          },
          onVerifyHostKey: _verifyHostKey,
          printDebug: handleDebug,
          printTrace: handleTrace,
        );
      }

      setState(() {
        _status = '正在验证...';
      });

      // Wait for authentication with timeout
      _log('Waiting for authentication...');

      await _client!.authenticated.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('认证超时 (30秒)');
        },
      );

      _log('Authentication successful!');

      if (!mounted || _closing) {
        _closeSshTransport();
        return;
      }

      setState(() {
        _status = '正在打开终端...';
      });

      // Open shell with PTY
      _log('Opening shell with PTY');

      _session = await _client!
          .shell(
        pty: const SSHPtyConfig(
          type: 'xterm-256color',
          width: 80,
          height: 24,
        ),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('打开终端超时');
        },
      );

      _log('Shell opened successfully');

      if (!mounted || _closing) {
        _session?.close();
        _closeSshTransport();
        return;
      }

      setState(() {
        _connected = true;
        _status = '已连接';
        _toolbarVisible = true;
        _shortcutBarVisible = true;
        _ctrlArmed = false;
        _altArmed = false;
      });
      unawaited(_startTunnels());

      // Pipe SSH stdout to terminal
      _stdoutSub = _session!.stdout.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          _terminal.write(text);
          if (data.length < 100) {
            _log(
                'stdout: ${text.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}');
          }
        },
        onError: (e) {
          _log('stdout error: $e');
          if (mounted && !_closing) {
            setState(() {
              _hasError = true;
              _status = '输出错误: $e';
            });
          }
        },
        onDone: () {
          _log('stdout done');
          if (mounted && !_closing) {
            setState(() {
              _status = '会话已结束';
            });
          }
        },
      );

      // Pipe stderr to terminal
      _stderrSub = _session!.stderr.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          _terminal.write(text);
          _log('stderr: $text');
        },
      );

      // Pipe terminal input to SSH
      _terminal.onOutput = (data) {
        _log('stdin: ${data.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}');
        _session?.write(utf8.encode(data));
      };

      // Handle terminal resize
      _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _log('Resize: ${width}x$height, pixel: ${pixelWidth}x$pixelHeight');
        _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };
    } catch (e, stack) {
      _log('Error: $e');
      _log('Stack: $stack');

      if (mounted && !_closing) {
        setState(() {
          _hasError = true;
          _status = '连接失败: $e';
        });
      }

      // Cleanup on error
      try {
        unawaited(_stopTunnels(clearStatuses: false));
        _session?.close();
        _closeSshTransport();
      } catch (_) {}
    }
  }

  Future<SSHSocket> _openSshSocket(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    final allConnections = context.read<ConnectionsProvider>().list;
    final jumpHost =
        SshConnectionService.resolveJumpHost(widget.connection, allConnections);
    if (jumpHost == null) {
      return SSHSocket.connect(host, port, timeout: timeout);
    }

    _log('Connecting jump host ${jumpHost.name}');
    _jumpSocket = await SSHSocket.connect(
      jumpHost.host,
      jumpHost.port,
      timeout: timeout,
    );

    try {
      _jumpClient = await _buildJumpClient(jumpHost, _jumpSocket!);
      await _jumpClient!.authenticated.timeout(
        SshConnectionService.authTimeout,
        onTimeout: () => throw TimeoutException(
          'Jump host authentication timed out',
          SshConnectionService.authTimeout,
        ),
      );

      _log('Opening jump channel to $host:$port');
      return _jumpClient!
          .forwardLocal(host, port)
          .timeout(SshConnectionService.jumpChannelTimeout);
    } catch (_) {
      _closeJumpHost();
      rethrow;
    }
  }

  Future<SSHClient> _buildJumpClient(
    Connection jumpHost,
    SSHSocket socket,
  ) async {
    final password = await loadPassword(jumpHost.id);
    final privateKey = await loadPrivateKey(jumpHost.id);
    final passphrase = await loadKeyPassphrase(jumpHost.id);
    final authType = jumpHost.sshAuthType ?? SshAuthType.password;

    if (authType == SshAuthType.privateKey &&
        privateKey != null &&
        privateKey.isNotEmpty) {
      final keyPairs = SSHKeyPair.fromPem(
        privateKey,
        passphrase?.isNotEmpty == true ? passphrase : null,
      );
      return SSHClient(
        socket,
        username: jumpHost.username,
        identities: keyPairs,
        onPasswordRequest: () => password,
        onVerifyHostKey: (type, fingerprint) =>
            _verifyHostKeyFor(jumpHost, type, fingerprint),
      );
    }

    return SSHClient(
      socket,
      username: jumpHost.username,
      onPasswordRequest: () => password,
      onVerifyHostKey: (type, fingerprint) =>
          _verifyHostKeyFor(jumpHost, type, fingerprint),
    );
  }

  Future<bool> _verifyHostKey(String type, Uint8List fingerprint) async {
    return _verifyHostKeyFor(widget.connection, type, fingerprint);
  }

  Future<bool> _verifyHostKeyFor(
    Connection connection,
    String type,
    Uint8List fingerprint,
  ) async {
    return SshHostKeyPrompt.verify(
      context: context,
      connection: connection,
      type: type,
      fingerprint: fingerprint,
      onLog: _log,
    );
  }

  void _closeJumpHost() {
    try {
      _jumpClient?.close();
    } catch (_) {}
    try {
      _jumpSocket?.close();
    } catch (_) {}
    _jumpClient = null;
    _jumpSocket = null;
  }

  void _closeSshTransport() {
    try {
      _client?.close();
    } catch (_) {}
    try {
      _socket?.close();
    } catch (_) {}
    _client = null;
    _socket = null;
    _closeJumpHost();
  }

  Future<void> _destroySession() async {
    if (_closing) return;
    _closing = true;

    _log('Destroying session');

    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    await _stopTunnels(clearStatuses: false);

    try {
      _session?.close();
      _closeSshTransport();
    } catch (e) {
      _log('Cleanup error: $e');
    }

    if (mounted && !widget.embedded) {
      Navigator.pop(context);
    }
  }

  void _toggleToolbar() {
    setState(() => _toolbarVisible = !_toolbarVisible);
  }

  void _toggleShortcutBar() {
    setState(() {
      _shortcutBarVisible = !_shortcutBarVisible;
      if (!_shortcutBarVisible) {
        _ctrlArmed = false;
        _altArmed = false;
      }
    });
  }

  void _toggleCtrlModifier() {
    setState(() => _ctrlArmed = !_ctrlArmed);
  }

  void _toggleAltModifier() {
    setState(() => _altArmed = !_altArmed);
  }

  void _resetModifiers() {
    if (!_ctrlArmed && !_altArmed) return;
    setState(() {
      _ctrlArmed = false;
      _altArmed = false;
    });
  }

  void _refocusTerminal() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_terminalFocusNode);
  }

  void _sendTerminalKey(TerminalKey key) {
    _terminal.keyInput(key, ctrl: _ctrlArmed, alt: _altArmed);
    _resetModifiers();
    _refocusTerminal();
  }

  void _sendCtrlKey(TerminalKey key) {
    _terminal.keyInput(key, ctrl: true);
    _resetModifiers();
    _refocusTerminal();
  }

  void _openSftp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SftpScreen(connection: widget.connection),
      ),
    );
  }

  Future<void> _startTunnels() async {
    final client = _client;
    if (client == null) return;

    final configs =
        widget.connection.sshTunnels.where((tunnel) => tunnel.enabled);
    for (final config in configs) {
      final runtime = SshTunnelRuntime(
        client: client,
        config: config,
        onStatus: _onTunnelStatus,
        onLog: _log,
      );
      _tunnelRuntimes.add(runtime);
      unawaited(runtime.start());
    }
  }

  Future<void> _stopTunnels({bool clearStatuses = true}) async {
    final runtimes = List<SshTunnelRuntime>.of(_tunnelRuntimes);
    _tunnelRuntimes.clear();
    await Future.wait(runtimes.map((runtime) => runtime.close()));
    if (clearStatuses && mounted) {
      setState(_tunnelStatuses.clear);
    }
  }

  void _onTunnelStatus(SshTunnelStatus status) {
    _log(
      'Tunnel ${status.config.localHost}:${status.config.localPort} -> '
      '${status.config.remoteHost}:${status.config.remotePort}: '
      '${status.state.name} active=${status.activeConnections}',
    );
    if (!mounted || _closing) return;
    setState(() => _tunnelStatuses[status.config.id] = status);
  }

  void _showTunnelStatus() {
    final l10n = context.l10n;
    final configs =
        widget.connection.sshTunnels.where((tunnel) => tunnel.enabled).toList();

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.t('sshPortForwarding')),
        content: SizedBox(
          width: double.maxFinite,
          child: configs.isEmpty
              ? Text(l10n.t('sshPortForwardingEmpty'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final config in configs)
                      _TunnelStatusTile(
                        config: config,
                        status: _tunnelStatuses[config.id],
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('close')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _closing = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    unawaited(_stopTunnels(clearStatuses: false));
    try {
      _session?.close();
      _closeSshTransport();
    } catch (_) {}
    _terminalController?.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabledTunnelCount =
        widget.connection.sshTunnels.where((tunnel) => tunnel.enabled).length;

    _log('build: connected=$_connected, hasError=$_hasError, status=$_status');

    final content = Stack(
      children: [
        Positioned.fill(
          child: !_connected || _hasError
              ? _StatusView(status: _status, hasError: _hasError)
              : _buildTerminal(),
        ),
        if (!widget.embedded && _toolbarVisible && _connected)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            right: 8,
            child: _Toolbar(
              title: widget.connection.name,
              status: _status,
              onClose: _destroySession,
              onHide: _toggleToolbar,
              onSftp: _openSftp,
              tunnelCount: enabledTunnelCount,
              onTunnels: enabledTunnelCount > 0 ? _showTunnelStatus : null,
            ),
          ),
        if (!widget.embedded && !_toolbarVisible && _connected)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: _RoundToolButton(
              icon: Icons.menu,
              tooltip: l10n.t('toolbar'),
              onPressed: _toggleToolbar,
            ),
          ),
        if (!widget.embedded && _connected && _shortcutBarVisible)
          Positioned(
            left: 8,
            right: 8,
            bottom: MediaQuery.paddingOf(context).bottom + 8,
            child: _SshShortcutBar(
              ctrlArmed: _ctrlArmed,
              altArmed: _altArmed,
              onToggleCtrl: _toggleCtrlModifier,
              onToggleAlt: _toggleAltModifier,
              onHide: _toggleShortcutBar,
              onKey: _sendTerminalKey,
              onCtrlKey: _sendCtrlKey,
            ),
          ),
        if (!widget.embedded && _connected && !_shortcutBarVisible)
          Positioned(
            right: 8,
            bottom: MediaQuery.paddingOf(context).bottom + 8,
            child: _RoundToolButton(
              icon: Icons.keyboard_command_key,
              tooltip: l10n.t('sshShortcutsShow'),
              onPressed: _toggleShortcutBar,
            ),
          ),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: Colors.black,
      body: content,
    );
  }

  Widget _buildTerminal() {
    final bottomPadding = !widget.embedded && _shortcutBarVisible ? 66.0 : 0.0;

    return TerminalView(
      _terminal,
      controller: _terminalController,
      focusNode: _terminalFocusNode,
      autofocus: true,
      textStyle: const TerminalStyle(
        fontSize: 14,
        fontFamily: 'monospace',
      ),
      padding: EdgeInsets.only(top: 48, bottom: bottomPadding),
    );
  }
}

class _TunnelStatusTile extends StatelessWidget {
  final SshTunnelConfig config;
  final SshTunnelStatus? status;

  const _TunnelStatusTile({
    required this.config,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = status?.state ?? SshTunnelRuntimeState.starting;
    final message = status?.message;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.hub_outlined, color: _stateColor(state)),
      title: Text(
        '${config.localHost}:${config.localPort} -> '
        '${config.remoteHost}:${config.remotePort}',
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        message == null || message.isEmpty
            ? _stateText(l10n, status)
            : '${_stateText(l10n, status)}\n$message',
      ),
      isThreeLine: message != null && message.isNotEmpty,
    );
  }

  Color _stateColor(SshTunnelRuntimeState state) {
    switch (state) {
      case SshTunnelRuntimeState.starting:
        return Colors.amberAccent;
      case SshTunnelRuntimeState.listening:
        return const Color(0xFF00D4FF);
      case SshTunnelRuntimeState.connected:
        return Colors.lightGreenAccent;
      case SshTunnelRuntimeState.failed:
        return Colors.redAccent;
      case SshTunnelRuntimeState.stopped:
        return Colors.white38;
    }
  }

  String _stateText(AppLocalizations l10n, SshTunnelStatus? status) {
    final state = status?.state ?? SshTunnelRuntimeState.starting;
    switch (state) {
      case SshTunnelRuntimeState.starting:
        return l10n.t('sshTunnelStatusStarting');
      case SshTunnelRuntimeState.listening:
        return l10n.t('sshTunnelStatusListening');
      case SshTunnelRuntimeState.connected:
        return l10n
            .t('sshTunnelStatusConnected')
            .replaceAll('{count}', '${status?.activeConnections ?? 0}');
      case SshTunnelRuntimeState.failed:
        return l10n.t('sshTunnelStatusFailed');
      case SshTunnelRuntimeState.stopped:
        return l10n.t('sshTunnelStatusStopped');
    }
  }
}

class _SshShortcutBar extends StatelessWidget {
  final bool ctrlArmed;
  final bool altArmed;
  final VoidCallback onToggleCtrl;
  final VoidCallback onToggleAlt;
  final VoidCallback onHide;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<TerminalKey> onCtrlKey;

  const _SshShortcutBar({
    required this.ctrlArmed,
    required this.altArmed,
    required this.onToggleCtrl,
    required this.onToggleAlt,
    required this.onHide,
    required this.onKey,
    required this.onCtrlKey,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            _ShortcutIconButton(
              icon: Icons.keyboard_hide_outlined,
              tooltip: l10n.t('sshShortcutsHide'),
              onPressed: onHide,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    _ShortcutTextButton(
                      label: 'Ctrl',
                      selected: ctrlArmed,
                      tooltip: l10n.t('sshCtrlModifier'),
                      onPressed: onToggleCtrl,
                    ),
                    _ShortcutTextButton(
                      label: 'Alt',
                      selected: altArmed,
                      tooltip: l10n.t('sshAltModifier'),
                      onPressed: onToggleAlt,
                    ),
                    const SizedBox(width: 6),
                    _ShortcutTextButton(
                      label: 'Esc',
                      tooltip: 'Esc',
                      onPressed: () => onKey(TerminalKey.escape),
                    ),
                    _ShortcutTextButton(
                      label: 'Tab',
                      tooltip: 'Tab',
                      onPressed: () => onKey(TerminalKey.tab),
                    ),
                    const SizedBox(width: 6),
                    _ShortcutTextButton(
                      label: '^C',
                      tooltip: 'Ctrl+C',
                      onPressed: () => onCtrlKey(TerminalKey.keyC),
                    ),
                    _ShortcutTextButton(
                      label: '^D',
                      tooltip: 'Ctrl+D',
                      onPressed: () => onCtrlKey(TerminalKey.keyD),
                    ),
                    _ShortcutTextButton(
                      label: '^Z',
                      tooltip: 'Ctrl+Z',
                      onPressed: () => onCtrlKey(TerminalKey.keyZ),
                    ),
                    _ShortcutTextButton(
                      label: '^L',
                      tooltip: 'Ctrl+L',
                      onPressed: () => onCtrlKey(TerminalKey.keyL),
                    ),
                    const SizedBox(width: 6),
                    _ShortcutTextButton(
                      label: '←',
                      tooltip: 'Left',
                      onPressed: () => onKey(TerminalKey.arrowLeft),
                    ),
                    _ShortcutTextButton(
                      label: '↑',
                      tooltip: 'Up',
                      onPressed: () => onKey(TerminalKey.arrowUp),
                    ),
                    _ShortcutTextButton(
                      label: '↓',
                      tooltip: 'Down',
                      onPressed: () => onKey(TerminalKey.arrowDown),
                    ),
                    _ShortcutTextButton(
                      label: '→',
                      tooltip: 'Right',
                      onPressed: () => onKey(TerminalKey.arrowRight),
                    ),
                    const SizedBox(width: 6),
                    _ShortcutTextButton(
                      label: 'PgUp',
                      tooltip: 'Page Up',
                      onPressed: () => onKey(TerminalKey.pageUp),
                    ),
                    _ShortcutTextButton(
                      label: 'PgDn',
                      tooltip: 'Page Down',
                      onPressed: () => onKey(TerminalKey.pageDown),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTextButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  const _ShortcutTextButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              backgroundColor:
                  selected ? const Color(0xFF00D4FF) : Colors.white10,
              foregroundColor: selected ? Colors.black : Colors.white,
              fixedSize: const Size(48, 36),
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: selected ? const Color(0xFF00D4FF) : Colors.white12,
                ),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1),
            ),
          ),
        ),
      );
}

class _ShortcutIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ShortcutIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 20),
          color: Colors.white70,
          onPressed: onPressed,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        ),
      );
}

class _StatusView extends StatelessWidget {
  final String status;
  final bool hasError;
  const _StatusView({required this.status, required this.hasError});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasError)
              const CircularProgressIndicator(color: Color(0xFF00D4FF))
            else
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SelectableText(
                status,
                style: TextStyle(
                  color: hasError ? Colors.redAccent : Colors.white54,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
}

class _Toolbar extends StatelessWidget {
  final String title;
  final String status;
  final VoidCallback onClose;
  final VoidCallback onHide;
  final VoidCallback onSftp;
  final int tunnelCount;
  final VoidCallback? onTunnels;
  const _Toolbar({
    required this.title,
    required this.status,
    required this.onClose,
    required this.onHide,
    required this.onSftp,
    required this.tunnelCount,
    required this.onTunnels,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.terminal, color: Color(0xFF00D4FF), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    status,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTunnels != null)
              _ToolbarButton(
                icon: Icons.hub_outlined,
                tooltip: '${l10n.t('sshPortForwarding')} ($tunnelCount)',
                onPressed: onTunnels!,
              ),
            _ToolbarButton(
              icon: Icons.folder_open_outlined,
              tooltip: l10n.t('sftp'),
              onPressed: onSftp,
            ),
            _ToolbarButton(
              icon: Icons.visibility_off,
              tooltip: l10n.t('hide'),
              onPressed: onHide,
            ),
            _ToolbarButton(
              icon: Icons.close,
              tooltip: l10n.t('close'),
              danger: true,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 20),
          color: danger ? Colors.redAccent : Colors.white70,
          onPressed: onPressed,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        ),
      );
}

class _RoundToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _RoundToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.72),
            foregroundColor: Colors.white70,
          ),
        ),
      );
}
