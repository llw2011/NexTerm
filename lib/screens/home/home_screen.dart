import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../i18n/app_localizations.dart';
import '../../models/connection.dart';
import '../../providers/connections_provider.dart';
import 'connection_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ConnectionType? _filter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConnectionsProvider>();
    final list = provider.list;
    final filtered = list
        .where((connection) => _filter == null || connection.type == _filter)
        .toList();
    final visible = filtered.where(_matchesQuery).toList();
    final hasGroupedConnections = filtered.any(_hasGroup);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NexTerm'),
        actions: [
          IconButton(
            tooltip: l10n.t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: list.isEmpty
          ? _EmptyState(onAdd: () => _showAddMenu(context))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _ConnectionOverview(total: list.length),
                const SizedBox(height: 14),
                _ConnectionSearchField(
                  query: _query,
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () => setState(() => _query = ''),
                ),
                const SizedBox(height: 12),
                _ProtocolFilter(
                  selected: _filter,
                  onChanged: (value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 14),
                if (visible.isEmpty)
                  _FilteredEmptyState(filter: _filter, hasQuery: _hasQuery)
                else if (hasGroupedConnections)
                  ..._buildGroupedEntries(context, visible)
                else
                  for (final connection in visible) ...[
                    ConnectionCard(connection: connection),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMenu(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.t('add')),
      ),
    );
  }

  bool get _hasQuery => _query.trim().isNotEmpty;

  bool _matchesQuery(Connection connection) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return connection.name.toLowerCase().contains(q) ||
        connection.host.toLowerCase().contains(q) ||
        connection.username.toLowerCase().contains(q) ||
        (connection.group?.toLowerCase().contains(q) ?? false);
  }

  bool _hasGroup(Connection connection) =>
      connection.group?.trim().isNotEmpty == true;

  List<Widget> _buildGroupedEntries(
    BuildContext context,
    List<Connection> visible,
  ) {
    final l10n = context.l10n;
    final sections = <_ConnectionGroupSection>[];
    final ungrouped =
        visible.where((connection) => !_hasGroup(connection)).toList();
    if (ungrouped.isNotEmpty) {
      sections.add(
        _ConnectionGroupSection(
          title: l10n.t('ungroupedConnections'),
          connections: ungrouped,
        ),
      );
    }

    final grouped = <String, List<Connection>>{};
    for (final connection in visible) {
      final group = connection.group?.trim();
      if (group == null || group.isEmpty) continue;
      grouped.putIfAbsent(group, () => []).add(connection);
    }

    final sortedGroupNames = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final groupName in sortedGroupNames) {
      sections.add(
        _ConnectionGroupSection(
          title: groupName,
          connections: grouped[groupName]!,
        ),
      );
    }

    final widgets = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      widgets
        ..add(_ConnectionGroupHeader(
          title: section.title,
          count: section.connections.length,
        ))
        ..add(const SizedBox(height: 8));
      for (var j = 0; j < section.connections.length; j++) {
        widgets.add(ConnectionCard(connection: section.connections[j]));
        if (j != section.connections.length - 1) {
          widgets.add(const SizedBox(height: 10));
        }
      }
      if (i != sections.length - 1) {
        widgets.add(const SizedBox(height: 14));
      }
    }
    return widgets;
  }

  void _showAddMenu(BuildContext context) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.desktop_windows_outlined,
                  color: Color(0xFF37D6C2)),
              title: Text(l10n.t('rdpConnection')),
              onTap: () {
                Navigator.pop(context);
                context.push('/connection/new/rdp');
              },
            ),
            ListTile(
              leading: const Icon(Icons.terminal, color: Color(0xFFA78BFA)),
              title: Text(l10n.t('sshConnection')),
              onTap: () {
                Navigator.pop(context);
                context.push('/connection/new/ssh');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ConnectionSearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _ConnectionSearchField({
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_ConnectionSearchField> createState() => _ConnectionSearchFieldState();
}

class _ConnectionSearchFieldState extends State<_ConnectionSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _focusNode = FocusNode(debugLabel: 'connection search');
  }

  @override
  void didUpdateWidget(covariant _ConnectionSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _controller.text != widget.query) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: (_) => _focusNode.unfocus(),
      onTapOutside: (_) => _focusNode.unfocus(),
      decoration: InputDecoration(
        hintText: l10n.t('connectionSearchHint'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: widget.query.isEmpty
            ? null
            : IconButton(
                tooltip: l10n.t('clearSearch'),
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  widget.onClear();
                },
              ),
      ),
    );
  }
}

class _ConnectionOverview extends StatelessWidget {
  final int total;
  const _ConnectionOverview({required this.total});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.hub_outlined,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.t('connections'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.connectionCount(total)} · ${l10n.t('tapCardConnect')}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(l10n.t('readyToConnect'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ProtocolFilter extends StatelessWidget {
  final ConnectionType? selected;
  final ValueChanged<ConnectionType?> onChanged;
  const _ProtocolFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = selected?.name ?? 'all';
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
            value: 'all',
            label: Text(l10n.t('all')),
            icon: const Icon(Icons.view_list_outlined)),
        const ButtonSegment(
            value: 'rdp',
            label: Text('RDP'),
            icon: Icon(Icons.desktop_windows_outlined)),
        const ButtonSegment(
            value: 'ssh', label: Text('SSH'), icon: Icon(Icons.terminal)),
      ],
      selected: {value},
      onSelectionChanged: (next) {
        final picked = next.first;
        onChanged(
            picked == 'all' ? null : ConnectionType.values.byName(picked));
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              l10n.t('noConnectionsYet'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('tapAddConnection'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white38),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: Text(l10n.t('addConnection'))),
          ],
        ),
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  final ConnectionType? filter;
  final bool hasQuery;
  const _FilteredEmptyState({required this.filter, required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = filter == ConnectionType.rdp ? 'RDP' : 'SSH';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.filter_alt_off_outlined,
              color: Colors.white24, size: 42),
          const SizedBox(height: 10),
          Text(
            hasQuery ? l10n.t('noMatchingConnections') : label,
            style: const TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ConnectionGroupSection {
  final String title;
  final List<Connection> connections;

  const _ConnectionGroupSection({
    required this.title,
    required this.connections,
  });
}

class _ConnectionGroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _ConnectionGroupHeader({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
