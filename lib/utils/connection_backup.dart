import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../models/connection.dart';
import '../providers/connections_provider.dart';
import 'secure_storage.dart';

class ConnectionBackupResult {
  final int total;
  final int added;
  final int updated;

  const ConnectionBackupResult({
    required this.total,
    required this.added,
    required this.updated,
  });
}

class ConnectionBackupService {
  static const format = 'nexterm.connections.backup';
  static const version = 1;
  static const encryptedVersion = 2;
  static const encryptedCipher = 'AES-256-GCM';
  static const encryptedKdf = 'PBKDF2-HMAC-SHA256';
  static const kdfIterations = 120000;

  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _keyLength = 32;
  static const _macSizeBits = 128;

  static Future<String> exportJson(List<Connection> connections) async {
    return const JsonEncoder.withIndent('  ').convert(
      await _buildPlainBackup(connections),
    );
  }

  static Future<String> exportEncryptedJson(
    List<Connection> connections,
    String passphrase,
  ) async {
    if (passphrase.isEmpty) {
      throw const FormatException('Backup passphrase is required.');
    }

    final plainJson = const JsonEncoder.withIndent('  ').convert(
      await _buildPlainBackup(connections),
    );
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = _deriveKey(passphrase, salt, kdfIterations);
    final encrypted = _crypt(
      encrypt: true,
      key: key,
      nonce: nonce,
      input: Uint8List.fromList(utf8.encode(plainJson)),
    );

    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': encryptedVersion,
      'encrypted': true,
      'cipher': encryptedCipher,
      'kdf': encryptedKdf,
      'iterations': kdfIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'payload': base64Encode(encrypted),
    });
  }

  static bool isEncryptedJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> &&
          decoded['format'] == format &&
          decoded['version'] == encryptedVersion &&
          decoded['encrypted'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> _buildPlainBackup(
    List<Connection> connections,
  ) async {
    final entries = <Map<String, dynamic>>[];
    for (final connection in connections) {
      entries.add({
        'connection': connection.toJson(),
        'credentials': {
          'password': await loadPassword(connection.id),
          'privateKey': await loadPrivateKey(connection.id),
          'keyPassphrase': await loadKeyPassphrase(connection.id),
        },
      });
    }

    return {
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'containsCredentials': true,
      'connections': entries,
    };
  }

  static Future<ConnectionBackupResult> importJson(
    String raw,
    ConnectionsProvider provider, {
    String? passphrase,
  }) async {
    final decoded = _decodeBackup(raw, passphrase: passphrase);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['version'] != version ||
        decoded['connections'] is! List) {
      throw const FormatException('Invalid NexTerm backup file.');
    }

    final imported = <Connection>[];
    for (final item in decoded['connections'] as List) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final connectionJson = item['connection'];
      if (connectionJson is! Map<String, dynamic>) {
        continue;
      }

      final connection = Connection.fromJson(connectionJson);
      imported.add(connection);

      final credentials = item['credentials'];
      if (credentials is Map<String, dynamic>) {
        await savePassword(
            connection.id, credentials['password'] as String? ?? '');

        final privateKey = credentials['privateKey'] as String?;
        if (privateKey != null && privateKey.isNotEmpty) {
          await savePrivateKey(connection.id, privateKey);
        } else {
          await deletePrivateKey(connection.id);
        }

        final passphrase = credentials['keyPassphrase'] as String?;
        if (passphrase != null && passphrase.isNotEmpty) {
          await saveKeyPassphrase(connection.id, passphrase);
        } else {
          await deleteKeyPassphrase(connection.id);
        }
      }
    }

    final summary = await provider.mergeConnections(imported);
    return ConnectionBackupResult(
      total: imported.length,
      added: summary.added,
      updated: summary.updated,
    );
  }

  static dynamic _decodeBackup(String raw, {String? passphrase}) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> &&
        decoded['format'] == format &&
        decoded['version'] == encryptedVersion &&
        decoded['encrypted'] == true) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException('Backup passphrase is required.');
      }
      return jsonDecode(_decryptPayload(decoded, passphrase));
    }
    return decoded;
  }

  static String _decryptPayload(
    Map<String, dynamic> decoded,
    String passphrase,
  ) {
    if (decoded['cipher'] != encryptedCipher ||
        decoded['kdf'] != encryptedKdf) {
      throw const FormatException('Unsupported encrypted backup format.');
    }

    try {
      final iterations = decoded['iterations'] as int;
      final salt = base64Decode(decoded['salt'] as String);
      final nonce = base64Decode(decoded['nonce'] as String);
      final payload = base64Decode(decoded['payload'] as String);
      final key = _deriveKey(passphrase, salt, iterations);
      final plain = _crypt(
        encrypt: false,
        key: key,
        nonce: nonce,
        input: payload,
      );
      return utf8.decode(plain);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Could not decrypt backup. Check the passphrase.',
      );
    }
  }

  static Uint8List _deriveKey(
    String passphrase,
    Uint8List salt,
    int iterations,
  ) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _crypt({
    required bool encrypt,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List input,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(
          KeyParameter(key),
          _macSizeBits,
          nonce,
          Uint8List(0),
        ),
      );
    return cipher.process(input);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
