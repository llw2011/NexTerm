import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../components/keyboard/virtual_keyboard.dart';
import '../../i18n/app_localizations.dart';
import '../../models/connection.dart';
import 'rdp_key_test_panel.dart';
import 'rdp_text_input_panel.dart';
import '../../utils/diagnostic_log.dart';
import '../../utils/rdp_service.dart';
import '../../utils/secure_storage.dart';

class RdpScreen extends StatefulWidget {
  final Connection connection;
  const RdpScreen({super.key, required this.connection});

  @override
  State<RdpScreen> createState() => _RdpScreenState();
}

enum _RdpUiState { connecting, connected, verifying, disconnected }

enum _RdpPointerMode { direct, touchpad, view }

class _RdpScreenState extends State<RdpScreen> with WidgetsBindingObserver {
  RdpSession? _session;
  String _statusOverride = '';
  _RdpUiState _uiState = _RdpUiState.connecting;
  bool _showToolbar = true;
  _RdpPointerMode _pointerMode = _RdpPointerMode.view;
  String _pointerModeTip = '';
  bool _textInputOpen = false;
  bool _controlKeysOpen = false;
  bool _keyTestOpen = false;
  bool _closing = false;
  bool _destroyIssued = false;
  Timer? _healthCheckTimer;
  int _healthMissCount = 0;
  static const _healthMissThreshold = 2;
  static const _startupGraceTicks = 4;

  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero;
  Offset _lastLocalPoint = Offset.zero;
  Offset? _dragStartLocal;
  Offset? _touchpadCursorRdp;
  bool _remoteDragging = false;
  bool _twoFingerWheelActive = false;
  double _wheelAccumulator = 0;
  static const _wheelStepPixels = 36.0;
  static const _wheelScaleThreshold = 0.04;
  static const _wheelDominanceRatio = 1.35;
  static const _touchpadSensitivity = 1.25;

  Timer? _clipboardCheckTimer;
  Timer? _pointerModeTipTimer;
  String _lastClipboardText = '';

  late int _rdpW;
  late int _rdpH;

