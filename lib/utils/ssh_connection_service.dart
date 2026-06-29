import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/connection.dart';
import 'secure_storage.dart';

typedef SshHostKeyVerifierForConnection = Future<bool> Function(
  Connection connection,
  String type,
  Uint8List fingerprint,
);

typedef SshConnectionLogCallback = void Function(String message);

class SshConnectionSession {
  final Connection connection;
  final SSHSocket socket;
  final SSHClient client;
  final Connection? jumpHost;
  final SSHSocket? jumpSocket;
  final SSHClient? jumpClient;

  const SshConnectionSession({
    required this.connection,
    required this.socket,
    required this.client,
    this.jumpHost,
    this.jumpSocket,
    this.jumpClient,
  });

  bool get viaJumpHost => jumpHost != null;

  void close() {
    try {
      client.close();
    } catch (_) {}
    try {
      socket.close();
    } catch (_) {}
    try {
      jumpClient?.close();
    } catch (_) {}
    try {
      jumpSocket?.close();
    } catch (_) {}
  }
}

class SshConnectionService {
  static const socketTimeout = Duration(seconds: 20);
  static const authTimeout = Duration(seconds: 30);
  static const jumpChannelTimeout = Duration(seconds: 20);

  static List<Connection> jumpHostCandidates(
    Connection target,
    List<Connection> connections,
  ) {
    return connections
        .where((connection) => connection.type == ConnectionType.ssh)
        .where((connection) => connection.id != target.id)
        .where((connection) => connection.sshJumpHostId == null)
        .toList();
  }

  static Connection? resolveJumpHost(
    Connection target,
    List<Connection> connections,
  ) {
    final jumpHostId = target.sshJumpHostId;
    if (jumpHostId == null || jumpHostId.isEmpty) return null;
    if (jumpHostId == target.id) {
      throw StateError('Jump host cannot reference the target connection.');
    }

    final matches =
        connections.where((connection) => connection.id == jumpHostId);
    if (matches.isEmpty) {
      throw StateError('Configured jump host was not found.');
    }

    final jumpHost = matches.single;
    if (jumpHost.type != ConnectionType.ssh) {
      throw StateError('Jump host must be an SSH connection.');
    }
    if (jumpHost.sshJumpHostId != null) {
      throw StateError(
          'Only one-hop jump hosts are supported in this version.');
    }
    return jumpHost;
  }

  static Future<SshConnectionSession> connect(
    Connection connection, {
    required List<Connection> allConnections,
    required SshHostKeyVerifierForConnection verifyHostKey,
    SshConnectionLogCallback? onLog,
    void Function(String?)? printDebug,
    void Function(String?)? printTrace,
  }) async {
    final jumpHost = resolveJumpHost(connection, allConnections);
    if (jumpHost == null) {
      final target = await _connectDirect(
        connection,
        verifyHostKey: verifyHostKey,
        onLog: onLog,
        printDebug: printDebug,
        printTrace: printTrace,
      );
      return SshConnectionSession(
        connection: connection,
        socket: target.socket,
        client: target.client,
      );
    }

    onLog?.call(
      'Connecting via jump host ${jumpHost.name} '
      '(${jumpHost.host}:${jumpHost.port})',
    );

    final jump = await _connectDirect(
      jumpHost,
      verifyHostKey: verifyHostKey,
      onLog: onLog,
      printDebug: printDebug,
      printTrace: printTrace,
    );

    SSHSocket? targetSocket;
    SSHClient? targetClient;
    try {
      onLog?.call(
        'Opening jump channel to ${connection.host}:${connection.port}',
      );
      targetSocket = await jump.client
          .forwardLocal(connection.host, connection.port)
          .timeout(
            jumpChannelTimeout,
            onTimeout: () => throw TimeoutException(
              'Opening jump channel timed out',
              jumpChannelTimeout,
            ),
          );

      targetClient = await _createAuthenticatedClient(
        socket: targetSocket,
        connection: connection,
        verifyHostKey: verifyHostKey,
        onLog: onLog,
        printDebug: printDebug,
        printTrace: printTrace,
      );

      return SshConnectionSession(
        connection: connection,
        socket: targetSocket,
        client: targetClient,
        jumpHost: jumpHost,
        jumpSocket: jump.socket,
        jumpClient: jump.client,
      );
    } catch (_) {
      try {
        targetClient?.close();
      } catch (_) {}
      try {
        targetSocket?.close();
      } catch (_) {}
      jump.close();
      rethrow;
    }
  }

  static Future<_DirectSshConnection> _connectDirect(
    Connection connection, {
    required SshHostKeyVerifierForConnection verifyHostKey,
    SshConnectionLogCallback? onLog,
    void Function(String?)? printDebug,
    void Function(String?)? printTrace,
  }) async {
    onLog?.call('Opening SSH socket to ${connection.host}:${connection.port}');
    final socket = await SSHSocket.connect(
      connection.host,
      connection.port,
      timeout: const Duration(seconds: 15),
    ).timeout(
      socketTimeout,
      onTimeout: () => throw TimeoutException(
        'Connection timed out',
        socketTimeout,
      ),
    );

    SSHClient? client;
    try {
      client = await _createAuthenticatedClient(
        socket: socket,
        connection: connection,
        verifyHostKey: verifyHostKey,
        onLog: onLog,
        printDebug: printDebug,
        printTrace: printTrace,
      );
      return _DirectSshConnection(socket: socket, client: client);
    } catch (_) {
      try {
        client?.close();
      } catch (_) {}
      try {
        socket.close();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<SSHClient> _createAuthenticatedClient({
    required SSHSocket socket,
    required Connection connection,
    required SshHostKeyVerifierForConnection verifyHostKey,
    SshConnectionLogCallback? onLog,
    void Function(String?)? printDebug,
    void Function(String?)? printTrace,
  }) async {
    final password = await loadPassword(connection.id);
    final privateKey = await loadPrivateKey(connection.id);
    final passphrase = await loadKeyPassphrase(connection.id);
    final authType = connection.sshAuthType ?? SshAuthType.password;

    onLog?.call('Authenticating ${connection.username}@${connection.host}');

    final SSHClient client;
    if (authType == SshAuthType.privateKey &&
        privateKey != null &&
        privateKey.isNotEmpty) {
      final keyPairs = SSHKeyPair.fromPem(
        privateKey,
        passphrase?.isNotEmpty == true ? passphrase : null,
      );
      client = SSHClient(
        socket,
        username: connection.username,
        identities: keyPairs,
        onPasswordRequest: () => password,
        onVerifyHostKey: (type, fingerprint) =>
            verifyHostKey(connection, type, fingerprint),
        printDebug: printDebug,
        printTrace: printTrace,
      );
    } else {
      client = SSHClient(
        socket,
        username: connection.username,
        onPasswordRequest: () => password,
        onVerifyHostKey: (type, fingerprint) =>
            verifyHostKey(connection, type, fingerprint),
        printDebug: printDebug,
        printTrace: printTrace,
      );
    }

    await client.authenticated.timeout(
      authTimeout,
      onTimeout: () => throw TimeoutException(
        'Authentication timed out',
        authTimeout,
      ),
    );
    onLog?.call('Authenticated ${connection.username}@${connection.host}');
    return client;
  }
}

class _DirectSshConnection {
  final SSHSocket socket;
  final SSHClient client;

  const _DirectSshConnection({
    required this.socket,
    required this.client,
  });

  void close() {
    try {
      client.close();
    } catch (_) {}
    try {
      socket.close();
    } catch (_) {}
  }
}
