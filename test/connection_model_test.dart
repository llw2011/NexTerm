import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/connection.dart';

void main() {
  test('connection json remains compatible without ssh tunnels', () {
    final connection = Connection.fromJson({
      'id': 'ssh-1',
      'name': 'Server',
      'host': 'example.com',
      'port': 22,
      'username': 'root',
      'type': 'ssh',
    });

    expect(connection.sshTunnels, isEmpty);
    expect(connection.sshJumpHostId, isNull);
    expect(connection.group, isNull);
    expect(connection.isFavorite, isFalse);
    expect(connection.lastOpenedAt, isNull);
    expect(connection.toJson().containsKey('sshTunnels'), isFalse);
    expect(connection.toJson().containsKey('sshJumpHostId'), isFalse);
    expect(connection.toJson().containsKey('group'), isFalse);
    expect(connection.toJson().containsKey('isFavorite'), isFalse);
    expect(connection.toJson().containsKey('lastOpenedAt'), isFalse);
  });

  test('connection list metadata round-trips through json', () {
    final lastOpenedAt = DateTime.utc(2026, 6, 25, 12, 30);
    final connection = Connection(
      id: 'rdp-1',
      name: 'Desktop',
      group: 'Production',
      host: 'example.com',
      port: 3389,
      username: 'admin',
      type: ConnectionType.rdp,
      isFavorite: true,
      lastOpenedAt: lastOpenedAt,
    );

    final restored = Connection.fromJson(connection.toJson());

    expect(restored.isFavorite, isTrue);
    expect(restored.lastOpenedAt, lastOpenedAt);
    expect(restored.group, 'Production');
    expect(restored.toJson()['isFavorite'], isTrue);
    expect(restored.toJson()['lastOpenedAt'], lastOpenedAt.toIso8601String());
    expect(restored.toJson()['group'], 'Production');
  });

  test('blank connection group is treated as unset', () {
    final connection = Connection.fromJson({
      'id': 'rdp-1',
      'name': 'Desktop',
      'group': '  ',
      'host': 'example.com',
      'port': 3389,
      'username': 'admin',
      'type': 'rdp',
    });

    expect(connection.group, isNull);
    expect(connection.toJson().containsKey('group'), isFalse);
  });

  test('ssh jump host id round-trips through connection json', () {
    const connection = Connection(
      id: 'ssh-1',
      name: 'Server',
      host: 'example.com',
      port: 22,
      username: 'root',
      type: ConnectionType.ssh,
      sshJumpHostId: 'jump-1',
    );

    final restored = Connection.fromJson(connection.toJson());

    expect(restored.sshJumpHostId, 'jump-1');
    expect(restored.toJson()['sshJumpHostId'], 'jump-1');
  });

  test('blank ssh jump host id is treated as unset', () {
    final connection = Connection.fromJson({
      'id': 'ssh-1',
      'name': 'Server',
      'host': 'example.com',
      'port': 22,
      'username': 'root',
      'type': 'ssh',
      'sshJumpHostId': '  ',
    });

    expect(connection.sshJumpHostId, isNull);
    expect(connection.toJson().containsKey('sshJumpHostId'), isFalse);
  });

  test('ssh tunnel config round-trips through connection json', () {
    const tunnel = SshTunnelConfig(
      id: 'tunnel-1',
      localPort: 15432,
      remoteHost: '127.0.0.1',
      remotePort: 5432,
    );
    const connection = Connection(
      id: 'ssh-1',
      name: 'Server',
      host: 'example.com',
      port: 22,
      username: 'root',
      type: ConnectionType.ssh,
      sshTunnels: [tunnel],
    );

    final restored = Connection.fromJson(connection.toJson());

    expect(restored.sshTunnels, hasLength(1));
    expect(restored.sshTunnels.single.id, 'tunnel-1');
    expect(restored.sshTunnels.single.localHost, '127.0.0.1');
    expect(restored.sshTunnels.single.localPort, 15432);
    expect(restored.sshTunnels.single.remoteHost, '127.0.0.1');
    expect(restored.sshTunnels.single.remotePort, 5432);
  });

  test('ssh tunnel config accepts numeric strings from imported json', () {
    final tunnel = SshTunnelConfig.fromJson({
      'id': 'tunnel-1',
      'localPort': '18080',
      'remoteHost': 'localhost',
      'remotePort': '8080',
    });

    expect(tunnel.localPort, 18080);
    expect(tunnel.remotePort, 8080);
  });
}
