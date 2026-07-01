import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/connection.dart';
import '../../providers/sessions_provider.dart';
import 'session_host.dart';

class SessionArea extends StatelessWidget {
  const SessionArea({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionsProvider>();
    if (sessions.tabs.isEmpty) return const _EmptyState();

    final activeIdx = sessions.tabs.indexWhere((t) => t.id == sessions.activeTabId);
    return Column(
      children: [
        _TabBar(tabs: sessions.tabs, activeId: sessions.activeTabId),
        Expanded(
          child: IndexedStack(
            index: activeIdx.clamp(0, sessions.tabs.length - 1),
            children: sessions.tabs
                .map((tab) => SessionHost(key: ValueKey(tab.id), tab: tab))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  final List<SessionTab> tabs;
  final String? activeId;
  const _TabBar({required this.tabs, required this.activeId});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: const Color(0xFF151A20),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (ctx, i) {
                final tab = tabs[i];
                final active = tab.id == activeId;
                final isRdp = tab.connection.type == ConnectionType.rdp;
                return GestureDetector(
                  onTap: () => context.read<SessionsProvider>().setActive(tab.id),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF1B222A) : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: active ? const Color(0xFF37D6C2) : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRdp ? Icons.desktop_windows : Icons.terminal,
                          size: 13,
                          color: isRdp ? const Color(0xFF37D6C2) : const Color(0xFFA78BFA),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tab.connection.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: active ? Colors.white : Colors.white54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => context.read<SessionsProvider>().closeSession(tab.id),
                          child: Icon(Icons.close, size: 14, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.desktop_windows_outlined, size: 48, color: Colors.white12),
          SizedBox(height: 12),
          Text('Select a connection from the sidebar',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }
}