  void _logRdp(String stage, String message, {String? error}) {
    DiagnosticLog.rdp(
      stage: stage,
      message: message,
      connectionName: widget.connection.name,
      host: widget.connection.host,
      port: widget.connection.port,
      username: widget.connection.username,
      error: error,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rdpW = widget.connection.width ?? 1600;
    _rdpH = widget.connection.height ?? 900;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _logRdp('resume', 'App resumed; verifying native RDP session');
        // App came back from background. The RDP socket may have been killed
        // by Doze / server-side idle timeout while we were away. Show a
        // calm "Resuming" indicator (not the red error) while we probe the
        // native session. Only flip to `disconnected` after verify fails.
        if (_uiState == _RdpUiState.connected) {
          setState(() => _uiState = _RdpUiState.verifying);
        }
        _verifySessionAfterResume();
        _startHealthCheck();
        if (_uiState == _RdpUiState.connected ||
            _uiState == _RdpUiState.verifying) {
          _startClipboardMonitoring();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        _logRdp('lifecycle',
            'App moved to ${state.name}; pausing health and clipboard checks');
        _stopHealthCheck();
        _stopClipboardMonitoring();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _verifySessionAfterResume() async {
    final session = _session;
    if (session == null || _uiState == _RdpUiState.disconnected) return;
    try {
      _logRdp('resume', 'Checking native isRunning/isConnected flags');
      final running = await RdpService.isRunning(session.handle);
      final connected = await RdpService.isConnected(session.handle);
      if (!mounted || _session?.handle != session.handle) return;
      if (running && connected) {
        if (_uiState == _RdpUiState.verifying) {
          setState(() => _uiState = _RdpUiState.connected);
        }
        _healthMissCount = 0;
        _logRdp('connected', 'Native session is still connected after resume');
        return;
      }
      final err = await RdpService.getLastError();
      if (!mounted || _session?.handle != session.handle) return;
      _logRdp(
        DiagnosticLog.inferRdpStageFromError(err),
        'Resume verification failed',
        error: err,
      );
      setState(() {
        _uiState = _RdpUiState.disconnected;
        _statusOverride = err;
      });
      _stopHealthCheck();
      _stopClipboardMonitoring();
    } catch (e) {
      _logRdp('resume', 'Resume verification threw an exception', error: '$e');
      // ignore; next health-check tick will catch it
    }
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthMissCount = 0;
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _closing) return;
      final session = _session;
      if (session == null) return;
      if (_uiState != _RdpUiState.connected &&
          _uiState != _RdpUiState.verifying) {
        return;
      }
      try {
        final running = await RdpService.isRunning(session.handle);
        if (running) {
          _healthMissCount = 0;
          return;
        }
        _healthMissCount++;
        if (_healthMissCount < _healthMissThreshold) return;
        if (!mounted || _session?.handle != session.handle) return;
        final err = await RdpService.getLastError();
        _logRdp(
          DiagnosticLog.inferRdpStageFromError(err),
          'Health check confirmed native session is not running',
          error: err,
        );
        setState(() {
          _uiState = _RdpUiState.disconnected;
          _statusOverride = err;
        });
        _stopHealthCheck();
        _stopClipboardMonitoring();
      } catch (e) {
        _logRdp('health', 'Health check threw an exception', error: '$e');
      }
    });
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> _reconnect() async {
    if (_closing) return;
    _logRdp('reconnect', 'Manual reconnect requested');
    await _destroySession();
    if (!mounted) return;
    setState(() {
      _session = null;
      _uiState = _RdpUiState.connecting;
      _destroyIssued = false;
      _statusOverride = '';
    });
    _healthMissCount = 0;
    _stopClipboardMonitoring();
    _stopHealthCheck();
    await _connect();
  }

  Future<void> _connect() async {
    _logRdp('create', 'Starting RDP session create');
    try {
      final password = await loadPassword(widget.connection.id);
      _logRdp(
        'settings',
        'Loaded credentials from secure storage; width=$_rdpW height=$_rdpH '
            'security=${widget.connection.rdpSecurity ?? RdpSecurityProtocol.auto}',
      );
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
      _logRdp(
        'create',
        'Native RDP context created handle=${session.handle} '
            'texture=${session.textureId}',
      );
      if (!mounted || _closing) {
        _logRdp('destroy', 'Destroying session before attaching to UI');
        await RdpService.destroy(session.handle);
        return;
      }
      setState(() {
        _session = session;
        _uiState = _RdpUiState.connecting;
        _statusOverride = '';
      });
      _logRdp(
        'preconnect',
        'Dispatching native connect; native side continues through '
            'PreConnect, DNS/TCP, auth and PostConnect',
      );
      await RdpService.connect(session.handle);
      _logRdp('dns_tcp', 'Native connect dispatched; waiting for readiness');
      unawaited(_watchConnectionStartup(session.handle));
    } on PlatformException catch (e) {
      final error = '[${e.code}] ${e.message ?? ''}';
      _logRdp(
        DiagnosticLog.inferRdpStageFromError(error),
        'RDP platform connection failed',
        error: error,
      );
      if (!mounted) return;
      setState(() {
        _uiState = _RdpUiState.disconnected;
        _statusOverride = error;
      });
    } catch (e) {
      final error = '$e';
      _logRdp(
        DiagnosticLog.inferRdpStageFromError(error),
        'RDP connection failed',
        error: error,
      );
      if (!mounted) return;
      setState(() {
        _uiState = _RdpUiState.disconnected;
        _statusOverride = '$e';
      });
    }
  }

  Future<void> _watchConnectionStartup(int handle) async {
    _logRdp('preconnect', 'Watching native startup state');
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || _closing || _session?.handle != handle) return;

      final connected = await RdpService.isConnected(handle);
      if (connected) {
        _logRdp('connected', 'RDP session reported connected');
        setState(() {
          _uiState = _RdpUiState.connected;
          _statusOverride = '';
        });
        _healthMissCount = 0;
        _startClipboardMonitoring();
        _startHealthCheck();
        return;
      }

      // Grace period: FreeRDP worker thread + TLS negotiation can take a
      // moment to flip isRunning to true. Don't surface transient errors
      // during the first ~2s of startup.
      if (i < _startupGraceTicks) continue;

      final running = await RdpService.isRunning(handle);
      if (running) continue;

      final error = await RdpService.getLastError();
      if (error.isEmpty) continue;
      _logRdp(
        DiagnosticLog.inferRdpStageFromError(error),
        'RDP startup failed before desktop became ready',
        error: error,
      );
      setState(() {
        _uiState = _RdpUiState.disconnected;
        _statusOverride = error;
      });
      await RdpService.destroy(handle);
      if (mounted && _session?.handle == handle) {
        setState(() {
          _session = null;
        });
      }
      return;
    }
    if (!mounted || _closing || _session?.handle != handle) return;
    setState(() {
      _uiState = _RdpUiState.disconnected;
      _statusOverride = '';
    });
    _logRdp('startup', 'RDP startup timed out before connected state');
    await RdpService.destroy(handle);
    if (mounted && _session?.handle == handle) {
      setState(() {
        _session = null;
      });
    }
  }

  Future<void> _destroySession() async {
    if (_destroyIssued) return;
    final session = _session;
    if (session == null) return;
    _destroyIssued = true;
    try {
      _logRdp('destroy', 'Destroying native RDP session');
      await RdpService.destroy(session.handle);
      _logRdp('destroy', 'Native RDP session destroyed');
    } catch (e) {
      _logRdp('destroy', 'Destroying native RDP session failed', error: '$e');
      // native side already owns shutdown errors
    }
  }

  Future<void> _closeScreen() async {
    if (_closing) return;
    _closing = true;
    _logRdp('close', 'Closing RDP screen');
    await _destroySession();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHealthCheck();
    _stopClipboardMonitoring();
    _pointerModeTipTimer?.cancel();
    unawaited(_destroySession());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  _CanvasMetrics _metrics(Size size) {
    final fit = math.min(size.width / _rdpW, size.height / _rdpH);
    final fitted = Size(_rdpW * fit, _rdpH * fit);
    final origin = Offset(
        (size.width - fitted.width) / 2, (size.height - fitted.height) / 2);
    return _CanvasMetrics(fitScale: fit, origin: origin);
  }

  Offset _toRdp(Offset local, Size viewport) {
    final m = _metrics(viewport);
    final totalScale = m.fitScale * _scale;
    final x = ((local.dx - m.origin.dx - _offset.dx) / totalScale)
        .clamp(0.0, _rdpW.toDouble());
    final y = ((local.dy - m.origin.dy - _offset.dy) / totalScale)
        .clamp(0.0, _rdpH.toDouble());
    return Offset(x, y);
  }

  Offset _clampRdp(Offset rdp) {
    return Offset(
      rdp.dx.clamp(0.0, _rdpW.toDouble()).toDouble(),
      rdp.dy.clamp(0.0, _rdpH.toDouble()).toDouble(),
    );
  }

  double _rdpPixelsPerLocalPixel(Size viewport) {
    final m = _metrics(viewport);
    final totalScale = m.fitScale * _scale;
    if (totalScale <= 0) return 1.0;
    return 1 / totalScale;
  }

  void _sendMouseAtRdp(Offset rdp, int flags) {
    final session = _session;
    if (session == null) return;
    final clamped = _clampRdp(rdp);
    _touchpadCursorRdp = clamped;
    RdpService.sendMouseEvent(
      session.handle,
      clamped.dx.round(),
      clamped.dy.round(),
      flags,
    );
  }

  void _sendMouseAt(Offset local, Size viewport, int flags) {
    _sendMouseAtRdp(_toRdp(local, viewport), flags);
  }

  Future<void> _sendClickAtRdp(Offset rdp) async {
    _sendMouseAtRdp(rdp, MouseFlags.move);
    _sendMouseAtRdp(rdp, MouseFlags.leftDown);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    _sendMouseAtRdp(rdp, MouseFlags.leftUp);
  }

  Future<void> _sendClick(Offset local, Size viewport) async {
    await _sendClickAtRdp(_toRdp(local, viewport));
  }

  Future<void> _sendDoubleClick(Offset local, Size viewport) async {
    await _sendClick(local, viewport);
    await Future<void>.delayed(const Duration(milliseconds: 55));
    await _sendClick(local, viewport);
  }

  Future<void> _sendRightClickAtRdp(Offset rdp) async {
    _sendMouseAtRdp(rdp, MouseFlags.move);
    _sendMouseAtRdp(rdp, MouseFlags.rightDown);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    _sendMouseAtRdp(rdp, MouseFlags.rightUp);
  }

  Future<void> _sendRightClick(Offset local, Size viewport) async {
    await _sendRightClickAtRdp(_toRdp(local, viewport));
  }

  Offset _ensureTouchpadCursor(Offset local, Size viewport) {
    return _touchpadCursorRdp ??= _toRdp(local, viewport);
  }

  Future<void> _sendTouchpadClick(Offset local, Size viewport) async {
    await _sendClickAtRdp(_ensureTouchpadCursor(local, viewport));
  }

  Future<void> _sendTouchpadDoubleClick(Offset local, Size viewport) async {
    final cursor = _ensureTouchpadCursor(local, viewport);
    await _sendClickAtRdp(cursor);
    await Future<void>.delayed(const Duration(milliseconds: 55));
    await _sendClickAtRdp(cursor);
  }

  Future<void> _sendTouchpadRightClick(Offset local, Size viewport) async {
    await _sendRightClickAtRdp(_ensureTouchpadCursor(local, viewport));
  }

  void _sendWheelDelta(double localDeltaY, Offset local, Size viewport) {
    if (localDeltaY.abs() < 0.5) return;
    _wheelAccumulator += localDeltaY;
    final rdp = _pointerMode == _RdpPointerMode.touchpad
        ? _ensureTouchpadCursor(local, viewport)
        : _toRdp(local, viewport);
    while (_wheelAccumulator.abs() >= _wheelStepPixels) {
      final down = _wheelAccumulator > 0;
      _sendMouseAtRdp(
        rdp,
        down ? MouseFlags.wheelDown : MouseFlags.wheelUp,
      );
      _wheelAccumulator += down ? -_wheelStepPixels : _wheelStepPixels;
    }
  }

  void _moveTouchpadCursor(Offset localDelta, Offset local, Size viewport) {
    if (localDelta.distance < 0.5) return;
    final current = _ensureTouchpadCursor(local, viewport);
    final rdpDelta =
        localDelta * _rdpPixelsPerLocalPixel(viewport) * _touchpadSensitivity;
    final next = _clampRdp(current + rdpDelta);
    _touchpadCursorRdp = next;
    _sendMouseAtRdp(next, MouseFlags.move);
  }

  void _resetView() {
    setState(() {
      _scale = 1.0;
      _baseScale = 1.0;
      _offset = Offset.zero;
      _baseOffset = Offset.zero;
    });
  }

  void _setPointerMode(_RdpPointerMode mode) {
    setState(() {
      _pointerMode = mode;
      _remoteDragging = false;
      _twoFingerWheelActive = false;
      _wheelAccumulator = 0;
      _pointerModeTip = _pointerModeTipText(context.l10n, mode);
    });
    _pointerModeTipTimer?.cancel();
    _pointerModeTipTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _pointerModeTip = '');
    });
  }

  String _pointerModeTipText(AppLocalizations l10n, _RdpPointerMode mode) {
    return switch (mode) {
      _RdpPointerMode.direct =>
        "${l10n.t('rdpDirectClickMode')}: ${l10n.t('rdpDirectClickModeSubtitle')}",
      _RdpPointerMode.view =>
        "${l10n.t('rdpMoveViewMode')}: ${l10n.t('rdpMoveViewModeSubtitle')}",
      _RdpPointerMode.touchpad =>
        "${l10n.t('rdpPrecisionTouchpadMode')}: ${l10n.t('rdpPrecisionTouchpadModeSubtitle')}",
    };
  }

  void _toggleTextInput() {
    setState(() => _textInputOpen = !_textInputOpen);
  }

  void _toggleKeyTest() {
    setState(() => _keyTestOpen = !_keyTestOpen);
  }

  void _startClipboardMonitoring() {
    _clipboardCheckTimer?.cancel();
    _clipboardCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _session == null) return;
      if (_uiState != _RdpUiState.connected) return;
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data != null && data.text != null && data.text!.isNotEmpty) {
          final text = data.text!;
          if (text != _lastClipboardText) {
            _lastClipboardText = text;
            await RdpService.sendClipboard(_session!.handle, text);
          }
        }
      } catch (_) {
        // Ignore clipboard errors
      }
    });
  }

  void _stopClipboardMonitoring() {
    _clipboardCheckTimer?.cancel();
    _clipboardCheckTimer = null;
  }

  String _resolveStatusText(AppLocalizations l10n) {
    if (_statusOverride.isNotEmpty) return _statusOverride;
    switch (_uiState) {
      case _RdpUiState.connecting:
        return l10n.t('connecting');
      case _RdpUiState.connected:
        return l10n.t('connected');
      case _RdpUiState.verifying:
        return l10n.t('resuming');
      case _RdpUiState.disconnected:
        return l10n.t('sessionLost');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showCanvas = _session != null && _uiState == _RdpUiState.connected;
    final showError = _uiState == _RdpUiState.disconnected;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: showCanvas
                ? _buildCanvas()
                : _StatusView(
                    status: _resolveStatusText(l10n),
                    hasError: showError,
                    onReconnect: showError ? _reconnect : null,
                  ),
          ),
          if (_showToolbar)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              right: 8,
              child: _Toolbar(
                title: widget.connection.name,
                pointerMode: _pointerMode,
                textInputOpen: _textInputOpen,
                onClose: () {
                  unawaited(_closeScreen());
                },
                onTextInput: _toggleTextInput,
                onKeyTest: _toggleKeyTest,
                onReset: _resetView,
                onPointerModeChanged: _setPointerMode,
                onHide: () => setState(() => _showToolbar = false),
              ),
            ),
          if (!_showToolbar)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: _RoundToolButton(
                  icon: Icons.menu,
                  tooltip: l10n.t('toolbar'),
                  onPressed: () => setState(() => _showToolbar = true)),
            ),
          if (_pointerModeTip.isNotEmpty && showCanvas)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 64,
              left: 16,
              right: 16,
              child: _PointerModeTip(message: _pointerModeTip),
            ),
          if (_textInputOpen && _session != null && showCanvas)
            RdpTextInputPanel(
              sessionHandle: _session!.handle,
              onControlKeys: () => setState(() => _controlKeysOpen = true),
              onClose: () => setState(() => _textInputOpen = false),
            ),
          if (_controlKeysOpen && _session != null && showCanvas)
            VirtualKeyboard(
              sessionHandle: _session!.handle,
              onClose: () => setState(() => _controlKeysOpen = false),
            ),
          if (_keyTestOpen && _session != null && showCanvas)
            RdpKeyTestPanel(
              sessionHandle: _session!.handle,
              onClose: () => setState(() => _keyTestOpen = false),
            ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final m = _metrics(viewport);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            switch (_pointerMode) {
              case _RdpPointerMode.direct:
                unawaited(_sendClick(d.localPosition, viewport));
                break;
              case _RdpPointerMode.touchpad:
                unawaited(_sendTouchpadClick(d.localPosition, viewport));
                break;
              case _RdpPointerMode.view:
                break;
            }
          },
          onDoubleTapDown: (d) {
            switch (_pointerMode) {
              case _RdpPointerMode.direct:
                unawaited(_sendDoubleClick(d.localPosition, viewport));
                break;
              case _RdpPointerMode.touchpad:
                unawaited(_sendTouchpadDoubleClick(d.localPosition, viewport));
                break;
              case _RdpPointerMode.view:
                break;
            }
          },
          onLongPressStart: (d) {
            switch (_pointerMode) {
              case _RdpPointerMode.direct:
                unawaited(_sendRightClick(d.localPosition, viewport));
                break;
              case _RdpPointerMode.touchpad:
                unawaited(_sendTouchpadRightClick(d.localPosition, viewport));
                break;
              case _RdpPointerMode.view:
                break;
            }
          },
          onScaleStart: (d) {
            _baseScale = _scale;
            _baseOffset = _offset;
            _dragStartLocal = d.localFocalPoint;
            _lastLocalPoint = d.localFocalPoint;
            _wheelAccumulator = 0;
            _twoFingerWheelActive = false;
            if (_pointerMode == _RdpPointerMode.touchpad) {
              _ensureTouchpadCursor(d.localFocalPoint, viewport);
            }
            _remoteDragging = false;
          },
          onScaleUpdate: (d) {
            final localDelta = d.localFocalPoint - _lastLocalPoint;
            if (d.pointerCount >= 2 && _remoteDragging) {
              _sendMouseAt(_lastLocalPoint, viewport, MouseFlags.leftUp);
              _remoteDragging = false;
            }
            if (d.pointerCount >= 2 && _pointerMode != _RdpPointerMode.view) {
              final verticalWheel = localDelta.dy.abs() > 1 &&
                  localDelta.dy.abs() >
                      localDelta.dx.abs() * _wheelDominanceRatio &&
                  (d.scale - 1.0).abs() < _wheelScaleThreshold;
              if (_twoFingerWheelActive || verticalWheel) {
                _twoFingerWheelActive = true;
                _sendWheelDelta(localDelta.dy, d.localFocalPoint, viewport);
                _lastLocalPoint = d.localFocalPoint;
                return;
              }
            }

            if (d.pointerCount >= 2 || _pointerMode == _RdpPointerMode.view) {
              setState(() {
                _scale = (_baseScale * d.scale).clamp(0.75, 5.0);
                _offset = _baseOffset +
                    (d.localFocalPoint -
                        (_dragStartLocal ?? d.localFocalPoint));
              });
              _lastLocalPoint = d.localFocalPoint;
              return;
            }

            if (_pointerMode == _RdpPointerMode.touchpad) {
              _moveTouchpadCursor(localDelta, d.localFocalPoint, viewport);
              _lastLocalPoint = d.localFocalPoint;
              return;
            }

            final start = _dragStartLocal;
            if (start == null) return;
            if (!_remoteDragging && (d.localFocalPoint - start).distance > 10) {
              _sendMouseAt(start, viewport, MouseFlags.move);
              _sendMouseAt(start, viewport, MouseFlags.leftDown);
              _remoteDragging = true;
            }
            if (_remoteDragging) {
              _sendMouseAt(d.localFocalPoint, viewport, MouseFlags.move);
            }
            _lastLocalPoint = d.localFocalPoint;
          },
          onScaleEnd: (_) {
            if (_remoteDragging) {
              _sendMouseAt(_lastLocalPoint, viewport, MouseFlags.leftUp);
              _remoteDragging = false;
            }
            _twoFingerWheelActive = false;
            _wheelAccumulator = 0;
          },
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: m.origin.dx + _offset.dx,
                  top: m.origin.dy + _offset.dy,
                  width: _rdpW * m.fitScale * _scale,
                  height: _rdpH * m.fitScale * _scale,
                  child: Texture(
                      textureId: _session!.textureId,
                      filterQuality: FilterQuality.high),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CanvasMetrics {
  final double fitScale;
  final Offset origin;
  const _CanvasMetrics({required this.fitScale, required this.origin});
}

