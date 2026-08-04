import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../i18n/app_localizations.dart';
import '../../models/connection.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/connections_provider.dart';
import '../../utils/connection_backup.dart';
import '../../utils/ota_service.dart';
import '../../utils/rdp_profile_io.dart';
import 'diagnostic_log_screen.dart';
import 'known_hosts_screen.dart';

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
  bool _buildTipVisible = false;
  bool _backupBusy = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = '${i.version}+${i.buildNumber}');
    });
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _updateState = _UpdateState.checking;
      _release = null;
    });
    try {
      final release = await OtaService.checkUpdate();
      if (!mounted) return;
      if (release == null) {
        setState(() => _updateState = _UpdateState.upToDate);
      } else {
        setState(() {
          _updateState = _UpdateState.available;
          _release = release;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _updateState = _UpdateState.error);
    }
  }

  Future<void> _doUpdate() async {
    if (_release == null) return;
    setState(() {
      _updateState = _UpdateState.downloading;
      _downloadProgress = 0;
    });
    try {
      await OtaService.downloadAndInstall(
        _release!,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (mounted) setState(() => _updateState = _UpdateState.installing);
    } catch (e) {
      if (mounted) setState(() => _updateState = _UpdateState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('settings'))),
      body: ListView(
        children: [
          _sectionHeader(l10n.t('general')),
          _languageTile(),
          ListTile(
            leading: const Icon(Icons.display_settings_outlined),
            title: Text(l10n.t('defaultRdpResolution')),
            subtitle: const Text('1280 x 720'),
            onTap: () {},
          ),
          _sectionHeader(l10n.t('sshSecurity')),
          _knownHostsTile(),
          _sectionHeader(l10n.t('backup')),
          _exportEncryptedConnectionsTile(),
          _exportConnectionsTile(),
          _importConnectionsTile(),
          _sectionHeader(l10n.t('rdpProfiles')),
          _exportRdpProfileTile(),
          _importRdpProfileTile(),
          _sectionHeader(l10n.t('diagnostics')),
          _diagnosticsTile(),
          _sectionHeader(l10n.t('update')),
          _forceStartupUpdateTile(),
          _updateTile(),
          _sectionHeader(l10n.t('about')),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.t('version')),
            subtitle: Text(_version.isEmpty ? '...' : _version),
            onTap: _showBuildTip,
          ),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('NexTerm'),
            subtitle: Text(l10n.t('appDescription')),
          ),
        ],
      ),
    );
  }

  void _showBuildTip() {
    if (_buildTipVisible) return;
    _buildTipVisible = true;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          const SnackBar(
            content: Text('由GPT5.5构建编译 - 龍'),
            behavior: SnackBarBehavior.floating,
          ),
        )
        .closed
        .whenComplete(() {
      _buildTipVisible = false;
    });
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      );

  Widget _languageTile() {
    final l10n = context.l10n;
    final settings = context.watch<AppSettingsProvider>();
    final currentLabel = settings.languageCode == 'zh'
        ? l10n.t('languageChinese')
        : l10n.t('languageEnglish');

    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text(l10n.t('language')),
      subtitle: Text('${l10n.t('languageSubtitle')} · $currentLabel'),
      onTap: () => _showLanguageSheet(settings.languageCode),
    );
  }

  void _showLanguageSheet(String selected) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: 'en',
              groupValue: selected,
              title: Text(l10n.t('languageEnglish')),
              onChanged: (value) => _setLanguage(sheetContext, value),
            ),
            RadioListTile<String>(
              value: 'zh',
              groupValue: selected,
              title: Text(l10n.t('languageChinese')),
              onChanged: (value) => _setLanguage(sheetContext, value),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _setLanguage(BuildContext sheetContext, String? value) {
    if (value == null) return;
    context.read<AppSettingsProvider>().setLanguage(value);
    Navigator.pop(sheetContext);
  }

  Widget _forceStartupUpdateTile() {
    final l10n = context.l10n;
    final settings = context.watch<AppSettingsProvider>();
    return SwitchListTile(
      secondary: const Icon(Icons.verified_user_outlined),
      title: Text(l10n.t('forceStartupUpdate')),
      subtitle: Text(l10n.t('forceStartupUpdateSubtitle')),
      value: settings.forceStartupUpdate,
      onChanged: (value) =>
          context.read<AppSettingsProvider>().setForceStartupUpdate(value),
    );
  }

  Widget _knownHostsTile() {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.shield_outlined),
      title: Text(l10n.t('knownHosts')),
      subtitle: Text(l10n.t('knownHostsSubtitle')),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const KnownHostsScreen(),
          ),
        );
      },
    );
  }

  Widget _diagnosticsTile() {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(l10n.t('diagnostics')),
      subtitle: Text(l10n.t('diagnosticsSubtitle')),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DiagnosticLogScreen(),
          ),
        );
      },
    );
  }

  Widget _exportConnectionsTile() {
    final l10n = context.l10n;
    return ListTile(
      leading: _backupBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file_outlined),
      title: Text(l10n.t('exportPlainConnections')),
      subtitle: Text(l10n.t('exportPlainConnectionsSubtitle')),
      enabled: !_backupBusy,
      onTap: _exportConnections,
    );
  }

  Widget _exportEncryptedConnectionsTile() {
    final l10n = context.l10n;
    return ListTile(
      leading: _backupBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.enhanced_encryption_outlined),
      title: Text(l10n.t('exportEncryptedConnections')),
      subtitle: Text(l10n.t('exportEncryptedConnectionsSubtitle')),
      enabled: !_backupBusy,
      onTap: _exportEncryptedConnections,
    );
  }

  Widget _importConnectionsTile() {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.download_for_offline_outlined),
      title: Text(l10n.t('importConnections')),
      subtitle: Text(l10n.t('importConnectionsSubtitle')),
      enabled: !_backupBusy,
      onTap: _importConnections,
    );
  }

  Widget _exportRdpProfileTile() {
    final l10n = context.l10n;
    return ListTile(
      leading: _backupBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.desktop_windows_outlined),
      title: Text(l10n.t('exportRdpProfile')),
      subtitle: Text(l10n.t('exportRdpProfileSubtitle')),
      enabled: !_backupBusy,
      onTap: _exportRdpProfile,
    );
  }

  Widget _importRdpProfileTile() {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.input_outlined),
      title: Text(l10n.t('importRdpProfile')),
      subtitle: Text(l10n.t('importRdpProfileSubtitle')),
      enabled: !_backupBusy,
      onTap: _importRdpProfile,
    );
  }

  Future<void> _exportConnections() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.t('exportBackupWarningTitle'),
      message: l10n.t('exportBackupWarningBody'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _backupBusy = true);
    try {
      final provider = context.read<ConnectionsProvider>();
      final json = await ConnectionBackupService.exportJson(provider.list);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final date = DateTime.now();
      final fileName =
          'nexterm-connections-${date.year}${_two(date.month)}${_two(date.day)}.json';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.t('exportConnections'),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (!mounted) return;
      _showSnack(path == null
          ? l10n.t('backupExportCancelled')
          : l10n.t('backupExportSuccess'));
    } catch (e) {
      if (mounted) _showSnack('${l10n.t('backupExportFailed')}: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _exportEncryptedConnections() async {
    final l10n = context.l10n;
    final passphrase = await _promptBackupPassphrase(
      title: l10n.t('encryptedBackupPassphraseTitle'),
      message: l10n.t('encryptedBackupPassphraseBody'),
      confirm: true,
    );
    if (passphrase == null || !mounted) return;

    setState(() => _backupBusy = true);
    try {
      final provider = context.read<ConnectionsProvider>();
      final json = await ConnectionBackupService.exportEncryptedJson(
        provider.list,
        passphrase,
      );
      final bytes = Uint8List.fromList(utf8.encode(json));
      final date = DateTime.now();
      final fileName =
          'nexterm-connections-encrypted-${date.year}${_two(date.month)}${_two(date.day)}.nexterm-backup';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.t('exportEncryptedConnections'),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['nexterm-backup', 'json'],
        bytes: bytes,
      );
      if (!mounted) return;
      _showSnack(path == null
          ? l10n.t('backupExportCancelled')
          : l10n.t('backupExportSuccess'));
    } catch (e) {
      if (mounted) _showSnack('${l10n.t('backupExportFailed')}: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importConnections() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.t('importBackupWarningTitle'),
      message: l10n.t('importBackupWarningBody'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _backupBusy = true);
    try {
      final provider = context.read<ConnectionsProvider>();
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) _showSnack(l10n.t('backupImportCancelled'));
        return;
      }

      final file = picked.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FormatException('Could not read selected file.');
      }

      final raw = utf8.decode(bytes);
      String? passphrase;
      if (ConnectionBackupService.isEncryptedJson(raw)) {
        if (!mounted) return;
        passphrase = await _promptBackupPassphrase(
          title: l10n.t('encryptedBackupImportTitle'),
          message: l10n.t('encryptedBackupImportBody'),
          confirm: false,
        );
        if (passphrase == null) {
          if (mounted) _showSnack(l10n.t('backupImportCancelled'));
          return;
        }
      }

      final result = await ConnectionBackupService.importJson(
        raw,
        provider,
        passphrase: passphrase,
      );
      if (!mounted) return;
      _showSnack(
          l10n.backupImportSuccess(result.total, result.added, result.updated));
    } catch (e) {
      if (mounted) _showSnack('${l10n.t('backupImportFailed')}: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _exportRdpProfile() async {
    final l10n = context.l10n;
    final provider = context.read<ConnectionsProvider>();
    final rdpConnections =
        provider.list.where((e) => e.type == ConnectionType.rdp).toList();
    if (rdpConnections.isEmpty) {
      _showSnack(l10n.t('rdpProfileNoConnections'));
      return;
    }

    final connection = await _selectRdpConnection(rdpConnections);
    if (connection == null || !mounted) return;

    setState(() => _backupBusy = true);
    try {
      final profile = RdpProfileIo.exportConnection(connection);
      final bytes = Uint8List.fromList(utf8.encode(profile));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.t('exportRdpProfile'),
        fileName: RdpProfileIo.defaultFileName(connection),
        type: FileType.custom,
        allowedExtensions: const ['rdp'],
        bytes: bytes,
      );
      if (!mounted) return;
      _showSnack(path == null
          ? l10n.t('rdpProfileExportCancelled')
          : l10n.t('rdpProfileExportSuccess'));
    } catch (e) {
      if (mounted) _showSnack('${l10n.t('rdpProfileExportFailed')}: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importRdpProfile() async {
    final l10n = context.l10n;
    final provider = context.read<ConnectionsProvider>();
    setState(() => _backupBusy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['rdp'],
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) _showSnack(l10n.t('rdpProfileImportCancelled'));
        return;
      }

      final file = picked.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FormatException('Could not read selected file.');
      }

      final connection = RdpProfileIo.importConnection(
        _decodeTextFile(bytes),
        id: const Uuid().v4(),
        displayName: file.name,
      );
      await provider.add(connection);
      if (!mounted) return;
      _showSnack(l10n
          .t('rdpProfileImportSuccess')
          .replaceAll('{name}', connection.name));
    } catch (e) {
      if (mounted) _showSnack('${l10n.t('rdpProfileImportFailed')}: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<Connection?> _selectRdpConnection(List<Connection> connections) {
    final l10n = context.l10n;
    return showModalBottomSheet<Connection>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: Text(l10n.t('rdpProfileSelectConnection')),
              subtitle: Text(l10n.t('rdpProfilePasswordNote')),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: connections.length,
                itemBuilder: (context, index) {
                  final connection = connections[index];
                  return ListTile(
                    leading: const Icon(Icons.desktop_windows_outlined),
                    title: Text(connection.name),
                    subtitle: Text('${connection.host}:${connection.port}'),
                    onTap: () => Navigator.pop(sheetContext, connection),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(
      {required String title, required String message}) async {
    final l10n = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.t('continueApp')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _promptBackupPassphrase({
    required String title,
    required String message,
    required bool confirm,
  }) {
    final l10n = context.l10n;
    final passController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 16),
                TextField(
                  controller: passController,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.t('backupPassphrase'),
                    errorText: errorText,
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.t('backupPassphraseConfirm'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () {
                final passphrase = passController.text;
                if (passphrase.isEmpty) {
                  setDialogState(
                    () => errorText = l10n.t('backupPassphraseRequired'),
                  );
                  return;
                }
                if (confirm && passphrase.length < 8) {
                  setDialogState(
                    () => errorText = l10n.t('backupPassphraseTooShort'),
                  );
                  return;
                }
                if (confirm && passphrase != confirmController.text) {
                  setDialogState(
                    () => errorText = l10n.t('backupPassphraseMismatch'),
                  );
                  return;
                }
                Navigator.pop(dialogContext, passphrase);
              },
              child: Text(l10n.t('continueApp')),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      passController.dispose();
      confirmController.dispose();
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _decodeTextFile(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, littleEndian: true, offset: 2);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, littleEndian: false, offset: 2);
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _decodeUtf16(
    Uint8List bytes, {
    required bool littleEndian,
    required int offset,
  }) {
    final codeUnits = <int>[];
    for (var i = offset; i + 1 < bytes.length; i += 2) {
      final codeUnit = littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1];
      codeUnits.add(codeUnit);
    }
    return String.fromCharCodes(codeUnits);
  }

  Widget _updateTile() {
    final l10n = context.l10n;
    switch (_updateState) {
      case _UpdateState.idle:
        return ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(l10n.t('checkForUpdates')),
          onTap: _checkUpdate,
        );
      case _UpdateState.checking:
        return ListTile(
          leading: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text(l10n.t('checking')),
        );
      case _UpdateState.upToDate:
        return ListTile(
          leading: const Icon(Icons.check_circle_outline, color: Colors.green),
          title: Text(l10n.t('alreadyUpToDate')),
          onTap: _checkUpdate,
        );
      case _UpdateState.available:
        return ListTile(
          leading:
              const Icon(Icons.download_outlined, color: Color(0xFF00D4FF)),
          title: Text(l10n.updateAvailable(_release!.version)),
          subtitle: Text(l10n.t('tapDownloadInstall')),
          onTap: _doUpdate,
        );
      case _UpdateState.downloading:
        return ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                strokeWidth: 2),
          ),
          title: Text(_downloadProgress > 0
              ? l10n.downloading((_downloadProgress * 100).toInt())
              : l10n.t('downloading')),
        );
      case _UpdateState.installing:
        return ListTile(
          leading: const Icon(Icons.install_mobile_outlined,
              color: Color(0xFF37D6C2)),
          title: Text(l10n.t('installingUpdate')),
        );
      case _UpdateState.error:
        return ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.redAccent),
          title: Text(l10n.t('updateCheckFailed')),
          subtitle: Text(l10n.t('tapRetry')),
          onTap: _checkUpdate,
        );
    }
  }
}

enum _UpdateState {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  error
}
