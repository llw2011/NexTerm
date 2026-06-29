import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../models/connection.dart';
import 'known_hosts.dart';

class SshHostKeyPrompt {
  static Future<bool> verify({
    required BuildContext context,
    required Connection connection,
    required String type,
    required Uint8List fingerprint,
    void Function(String message)? onLog,
  }) async {
    final fpHex = KnownHosts.fingerprintHex(fingerprint);
    final saved = await KnownHosts.load(connection.host, connection.port);

    if (saved == fpHex) {
      onLog?.call('Host key fingerprint matches known_hosts');
      return true;
    }

    if (!context.mounted) return false;

    if (saved == null) {
      final trust = await _showDialog(
        context: context,
        connection: connection,
        isMismatch: false,
        type: type,
        newFp: fpHex,
        oldFp: null,
      );
      if (trust == true) {
        await KnownHosts.save(connection.host, connection.port, fpHex);
        onLog?.call('Host key trusted on first use');
        return true;
      }
      onLog?.call('Host key first-seen rejected by user');
      return false;
    }

    final trust = await _showDialog(
      context: context,
      connection: connection,
      isMismatch: true,
      type: type,
      newFp: fpHex,
      oldFp: saved,
    );
    if (trust == true) {
      await KnownHosts.save(connection.host, connection.port, fpHex);
      onLog?.call('Host key mismatch - user accepted new fingerprint');
      return true;
    }

    onLog?.call('Host key mismatch - user aborted');
    return false;
  }

  static Future<bool?> _showDialog({
    required BuildContext context,
    required Connection connection,
    required bool isMismatch,
    required String type,
    required String newFp,
    String? oldFp,
  }) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          isMismatch ? Icons.warning_amber : Icons.shield_outlined,
          color: isMismatch ? Colors.redAccent : Colors.amber,
          size: 40,
        ),
        title: Text(isMismatch
            ? l10n.t('sshHostKeyMismatch')
            : l10n.t('sshHostKeyFirstSeen')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isMismatch
                  ? l10n.t('sshHostKeyMismatchDetail')
                  : l10n.t('sshHostKeyFirstSeenDetail')),
              const SizedBox(height: 12),
              Text(
                '${connection.host}:${connection.port}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${l10n.t('sshKeyType')}: $type',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              if (oldFp != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.t('sshOldFingerprint'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                SelectableText(
                  oldFp,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white54,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                oldFp != null
                    ? l10n.t('sshNewFingerprint')
                    : l10n.t('sshHostFingerprint'),
                style: const TextStyle(fontSize: 12),
              ),
              SelectableText(
                newFp,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('sshAbort')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isMismatch ? Colors.redAccent : null,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
                isMismatch ? l10n.t('sshTrustAnyway') : l10n.t('sshTrustHost')),
          ),
        ],
      ),
    );
  }
}
