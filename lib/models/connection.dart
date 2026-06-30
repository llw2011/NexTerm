import 'dart:convert';

enum ConnectionType { rdp, ssh }

enum RdpSecurityProtocol {
  auto, // 默认自动选择
  rdp, // 旧 RDP 协议
  nla, // NLA 协议
  tls, // TLS 协议
  ext, // 扩展协议
}

enum SshAuthType { password, privateKey }

enum SshTunnelType { local }

class SshTunnelConfig {
  final String id;
  final SshTunnelType type;
  final bool enabled;
  final String localHost;
  final int localPort;
  final String remoteHost;
  final int remotePort;

  const SshTunnelConfig({
    required this.id,
    this.type = SshTunnelType.local,
    this.enabled = true,
    this.localHost = '127.0.0.1',
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
  });

  SshTunnelConfig copyWith({
    bool? enabled,
    String? localHost,
    int? localPort,
    String? remoteHost,
    int? remotePort,
  }) =>
      SshTunnelConfig(
        id: id,
        type: type,
        enabled: enabled ?? this.enabled,
        localHost: localHost ?? this.localHost,
        localPort: localPort ?? this.localPort,
        remoteHost: remoteHost ?? this.remoteHost,
        remotePort: remotePort ?? this.remotePort,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'enabled': enabled,
        'localHost': localHost,
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
      };

  factory SshTunnelConfig.fromJson(Map<String, dynamic> j) {
    final typeName = j['type'] as String? ?? SshTunnelType.local.name;
    var type = SshTunnelType.local;
    for (final value in SshTunnelType.values) {
      if (value.name == typeName) {
        type = value;
        break;
      }
    }
    final localHost = j['localHost'] as String? ?? '127.0.0.1';
    final localPort = _jsonInt(j['localPort']) ?? 0;
    final remoteHost = j['remoteHost'] as String? ?? '127.0.0.1';
    final remotePort = _jsonInt(j['remotePort']) ?? 0;

    return SshTunnelConfig(
      id: j['id'] as String? ??
          '${type.name}:$localHost:$localPort:$remoteHost:$remotePort',
      type: type,
      enabled: j['enabled'] as bool? ?? true,
      localHost: localHost,
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
  }

  static int? _jsonInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

extension RdpSecurityProtocolExtension on RdpSecurityProtocol {
  String get displayName {
    switch (this) {
      case RdpSecurityProtocol.auto:
        return '自动';
      case RdpSecurityProtocol.rdp:
        return 'RDP';
      case RdpSecurityProtocol.nla:
        return 'NLA';
      case RdpSecurityProtocol.tls:
        return 'TLS';
      case RdpSecurityProtocol.ext:
        return 'EXT';
    }
  }

  String get shortName {
    switch (this) {
      case RdpSecurityProtocol.auto:
        return 'Auto';
      case RdpSecurityProtocol.rdp:
        return 'RDP';
      case RdpSecurityProtocol.nla:
        return 'NLA';
      case RdpSecurityProtocol.tls:
        return 'TLS';
      case RdpSecurityProtocol.ext:
        return 'EXT';
    }
  }
}

class Connection {
  final String id;
  final String name;
  final String? group;
  final String host;
  final int port;
  final String username;
  final ConnectionType type;
  final String? domain;
  final int? width;
  final int? height;
  final RdpSecurityProtocol? rdpSecurity;
  final SshAuthType? sshAuthType;
  final String? sshJumpHostId;
  final List<SshTunnelConfig> sshTunnels;
  final bool isFavorite;
  final DateTime? lastOpenedAt;

  const Connection({
    required this.id,
    required this.name,
    this.group,
    required this.host,
    required this.port,
    required this.username,
    required this.type,
    this.domain,
    this.width,
    this.height,
    this.rdpSecurity,
    this.sshAuthType,
    this.sshJumpHostId,
    this.sshTunnels = const [],
    this.isFavorite = false,
    this.lastOpenedAt,
  });

  int get defaultPort => type == ConnectionType.rdp ? 3389 : 22;

  Connection copyWith({
    String? name,
    String? group,
    String? host,
    int? port,
    String? username,
    String? domain,
    int? width,
    int? height,
    RdpSecurityProtocol? rdpSecurity,
    SshAuthType? sshAuthType,
    String? sshJumpHostId,
    List<SshTunnelConfig>? sshTunnels,
    bool? isFavorite,
    DateTime? lastOpenedAt,
  }) =>
      Connection(
        id: id,
        name: name ?? this.name,
        group: group ?? this.group,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        type: type,
        domain: domain ?? this.domain,
        width: width ?? this.width,
        height: height ?? this.height,
        rdpSecurity: rdpSecurity ?? this.rdpSecurity,
        sshAuthType: sshAuthType ?? this.sshAuthType,
        sshJumpHostId: sshJumpHostId ?? this.sshJumpHostId,
        sshTunnels: sshTunnels ?? this.sshTunnels,
        isFavorite: isFavorite ?? this.isFavorite,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (group != null && group!.isNotEmpty) 'group': group,
        'host': host,
        'port': port,
        'username': username,
        'type': type.name,
        if (domain != null) 'domain': domain,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (rdpSecurity != null) 'rdpSecurity': rdpSecurity!.name,
        if (sshAuthType != null) 'sshAuthType': sshAuthType!.name,
        if (sshJumpHostId != null && sshJumpHostId!.isNotEmpty)
          'sshJumpHostId': sshJumpHostId,
        if (sshTunnels.isNotEmpty)
          'sshTunnels': sshTunnels.map((e) => e.toJson()).toList(),
        if (isFavorite) 'isFavorite': true,
        if (lastOpenedAt != null)
          'lastOpenedAt': lastOpenedAt!.toUtc().toIso8601String(),
      };

  factory Connection.fromJson(Map<String, dynamic> j) => Connection(
        id: j['id'] as String,
        name: j['name'] as String,
        group: _jsonString(j['group']),
        host: j['host'] as String,
        port: j['port'] as int,
        username: j['username'] as String,
        type: ConnectionType.values.byName(j['type'] as String),
        domain: j['domain'] as String?,
        width: j['width'] as int?,
        height: j['height'] as int?,
        rdpSecurity: j['rdpSecurity'] != null
            ? RdpSecurityProtocol.values.byName(j['rdpSecurity'] as String)
            : null,
        sshAuthType: j['sshAuthType'] != null
            ? SshAuthType.values.byName(j['sshAuthType'] as String)
            : null,
        sshJumpHostId: _jsonString(j['sshJumpHostId']),
        sshTunnels: (j['sshTunnels'] as List<dynamic>?)
                ?.map(
                    (e) => SshTunnelConfig.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        isFavorite: j['isFavorite'] as bool? ?? false,
        lastOpenedAt: _jsonDateTime(j['lastOpenedAt']),
      );

  static List<Connection> listFromJson(String raw) => (jsonDecode(raw) as List)
      .map((e) => Connection.fromJson(e as Map<String, dynamic>))
      .toList();

  static String listToJson(List<Connection> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static String? _jsonString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _jsonDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}
