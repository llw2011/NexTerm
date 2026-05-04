import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/connections_provider.dart';
import 'connection_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionsProvider>();
    final list = provider.list;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NexTerm', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: list.isEmpty
          ? _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (ctx, i) => ConnectionCard(connection: list[i]),
            ),
      floatingActionButton: _AddButton(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            Text('No connections yet',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white38)),
            const SizedBox(height: 8),
            Text('Tap + to add RDP or SSH',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white24)),
          ],
        ),
      );
}

class _AddButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        child: const Icon(Icons.add),
      );

  void _showAddMenu(BuildContext context) {
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
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.desktop_windows_outlined, color: Color(0xFF00D4FF)),
              title: const Text('RDP Connection'),
              onTap: () { Navigator.pop(context); context.push('/connection/new/rdp'); },
            ),
            ListTile(
              leading: const Icon(Icons.terminal, color: Color(0xFF7B2FF7)),
              title: const Text('SSH Connection'),
              onTap: () { Navigator.pop(context); context.push('/connection/new/ssh'); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
