import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// TODO: 替换为你的 GitHub 仓库
const _repoOwner = 'llw2011';
const _repoName  = 'NexTerm';

class ReleaseInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  const ReleaseInfo({required this.version, required this.downloadUrl, required this.releaseNotes});
}

class OtaService {
  static const _installChannel = MethodChannel('nexterm/ota');

  /// 检查是否有新版本，有则返回 ReleaseInfo，否则返回 null
  static Future<ReleaseInfo?> checkUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version; // e.g. "1.0.0"

    final resp = await http.get(
      Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) return null;

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag  = (json['tag_name'] as String).replaceFirst('v', '');
    final body = json['body'] as String? ?? '';

    if (!_isNewer(tag, current)) return null;

    // 找 APK asset
    final assets = json['assets'] as List<dynamic>;
    final apkAsset = assets.firstWhere(
      (a) => (a['name'] as String).endsWith('.apk'),
      orElse: () => null,
    );
    if (apkAsset == null) return null;

    return ReleaseInfo(
      version: tag,
      downloadUrl: apkAsset['browser_download_url'] as String,
      releaseNotes: body,
    );
  }

  /// 下载 APK 并触发系统安装
  static Future<void> downloadAndInstall(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    final dir  = await getExternalCacheDirectories();
    final file = File('${dir!.first.path}/nexterm-update.apk');

    final req  = http.Request('GET', Uri.parse(release.downloadUrl));
    final resp = await req.send();
    final total = resp.contentLength ?? 0;
    int received = 0;

    final sink = file.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();

    // Kotlin side handles FileProvider + install intent
    await _installChannel.invokeMethod('installApk', {'path': file.path});
  }

  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map(int.tryParse).toList();
    final l = local.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final rv = i < r.length ? (r[i] ?? 0) : 0;
      final lv = i < l.length ? (l[i] ?? 0) : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }
}
