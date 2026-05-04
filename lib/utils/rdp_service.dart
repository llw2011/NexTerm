import 'package:flutter/services.dart';

/// Mouse button flags matching FreeRDP PTR_FLAGS_*
class MouseFlags {
  static const int move       = 0x0800;
  static const int leftDown   = 0x1000;
  static const int leftUp     = 0x2000;
  static const int rightDown  = 0x4000;
  static const int rightUp    = 0x8000;
  static const int wheelDown  = 0x0180;
  static const int wheelUp    = 0x0100;
}

class RdpSession {
  final int handle;
  final int textureId;
  const RdpSession({required this.handle, required this.textureId});
}

class RdpService {
  static const _ch = MethodChannel('rdp/bridge');

  static Future<RdpSession> create({
    required String host,
    required int port,
    required String username,
    required String password,
    String domain = '',
    int width = 1280,
    int height = 720,
  }) async {
    final result = await _ch.invokeMapMethod<String, dynamic>('create', {
      'host': host,
      'port': port,
      'user': username,
      'pass': password,
      'domain': domain,
      'width': width,
      'height': height,
    });
    return RdpSession(
      handle: result!['handle'] as int,
      textureId: result['textureId'] as int,
    );
  }

  static Future<void> connect(int handle) =>
      _ch.invokeMethod('connect', {'handle': handle});

  static Future<void> disconnect(int handle) =>
      _ch.invokeMethod('disconnect', {'handle': handle});

  static Future<void> destroy(int handle) =>
      _ch.invokeMethod('destroy', {'handle': handle});

  static Future<void> sendMouseEvent(int handle, int x, int y, int flags) =>
      _ch.invokeMethod('mouseEvent', {'handle': handle, 'x': x, 'y': y, 'flags': flags});

  static Future<void> sendKeyEvent(int handle, int keycode, bool down) =>
      _ch.invokeMethod('keyEvent', {'handle': handle, 'keycode': keycode, 'down': down});
}
