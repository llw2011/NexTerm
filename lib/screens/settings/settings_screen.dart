import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../utils/ota_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  _UpdateState _updateState = _UpdateState.idle;
  ReleaseInfo? _release;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = '${i.version}+${i.buildNumber}');
    });
  }

  Future<void> _checkUpdate() async {
    setState(() { _updateState = _UpdateState.checking; _release = null; });
    try {
      final release = await OtaService.checkUpdate();
      if (!mounted) return;
      if (release == null) {
        setState(() => _updateState = _UpdateState.upToDate);
      } else {
        setState(() { _updateState = _UpdateState.available; _release = release; });
      }
    } catch (e) {
      if (mounted) setState(() => _updateState = _UpdateState.error);
    }
  }

  Future<void> _doUpdate() async {
    if (_release == null) return;
    setState(() { _updateState = _UpdateState.downloading; _downloadProgress = 0; });
    try {
      await OtaService.downloadAndInstall(
        _release!,
        onProgress: (p) { if (mounted) setState(() => _downloadProgress = p); },
      );
    } catch (e) {
      if (mounted) setState(() => _updateState = _UpdateState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _sectionHeader('General'),
          // (future: default resolution, theme, etc.)
          ListTile(
            leading: const Icon(Icons.display_settings_outlined),
            title: const Text('Default RDP Resolution'),
            subtitle: const Text('1280 × 720'),
            onTap: () {}, // TODO
          ),

          _sectionHeader('Update'),
          _updateTile(),

          _sectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_version.isEmpty ? '…' : _version),
          ),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('NexTerm'),
            subtitle: const Text('RDP / SSH client · Flutter + FreeRDP'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1)),
      );

  Widget _updateTile() {
    switch (_updateState) {
      case _UpdateState.idle:
        return ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: const Text('Check for Updates'),
          onTap: _checkUpdate,
        );
      case _UpdateState.checking:
        return const ListTile(
          leading: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text('Checking…'),
        );
      case _UpdateState.upToDate:
        return ListTile(
          leading: const Icon(Icons.check_circle_outline, color: Colors.green),
          title: const Text('Already up to date'),
          onTap: _checkUpdate,
        );
      case _UpdateState.available:
        return ListTile(
          leading: const Icon(Icons.download_outlined, color: Color(0xFF00D4FF)),
          title: Text('Update available: v${_release!.version}'),
          subtitle: const Text('Tap to download and install'),
          onTap: _doUpdate,
        );
      case _UpdateState.downloading:
        return ListTile(
          leading: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                strokeWidth: 2),
          ),
          title: Text(_downloadProgress > 0
              ? 'Downloading… ${(_downloadProgress * 100).toInt()}%'
              : 'Downloading…'),
        );
      case _UpdateState.error:
        return ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.redAccent),
          title: const Text('Update check failed'),
          subtitle: const Text('Tap to retry'),
          onTap: _checkUpdate,
        );
    }
  }
}

enum _UpdateState { idle, checking, upToDate, available, downloading, error }
