import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../i18n/app_localizations.dart';
import '../../models/connection.dart';
import '../../providers/connections_provider.dart';

class ConnectionCard extends StatelessWidget {
  final Connection connection;
  const ConnectionCard({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    final isRdp = connection.type == ConnectionType.rdp;
    final accent = isRdp ? const Color(0xFF37D6C2) : const Color(0xFFA78BFA);
    final l10n = context.l10n;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _connect(context),
        onLongPress: () => _showOptions(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(
                    isRdp ? Icons.desktop_windows_outlined : Icons.terminal,
                    color: accent,
                    size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            connection.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _MetaChip(label: isRdp ? 'RDP' : 'SSH', color: accent),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${connection.username}@${connection.host}:${connection.port}',
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (connection.lastOpenedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.lastUsed(
                            _formatDateTime(connection.lastOpenedAt!)),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (isRdp) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _MetaChip(
                            label:
                                '${connection.width ?? 1600}x${connection.height ?? 900}',
                            color: Theme.of(context).colorScheme.tertiary,
                            dense: true,
                          ),
                          if (connection.rdpSecurity != null &&
                              connection.rdpSecurity !=
                                  RdpSecurityProtocol.auto) ...[
                            const SizedBox(width: 6),
                            _MetaChip(
                              label: connection.rdpSecurity!.shortName,
                              color: const Color(0xFFFFB74D),
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: connection.isFavorite
                    ? l10n.t('unfavoriteConnection')
                    : l10n.t('favoriteConnection'),
                icon: Icon(
                  connection.isFavorite ? Icons.star : Icons.star_border,
                  size: 20,
                ),
                color: connection.isFavorite
                    ? const Color(0xFFFFD54F)
                    : Colors.white38,
                onPressed: () => context
                    .read<ConnectionsProvider>()
                    .toggleFavorite(connection.id),
              ),
              IconButton(
                tooltip: l10n.t('manageConnection'),
                icon: const Icon(Icons.more_vert, size: 20),
                color: Colors.white54,
                onPressed: () => _showOptions(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connect(BuildContext context) async {
    final route = connection.type == ConnectionType.rdp ? '/rdp' : '/ssh';
    final opened =
        await context.read<ConnectionsProvider>().markOpened(connection.id);
    if (!context.mounted) return;
    context.push(route, extra: opened ?? connection);
  }

  void _showOptions(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.read<ConnectionsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                connection.isFavorite ? Icons.star : Icons.star_border,
                color: connection.isFavorite ? const Color(0xFFFFD54F) : null,
              ),
              title: Text(connection.isFavorite
                  ? l10n.t('unfavoriteConnection')
                  : l10n.t('favoriteConnection')),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(provider.toggleFavorite(connection.id));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.t('edit')),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/connection/edit', extra: connection);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.t('duplicateConnection')),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(() async {
                  final copy = await provider.duplicate(
                    connection.id,
                    name: l10n.connectionCopyName(connection.name),
                  );
                  if (copy == null) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.connectionDuplicated(copy.name)),
                    ),
                  );
                }());
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(l10n.t('delete'),
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(provider.remove(connection.id));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool dense;
  const _MetaChip(
      {required this.label, required this.color, this.dense = false});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: dense ? 7 : 8, vertical: dense ? 3 : 4),
          child: Text(
            label,
            style: TextStyle(
                color: color,
                fontSize: dense ? 11 : 12,
                fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}
