import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/known_hosts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('lists saved known hosts in stable order', () async {
    await KnownHosts.save('Beta.example.com', 2222, 'bb:22');
    await KnownHosts.save('alpha.example.com', 22, 'aa:22');

    final entries = await KnownHosts.list();

    expect(entries, hasLength(2));
    expect(entries[0].host, 'alpha.example.com');
    expect(entries[0].port, 22);
    expect(entries[0].fingerprint, 'aa:22');
    expect(entries[1].host, 'beta.example.com');
    expect(entries[1].port, 2222);
    expect(entries[1].fingerprint, 'bb:22');
  });

  test('remove deletes trusted fingerprint so TOFU can run again', () async {
    await KnownHosts.save('example.com', 22, 'aa:bb:cc');

    expect(await KnownHosts.load('example.com', 22), 'aa:bb:cc');

    await KnownHosts.remove('example.com', 22);

    expect(await KnownHosts.load('example.com', 22), isNull);
    expect(await KnownHosts.list(), isEmpty);
  });
}
