import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/connection.dart';
import 'package:nexterm/utils/ssh_connection_service.dart';

void main() {
  const target = Connection(
    id: 'target',
    name: 'Target',
    host: 'target.internal',
    port: 22,
    username: 'root',
    type: ConnectionType.ssh,
    sshJumpHostId: 'jump',
  );

  const jump = Connection(
    id: 'jump',
    name: 'Jump',
    host: 'jump.example.com',
    port: 22,
    username: 'ops',
    type: ConnectionType.ssh,
  );

  const nestedJump = Connection(
    id: 'nested',
    name: 'Nested',
    host: 'nested.example.com',
    port: 22,
    username: 'ops',
    type: ConnectionType.ssh,
    sshJumpHostId: 'jump',
  );

  const rdp = Connection(
    id: 'rdp',
    name: 'RDP',
    host: 'rdp.example.com',
    port: 3389,
    username: 'administrator',
    type: ConnectionType.rdp,
  );

  test('jump host candidates are ssh-only, one-hop, and not self', () {
    final candidates = SshConnectionService.jumpHostCandidates(
      target,
      [target, jump, nestedJump, rdp],
    );

    expect(candidates, [jump]);
  });

  test('resolve jump host returns configured one-hop connection', () {
    final resolved =
        SshConnectionService.resolveJumpHost(target, [target, jump]);

    expect(resolved, jump);
  });

  test('resolve jump host rejects missing jump connection', () {
    expect(
      () => SshConnectionService.resolveJumpHost(target, [target]),
      throwsStateError,
    );
  });

  test('resolve jump host rejects self reference', () {
    final selfReferencing = target.copyWith(sshJumpHostId: target.id);

    expect(
      () => SshConnectionService.resolveJumpHost(
        selfReferencing,
        [selfReferencing],
      ),
      throwsStateError,
    );
  });

  test('resolve jump host rejects multi-hop chains', () {
    final targetViaNested = target.copyWith(sshJumpHostId: nestedJump.id);

    expect(
      () => SshConnectionService.resolveJumpHost(
        targetViaNested,
        [targetViaNested, jump, nestedJump],
      ),
      throwsStateError,
    );
  });
}
