import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/connection.dart';
import '../../providers/connections_provider.dart';

class ConnectionCard extends StatelessWidget {
  final Connection connection;
  const ConnectionCard({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    final isRdp = connection.type == ConnectionType.rdp;
    final accent = isRdp ? const Color(0xFF00D4FF) : const Color(0xFF7B2FF7);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _connect(context),
        onLongPress: () => _showOptions(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isRdp ? Icons.desktop_windows_outlined : Icons.terminal,
                  color: accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connection.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('${connection.username}@${connection.host}:${connection.port}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  void _connect(BuildContext context) {
    final route = connection.type == ConnectionType.rdp ? '/rdp' : '/ssh';
    context.push(route, extra: connection);
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                context.push('/connection/edit', extra: connection);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                context.read<ConnectionsProvider>().remove(connection.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
