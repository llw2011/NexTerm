import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/components/keyboard/keyboard_layout.dart';
import 'package:nexterm/components/keyboard/keyboard_types.dart';
import 'package:nexterm/utils/rdp_key_test_catalog.dart';

void main() {
  test('rdp key test catalog uses expected scan codes', () {
    final byLabel = {
      for (final key in RdpKeyTestCatalog.all) key.label: key,
    };

    expect(byLabel['Left']!.scanCode, 0x4B);
    expect(byLabel['Left']!.extended, isTrue);
    expect(byLabel['Delete']!.scanCode, 0x53);
    expect(byLabel['Delete']!.extended, isTrue);
    expect(byLabel['Insert']!.scanCode, 0x52);
    expect(byLabel['Insert']!.extended, isTrue);
    expect(byLabel['LWin']!.scanCode, 0x5B);
    expect(byLabel['LWin']!.extended, isTrue);
    expect(byLabel['F12']!.scanCode, 0x58);
    expect(byLabel['F12']!.extended, isFalse);
  });

  test('rdp key test catalog has unique scan and extended pairs', () {
    final pairs = <String>{};
    for (final key in RdpKeyTestCatalog.all) {
      final pair = '${key.scanCode}:${key.extended}';
      expect(pairs.add(pair), isTrue, reason: 'duplicate ${key.label}');
    }
  });

  test('formal RDP function keyboard uses cataloged scan pairs', () {
    final functionKeys = KeyboardLayout.getLayout(KeyboardPage.function)
        .expand((row) => row)
        .where((key) => key.virtualKeyCode != null);

    for (final key in functionKeys) {
      expect(
        RdpKeyTestCatalog.containsScanPair(
          key.virtualKeyCode!,
          key.extended,
        ),
        isTrue,
        reason: 'uncataloged formal key ${key.label}',
      );
    }
  });

  test('formal RDP function keyboard exposes advanced key MVP', () {
    final labels = KeyboardLayout.getLayout(KeyboardPage.function)
        .expand((row) => row)
        .map((key) => key.label)
        .toSet();

    for (final label in [
      'Ctrl',
      'Alt',
      'Win',
      '←',
      '↑',
      '↓',
      '→',
      'Home',
      'End',
      'PgUp',
      'PgDn',
      'Ins',
      'Del',
      'F1',
      'F2',
      'F3',
      'F4',
      'F5',
      'F6',
      'F7',
      'F8',
      'F9',
      'F10',
      'F11',
      'F12',
    ]) {
      expect(labels, contains(label));
    }
  });

  test('remote Del buttons send true Delete scan code', () {
    for (final page in [KeyboardPage.english, KeyboardPage.symbols]) {
      final deleteKeys = KeyboardLayout.getLayout(page)
          .expand((row) => row)
          .where((key) => key.action == 'del_remote');

      for (final key in deleteKeys) {
        expect(key.virtualKeyCode, 0x53);
        expect(key.extended, isTrue);
      }
    }
  });
}
