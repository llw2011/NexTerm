import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/connection.dart';
import 'package:nexterm/providers/connections_provider.dart';
import 'package:nexterm/utils/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('connections are sorted by favorite, recent use, then name', () async {
    final provider = ConnectionsProvider();
    await provider.load();

    await provider.add(Connection(
      id: 'b',
      name: 'Beta',
      host: 'b.example.com',
      port: 22,
      username: 'root',
      type: ConnectionType.ssh,
      lastOpenedAt: DateTime.utc(2026, 6, 24),
    ));
    await provider.add(Connection(
      id: 'a',
      name: 'Alpha',
      host: 'a.example.com',
      port: 3389,
      username: 'admin',
      type: ConnectionType.rdp,
    ));
    await provider.add(Connection(
      id: 'c',
      name: 'Gamma',
      host: 'c.example.com',
      port: 22,
      username: 'root',
      type: ConnectionType.ssh,
      isFavorite: true,
      lastOpenedAt: DateTime.utc(2026, 6, 20),
    ));

    expect(provider.list.map((e) => e.id), ['c', 'b', 'a']);
  });

  test('duplicate copies metadata and credentials', () async {
    final provider = ConnectionsProvider();
    await provider.load();
    const source = Connection(
      id: 'ssh-1',
      name: 'Server',
      group: 'Production',
      host: 'example.com',
      port: 22,
      username: 'root',
      type: ConnectionType.ssh,
      sshAuthType: SshAuthType.privateKey,
      isFavorite: true,
    );
    await provider.add(source);
    await savePassword(source.id, 'password');
    await savePrivateKey(source.id, 'private-key');
    await saveKeyPassphrase(source.id, 'passphrase');

    final copy = await provider.duplicate(source.id, name: 'Server Copy');

    expect(copy, isNotNull);
    expect(copy!.id, isNot(source.id));
    expect(copy.name, 'Server Copy');
    expect(copy.group, source.group);
    expect(copy.host, source.host);
    expect(copy.isFavorite, isFalse);
    expect(copy.lastOpenedAt, isNull);
    expect(await loadPassword(copy.id), 'password');
    expect(await loadPrivateKey(copy.id), 'private-key');
    expect(await loadKeyPassphrase(copy.id), 'passphrase');
  });

  test('remove deletes all stored credentials', () async {
    final provider = ConnectionsProvider();
    await provider.load();
    const connection = Connection(
      id: 'ssh-1',
      name: 'Server',
      host: 'example.com',
      port: 22,
      username: 'root',
      type: ConnectionType.ssh,
      sshAuthType: SshAuthType.privateKey,
    );
    await provider.add(connection);
    await savePassword(connection.id, 'password');
    await savePrivateKey(connection.id, 'private-key');
    await saveKeyPassphrase(connection.id, 'passphrase');

    await provider.remove(connection.id);

    expect(await loadPassword(connection.id), isEmpty);
    expect(await loadPrivateKey(connection.id), isNull);
    expect(await loadKeyPassphrase(connection.id), isNull);
  });
}
