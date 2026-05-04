import 'dart:convert';

enum ConnectionType { rdp, ssh }

class Connection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final ConnectionType type;
  // RDP extras
  final String? domain;
  final int? width;
  final int? height;

  const Connection({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.type,
    this.domain,
    this.width,
    this.height,
  });

  int get defaultPort => type == ConnectionType.rdp ? 3389 : 22;

  Connection copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? domain,
    int? width,
    int? height,
  }) =>
      Connection(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        type: type,
        domain: domain ?? this.domain,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'type': type.name,
        if (domain != null) 'domain': domain,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };

  factory Connection.fromJson(Map<String, dynamic> j) => Connection(
        id: j['id'] as String,
        name: j['name'] as String,
        host: j['host'] as String,
        port: j['port'] as int,
        username: j['username'] as String,
        type: ConnectionType.values.byName(j['type'] as String),
        domain: j['domain'] as String?,
        width: j['width'] as int?,
        height: j['height'] as int?,
      );

  static List<Connection> listFromJson(String raw) =>
      (jsonDecode(raw) as List).map((e) => Connection.fromJson(e as Map<String, dynamic>)).toList();

  static String listToJson(List<Connection> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
