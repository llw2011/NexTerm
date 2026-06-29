import 'package:dartssh2/dartssh2.dart';

import '../models/connection.dart';
import 'ssh_connection_service.dart';

class SftpSession {
  final SshConnectionSession ssh;
  final SftpClient sftp;

  const SftpSession({
    required this.ssh,
    required this.sftp,
  });

  SSHSocket get socket => ssh.socket;
  SSHClient get client => ssh.client;

  void close() {
    try {
      sftp.close();
    } catch (_) {}
    ssh.close();
  }
}

class SftpService {
  static Future<SftpSession> connect(
    Connection connection, {
    required List<Connection> allConnections,
    required SshHostKeyVerifierForConnection verifyHostKey,
  }) async {
    SshConnectionSession? ssh;
    SftpClient? sftp;
    try {
      ssh = await SshConnectionService.connect(
        connection,
        allConnections: allConnections,
        verifyHostKey: verifyHostKey,
      );

      sftp = await ssh.client.sftp().timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Opening SFTP timed out (15s)'),
          );
      await sftp.handshake.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('SFTP handshake timed out (10s)'),
      );

      return SftpSession(ssh: ssh, sftp: sftp);
    } catch (_) {
      try {
        sftp?.close();
      } catch (_) {}
      ssh?.close();
      rethrow;
    }
  }
}
