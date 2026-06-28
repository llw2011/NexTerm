import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/rdp_key_test_catalog.dart';
import '../../utils/rdp_service.dart';
import 'keyboard_layout.dart';
import 'keyboard_types.dart';

enum _RdpKeyboardModifier { ctrl, alt, win }

class VirtualKeyboard extends StatefulWidget {
  final int sessionHandle;
  final VoidCallback? onClose;

  const VirtualKeyboard({
    super.key,
    required this.sessionHandle,
    this.onClose,
  });

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard> {
  final Set<_RdpKeyboardModifier> _activeModifiers = {};
  Offset _position = const Offset(16, 96);
  bool _isDragging = false;

  static const _modifierLabels = {
    _RdpKeyboardModifier.ctrl: 'LCtrl',
    _RdpKeyboardModifier.alt: 'LAlt',
    _RdpKeyboardModifier.win: 'LWin',
  };

  static const _orderedModifiers = [
    _RdpKeyboardModifier.ctrl,
    _RdpKeyboardModifier.alt,
    _RdpKeyboardModifier.win,
  ];

  Future<void> _sendKey(int code, {bool extended = false}) async {
    final modifiers = _orderedModifiers
        .where((modifier) => _activeModifiers.contains(modifier))
        .toList();

    for (final modifier in modifiers) {
      await _sendModifier(modifier, true);
    }
    await RdpService.sendKeyEvent(
      widget.sessionHandle,
      code,
      true,
      extended: extended,
    );
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await RdpService.sendKeyEvent(
      widget.sessionHandle,
      code,
      false,
      extended: extended,
    );
    for (final modifier in modifiers.reversed) {
      await _sendModifier(modifier, false);
    }

    if (modifiers.isNotEmpty && mounted) {
      setState(_activeModifiers.clear);
    }
  }

  Future<void> _sendModifier(
    _RdpKeyboardModifier modifier,
    bool down,
  ) async {
    final label = _modifierLabels[modifier]!;
    final key = RdpKeyTestCatalog.byLabel(label);
    await RdpService.sendKeyEvent(
      widget.sessionHandle,
      key.scanCode,
      down,
      extended: key.extended,
    );
  }

  Future<void> _onKey(KeyDefinition key) async {
    final modifier = _modifierFromAction(key.action);
    if (modifier != null) {
      _toggleModifier(modifier);
      return;
    }
    final scanCode = key.virtualKeyCode;
    if (scanCode == null) return;
    await _sendKey(scanCode, extended: key.extended);
  }

  _RdpKeyboardModifier? _modifierFromAction(String? action) {
    switch (action) {
      case 'modifier_ctrl':
        return _RdpKeyboardModifier.ctrl;
      case 'modifier_alt':
        return _RdpKeyboardModifier.alt;
      case 'modifier_win':
        return _RdpKeyboardModifier.win;
    }
    return null;
  }

  void _toggleModifier(_RdpKeyboardModifier modifier) {
    setState(() {
      if (!_activeModifiers.add(modifier)) {
        _activeModifiers.remove(modifier);
      }
    });
  }

  bool _isModifierActive(KeyDefinition key) {
    final modifier = _modifierFromAction(key.action);
    return modifier != null && _activeModifiers.contains(modifier);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (d) {
          setState(() {
            _position = Offset(
              (_position.dx + d.delta.dx).clamp(0, screen.width - 320),
              (_position.dy + d.delta.dy).clamp(0, screen.height - 286),
            );
          });
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: _buildPanel(context),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 100),
      opacity: _isDragging ? 0.82 : 1.0,
      child: Container(
        width: 320,
        height: 286,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F26),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A3040)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(l10n),
            Expanded(child: _buildKeys()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A3040))),
      ),
      child: Row(
        children: [
          const Icon(Icons.keyboard_command_key,
              size: 16, color: Color(0xFF37D6C2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.t('rdpControlKeys'),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: const Icon(Icons.close, size: 18, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildKeys() {
    final layout = KeyboardLayout.getLayout(KeyboardPage.function);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: layout
            .map(
              (row) => Expanded(
                child: Row(
                  children: row
                      .map(
                        (key) => Expanded(
                          child: _KeyBtn(
                            keyDef: key,
                            active: _isModifierActive(key),
                            onTap: () => unawaited(_onKey(key)),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _KeyBtn extends StatelessWidget {
  final KeyDefinition keyDef;
  final bool active;
  final VoidCallback onTap;

  const _KeyBtn({
    required this.keyDef,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = keyDef.getDisplayLabel();
    var bg = const Color(0xFF252830);
    var text = Colors.white;

    if (active) {
      bg = const Color(0xFF1B222A);
      text = const Color(0xFF37D6C2);
    } else if (keyDef.type == KeyType.modifier) {
      bg = const Color(0xFF1A2030);
      text = const Color(0xFF37D6C2);
    } else if (keyDef.type == KeyType.function) {
      bg = const Color(0xFF1E2530);
      text = Colors.white70;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF2A3040)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: TextStyle(color: text, fontSize: 12)),
            ),
          ),
        ),
      ),
    );
  }
}
