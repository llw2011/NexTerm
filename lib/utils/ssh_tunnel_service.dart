import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../models/connection.dart';

enum SshTunnelRuntimeState {
  starting,
  listening,
  connected,
  failed,
  stopped,
}

class SshTunnelStatus {
  final SshTunnelConfig config;
  final SshTunnelRuntimeState state;
  final int activeConnections;
  final String? message;

  const SshTunnelStatus({
    required this.config,
    required this.state,
    this.activeConnections = 0,
    this.message,
  });
}

typedef SshTunnelStatusCallback = void Function(SshTunnelStatus status);
typedef SshTunnelLogCallback = void Function(String message);

class SshTunnelRuntime {
  final SSHClient client;
  final SshTunnelConfig config;
  final SshTunnelStatusCallback onStatus;
  final SshTunnelLogCallback? onLog;

  SshTunnelRuntime({
    required this.client,
    required this.config,
    required this.onStatus,
    this.onLog,
  });

  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSub;
  final _localSockets = <Socket>{};
  final _forwardChannels = <SSHForwardChannel>{};
  var _activeConnections = 0;
  var _closed = false;

  Future<void> start() async {
    if (!config.enabled) {
      _emit(SshTunnelRuntimeState.stopped);
      return;
    }

    _emit(SshTunnelRuntimeState.starting);
    try {
      _server = await ServerSocket.bind(
        config.localHost,
        config.localPort,
        shared: false,
      );
      _serverSub = _server!.listen(
        (socket) => unawaited(_handleLocalSocket(socket)),
        onError: (Object error) {
          if (_closed) return;
          _emit(
            SshTunnelRuntimeState.failed,
            message: 'Local listener failed: $error',
          );
        },
      );
      _emit(SshTunnelRuntimeState.listening);
    } catch (e) {
      _emit(
        SshTunnelRuntimeState.failed,
        message: 'Cannot listen on ${config.localHost}:${config.localPort}: $e',
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _serverSub?.cancel();
    _serverSub = null;
    await _server?.close();
    _server = null;

    for (final socket in List<Socket>.of(_localSockets)) {
      socket.destroy();
    }
    _localSockets.clear();

    for (final channel in List<SSHForwardChannel>.of(_forwardChannels)) {
      channel.destroy();
    }
    _forwardChannels.clear();

    _activeConnections = 0;
    _emit(SshTunnelRuntimeState.stopped);
  }

  Future<void> _handleLocalSocket(Socket socket) async {
    if (_closed) {
      socket.destroy();
      return;
    }

    _localSockets.add(socket);
    _activeConnections++;
    _emit(SshTunnelRuntimeState.connected);

    SSHForwardChannel? channel;
    try {
      onLog?.call(
        'Opening local forward ${config.localHost}:${config.localPort} -> '
        '${config.remoteHost}:${config.remotePort}',
      );
      channel = await client
          .forwardLocal(
            config.remoteHost,
            config.remotePort,
            localHost: socket.remoteAddress.address,
            localPort: socket.remotePort,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Remote channel timeout'),
          );
      _forwardChannels.add(channel);

      final localToRemote = socket.cast<List<int>>().pipe(channel.sink);
      final remoteToLocal = channel.stream.cast<List<int>>().pipe(socket);
      await Future.any([
        localToRemote.catchError((_) {}),
        remoteToLocal.catchError((_) {}),
      ]);
    } catch (e) {
      if (!_closed) {
        _emit(
          _activeConnections > 1
              ? SshTunnelRuntimeState.connected
              : SshTunnelRuntimeState.listening,
          message:
              'Forward to ${config.remoteHost}:${config.remotePort} failed: $e',
        );
      }
    } finally {
      _localSockets.remove(socket);
      socket.destroy();

      if (channel != null) {
        _forwardChannels.remove(channel);
        channel.destroy();
      }

      if (_activeConnections > 0) {
        _activeConnections--;
      }
      if (!_closed) {
        _emit(
          _activeConnections > 0
              ? SshTunnelRuntimeState.connected
              : SshTunnelRuntimeState.listening,
        );
      }
    }
  }

  void _emit(SshTunnelRuntimeState state, {String? message}) {
    onStatus(
      SshTunnelStatus(
        config: config,
        state: state,
        activeConnections: _activeConnections,
        message: message,
      ),
    );
  }
}
