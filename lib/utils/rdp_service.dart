import 'dart:io';
import 'package:flutter/services.dart';
import '../models/connection.dart';
import 'rdp_ffi.dart';

/// Mouse button flags matching FreeRDP PTR_FLAGS_*
class MouseFlags {
  static const int move = 0x0800;
  static const int down = 0x8000;
  static const int leftDown = down | 0x1000;
  static const int leftUp = 0x1000;
  static const int rightDown = down | 0x2000;
  static const int rightUp = 0x2000;
  static const int wheelDown = 0x0200 | 0x0100;
  static const int wheelUp = 0x0200;
}

class RdpSession {
  final int handle;
  final int textureId;
  const RdpSession({required this.handle, required this.textureId});
}

class RdpService {
  static const _ch = MethodChannel('rdp/bridge');
  static bool get _useFFI => Platform.isWindows;

  static Future<RdpSession> create({
    required String host,
    required int port,
    required String username,
    required String password,
    String domain = '',
    int width = 1280,
    int height = 720,
    RdpSecurityProtocol security = RdpSecurityProtocol.auto,
  }) async {
    if (_useFFI) {
      final handle = RdpFfi.instance.create(
        host: host,
        port: port,
        user: username,
        pass: password,
        domain: domain,
        width: width,
        height: height,
        securityProtocol: security.index,
      );
      if (handle == 0) {
        throw Exception('RDP create failed: ${RdpFfi.instance.getLastError()}');
      }
      return RdpSession(handle: handle, textureId: 0);
    }
    final result = await _ch.invokeMapMethod<String, dynamic>('create', {
      'host': host,
      'port': port,
      'user': username,
      'pass': password,
      'domain': domain,
      'width': width,
      'height': height,
      'security': security.index,
    });
    return RdpSession(
      handle: result!['handle'] as int,
      textureId: result['textureId'] as int,
    );
  }

  static Future<void> connect(int handle) async {
    if (_useFFI) {
      RdpFfi.instance.connect(handle);
      return;
    }
    await _ch.invokeMethod('connect', {'handle': handle});
  }

  static Future<void> disconnect(int handle) async {
    if (_useFFI) {
      RdpFfi.instance.disconnect(handle);
      return;
    }
    await _ch.invokeMethod('disconnect', {'handle': handle});
  }

  static Future<void> destroy(int handle) async {
    if (_useFFI) {
      RdpFfi.instance.destroy(handle);
      return;
    }
    await _ch.invokeMethod('destroy', {'handle': handle});
  }

  static Future<void> sendMouseEvent(
      int handle, int x, int y, int flags) async {
    if (_useFFI) {
      RdpFfi.instance.sendMouseEvent(handle, x, y, flags);
      return;
    }
    await _ch.invokeMethod(
        'mouseEvent', {'handle': handle, 'x': x, 'y': y, 'flags': flags});
  }

  static Future<void> sendKeyEvent(
    int handle,
    int keycode,
    bool down, {
    bool extended = false,
    String? debugLabel,
  }) async {
    if (_useFFI) {
      RdpFfi.instance.sendKeyEvent(handle, keycode, down, extended: extended);
      return;
    }
    await _ch.invokeMethod('keyEvent', {
      'handle': handle,
      'keycode': keycode,
      'down': down,
      'extended': extended,
      if (debugLabel != null) 'debugLabel': debugLabel,
    });
  }

  static Future<void> sendUnicodeEvent(int handle, int codepoint) async {
    if (_useFFI) {
      RdpFfi.instance.sendUnicodeEvent(handle, codepoint);
      return;
    }
    await _ch.invokeMethod(
        'unicodeEvent', {'handle': handle, 'codepoint': codepoint});
  }

  static Future<bool> isRunning(int handle) async {
    if (_useFFI) return RdpFfi.instance.isRunning(handle);
    return await _ch.invokeMethod<bool>('isRunning', {'handle': handle}) ??
        false;
  }

  static Future<bool> isConnected(int handle) async {
    if (_useFFI) return RdpFfi.instance.isConnected(handle);
    return await _ch.invokeMethod<bool>('isConnected', {'handle': handle}) ??
        false;
  }

  static Future<String> getLastError() async {
    if (_useFFI) return RdpFfi.instance.getLastError();
    return await _ch.invokeMethod<String>('lastError') ?? '';
  }

  static Future<void> sendClipboard(int handle, String text) async {
    if (_useFFI) {
      RdpFfi.instance.sendClipboardText(handle, text);
      return;
    }
    await _ch.invokeMethod('sendClipboard', {'handle': handle, 'text': text});
  }
}
