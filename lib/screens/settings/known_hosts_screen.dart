import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/known_hosts.dart';

class KnownHostsScreen extends StatefulWidget {
  const KnownHostsScreen({super.key});

  @override
  State<KnownHostsScreen> createState() => _KnownHostsScreenState();
}

class _KnownHostsScreenState extends State<KnownHostsScreen> {
  late Future<List<KnownHostEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = KnownHosts.list();
  }

  void _reload() {
    setState(() => _future = KnownHosts.list());
  }

  Future<void> _delete(KnownHostEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('knownHostDeleteTitle')),
        content: Text(
          l10n
              .t('knownHostDeleteBody')
              .replaceAll('{host}', entry.host)
              .replaceAll('{port}', entry.port.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await KnownHosts.remove(entry.host, entry.port);
      if (!mounted) return;
      _showSnack(l10n.t('knownHostDeleted'));
      _reload();
    } catch (e) {
      if (mounted) {
        _showSnack('${l10n.t('knownHostDeleteFailed')}: $e');
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('knownHosts')),
        actions: [
          IconButton(
            tooltip: l10n.t('knownHostsRefresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<KnownHostEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? const <KnownHostEntry>[];
          if (entries.isEmpty) {
            return _EmptyKnownHosts(
              title: l10n.t('knownHostsEmpty'),
              subtitle: l10n.t('knownHostsEmptySubtitle'),
            );
          }

          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text('${entry.host}:${entry.port}'),
                subtitle: SelectableText(
                  entry.fingerprint,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  tooltip: l10n.t('delete'),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.redAccent,
                  onPressed: () => _delete(entry),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyKnownHosts extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyKnownHosts({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined, size: 48, color: Colors.white54),
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
