import '../models/connection.dart';

class RdpProfileIo {
  static Connection importConnection(
    String raw, {
    required String id,
    String? displayName,
  }) {
    final fields = _parseFields(raw);
    final fullAddress = _requiredString(fields, 'full address');
    final parsedAddress = _parseFullAddress(fullAddress);
    final serverPort = _intField(fields, 'server port');
    final width = _intField(fields, 'desktopwidth');
    final height = _intField(fields, 'desktopheight');
    final username = _stringField(fields, 'username') ?? '';
    final domain = _stringField(fields, 'domain');
    final security = _securityFromFields(fields);
    final name = _cleanDisplayName(displayName) ??
        _stringField(fields, 'connection name') ??
        parsedAddress.host;

    if (!_isValidPort(serverPort ?? parsedAddress.port)) {
      throw const FormatException('RDP profile contains an invalid port.');
    }

    return Connection(
      id: id,
      name: name,
      host: parsedAddress.host,
      port: serverPort ?? parsedAddress.port,
      username: username,
      type: ConnectionType.rdp,
      domain: domain,
      width: width,
      height: height,
      rdpSecurity: security,
    );
  }

  static String exportConnection(Connection connection) {
    if (connection.type != ConnectionType.rdp) {
      throw ArgumentError('Only RDP connections can be exported as .rdp.');
    }
    final width = connection.width ?? 1600;
    final height = connection.height ?? 900;
    final security = connection.rdpSecurity ?? RdpSecurityProtocol.auto;
    final negotiate = security == RdpSecurityProtocol.rdp ? 0 : 1;
    final credSsp = security == RdpSecurityProtocol.nla ? 1 : 0;
    final lines = <String>[
      'full address:s:${connection.host}',
      'server port:i:${connection.port}',
      'username:s:${connection.username}',
      if (connection.domain != null && connection.domain!.isNotEmpty)
        'domain:s:${connection.domain}',
      'desktopwidth:i:$width',
      'desktopheight:i:$height',
      'session bpp:i:32',
      'screen mode id:i:2',
      'use multimon:i:0',
      'authentication level:i:2',
      'negotiate security layer:i:$negotiate',
      'enablecredsspsupport:i:$credSsp',
      'prompt for credentials:i:1',
      'redirectclipboard:i:1',
      'audiomode:i:0',
      'connection name:s:${connection.name}',
    ];
    return '${lines.join('\r\n')}\r\n';
  }

  static String defaultFileName(Connection connection) {
    final safeName = connection.name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '-');
    final base = safeName.isEmpty ? 'nexterm-rdp' : safeName;
    return '$base.rdp';
  }

  static Map<String, _RdpField> _parseFields(String raw) {
    final fields = <String, _RdpField>{};
    for (final line in raw.replaceAll('\r\n', '\n').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final match = RegExp(r'^([^:]+):([a-z]):(.*)$').firstMatch(trimmed);
      if (match == null) {
        throw FormatException('Invalid RDP profile line: $trimmed');
      }
      final key = match.group(1)!.trim().toLowerCase();
      final type = match.group(2)!.toLowerCase();
      final value = match.group(3)!.trim();
      fields[key] = _RdpField(type, value);
    }
    if (fields.isEmpty) {
      throw const FormatException('RDP profile is empty.');
    }
    return fields;
  }

  static String _requiredString(Map<String, _RdpField> fields, String key) {
    final value = _stringField(fields, key);
    if (value == null || value.isEmpty) {
      throw FormatException('RDP profile is missing "$key".');
    }
    return value;
  }

  static String? _stringField(Map<String, _RdpField> fields, String key) {
    final field = fields[key.toLowerCase()];
    if (field == null || field.type != 's') return null;
    final value = field.value.trim();
    return value.isEmpty ? null : value;
  }

  static int? _intField(Map<String, _RdpField> fields, String key) {
    final field = fields[key.toLowerCase()];
    if (field == null || field.type != 'i') return null;
    return int.tryParse(field.value.trim());
  }

  static RdpSecurityProtocol _securityFromFields(
    Map<String, _RdpField> fields,
  ) {
    final negotiate = _intField(fields, 'negotiate security layer');
    final credSsp = _intField(fields, 'enablecredsspsupport');
    if (negotiate == 0) return RdpSecurityProtocol.rdp;
    if (credSsp == 1) return RdpSecurityProtocol.nla;
    return RdpSecurityProtocol.auto;
  }

  static _ParsedAddress _parseFullAddress(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('RDP profile host is empty.');
    }
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end <= 1) {
        throw const FormatException('RDP profile host is invalid.');
      }
      final host = value.substring(1, end);
      final suffix = value.substring(end + 1);
      if (suffix.startsWith(':')) {
        final port = int.tryParse(suffix.substring(1));
        if (!_isValidPort(port)) {
          throw const FormatException('RDP profile contains an invalid port.');
        }
        return _ParsedAddress(host, port!);
      }
      return _ParsedAddress(host, 3389);
    }

    final firstColon = value.indexOf(':');
    final lastColon = value.lastIndexOf(':');
    if (firstColon > 0 && firstColon == lastColon) {
      final host = value.substring(0, lastColon).trim();
      final port = int.tryParse(value.substring(lastColon + 1).trim());
      if (host.isEmpty || !_isValidPort(port)) {
        throw const FormatException('RDP profile contains an invalid port.');
      }
      return _ParsedAddress(host, port!);
    }
    return _ParsedAddress(value, 3389);
  }

  static bool _isValidPort(int? port) =>
      port != null && port > 0 && port < 65536;

  static String? _cleanDisplayName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.endsWith('.rdp')
        ? trimmed.substring(0, trimmed.length - 4).trim()
        : trimmed;
  }
}

class _RdpField {
  final String type;
  final String value;

  const _RdpField(this.type, this.value);
}

class _ParsedAddress {
  final String host;
  final int port;

  const _ParsedAddress(this.host, this.port);
}
