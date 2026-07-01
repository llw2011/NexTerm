import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/connection.dart';
import '../../utils/rdp_ffi.dart';
import '../../utils/rdp_service.dart';
import '../../utils/secure_storage.dart';

class RdpScreenWindows extends StatefulWidget {
  final Connection connection;
  final bool embedded;
  const RdpScreenWindows({super.key, required this.connection, this.embedded = false});

  @override
  State<RdpScreenWindows> createState() => _RdpScreenWindowsState();
}

class _RdpScreenWindowsState extends State<RdpScreenWindows> {
  int _handle = 0;
  String _status = 'Connecting...';
  bool _hasError = false;
  bool _connected = false;
  Timer? _frameTimer;
  Timer? _clipTimer;
  ui.Image? _frame;
  late int _rdpW;
  late int _rdpH;
  String _lastClip = '';
  int _pressedButtons = 0;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _rdpW = widget.connection.width ?? 1280;
    _rdpH = widget.connection.height ?? 720;
    _connect();
  }

  Future<void> _connect() async {
    try {
      final password = await loadPassword(widget.connection.id);
      final session = await RdpService.create(
        host: widget.connection.host,
        port: widget.connection.port,
        username: widget.connection.username,
        password: password,
        domain: widget.connection.domain ?? '',
        width: _rdpW,
        height: _rdpH,
        security: widget.connection.rdpSecurity ?? RdpSecurityProtocol.auto,
      );
      _handle = session.handle;
      await RdpService.connect(_handle);
      _watchStartup();
    } catch (e) {
      if (!mounted) return;
      setState(() { _hasError = true; _status = '$e'; });
    }
  }

  void _watchStartup() {
    Timer.periodic(const Duration(milliseconds: 500), (t) async {
      if (!mounted || _handle == 0) { t.cancel(); return; }
      if (await RdpService.isConnected(_handle)) {
        t.cancel();
        setState(() { _connected = true; _status = 'Connected'; });
        _startFrameLoop();
        _startClipboardLoop();
        return;
      }
      if (!(await RdpService.isRunning(_handle))) {
        t.cancel();
        final err = await RdpService.getLastError();
        setState(() { _hasError = true; _status = err.isEmpty ? 'Disconnected' : err; });
      }
    });
  }

  void _startFrameLoop() {
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) => _updateFrame());
  }

  Future<void> _updateFrame() async {
    if (_handle == 0 || !_connected) return;
    final ffi = RdpFfi.instance;
    final buf = ffi.getFrameBuffer(_handle);
    if (buf == nullptr) return;
    final w = ffi.getFrameWidth(_handle);
    final h = ffi.getFrameHeight(_handle);
    if (w <= 0 || h <= 0) return;

    final bytes = buf.asTypedList(w * h * 4);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(bytes), w, h, ui.PixelFormat.bgra8888,
      (img) => completer.complete(img),
    );
    final img = await completer.future;
    if (!mounted) { img.dispose(); return; }
    final old = _frame;
    setState(() { _frame = img; _rdpW = w; _rdpH = h; });
    old?.dispose();
  }

  void _startClipboardLoop() {
    _clipTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_handle == 0) return;
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null && data!.text!.isNotEmpty && data.text != _lastClip) {
          _lastClip = data.text!;
          await RdpService.sendClipboard(_handle, _lastClip);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _clipTimer?.cancel();
    _frame?.dispose();
    _focusNode.dispose();
    if (_handle != 0) RdpService.destroy(_handle);
    super.dispose();
  }

  Offset _toRdp(Offset local, Size viewport) {
    final scale = _fitScale(viewport);
    final origin = _origin(viewport, scale);
    final x = ((local.dx - origin.dx) / scale).clamp(0.0, _rdpW.toDouble());
    final y = ((local.dy - origin.dy) / scale).clamp(0.0, _rdpH.toDouble());
    return Offset(x, y);
  }

  double _fitScale(Size vp) => (vp.width / _rdpW).clamp(0, vp.height / _rdpH).toDouble();
  Offset _origin(Size vp, double s) => Offset((vp.width - _rdpW * s) / 2, (vp.height - _rdpH * s) / 2);

  void _onPointerDown(PointerDownEvent e, Size vp) {
    final rdp = _toRdp(e.localPosition, vp);
    RdpService.sendMouseEvent(_handle, rdp.dx.round(), rdp.dy.round(), MouseFlags.move);
    if (e.buttons & kPrimaryButton != 0) {
      _pressedButtons |= kPrimaryButton;
      RdpService.sendMouseEvent(_handle, rdp.dx.round(), rdp.dy.round(), MouseFlags.leftDown);
    } else if (e.buttons & kSecondaryButton != 0) {
      _pressedButtons |= kSecondaryButton;
      RdpService.sendMouseEvent(_handle, rdp.dx.round(), rdp.dy.round(), MouseFlags.rightDown);
    } else if (e.buttons & kTertiaryButton != 0) {
      _pressedButtons |= kTertiaryButton;
    }
  }

  void _onPointerMove(PointerMoveEvent e, Size vp) {
    final rdp = _toRdp(e.localPosition, vp);
    RdpService.sendMouseEvent(_handle, rdp.dx.round(), rdp.dy.round(), MouseFlags.move);
  }

  void _onPointerUp(PointerUpEvent e, Size vp) {
    final rdp = _toRdp(e.localPosition, vp);
    if (_pressedButtons & kPrimaryButton != 0) {
      RdpService.sendMouseEvent(_handle, rdp.dx.round(), rdp.dy.round(), MouseFlags.leftUp);
    }
    if (_pressedButtons & kSecondaryButton != 0) {
      RdpService.sendMouseEvent(_handle, rdp.dx.round(), rdp.dy.round(), MouseFlags.rightUp);
    }
    _pressedButtons = 0;
  }

  void _onPointerSignal(PointerSignalEvent e, Size vp) {
    if (e is PointerScrollEvent) {
      final rdp = _toRdp(e.localPosition, vp);
      final flags = e.scrollDelta.dy < 0 ? MouseFlags.wheelUp : MouseFlags.wheelDown;
      RdpService.sendMouseEvent(_handle, rdp.dx.round(), rdp.dy.round(), flags);
    }
  }

  // Keyboard scan code mapping
  static final _keyMap = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.escape: 0x01,
    LogicalKeyboardKey.f1: 0x3B, LogicalKeyboardKey.f2: 0x3C,
    LogicalKeyboardKey.f3: 0x3D, LogicalKeyboardKey.f4: 0x3E,
    LogicalKeyboardKey.f5: 0x3F, LogicalKeyboardKey.f6: 0x40,
    LogicalKeyboardKey.f7: 0x41, LogicalKeyboardKey.f8: 0x42,
    LogicalKeyboardKey.f9: 0x43, LogicalKeyboardKey.f10: 0x44,
    LogicalKeyboardKey.f11: 0x57, LogicalKeyboardKey.f12: 0x58,
    LogicalKeyboardKey.backquote: 0x29,
    LogicalKeyboardKey.digit1: 0x02, LogicalKeyboardKey.digit2: 0x03,
    LogicalKeyboardKey.digit3: 0x04, LogicalKeyboardKey.digit4: 0x05,
    LogicalKeyboardKey.digit5: 0x06, LogicalKeyboardKey.digit6: 0x07,
    LogicalKeyboardKey.digit7: 0x08, LogicalKeyboardKey.digit8: 0x09,
    LogicalKeyboardKey.digit9: 0x0A, LogicalKeyboardKey.digit0: 0x0B,
    LogicalKeyboardKey.minus: 0x0C, LogicalKeyboardKey.equal: 0x0D,
    LogicalKeyboardKey.backspace: 0x0E, LogicalKeyboardKey.tab: 0x0F,
    LogicalKeyboardKey.keyQ: 0x10, LogicalKeyboardKey.keyW: 0x11,
    LogicalKeyboardKey.keyE: 0x12, LogicalKeyboardKey.keyR: 0x13,
    LogicalKeyboardKey.keyT: 0x14, LogicalKeyboardKey.keyY: 0x15,
    LogicalKeyboardKey.keyU: 0x16, LogicalKeyboardKey.keyI: 0x17,
    LogicalKeyboardKey.keyO: 0x18, LogicalKeyboardKey.keyP: 0x19,
    LogicalKeyboardKey.bracketLeft: 0x1A, LogicalKeyboardKey.bracketRight: 0x1B,
    LogicalKeyboardKey.enter: 0x1C, LogicalKeyboardKey.capsLock: 0x3A,
    LogicalKeyboardKey.keyA: 0x1E, LogicalKeyboardKey.keyS: 0x1F,
    LogicalKeyboardKey.keyD: 0x20, LogicalKeyboardKey.keyF: 0x21,
    LogicalKeyboardKey.keyG: 0x22, LogicalKeyboardKey.keyH: 0x23,
    LogicalKeyboardKey.keyJ: 0x24, LogicalKeyboardKey.keyK: 0x25,
    LogicalKeyboardKey.keyL: 0x26, LogicalKeyboardKey.semicolon: 0x27,
    LogicalKeyboardKey.quote: 0x28, LogicalKeyboardKey.backslash: 0x2B,
    LogicalKeyboardKey.shiftLeft: 0x2A,
    LogicalKeyboardKey.keyZ: 0x2C, LogicalKeyboardKey.keyX: 0x2D,
    LogicalKeyboardKey.keyC: 0x2E, LogicalKeyboardKey.keyV: 0x2F,
    LogicalKeyboardKey.keyB: 0x30, LogicalKeyboardKey.keyN: 0x31,
    LogicalKeyboardKey.keyM: 0x32, LogicalKeyboardKey.comma: 0x33,
    LogicalKeyboardKey.period: 0x34, LogicalKeyboardKey.slash: 0x35,
    LogicalKeyboardKey.shiftRight: 0x36,
    LogicalKeyboardKey.controlLeft: 0x1D, LogicalKeyboardKey.altLeft: 0x38,
    LogicalKeyboardKey.space: 0x39,
    LogicalKeyboardKey.printScreen: 0x37,
    LogicalKeyboardKey.scrollLock: 0x46, LogicalKeyboardKey.pause: 0x45,
    LogicalKeyboardKey.numLock: 0x45,
  };

  static final _extKeyMap = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.insert: 0x52, LogicalKeyboardKey.delete: 0x53,
    LogicalKeyboardKey.home: 0x47, LogicalKeyboardKey.end: 0x4F,
    LogicalKeyboardKey.pageUp: 0x49, LogicalKeyboardKey.pageDown: 0x51,
    LogicalKeyboardKey.arrowUp: 0x48, LogicalKeyboardKey.arrowDown: 0x50,
    LogicalKeyboardKey.arrowLeft: 0x4B, LogicalKeyboardKey.arrowRight: 0x4D,
    LogicalKeyboardKey.controlRight: 0x1D, LogicalKeyboardKey.altRight: 0x38,
    LogicalKeyboardKey.metaLeft: 0x5B, LogicalKeyboardKey.metaRight: 0x5C,
  };

  void _onKey(KeyEvent event) {
    if (_handle == 0 || !_connected) return;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final key = event.logicalKey;

    if (_keyMap.containsKey(key)) {
      RdpService.sendKeyEvent(_handle, _keyMap[key]!, down);
      return;
    }
    if (_extKeyMap.containsKey(key)) {
      RdpService.sendKeyEvent(_handle, _extKeyMap[key]!, down, extended: true);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _connected && _frame != null ? _buildDesktop() : _buildStatus();
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: Colors.black,
      body: content,
    );
  }

  Widget _buildStatus() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_hasError) const CircularProgressIndicator(color: Color(0xFF00D4FF))
          else const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          SelectableText(_status, style: TextStyle(
            color: _hasError ? Colors.redAccent : Colors.white54,
            fontSize: 13, fontFamily: 'monospace',
          )),
        ],
      ),
    );
  }

  Widget _buildDesktop() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final vp = Size(constraints.maxWidth, constraints.maxHeight);
      return KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (e) => _onPointerDown(e, vp),
          onPointerMove: (e) => _onPointerMove(e, vp),
          onPointerUp: (e) => _onPointerUp(e, vp),
          onPointerSignal: (e) => _onPointerSignal(e, vp),
          child: MouseRegion(
            cursor: SystemMouseCursors.none,
            child: CustomPaint(
              size: vp,
              painter: _RdpPainter(_frame!, _rdpW, _rdpH, vp),
            ),
          ),
        ),
      );
    });
  }
}

class _RdpPainter extends CustomPainter {
  final ui.Image image;
  final int rdpW, rdpH;
  final Size viewport;
  _RdpPainter(this.image, this.rdpW, this.rdpH, this.viewport);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / rdpW).clamp(0, size.height / rdpH).toDouble();
    final dx = (size.width - rdpW * scale) / 2;
    final dy = (size.height - rdpH * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RdpPainter old) => true;
}
