import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/connection.dart';
import 'package:nexterm/utils/rdp_profile_io.dart';

void main() {
  test('imports common Windows RDP profile fields', () {
    final connection = RdpProfileIo.importConnection(
      '''
screen mode id:i:2
full address:s:rdp.example.com:3390
username:s:alice
domain:s:ACME
desktopwidth:i:1920
desktopheight:i:1080
enablecredsspsupport:i:1
''',
      id: 'imported-id',
      displayName: 'prod.rdp',
    );

    expect(connection.id, 'imported-id');
    expect(connection.name, 'prod');
    expect(connection.type, ConnectionType.rdp);
    expect(connection.host, 'rdp.example.com');
    expect(connection.port, 3390);
    expect(connection.username, 'alice');
    expect(connection.domain, 'ACME');
    expect(connection.width, 1920);
    expect(connection.height, 1080);
    expect(connection.rdpSecurity, RdpSecurityProtocol.nla);
  });

  test('server port overrides full address port', () {
    final connection = RdpProfileIo.importConnection(
      '''
full address:s:rdp.example.com:3390
server port:i:3389
username:s:bob
''',
      id: 'id',
    );

    expect(connection.host, 'rdp.example.com');
    expect(connection.port, 3389);
  });

  test('exports an RDP profile without credentials', () {
    const connection = Connection(
      id: 'id',
      name: 'Prod Server',
      host: '10.0.0.5',
      port: 3391,
      username: 'administrator',
      type: ConnectionType.rdp,
      domain: 'LAB',
      width: 1600,
      height: 900,
      rdpSecurity: RdpSecurityProtocol.rdp,
    );

    final profile = RdpProfileIo.exportConnection(connection);

    expect(profile, contains('full address:s:10.0.0.5'));
    expect(profile, contains('server port:i:3391'));
    expect(profile, contains('username:s:administrator'));
    expect(profile, contains('domain:s:LAB'));
    expect(profile, contains('desktopwidth:i:1600'));
    expect(profile, contains('desktopheight:i:900'));
    expect(profile, contains('negotiate security layer:i:0'));
    expect(profile, isNot(contains('password')));
  });

  test('imports profiles without carrying password fields', () {
    final connection = RdpProfileIo.importConnection(
      '''
full address:s:rdp.example.com
username:s:alice
password 51:b:01000000d08c9ddf0115d1118c7a00c04fc297eb
''',
      id: 'id',
    );

    expect(connection.host, 'rdp.example.com');
    expect(connection.username, 'alice');
    expect(connection.toJson().containsKey('password'), isFalse);
  });

  test('rejects invalid profiles with readable errors', () {
    expect(
      () => RdpProfileIo.importConnection('username:s:alice', id: 'id'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => RdpProfileIo.importConnection(
        'full address:s:server:99999',
        id: 'id',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects exporting non-RDP connections', () {
    const connection = Connection(
      id: 'id',
      name: 'SSH',
      host: 'example.com',
      port: 22,
      username: 'alice',
      type: ConnectionType.ssh,
    );

    expect(
      () => RdpProfileIo.exportConnection(connection),
      throwsA(isA<ArgumentError>()),
    );
  });
}
