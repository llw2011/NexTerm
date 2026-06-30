import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

String _pwdKey(String id) => 'pwd_$id';
String _keyKey(String id) => 'key_$id';
String _passphraseKey(String id) => 'passphrase_$id';

Future<void> savePassword(String connectionId, String password) =>
    _storage.write(key: _pwdKey(connectionId), value: password);

Future<String> loadPassword(String connectionId) async =>
    await _storage.read(key: _pwdKey(connectionId)) ?? '';

Future<void> deletePassword(String connectionId) =>
    _storage.delete(key: _pwdKey(connectionId));

Future<void> savePrivateKey(String connectionId, String pemContent) =>
    _storage.write(key: _keyKey(connectionId), value: pemContent);

Future<String?> loadPrivateKey(String connectionId) =>
    _storage.read(key: _keyKey(connectionId));

Future<void> deletePrivateKey(String connectionId) =>
    _storage.delete(key: _keyKey(connectionId));

Future<void> saveKeyPassphrase(String connectionId, String passphrase) =>
    _storage.write(key: _passphraseKey(connectionId), value: passphrase);

Future<String?> loadKeyPassphrase(String connectionId) =>
    _storage.read(key: _passphraseKey(connectionId));

Future<void> deleteKeyPassphrase(String connectionId) =>
    _storage.delete(key: _passphraseKey(connectionId));
