import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/app_localizations.dart';
import '../../models/connection.dart';
import '../../providers/connections_provider.dart';
import '../../utils/sftp_service.dart';
import '../../utils/ssh_host_key_prompt.dart';

class SftpScreen extends StatefulWidget {
  final Connection connection;

  const SftpScreen({super.key, required this.connection});

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> {
  SftpSession? _session;
  List<SftpName> _entries = const [];
  String _path = '.';
  bool _connecting = true;
  bool _loading = false;
  String? _error;

  _TransferInfo? _transfer;
  SftpFile? _activeRemoteFile;
  SftpFileWriter? _activeUpload;
  StreamSubscription<Uint8List>? _activeDownload;
  Completer<void>? _activeDownloadDone;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _activeUpload?.abort();
    _activeDownload?.cancel();
    _activeRemoteFile?.close();
    _session?.close();
    super.dispose();
  }

  Future<bool> _verifyHostKey(
    Connection connection,
    String type,
    Uint8List fingerprint,
  ) {
    return SshHostKeyPrompt.verify(
      context: context,
      connection: connection,
      type: type,
      fingerprint: fingerprint,
    );
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      final session = await SftpService.connect(
        widget.connection,
        allConnections: context.read<ConnectionsProvider>().list,
        verifyHostKey: _verifyHostKey,
      );
      if (!mounted) {
        session.close();
        return;
      }
      _session = session;
      final initialPath = await _resolvePath('.');
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _path = initialPath;
      });
      await _loadDirectory(initialPath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = _cleanError(e);
      });
    }
  }

  Future<String> _resolvePath(String path) async {
    final sftp = _session?.sftp;
    if (sftp == null) return path;
    try {
      return await sftp.absolute(path);
    } catch (_) {
      return path;
    }
  }

  Future<void> _loadDirectory([String? path]) async {
    final sftp = _session?.sftp;
    if (sftp == null) return;

    final target = path ?? _path;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resolved = await _resolvePath(target);
      final entries = await sftp.listdir(resolved);
      final visible = entries
          .where((entry) => entry.filename != '.' && entry.filename != '..')
          .toList()
        ..sort(_compareEntries);

      if (!mounted) return;
      setState(() {
        _path = resolved;
        _entries = visible;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _compareEntries(SftpName a, SftpName b) {
    final aDir = a.attr.isDirectory;
    final bDir = b.attr.isDirectory;
    if (aDir != bDir) return aDir ? -1 : 1;
    return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
  }

  Future<void> _openEntry(SftpName entry) async {
    if (!entry.attr.isDirectory) return;
    await _loadDirectory(_joinPath(_path, entry.filename));
  }

  Future<void> _goParent() async {
    if (_isRoot(_path)) return;
    await _loadDirectory(_parentPath(_path));
  }

  Future<void> _createDirectory() async {
    if (!_ensureNoTransfer()) return;
    final l10n = context.l10n;
    final name = await _showNameDialog(
      title: l10n.t('sftpNewFolder'),
      action: l10n.t('add'),
    );
    if (name == null) return;

    try {
      await _session!.sftp.mkdir(_joinPath(_path, name));
      await _loadDirectory();
    } catch (e) {
      _showSnack('${l10n.t('sftpOperationFailed')}: ${_cleanError(e)}');
    }
  }

  Future<void> _rename(SftpName entry) async {
    if (!_ensureNoTransfer()) return;
    final l10n = context.l10n;
    final name = await _showNameDialog(
      title: l10n.t('sftpRename'),
      action: l10n.t('save'),
      initialValue: entry.filename,
    );
    if (name == null || name == entry.filename) return;

    try {
      await _session!.sftp.rename(
        _joinPath(_path, entry.filename),
        _joinPath(_path, name),
      );
      await _loadDirectory();
    } catch (e) {
      _showSnack('${l10n.t('sftpOperationFailed')}: ${_cleanError(e)}');
    }
  }

  Future<void> _delete(SftpName entry) async {
    if (!_ensureNoTransfer()) return;
    final l10n = context.l10n;
    final confirmed = await _confirmDelete(entry);
    if (confirmed != true) return;

    try {
      final fullPath = _joinPath(_path, entry.filename);
      if (entry.attr.isDirectory) {
        await _session!.sftp.rmdir(fullPath);
      } else {
        await _session!.sftp.remove(fullPath);
      }
      await _loadDirectory();
    } catch (e) {
      _showSnack('${l10n.t('sftpOperationFailed')}: ${_cleanError(e)}');
    }
  }

  Future<void> _uploadFile() async {
    if (!_ensureNoTransfer()) return;
    final l10n = context.l10n;

    final picked = await FilePicker.platform.pickFiles(
      withReadStream: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;

    final pickedFile = picked.files.single;
    final stream = _openPickedFileStream(pickedFile);
    if (stream == null) {
      _showSnack(l10n.t('sftpUploadNoStream'));
      return;
    }

    SftpFile? remoteFile;
    _cancelRequested = false;

    try {
      remoteFile = await _session!.sftp.open(
        _joinPath(_path, pickedFile.name),
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      _activeRemoteFile = remoteFile;
      _setTransfer(
        label: _message('sftpUploadingFile', {'name': pickedFile.name}),
        totalBytes: pickedFile.size,
      );

      final writer = remoteFile.write(
        _asUint8ListStream(stream),
        onProgress: (bytes) => _updateTransfer(bytes, pickedFile.size),
      );
      _activeUpload = writer;
      await writer.done;

      if (_cancelRequested) throw const _SftpCancelled();
      _showSnack(l10n.t('sftpTransferComplete'));
      await _loadDirectory();
    } on _SftpCancelled {
      _showSnack(l10n.t('sftpCancelled'));
    } catch (e) {
      _showSnack('${l10n.t('sftpTransferFailed')}: ${_cleanError(e)}');
    } finally {
      _activeUpload = null;
      _activeRemoteFile = null;
      await remoteFile?.close();
      _clearTransfer();
    }
  }

  Future<void> _downloadFile(SftpName entry) async {
    if (!_ensureNoTransfer()) return;
    final l10n = context.l10n;
    final total = entry.attr.size;
    final buffer = BytesBuilder(copy: false);
    SftpFile? remoteFile;
    _cancelRequested = false;

    try {
      remoteFile = await _session!.sftp.open(_joinPath(_path, entry.filename));
      _activeRemoteFile = remoteFile;
      _setTransfer(
        label: _message('sftpDownloadingFile', {'name': entry.filename}),
        totalBytes: total,
      );

      final done = Completer<void>();
      _activeDownloadDone = done;
      _activeDownload = remoteFile
          .read(
        length: total,
        onProgress: (bytes) => _updateTransfer(bytes, total),
      )
          .listen(
        buffer.add,
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );

      await done.future;
      if (_cancelRequested) throw const _SftpCancelled();

      final savedPath = await _saveBytes(entry.filename, buffer.takeBytes());
      if (savedPath == null) {
        _showSnack(l10n.t('sftpSaveCancelled'));
      } else {
        _showSnack(l10n.t('sftpTransferComplete'));
      }
    } on _SftpCancelled {
      _showSnack(l10n.t('sftpCancelled'));
    } catch (e) {
      _showSnack('${l10n.t('sftpTransferFailed')}: ${_cleanError(e)}');
    } finally {
      _activeDownloadDone = null;
      _activeDownload = null;
      _activeRemoteFile = null;
      await remoteFile?.close();
      _clearTransfer();
    }
  }

  Stream<List<int>>? _openPickedFileStream(PlatformFile pickedFile) {
    final readStream = pickedFile.readStream;
    if (readStream != null) return readStream;

    final path = pickedFile.path;
    if (path == null || path.isEmpty) return null;
    return File(path).openRead();
  }

  Stream<Uint8List> _asUint8ListStream(Stream<List<int>> stream) {
    return stream.map((chunk) {
      if (chunk is Uint8List) return chunk;
      return Uint8List.fromList(chunk);
    });
  }

  Future<String?> _saveBytes(String fileName, Uint8List bytes) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
    }

    final path = await FilePicker.platform.saveFile(fileName: fileName);
    if (path == null) return null;
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  void _cancelTransfer() {
    _cancelRequested = true;
    final done = _activeDownloadDone;
    if (done != null && !done.isCompleted) {
      done.completeError(const _SftpCancelled());
    }
    unawaited(_activeUpload?.abort());
    unawaited(_activeDownload?.cancel());
    setState(() => _transfer = _transfer?.copyWith(cancelling: true));
  }

  bool _ensureNoTransfer() {
    if (_transfer == null) return true;
    _showSnack(context.l10n.t('sftpTransferBusy'));
    return false;
  }

  void _setTransfer({required String label, required int? totalBytes}) {
    if (!mounted) return;
    setState(() {
      _transfer = _TransferInfo(
        label: label,
        bytesDone: 0,
        totalBytes: totalBytes,
        startedAt: DateTime.now(),
      );
    });
  }

  void _updateTransfer(int bytesDone, int? totalBytes) {
    final transfer = _transfer;
    if (!mounted || transfer == null) return;
    setState(() {
      _transfer = transfer.copyWith(
        bytesDone: bytesDone,
        totalBytes: totalBytes ?? transfer.totalBytes,
      );
    });
  }

  void _clearTransfer() {
    if (!mounted) return;
    setState(() => _transfer = null);
  }

  Future<String?> _showNameDialog({
    required String title,
    required String action,
    String initialValue = '',
  }) {
    final l10n = context.l10n;
    final controller = TextEditingController(text: initialValue);
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.t('sftpName'),
              errorText: errorText,
            ),
            onSubmitted: (_) => _submitNameDialog(
              ctx,
              controller,
              setDialogState,
              (value) => errorText = value,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => _submitNameDialog(
                ctx,
                controller,
                setDialogState,
                (value) => errorText = value,
              ),
              child: Text(action),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _submitNameDialog(
    BuildContext dialogContext,
    TextEditingController controller,
    StateSetter setDialogState,
    ValueChanged<String?> setError,
  ) {
    final value = controller.text.trim();
    if (value.isEmpty || value.contains('/') || value.contains('\\')) {
      setDialogState(() => setError(context.l10n.t('sftpInvalidName')));
      return;
    }
    Navigator.of(dialogContext).pop(value);
  }

  Future<bool?> _confirmDelete(SftpName entry) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('sftpDeleteConfirmTitle')),
        content: Text(
          _message('sftpDeleteConfirmBody', {'name': entry.filename}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.t('delete')),
          ),
        ],
      ),
    );
  }

  String _message(String key, Map<String, String> values) {
    var text = context.l10n.t(key);
    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  String _joinPath(String base, String name) {
    if (base.isEmpty || base == '.') return name;
    if (base == '/') return '/$name';
    if (base.endsWith('/')) return '$base$name';
    return '$base/$name';
  }

  String _parentPath(String path) {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return '/';
    return trimmed.substring(0, index);
  }

  bool _isRoot(String path) => path == '/' || path.isEmpty;

  String _cleanError(Object error) {
    final raw = error.toString();
    return raw.replaceFirst(RegExp(r'^Exception: '), '');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final transfer = _transfer;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.t('sftp')),
            Text(
              widget.connection.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.t('sftpRefresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _connecting ? null : () => _loadDirectory(),
          ),
          IconButton(
            tooltip: l10n.t('sftpUpload'),
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _connecting ? null : _uploadFile,
          ),
          IconButton(
            tooltip: l10n.t('sftpNewFolder'),
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _connecting ? null : _createDirectory,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody(context)),
          if (transfer != null)
            _TransferPanel(
              transfer: transfer,
              onCancel: _cancelTransfer,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;

    if (_connecting) {
      return _SftpStatusView(
        icon: null,
        title: l10n.t('sftpConnecting'),
        message:
            '${widget.connection.username}@${widget.connection.host}:${widget.connection.port}',
        showProgress: true,
      );
    }

    if (_error != null && _entries.isEmpty) {
      return _SftpStatusView(
        icon: Icons.error_outline,
        title: l10n.t('sftpOpenFailed'),
        message: _error!,
        actionLabel: l10n.t('retry'),
        onAction: _connect,
      );
    }

    return Column(
      children: [
        _PathHeader(path: _path),
        if (_error != null)
          Material(
            color: Colors.redAccent.withValues(alpha: 0.10),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.error_outline, color: Colors.redAccent),
              title: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        Expanded(
          child: _entries.isEmpty && _isRoot(_path)
              ? _SftpStatusView(
                  icon: Icons.folder_open_outlined,
                  title: l10n.t('sftpNoFiles'),
                )
              : ListView.separated(
                  itemCount: _entries.length + (_isRoot(_path) ? 0 : 1),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (!_isRoot(_path) && index == 0) {
                      return ListTile(
                        leading: const Icon(Icons.drive_folder_upload_outlined),
                        title: Text(l10n.t('sftpParentDirectory')),
                        subtitle: Text(_parentPath(_path)),
                        onTap: _goParent,
                      );
                    }
                    final entryIndex = index - (_isRoot(_path) ? 0 : 1);
                    final entry = _entries[entryIndex];
                    return _SftpEntryTile(
                      entry: entry,
                      onOpen: () => _openEntry(entry),
                      onDownload: entry.attr.isDirectory
                          ? null
                          : () => _downloadFile(entry),
                      onRename: () => _rename(entry),
                      onDelete: () => _delete(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SftpEntryTile extends StatelessWidget {
  final SftpName entry;
  final VoidCallback onOpen;
  final VoidCallback? onDownload;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SftpEntryTile({
    required this.entry,
    required this.onOpen,
    required this.onDownload,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDirectory = entry.attr.isDirectory;

    return ListTile(
      leading: Icon(
        isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
        color: isDirectory ? Colors.amber : null,
      ),
      title: Text(entry.filename, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (!isDirectory) _formatBytes(entry.attr.size),
          if (entry.attr.modifyTime != null)
            _formatModified(entry.attr.modifyTime!),
        ].where((part) => part.isNotEmpty).join(' · '),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: isDirectory ? onOpen : onDownload,
      trailing: PopupMenuButton<_SftpEntryAction>(
        tooltip: l10n.t('manageConnection'),
        onSelected: (action) {
          switch (action) {
            case _SftpEntryAction.open:
              onOpen();
              break;
            case _SftpEntryAction.download:
              onDownload?.call();
              break;
            case _SftpEntryAction.rename:
              onRename();
              break;
            case _SftpEntryAction.delete:
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          if (isDirectory)
            PopupMenuItem(
              value: _SftpEntryAction.open,
              child: Text(l10n.t('sftpOpen')),
            ),
          if (!isDirectory)
            PopupMenuItem(
              value: _SftpEntryAction.download,
              child: Text(l10n.t('sftpDownload')),
            ),
          PopupMenuItem(
            value: _SftpEntryAction.rename,
            child: Text(l10n.t('sftpRename')),
          ),
          PopupMenuItem(
            value: _SftpEntryAction.delete,
            child: Text(l10n.t('delete')),
          ),
        ],
      ),
    );
  }
}

class _PathHeader extends StatelessWidget {
  final String path;

  const _PathHeader({required this.path});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                path,
                maxLines: 1,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferPanel extends StatelessWidget {
  final _TransferInfo transfer;
  final VoidCallback onCancel;

  const _TransferPanel({required this.transfer, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final progress = transfer.progress;

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatBytes(transfer.bytesDone)}'
                      '${transfer.totalBytes == null ? '' : ' / ${_formatBytes(transfer.totalBytes)}'}'
                      ' · ${_formatBytes(transfer.speedBytesPerSecond)}/s',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: transfer.cancelling ? null : onCancel,
                child: Text(l10n.t('cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SftpStatusView extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? message;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SftpStatusView({
    required this.icon,
    required this.title,
    this.message,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              const CircularProgressIndicator()
            else if (icon != null)
              Icon(icon, size: 44, color: Colors.white54),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _SftpEntryAction { open, download, rename, delete }

class _TransferInfo {
  final String label;
  final int bytesDone;
  final int? totalBytes;
  final DateTime startedAt;
  final bool cancelling;

  const _TransferInfo({
    required this.label,
    required this.bytesDone,
    required this.totalBytes,
    required this.startedAt,
    this.cancelling = false,
  });

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesDone / total).clamp(0.0, 1.0);
  }

  int get speedBytesPerSecond {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsed <= 0) return 0;
    return (bytesDone * 1000 / elapsed).round();
  }

  _TransferInfo copyWith({
    int? bytesDone,
    int? totalBytes,
    bool? cancelling,
  }) {
    return _TransferInfo(
      label: label,
      bytesDone: bytesDone ?? this.bytesDone,
      totalBytes: totalBytes ?? this.totalBytes,
      startedAt: startedAt,
      cancelling: cancelling ?? this.cancelling,
    );
  }
}

class _SftpCancelled implements Exception {
  const _SftpCancelled();
}

String _formatBytes(int? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.toStringAsFixed(0)} ${units[unit]}';
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
}

String _formatModified(int seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
