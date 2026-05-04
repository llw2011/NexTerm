import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/connection.dart';
import '../../utils/rdp_service.dart';
import '../../utils/secure_storage.dart';

class RdpScreen extends StatefulWidget {
  final Connection connection;
  const RdpScreen({super.key, required this.connection});

  @override
  State<RdpScreen> createState() => _RdpScreenState();
}

class _RdpScreenState extends State<RdpScreen> {
  RdpSession? _session;
  String _status = 'Connecting…';
  bool _hasError = false;
  bool _showToolbar = true;

  // Viewport scale/offset for pan+zoom
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;

  // RDP canvas size
  late int _rdpW;
  late int _rdpH;

  @override
  void initState() {
    super.initState();
    _rdpW = widget.connection.width  ?? 1280;
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
      );
      setState(() { _session = session; _status = 'Connected'; });
      await RdpService.connect(session.handle);
    } on PlatformException catch (e) {
      setState(() { _hasError = true; _status = '[${e.code}] ${e.message}'; });
    } catch (e) {
      setState(() { _hasError = true; _status = '$e'; });
    }
  }

  @override
  void dispose() {
    if (_session != null) RdpService.destroy(_session!.handle);
    super.dispose();
  }

  // Convert screen tap position → RDP coordinates
  Offset _toRdp(Offset screen) {
    final sz = MediaQuery.sizeOf(context);
    final fitScale = (sz.width / _rdpW).clamp(0.1, 10.0);
    final x = (screen.dx / (_scale * fitScale) - _offset.dx / (_scale * fitScale))
        .clamp(0.0, _rdpW.toDouble());
    final y = (screen.dy / (_scale * fitScale) - _offset.dy / (_scale * fitScale))
        .clamp(0.0, _rdpH.toDouble());
    return Offset(x, y);
  }

  void _sendMouse(Offset pos, int flags) {
    if (_session == null) return;
    final rdp = _toRdp(pos);
    RdpService.sendMouseEvent(_session!.handle, rdp.dx.toInt(), rdp.dy.toInt(), flags);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── RDP canvas ──────────────────────────────────────────
          _session == null
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_hasError)
                      const CircularProgressIndicator(color: Color(0xFF00D4FF))
                    else
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SelectableText(
                        _status,
                        style: TextStyle(
                          color: _hasError ? Colors.redAccent : Colors.white54,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ))
              : _RdpCanvas(
                  session: _session!,
                  rdpW: _rdpW,
                  rdpH: _rdpH,
                  scale: _scale,
                  offset: _offset,
                  onTap: (pos) => _sendMouse(pos, MouseFlags.leftDown | MouseFlags.leftUp),
                  onLongPress: (pos) => _sendMouse(pos, MouseFlags.rightDown | MouseFlags.rightUp),
                  onPanUpdate: (delta) => setState(() => _offset += delta),
                  onScaleStart: (_) { _baseScale = _scale; },
                  onScaleUpdate: (details) => setState(() {
                    _scale = (_baseScale * details.scale).clamp(0.5, 4.0);
                  }),
                  onPointerMove: (pos) => _sendMouse(pos, MouseFlags.move),
                ),

          // ── Toolbar ─────────────────────────────────────────────
          if (_showToolbar)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 0, right: 0,
              child: _Toolbar(
                title: widget.connection.name,
                onClose: () => Navigator.pop(context),
                onKeyboard: () {/* TODO: show virtual keyboard */},
                onHide: () => setState(() => _showToolbar = false),
              ),
            ),

          // ── Show toolbar button when hidden ──────────────────────
          if (!_showToolbar)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: GestureDetector(
                onTap: () => setState(() => _showToolbar = true),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.menu, color: Colors.white70, size: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── RDP canvas with gesture handling ────────────────────────────────
class _RdpCanvas extends StatelessWidget {
  final RdpSession session;
  final int rdpW, rdpH;
  final double scale;
  final Offset offset;
  final void Function(Offset) onTap;
  final void Function(Offset) onLongPress;
  final void Function(Offset) onPanUpdate;
  final void Function(ScaleStartDetails) onScaleStart;
  final void Function(ScaleUpdateDetails) onScaleUpdate;
  final void Function(Offset) onPointerMove;

  const _RdpCanvas({
    required this.session,
    required this.rdpW, required this.rdpH,
    required this.scale, required this.offset,
    required this.onTap, required this.onLongPress,
    required this.onPanUpdate, required this.onScaleStart,
    required this.onScaleUpdate, required this.onPointerMove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp:       (d) => onTap(d.localPosition),
      onLongPressStart: (d) => onLongPress(d.localPosition),
      onScaleStart:  onScaleStart,
      onScaleUpdate: (d) {
        if (d.pointerCount == 1) {
          onPanUpdate(d.focalPointDelta);
        } else {
          onScaleUpdate(d);
        }
      },
      child: Listener(
        onPointerMove: (e) => onPointerMove(e.localPosition),
        child: SizedBox.expand(
          child: Transform(
            transform: Matrix4.identity()
              ..translate(offset.dx, offset.dy)
              ..scale(scale),
            child: AspectRatio(
              aspectRatio: rdpW / rdpH,
              child: Texture(textureId: session.textureId),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Floating toolbar ─────────────────────────────────────────────────
class _Toolbar extends StatelessWidget {
  final String title;
  final VoidCallback onClose, onKeyboard, onHide;
  const _Toolbar({required this.title, required this.onClose,
      required this.onKeyboard, required this.onHide});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Icons.desktop_windows_outlined, color: Color(0xFF00D4FF), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.keyboard, size: 20),
            color: Colors.white70,
            onPressed: onKeyboard,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.visibility_off, size: 20),
            color: Colors.white70,
            onPressed: onHide,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: Colors.redAccent,
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    ),
  );
}
