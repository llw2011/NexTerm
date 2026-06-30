class DiagnosticLogEntry {
  final DateTime timestamp;
  final String area;
  final String stage;
  final String message;
  final String? connectionName;
  final String? host;
  final int? port;
  final String? username;
  final String? error;

  DiagnosticLogEntry({
    required this.timestamp,
    required this.area,
    required this.stage,
    required this.message,
    this.connectionName,
    this.host,
    this.port,
    this.username,
    this.error,
  });

  String toLine({bool redacted = false}) {
    final parts = <String>[
      timestamp.toLocal().toIso8601String(),
      '[$area/$stage]',
    ];
    if (connectionName != null && connectionName!.isNotEmpty) {
      parts.add('connection="$connectionName"');
    }
    if (host != null && host!.isNotEmpty) {
      parts.add('host=${port == null ? host : '$host:$port'}');
    }
    if (username != null && username!.isNotEmpty) {
      parts.add('user=$username');
    }
    parts.add(message);
    if (error != null && error!.isNotEmpty) {
      parts.add('error="$error"');
    }

    final line = parts.join(' ');
    return redacted ? DiagnosticLogRedactor.redact(line) : line;
  }
}

class DiagnosticLog {
  static const int maxEntries = 200;
  static final List<DiagnosticLogEntry> _entries = [];

  static List<DiagnosticLogEntry> get entries =>
      List<DiagnosticLogEntry>.unmodifiable(_entries);

  static DiagnosticLogEntry? get latest =>
      _entries.isEmpty ? null : _entries.last;

  static void add(DiagnosticLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  static void rdp({
    required String stage,
    required String message,
    String? connectionName,
    String? host,
    int? port,
    String? username,
    String? error,
  }) {
    add(
      DiagnosticLogEntry(
        timestamp: DateTime.now(),
        area: 'rdp',
        stage: stage,
        message: message,
        connectionName: connectionName,
        host: host,
        port: port,
        username: username,
        error: error,
      ),
    );
  }

  static void clear() {
    _entries.clear();
  }

  static String exportText({bool redacted = true}) {
    if (_entries.isEmpty) return '';
    return _entries.map((entry) => entry.toLine(redacted: redacted)).join('\n');
  }

  static String inferRdpStageFromError(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('nativecreate') ||
        lower.contains('native create') ||
        lower.contains('rdp create failed')) {
      return 'create';
    }
    if (lower.contains('settings') ||
        lower.contains('monitor') ||
        lower.contains('seclevel')) {
      return 'settings';
    }
    if (lower.contains('preconnect') ||
        lower.contains('pre-connect') ||
        lower.contains('utils_reload_channels') ||
        lower.contains('0x00020001')) {
      return 'preconnect';
    }
    if (lower.contains('dns') ||
        lower.contains('name not found') ||
        lower.contains('tcp') ||
        lower.contains('transport') ||
        lower.contains('0x00020005') ||
        lower.contains('0x0002000d')) {
      return 'dns_tcp';
    }
    if (lower.contains('auth') ||
        lower.contains('logon') ||
        lower.contains('0x00020014')) {
      return 'auth';
    }
    if (lower.contains('postconnect') ||
        lower.contains('post-connect') ||
        lower.contains('gdi')) {
      return 'postconnect';
    }
    if (lower.contains('connected')) {
      return 'connected';
    }
    return 'startup';
  }
}

class DiagnosticLogRedactor {
  static final RegExp _privateKeyBlock = RegExp(
    r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
    multiLine: true,
  );
  static final RegExp _githubToken = RegExp(
    r'\b(?:github_' r'pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]{20,})\b',
  );
  static final RegExp _namedSecret = RegExp(
    r'''\b(password|passphrase|token|privateKey|private_key|secret)\s*[:=]\s*("[^"]*"|'[^']*'|[^\s,;\]]+)''',
    caseSensitive: false,
  );
  static final RegExp _jsonSecret = RegExp(
    r'("(?:password|passphrase|token|privateKey|private_key|secret)"\s*:\s*)"[^"]*"',
    caseSensitive: false,
  );
  static final RegExp _uriCredentials = RegExp(
    r'([a-z][a-z0-9+.-]*://)([^/\s:@]+):([^/\s@]+)@',
    caseSensitive: false,
  );

  static String redact(String input) {
    var output = input.replaceAll(
      _privateKeyBlock,
      '-----BEGIN '
      'PRIVATE KEY-----<redacted>-----END '
      'PRIVATE KEY-----',
    );
    output = output.replaceAll(_githubToken, '<redacted-token>');
    output = output.replaceAllMapped(
      _jsonSecret,
      (match) => '${match.group(1)}"<redacted>"',
    );
    output = output.replaceAllMapped(
      _namedSecret,
      (match) => '${match.group(1)}=<redacted>',
    );
    output = output.replaceAllMapped(
      _uriCredentials,
      (match) => '${match.group(1)}<redacted>@',
    );
    return output;
  }
}
