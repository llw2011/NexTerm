import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/rdp_key_test_catalog.dart';
import '../../utils/rdp_service.dart';

enum _KeySendMode { press, down, up }

class RdpKeyTestPanel extends StatefulWidget {
  final int sessionHandle;
  final VoidCallback onClose;

  const RdpKeyTestPanel({
    super.key,
    required this.sessionHandle,
    required this.onClose,
  });

  @override
  State<RdpKeyTestPanel> createState() => _RdpKeyTestPanelState();
}

class _RdpKeyTestPanelState extends State<RdpKeyTestPanel> {
  _KeySendMode _mode = _KeySendMode.press;
  final List<String> _recentEvents = [];

  Future<void> _send(RdpKeyTestDefinition key) async {
    switch (_mode) {
      case _KeySendMode.press:
        await RdpService.sendKeyEvent(
          widget.sessionHandle,
          key.scanCode,
          true,
          extended: key.extended,
          debugLabel: key.label,
        );
        await Future<void>.delayed(const Duration(milliseconds: 35));
        await RdpService.sendKeyEvent(
          widget.sessionHandle,
          key.scanCode,
          false,
          extended: key.extended,
          debugLabel: key.label,
        );
        _record(key, 'press');
        break;
      case _KeySendMode.down:
        await RdpService.sendKeyEvent(
          widget.sessionHandle,
          key.scanCode,
          true,
          extended: key.extended,
          debugLabel: key.label,
        );
        _record(key, 'down');
        break;
      case _KeySendMode.up:
        await RdpService.sendKeyEvent(
          widget.sessionHandle,
          key.scanCode,
          false,
          extended: key.extended,
          debugLabel: key.label,
        );
        _record(key, 'up');
        break;
    }
  }

  void _record(RdpKeyTestDefinition key, String action) {
    if (!mounted) return;
    final event =
        '${key.label} $action ${key.scanHex} ext=${key.extended ? 1 : 0}';
    setState(() {
      _recentEvents.insert(0, event);
      if (_recentEvents.length > 5) {
        _recentEvents.removeRange(5, _recentEvents.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom + 12;

    return Positioned(
      right: 12,
      bottom: bottom,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width < 620 ? size.width - 24 : 560,
          maxHeight: size.height * 0.72,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  mode: _mode,
                  onModeChanged: (mode) => setState(() => _mode = mode),
                  onClose: widget.onClose,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KeyGroup(
                          title: 'Nav',
                          keys: RdpKeyTestCatalog.navigation,
                          onKey: _send,
                        ),
                        _KeyGroup(
                          title: 'Edit',
                          keys: RdpKeyTestCatalog.editing,
                          onKey: _send,
                        ),
                        _KeyGroup(
                          title: 'Mods',
                          keys: RdpKeyTestCatalog.modifiers,
                          onKey: _send,
                        ),
                        _KeyGroup(
                          title: 'Fn',
                          keys: RdpKeyTestCatalog.functionKeys,
                          onKey: _send,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _EventLog(events: _recentEvents),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final _KeySendMode mode;
  final ValueChanged<_KeySendMode> onModeChanged;
  final VoidCallback onClose;

  const _Header({
    required this.mode,
    required this.onModeChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        const Icon(Icons.bug_report_outlined,
            size: 18, color: Color(0xFF00D4FF)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.t('rdpKeyTest'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SegmentedButton<_KeySendMode>(
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          segments: [
            ButtonSegment(
              value: _KeySendMode.press,
              label: Text(l10n.t('rdpKeyTestPress')),
            ),
            ButtonSegment(
              value: _KeySendMode.down,
              label: Text(l10n.t('rdpKeyTestDown')),
            ),
            ButtonSegment(
              value: _KeySendMode.up,
              label: Text(l10n.t('rdpKeyTestUp')),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (value) => onModeChanged(value.first),
        ),
        IconButton(
          tooltip: l10n.t('close'),
          icon: const Icon(Icons.close, size: 18),
          color: Colors.white70,
          onPressed: onClose,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        ),
      ],
    );
  }
}

class _KeyGroup extends StatelessWidget {
  final String title;
  final List<RdpKeyTestDefinition> keys;
  final ValueChanged<RdpKeyTestDefinition> onKey;

  const _KeyGroup({
    required this.title,
    required this.keys,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final key in keys)
                SizedBox(
                  width: 76,
                  height: 38,
                  child: OutlinedButton(
                    onPressed: () => onKey(key),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: key.extended
                            ? const Color(0xFF00D4FF)
                            : Colors.white24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            key.label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            key.scanHex,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  final List<String> events;

  const _EventLog({required this.events});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 72,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: events.isEmpty
              ? const Text(
                  'logcat: NexTermJNI',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final event in events)
                      Text(
                        event,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
