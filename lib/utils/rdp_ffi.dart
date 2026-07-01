import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef _NexCreateNative = Int64 Function(Pointer<Utf8>, Int32, Pointer<Utf8>,
    Pointer<Utf8>, Pointer<Utf8>, Int32, Int32, Int32);
typedef _NexCreate = int Function(Pointer<Utf8>, int, Pointer<Utf8>,
    Pointer<Utf8>, Pointer<Utf8>, int, int, int);

typedef _NexHandleNative = Void Function(Int64);
typedef _NexHandle = void Function(int);

typedef _NexIntNative = Int32 Function(Int64);
typedef _NexInt = int Function(int);

typedef _NexMouseNative = Void Function(Int64, Int32, Int32, Int32);
typedef _NexMouse = void Function(int, int, int, int);

typedef _NexKeyNative = Void Function(Int64, Int32, Int32, Int32);
typedef _NexKey = void Function(int, int, int, int);

typedef _NexUnicodeNative = Void Function(Int64, Int32);
typedef _NexUnicode = void Function(int, int);

typedef _NexClipNative = Void Function(Int64, Pointer<Utf8>);
typedef _NexClip = void Function(int, Pointer<Utf8>);

typedef _NexGetErrorNative = Pointer<Utf8> Function();
typedef _NexGetError = Pointer<Utf8> Function();

typedef _NexGetBufferNative = Pointer<Uint8> Function(Int64);
typedef _NexGetBuffer = Pointer<Uint8> Function(int);

class RdpFfi {
  static RdpFfi? _instance;
  static RdpFfi get instance => _instance ??= RdpFfi._();

  late final DynamicLibrary _lib;
  late final _NexCreate _create;
  late final _NexHandle _connect;
  late final _NexHandle _disconnect;
  late final _NexHandle _destroy;
  late final _NexInt _isRunning;
  late final _NexInt _isConnected;
  late final _NexGetError _getLastError;
  late final _NexMouse _sendMouseEvent;
  late final _NexKey _sendKeyEvent;
  late final _NexUnicode _sendUnicodeEvent;
  late final _NexClip _sendClipboardText;
  late final _NexGetBuffer _getFrameBuffer;
  late final _NexInt _getFrameWidth;
  late final _NexInt _getFrameHeight;

  RdpFfi._() {
    _lib = DynamicLibrary.open('nexterm_rdp.dll');
    _create = _lib.lookupFunction<_NexCreateNative, _NexCreate>('nex_create');
    _connect = _lib.lookupFunction<_NexHandleNative, _NexHandle>('nex_connect');
    _disconnect =
        _lib.lookupFunction<_NexHandleNative, _NexHandle>('nex_disconnect');
    _destroy = _lib.lookupFunction<_NexHandleNative, _NexHandle>('nex_destroy');
    _isRunning = _lib.lookupFunction<_NexIntNative, _NexInt>('nex_is_running');
    _isConnected =
        _lib.lookupFunction<_NexIntNative, _NexInt>('nex_is_connected');
    _getLastError = _lib
        .lookupFunction<_NexGetErrorNative, _NexGetError>('nex_get_last_error');
    _sendMouseEvent =
        _lib.lookupFunction<_NexMouseNative, _NexMouse>('nex_send_mouse_event');
    _sendKeyEvent =
        _lib.lookupFunction<_NexKeyNative, _NexKey>('nex_send_key_event');
    _sendUnicodeEvent = _lib.lookupFunction<_NexUnicodeNative, _NexUnicode>(
        'nex_send_unicode_event');
    _sendClipboardText = _lib
        .lookupFunction<_NexClipNative, _NexClip>('nex_send_clipboard_text');
    _getFrameBuffer = _lib.lookupFunction<_NexGetBufferNative, _NexGetBuffer>(
        'nex_get_frame_buffer');
    _getFrameWidth =
        _lib.lookupFunction<_NexIntNative, _NexInt>('nex_get_frame_width');
    _getFrameHeight =
        _lib.lookupFunction<_NexIntNative, _NexInt>('nex_get_frame_height');
  }

  int create({
    required String host,
    required int port,
    required String user,
    required String pass,
    String domain = '',
    int width = 1280,
    int height = 720,
    int securityProtocol = 0,
  }) {
    final h = host.toNativeUtf8();
    final u = user.toNativeUtf8();
    final p = pass.toNativeUtf8();
    final d = domain.toNativeUtf8();
    try {
      return _create(h, port, u, p, d, width, height, securityProtocol);
    } finally {
      calloc.free(h);
      calloc.free(u);
      calloc.free(p);
      calloc.free(d);
    }
  }

  void connect(int handle) => _connect(handle);
  void disconnect(int handle) => _disconnect(handle);
  void destroy(int handle) => _destroy(handle);
  bool isRunning(int handle) => _isRunning(handle) != 0;
  bool isConnected(int handle) => _isConnected(handle) != 0;
  String getLastError() => _getLastError().toDartString();

  void sendMouseEvent(int handle, int x, int y, int flags) =>
      _sendMouseEvent(handle, x, y, flags);
  void sendKeyEvent(int handle, int keycode, bool down,
          {bool extended = false}) =>
      _sendKeyEvent(handle, keycode, down ? 1 : 0, extended ? 1 : 0);
  void sendUnicodeEvent(int handle, int codepoint) =>
      _sendUnicodeEvent(handle, codepoint);

  void sendClipboardText(int handle, String text) {
    final t = text.toNativeUtf8();
    try {
      _sendClipboardText(handle, t);
    } finally {
      calloc.free(t);
    }
  }

  Pointer<Uint8> getFrameBuffer(int handle) => _getFrameBuffer(handle);
  int getFrameWidth(int handle) => _getFrameWidth(handle);
  int getFrameHeight(int handle) => _getFrameHeight(handle);
}
