import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/connection.dart';
import 'package:nexterm/providers/connections_provider.dart';
import 'package:nexterm/utils/connection_backup.dart';
import 'package:nexterm/utils/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connection = Connection(
    id: 'ssh-1',
    name: 'SSH One',
    group: 'Production',
    host: 'example.com',
    port: 22,
    username: 'root',
    type: ConnectionType.ssh,
    sshAuthType: SshAuthType.privateKey,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('encrypted backup hides credentials and imports with passphrase',
      () async {
    await _saveCredentials(connection.id);

    final raw = await ConnectionBackupService.exportEncryptedJson(
      [connection],
      'correct horse battery staple',
    );

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['format'], ConnectionBackupService.format);
    expect(decoded['version'], ConnectionBackupService.encryptedVersion);
    expect(decoded['encrypted'], isTrue);
    expect(ConnectionBackupService.isEncryptedJson(raw), isTrue);
    expect(raw, isNot(contains('rdp-password')));
    expect(raw, isNot(contains('fake-private-key-content')));
    expect(raw, isNot(contains('key-passphrase')));

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    final provider = ConnectionsProvider();
    await provider.load();

    final result = await ConnectionBackupService.importJson(
      raw,
      provider,
      passphrase: 'correct horse battery staple',
    );

    expect(result.total, 1);
    expect(result.added, 1);
    expect(result.updated, 0);
    expect(provider.list.single.host, connection.host);
    expect(provider.list.single.group, connection.group);
    expect(await loadPassword(connection.id), 'rdp-password');
    expect(await loadPrivateKey(connection.id), 'fake-private-key-content');
    expect(await loadKeyPassphrase(connection.id), 'key-passphrase');
  });

  test('encrypted backup rejects wrong passphrase', () async {
    await _saveCredentials(connection.id);

    final raw = await ConnectionBackupService.exportEncryptedJson(
      [connection],
      'correct horse battery staple',
    );

    final provider = ConnectionsProvider();
    await provider.load();

    expect(
      () => ConnectionBackupService.importJson(
        raw,
        provider,
        passphrase: 'wrong passphrase',
      ),
      throwsFormatException,
    );
  });

  test('plain version 1 backup remains import compatible', () async {
    await _saveCredentials(connection.id);

    final raw = await ConnectionBackupService.exportJson([connection]);

    expect(ConnectionBackupService.isEncryptedJson(raw), isFalse);
    expect(raw, contains('rdp-password'));
    expect(raw, contains('fake-private-key-content'));
    expect(raw, contains('key-passphrase'));

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    final provider = ConnectionsProvider();
    await provider.load();
    final result = await ConnectionBackupService.importJson(raw, provider);

    expect(result.total, 1);
    expect(result.added, 1);
    expect(provider.list.single.group, connection.group);
    expect(await loadPassword(connection.id), 'rdp-password');
    expect(await loadPrivateKey(connection.id), 'fake-private-key-content');
    expect(await loadKeyPassphrase(connection.id), 'key-passphrase');
  });
}

Future<void> _saveCredentials(String connectionId) async {
  await savePassword(connectionId, 'rdp-password');
  await savePrivateKey(connectionId, 'fake-private-key-content');
  await saveKeyPassphrase(connectionId, 'key-passphrase');
}
