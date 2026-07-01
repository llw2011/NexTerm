import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/connection.dart';
import '../../providers/connections_provider.dart';
import '../../providers/sessions_provider.dart';
import '../../screens/home/edit_connection_screen.dart';
import '../../screens/settings/settings_screen.dart';

class Sidebar extends StatelessWidget {
  final VoidCallback onCollapse;
  const Sidebar({super.key, required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    final connections = context.watch<ConnectionsProvider>().list;
    return Container(
      color: const Color(0xFF151A20),
      child: Column(
        children: [
          _Header(onCollapse: onCollapse, onAdd: () => _showAddDialog(context)),
          const Divider(height: 1),
          Expanded(
            child: connections.isEmpty
                ? const Center(
                    child: Text('No connections',
                        style: TextStyle(color: Colors.white38, fontSize: 13)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: connections.length,
                    itemBuilder: (ctx, i) =>
                        _ConnectionTile(connection: connections[i]),
                  ),
          ),
          const Divider(height: 1),
          _Footer(),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showMenu<ConnectionType>(
      context: context,
      position: const RelativeRect.fromLTRB(60, 40, 0, 0),
      items: const [
        PopupMenuItem(value: ConnectionType.rdp, child: Text('RDP')),
        PopupMenuItem(value: ConnectionType.ssh, child: Text('SSH')),
      ],
    ).then((type) {
      if (type != null && context.mounted) {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            child: SizedBox(
              width: 480,
              height: 560,
              child: EditConnectionScreen(type: type),
            ),
          ),
        );
      }
    });
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onCollapse;
  final VoidCallback onAdd;
  const _Header({required this.onCollapse, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.terminal, color: Color(0xFF37D6C2), size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('NexTerm',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            color: Colors.white70,
            onPressed: onAdd,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            color: Colors.white70,
            onPressed: onCollapse,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            color: Colors.white54,
            onPressed: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                child:
                    SizedBox(width: 480, height: 500, child: SettingsScreen()),
              ),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final Connection connection;
  const _ConnectionTile({required this.connection});

  @override
  Widget build(BuildContext context) {
    final isRdp = connection.type == ConnectionType.rdp;
    return GestureDetector(
      onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
      child: ListTile(
        dense: true,
        leading: Icon(
          isRdp ? Icons.desktop_windows : Icons.terminal,
          size: 16,
          color: isRdp ? const Color(0xFF37D6C2) : const Color(0xFFA78BFA),
        ),
        title: Text(connection.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          '${connection.host}:${connection.port}',
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
        onTap: () => unawaited(_openSession(context)),
      ),
    );
  }

  Future<void> _openSession(BuildContext context) async {
    final opened =
        await context.read<ConnectionsProvider>().markOpened(connection.id);
    if (!context.mounted) return;
    context.read<SessionsProvider>().openSession(opened ?? connection);
  }

  void _showContextMenu(BuildContext context, Offset pos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: const [
        PopupMenuItem(value: 'connect', child: Text('Connect')),
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    ).then((action) {
      if (!context.mounted) return;
      switch (action) {
        case 'connect':
          unawaited(_openSession(context));
        case 'edit':
          showDialog(
            context: context,
            builder: (_) => Dialog(
              child: SizedBox(
                width: 480,
                height: 560,
                child: EditConnectionScreen(
                    type: connection.type, existing: connection),
              ),
            ),
          );
        case 'delete':
          context.read<ConnectionsProvider>().remove(connection.id);
      }
    });
  }
}
