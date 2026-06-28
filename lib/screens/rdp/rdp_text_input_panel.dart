import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/rdp_service.dart';

class RdpTextInputPanel extends StatefulWidget {
  final int sessionHandle;
  final VoidCallback onClose;
  final VoidCallback onControlKeys;

  const RdpTextInputPanel({
    super.key,
    required this.sessionHandle,
    required this.onClose,
    required this.onControlKeys,
  });

  @override
  State<RdpTextInputPanel> createState() => _RdpTextInputPanelState();
}

class _RdpTextInputPanelState extends State<RdpTextInputPanel> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _mutatingText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (_mutatingText) return;
    final value = _controller.value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    final text = value.text;
    if (text.isEmpty) return;

    unawaited(_sendText(text));
    _mutatingText = true;
    _controller.clear();
    _mutatingText = false;
  }

  Future<void> _sendText(String text) async {
    for (final codepoint in text.runes) {
      if (codepoint <= 0 || codepoint > 0xFFFF) continue;
      await RdpService.sendUnicodeEvent(widget.sessionHandle, codepoint);
    }
  }

  Future<void> _sendKey(int scanCode, {bool extended = false}) async {
    await RdpService.sendKeyEvent(
      widget.sessionHandle,
      scanCode,
      true,
      extended: extended,
    );
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await RdpService.sendKeyEvent(
      widget.sessionHandle,
      scanCode,
      false,
      extended: extended,
    );
    if (mounted) _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottom = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom +
        12;

    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF141922).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: true,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  cursorColor: const Color(0xFF00D4FF),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.t('rdpNativeInputHint'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E2530),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                  ),
                  onSubmitted: (_) {
                    if (_controller.text.isEmpty) {
                      unawaited(_sendKey(0x1C));
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              _InputButton(
                icon: Icons.backspace_outlined,
                tooltip: l10n.t('rdpRemoteBackspace'),
                onPressed: () => unawaited(_sendKey(0x0E)),
              ),
              _InputButton(
                icon: Icons.keyboard_return,
                tooltip: l10n.t('rdpRemoteEnter'),
                onPressed: () => unawaited(_sendKey(0x1C)),
              ),
              _InputButton(
                icon: Icons.keyboard_command_key,
                tooltip: l10n.t('rdpControlKeys'),
                onPressed: widget.onControlKeys,
              ),
              _InputButton(
                icon: Icons.close,
                tooltip: l10n.t('close'),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _InputButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: Colors.white70,
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      ),
    );
  }
}
