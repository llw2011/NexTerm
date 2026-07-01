import 'package:flutter/material.dart';
import 'session_area.dart';
import 'sidebar.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  bool _sidebarCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          if (!_sidebarCollapsed)
            SizedBox(
              width: 260,
              child: Sidebar(onCollapse: () => setState(() => _sidebarCollapsed = true)),
            )
          else
            _CollapsedStrip(onExpand: () => setState(() => _sidebarCollapsed = false)),
          Container(width: 1, color: Theme.of(context).colorScheme.outline),
          const Expanded(child: SessionArea()),
        ],
      ),
    );
  }
}

class _CollapsedStrip extends StatelessWidget {
  final VoidCallback onExpand;
  const _CollapsedStrip({required this.onExpand});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      color: const Color(0xFF151A20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.menu, size: 20),
            color: Colors.white70,
            onPressed: onExpand,
          ),
        ],
      ),
    );
  }
}
