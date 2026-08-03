import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../i18n/app_localizations.dart';
import '../../providers/app_settings_provider.dart';
import '../../utils/ota_service.dart';

typedef StartupUpdateChecker = Future<ReleaseInfo?> Function();
typedef StartupUpdateInstaller = Future<void> Function(
  ReleaseInfo release, {
  void Function(double progress)? onProgress,
});

class StartupUpdateGate extends StatefulWidget {
  final Widget child;
  final StartupUpdateChecker? checkUpdate;
  final StartupUpdateInstaller? downloadAndInstall;

  const StartupUpdateGate({
    super.key,
    required this.child,
    this.checkUpdate,
    this.downloadAndInstall,
  });

  @override
  State<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends State<StartupUpdateGate> {
  _StartupUpdateState _state = _StartupUpdateState.checking;
  ReleaseInfo? _release;
  String? _errorDetail;
  _StartupUpdateFailureStage? _failureStage;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (!mounted) return;
    setState(() {
      _state = _StartupUpdateState.checking;
      _release = null;
      _errorDetail = null;
      _failureStage = null;
      _progress = 0;
    });
    try {
      final checkUpdate = widget.checkUpdate ?? OtaService.checkUpdate;
      final release = await checkUpdate();
      if (!mounted) return;
      if (release == null) {
        setState(() => _state = _StartupUpdateState.ready);
      } else {
        setState(() {
          _release = release;
          _state = _StartupUpdateState.available;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorDetail = e.toString();
        _failureStage = _StartupUpdateFailureStage.check;
        _state = _StartupUpdateState.error;
      });
    }
  }

  Future<void> _installUpdate() async {
    final release = _release;
    if (release == null) return;
    setState(() {
      _state = _StartupUpdateState.downloading;
      _errorDetail = null;
      _failureStage = null;
      _progress = 0;
    });
    try {
      final downloadAndInstall =
          widget.downloadAndInstall ?? OtaService.downloadAndInstall;
      await downloadAndInstall(
        release,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) setState(() => _state = _StartupUpdateState.installing);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorDetail = e.toString();
        _failureStage = _StartupUpdateFailureStage.download;
        _state = _StartupUpdateState.error;
      });
    }
  }

  void _continue() => setState(() => _state = _StartupUpdateState.ready);

  @override
  Widget build(BuildContext context) {
    if (_state == _StartupUpdateState.ready) return widget.child;

    final force = context.watch<AppSettingsProvider>().forceStartupUpdate;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildContent(force),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool force) {
    final l10n = context.l10n;
    final failureStage = _failureStage ?? _StartupUpdateFailureStage.check;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_state) {
            _StartupUpdateState.checking =>
              _CheckingView(key: const ValueKey('checking')),
            _StartupUpdateState.available => _AvailableView(
                key: const ValueKey('available'),
                release: _release!,
                force: force,
                onInstall: _installUpdate,
                onLater: _continue,
              ),
            _StartupUpdateState.downloading => _DownloadingView(
                key: const ValueKey('downloading'),
                progress: _progress,
              ),
            _StartupUpdateState.installing => _MessageView(
                key: const ValueKey('installing'),
                icon: Icons.install_mobile_outlined,
                title: l10n.t('installingUpdate'),
                subtitle: '',
                busy: false,
              ),
            _StartupUpdateState.error => _ErrorView(
                key: const ValueKey('error'),
                detail: _errorDetail,
                failureStage: failureStage,
                allowContinue:
                    failureStage == _StartupUpdateFailureStage.check || !force,
                onRetry: failureStage == _StartupUpdateFailureStage.download
                    ? _installUpdate
                    : _checkUpdate,
                onContinue: _continue,
              ),
            _StartupUpdateState.ready => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

enum _StartupUpdateState {
  checking,
  available,
  downloading,
  installing,
  error,
  ready
}

enum _StartupUpdateFailureStage { check, download }

class _CheckingView extends StatelessWidget {
  const _CheckingView({super.key});

  @override
  Widget build(BuildContext context) => _MessageView(
        icon: Icons.system_update_outlined,
        title: context.l10n.t('startupCheckingUpdates'),
        subtitle: 'NexTerm',
        busy: true,
      );
}

class _AvailableView extends StatelessWidget {
  final ReleaseInfo release;
  final bool force;
  final VoidCallback onInstall;
  final VoidCallback onLater;
  const _AvailableView(
      {super.key,
      required this.release,
      required this.force,
      required this.onInstall,
      required this.onLater});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final notes = release.releaseNotes.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderIcon(icon: Icons.new_releases_outlined),
        const SizedBox(height: 14),
        Text(l10n.updateAvailable(release.version),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
            force
                ? l10n.t('startupForceUpdateSubtitle')
                : l10n.t('startupUpdateSubtitle'),
            style: const TextStyle(color: Colors.white60)),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.t('releaseNotes'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Text(notes,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12, height: 1.35)),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onInstall,
                icon: const Icon(Icons.download_outlined),
                label: Text(l10n.t('updateNow')),
              ),
            ),
            if (!force) ...[
              const SizedBox(width: 10),
              TextButton(onPressed: onLater, child: Text(l10n.t('later'))),
            ],
          ],
        ),
      ],
    );
  }
}

class _DownloadingView extends StatelessWidget {
  final double progress;
  const _DownloadingView({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final known = progress > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderIcon(icon: Icons.downloading_outlined),
        const SizedBox(height: 16),
        Text(
            known
                ? l10n.downloading((progress * 100).toInt())
                : l10n.t('downloading'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        LinearProgressIndicator(value: known ? progress.clamp(0.0, 1.0) : null),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? detail;
  final _StartupUpdateFailureStage failureStage;
  final bool allowContinue;
  final VoidCallback onRetry;
  final VoidCallback onContinue;
  const _ErrorView(
      {super.key,
      required this.detail,
      required this.failureStage,
      required this.allowContinue,
      required this.onRetry,
      required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDownloadFailure =
        failureStage == _StartupUpdateFailureStage.download;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeaderIcon(icon: Icons.error_outline, danger: true),
        const SizedBox(height: 14),
        Text(
            l10n.t(isDownloadFailure
                ? 'startupUpdateDownloadFailed'
                : 'startupUpdateFailed'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
            l10n.t(isDownloadFailure
                ? 'startupUpdateDownloadFailedSubtitle'
                : 'startupUpdateFailedSubtitle'),
            style: const TextStyle(color: Colors.white60)),
        if (detail != null && detail!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            detail!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.t('retry')))),
            if (allowContinue) ...[
              const SizedBox(width: 10),
              TextButton(
                  onPressed: onContinue, child: Text(l10n.t('continueApp'))),
            ],
          ],
        ),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  const _MessageView(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.busy});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HeaderIcon(icon: icon),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.white54)),
          ],
          if (busy) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
          ],
        ],
      );
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final bool danger;
  const _HeaderIcon({required this.icon, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color =
        danger ? Colors.redAccent : Theme.of(context).colorScheme.primary;
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: color),
    );
  }
}
