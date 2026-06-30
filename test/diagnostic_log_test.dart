import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/diagnostic_log.dart';

void main() {
  setUp(DiagnosticLog.clear);

  test('keeps a bounded in-memory ring buffer', () {
    for (var i = 0; i < DiagnosticLog.maxEntries + 5; i++) {
      DiagnosticLog.rdp(stage: 'stage_$i', message: 'message_$i');
    }

    final entries = DiagnosticLog.entries;

    expect(entries, hasLength(DiagnosticLog.maxEntries));
    expect(entries.first.stage, 'stage_5');
    expect(entries.last.stage, 'stage_204');
  });

  test('exports redacted logs without credentials or tokens', () {
    final fakeToken = 'github_' 'pat_abc1234567890_secret';
    final fakePrivateKey = [
      '-----BEGIN OPENSSH ' 'PRIVATE KEY-----',
      'secret-key-body',
      '-----END OPENSSH ' 'PRIVATE KEY-----',
    ].join('\n');
    DiagnosticLog.rdp(
      stage: 'auth',
      message: 'password=secret passphrase=hunter2 token=$fakeToken',
      error: fakePrivateKey,
    );

    final exported = DiagnosticLog.exportText(redacted: true);

    expect(exported, isNot(contains('secret')));
    expect(exported, isNot(contains('hunter2')));
    expect(exported, isNot(contains(fakeToken)));
    expect(exported, isNot(contains('OPENSSH PRIVATE KEY')));
    expect(exported, contains('<redacted>'));
  });

  test('classifies common RDP native errors into useful stages', () {
    expect(
      DiagnosticLog.inferRdpStageFromError(
        'connect_begin: utils_reload_channels status=0 error 0x00020001',
      ),
      'preconnect',
    );
    expect(
      DiagnosticLog.inferRdpStageFromError('DNS name not found 0x00020005'),
      'dns_tcp',
    );
    expect(
      DiagnosticLog.inferRdpStageFromError('Logon failed 0x00020014'),
      'auth',
    );
    expect(
      DiagnosticLog.inferRdpStageFromError('PostConnect failed: gdi_init'),
      'postconnect',
    );
  });
}
