import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class KnownHostEntry {
  final String host;
  final int port;
  final String fingerprint;

  const KnownHostEntry({
    required this.host,
    required this.port,
    required this.fingerprint,
  });
}

class KnownHosts {
  static const _prefix = 'known_host_';

  static String _key(String host, int port) =>
      '$_prefix${host.toLowerCase()}:$port';

  static String fingerprintHex(Uint8List fp) =>
      fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');

  static Future<String?> load(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(host, port));
  }

  static Future<void> save(String host, int port, String fpHex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(host, port), fpHex);
  }

  static Future<void> remove(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(host, port));
  }

  static Future<List<KnownHostEntry>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <KnownHostEntry>[];

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;

      final hostPort = key.substring(_prefix.length);
      final separator = hostPort.lastIndexOf(':');
      if (separator <= 0 || separator == hostPort.length - 1) continue;

      final port = int.tryParse(hostPort.substring(separator + 1));
      final fingerprint = prefs.getString(key);
      if (port == null || fingerprint == null || fingerprint.isEmpty) {
        continue;
      }

      entries.add(
        KnownHostEntry(
          host: hostPort.substring(0, separator),
          port: port,
          fingerprint: fingerprint,
        ),
      );
    }

    entries.sort((a, b) {
      final host = a.host.compareTo(b.host);
      if (host != 0) return host;
      return a.port.compareTo(b.port);
    });
    return entries;
  }
}