class _StatusView extends StatelessWidget {
  final String status;
  final bool hasError;
  final VoidCallback? onReconnect;
  const _StatusView(
      {required this.status, required this.hasError, this.onReconnect});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasError)
            const CircularProgressIndicator(color: Color(0xFF00D4FF))
          else
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SelectableText(
              status,
              style: TextStyle(
                  color: hasError ? Colors.redAccent : Colors.white54,
                  fontSize: 13,
                  fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ),
          if (onReconnect != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onReconnect,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.t('reconnect')),
            ),
          ],
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final String title;
  final _RdpPointerMode pointerMode;
  final bool textInputOpen;
  final VoidCallback onClose, onTextInput, onKeyTest, onReset, onHide;
  final ValueChanged<_RdpPointerMode> onPointerModeChanged;
  const _Toolbar({
    required this.title,
    required this.pointerMode,
    required this.textInputOpen,
    required this.onClose,
    required this.onTextInput,
    required this.onKeyTest,
    required this.onReset,
    required this.onPointerModeChanged,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.desktop_windows_outlined,
                color: Color(0xFF00D4FF), size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
            _ToolbarButton(
                icon: textInputOpen ? Icons.keyboard_hide : Icons.keyboard,
                tooltip: l10n.t('rdpTextInput'),
                active: textInputOpen,
                onPressed: onTextInput,
                onLongPress: onKeyTest),
            _PointerModeSelector(
              pointerMode: pointerMode,
              onChanged: onPointerModeChanged,
            ),
            _ToolbarButton(
                icon: Icons.fit_screen,
                tooltip: l10n.t('fit'),
                onPressed: onReset),
            _ToolbarButton(
                icon: Icons.visibility_off,
                tooltip: l10n.t('hide'),
                onPressed: onHide),
            _ToolbarButton(
                icon: Icons.close,
                tooltip: l10n.t('close'),
                danger: true,
                onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

class _PointerModeTip extends StatelessWidget {
  final String message;

  const _PointerModeTip({required this.message});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x6600D4FF)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PointerModeSelector extends StatelessWidget {
  final _RdpPointerMode pointerMode;
  final ValueChanged<_RdpPointerMode> onChanged;

  const _PointerModeSelector({
    required this.pointerMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PointerModeButton(
            icon: Icons.open_with,
            tooltip: l10n.t('rdpMoveViewMode'),
            selected: pointerMode == _RdpPointerMode.view,
            onPressed: () => onChanged(_RdpPointerMode.view),
          ),
          _PointerModeButton(
            icon: Icons.touch_app,
            tooltip: l10n.t('rdpDirectClickMode'),
            selected: pointerMode == _RdpPointerMode.direct,
            onPressed: () => onChanged(_RdpPointerMode.direct),
          ),
          _PointerModeButton(
            icon: Icons.mouse,
            tooltip: l10n.t('rdpPrecisionTouchpadMode'),
            selected: pointerMode == _RdpPointerMode.touchpad,
            onPressed: () => onChanged(_RdpPointerMode.touchpad),
          ),
        ],
      ),
    );
  }
}

class _PointerModeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  const _PointerModeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: selected ? const Color(0xFF00D4FF) : Colors.white54,
        style: IconButton.styleFrom(
          backgroundColor:
              selected ? const Color(0x1F00D4FF) : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool active;
  final bool danger;
  const _ToolbarButton(
      {required this.icon,
      required this.tooltip,
      required this.onPressed,
      this.onLongPress,
      this.active = false,
      this.danger = false});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: IconButton(
            icon: Icon(icon, size: 20),
            color: danger
                ? Colors.redAccent
                : (active ? const Color(0xFF00D4FF) : Colors.white70),
            onPressed: onPressed,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          ),
        ),
      );
}

class _RoundToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _RoundToolButton(
      {required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.72),
              foregroundColor: Colors.white70),
        ),
      );
}
