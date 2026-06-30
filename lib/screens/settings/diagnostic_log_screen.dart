import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/diagnostic_log.dart';
import '../../utils/rdp_service.dart';

class DiagnosticLogScreen extends StatefulWidget {
  const DiagnosticLogScreen({super.key});

  @override
  State<DiagnosticLogScreen> createState() => _DiagnosticLogScreenState();
}

class _DiagnosticLogScreenState extends State<DiagnosticLogScreen> {
  String _latestRdpError = '';
  bool _loadingError = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loadingError = true);
    try {
      final error = await RdpService.getLastError();
      if (!mounted) return;
      setState(() {
        _latestRdpError = error;
        _loadingError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _latestRdpError = '$e';
        _loadingError = false;
      });
    }
  }

  Future<void> _copyRedactedLogs() async {
    final l10n = context.l10n;
    final lines = DiagnosticLog.exportText(redacted: true);
    final nativeError = DiagnosticLogRedactor.redact(_latestRdpError);
    final text = [
      'NexTerm diagnostics',
      'latest_rdp_last_error=${nativeError.isEmpty ? '<empty>' : nativeError}',
      if (lines.isNotEmpty) lines,
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showSnack(l10n.t('diagnosticsCopied'));
  }

  void _clearLogs() {
    final l10n = context.l10n;
    setState(DiagnosticLog.clear);
    _showSnack(l10n.t('diagnosticsCleared'));
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = DiagnosticLog.entries.reversed.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('diagnostics')),
        actions: [
          IconButton(
            tooltip: l10n.t('diagnosticsRefresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: l10n.t('diagnosticsCopyRedacted'),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _copyRedactedLogs,
          ),
          IconButton(
            tooltip: l10n.t('diagnosticsClear'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: entries.isEmpty ? null : _clearLogs,
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: _loadingError
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.memory_outlined),
            title: Text(l10n.t('diagnosticsLatestRdpError')),
            subtitle: SelectableText(
              _latestRdpError.isEmpty
                  ? l10n.t('diagnosticsNoNativeError')
                  : _latestRdpError,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const Divider(height: 1),
          if (entries.isEmpty)
            _EmptyDiagnostics(
              title: l10n.t('diagnosticsEmpty'),
              subtitle: l10n.t('diagnosticsEmptySubtitle'),
            )
          else
            for (final entry in entries) _DiagnosticEntryTile(entry: entry),
        ],
      ),
    );
  }
}

class _DiagnosticEntryTile extends StatelessWidget {
  final DiagnosticLogEntry entry;

  const _DiagnosticEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final local = entry.timestamp.toLocal();
    final title = '${_two(local.hour)}:${_two(local.minute)}:'
        '${_two(local.second)}  ${entry.area}/${entry.stage}';
    final details = <String>[
      if (entry.connectionName != null && entry.connectionName!.isNotEmpty)
        entry.connectionName!,
      if (entry.host != null && entry.host!.isNotEmpty)
        entry.port == null ? entry.host! : '${entry.host}:${entry.port}',
      if (entry.username != null && entry.username!.isNotEmpty) entry.username!,
    ].join('  ');
    return ListTile(
      dense: true,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty) Text(details),
          SelectableText(
            entry.error == null || entry.error!.isEmpty
                ? entry.message
                : '${entry.message}\n${entry.error}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _EmptyDiagnostics extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyDiagnostics({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
