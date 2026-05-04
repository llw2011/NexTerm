import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

String _key(String id) => 'pwd_$id';

Future<void> savePassword(String connectionId, String password) =>
    _storage.write(key: _key(connectionId), value: password);

Future<String> loadPassword(String connectionId) async =>
    await _storage.read(key: _key(connectionId)) ?? '';

Future<void> deletePassword(String connectionId) =>
    _storage.delete(key: _key(connectionId));
