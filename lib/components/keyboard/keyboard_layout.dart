import 'keyboard_types.dart';
import '../../utils/rdp_key_test_catalog.dart';

class KeyDefinition {
  final String label;
  final String? shiftLabel;
  final int? virtualKeyCode;
  final bool extended;
  final KeySize size;
  final KeyType type;
  final String? action;

  const KeyDefinition({
    required this.label,
    this.shiftLabel,
    this.virtualKeyCode,
    this.extended = false,
    this.size = KeySize.normal,
    this.type = KeyType.character,
    this.action,
  });

  String getDisplayLabel({bool shift = false}) {
    if (shift && shiftLabel != null) return shiftLabel!;
    return label;
  }
}

enum KeySize { normal, wide, extraWide }

enum KeyType { character, function, modifier, space }

class KeyboardLayout {
  static const List<List<KeyDefinition>> englishLayout = [
    // Row 1: Q-P
    [
      KeyDefinition(label: 'q', shiftLabel: 'Q'),
      KeyDefinition(label: 'w', shiftLabel: 'W'),
      KeyDefinition(label: 'e', shiftLabel: 'E'),
      KeyDefinition(label: 'r', shiftLabel: 'R'),
      KeyDefinition(label: 't', shiftLabel: 'T'),
      KeyDefinition(label: 'y', shiftLabel: 'Y'),
      KeyDefinition(label: 'u', shiftLabel: 'U'),
      KeyDefinition(label: 'i', shiftLabel: 'I'),
      KeyDefinition(label: 'o', shiftLabel: 'O'),
      KeyDefinition(label: 'p', shiftLabel: 'P'),
    ],
    // Row 2: A-L
    [
      KeyDefinition(label: 'a', shiftLabel: 'A'),
      KeyDefinition(label: 's', shiftLabel: 'S'),
      KeyDefinition(label: 'd', shiftLabel: 'D'),
      KeyDefinition(label: 'f', shiftLabel: 'F'),
      KeyDefinition(label: 'g', shiftLabel: 'G'),
      KeyDefinition(label: 'h', shiftLabel: 'H'),
      KeyDefinition(label: 'j', shiftLabel: 'J'),
      KeyDefinition(label: 'k', shiftLabel: 'K'),
      KeyDefinition(label: 'l', shiftLabel: 'L'),
    ],
    // Row 3: Shift + Z-M + Backspace + Del
    [
      KeyDefinition(
          label: '⇧',
          virtualKeyCode: 0x2A,
          type: KeyType.modifier,
          size: KeySize.wide,
          action: 'shift'),
      KeyDefinition(label: 'z', shiftLabel: 'Z'),
      KeyDefinition(label: 'x', shiftLabel: 'X'),
      KeyDefinition(label: 'c', shiftLabel: 'C'),
      KeyDefinition(label: 'v', shiftLabel: 'V'),
      KeyDefinition(label: 'b', shiftLabel: 'B'),
      KeyDefinition(label: 'n', shiftLabel: 'N'),
      KeyDefinition(label: 'm', shiftLabel: 'M'),
      KeyDefinition(
          label: '⌫',
          virtualKeyCode: 0x0E,
          type: KeyType.function,
          action: 'backspace'),
    ],
    // Row 4: Bottom row
    [
      KeyDefinition(
          label: '123',
          action: 'symbols',
          type: KeyType.function,
          size: KeySize.wide),
      KeyDefinition(label: '⌨', action: 'function', type: KeyType.function),
      KeyDefinition(label: ' ', size: KeySize.extraWide, type: KeyType.space),
      KeyDefinition(
          label: 'Del',
          virtualKeyCode: 0x53,
          extended: true,
          type: KeyType.function,
          action: 'del_remote'),
      KeyDefinition(
          label: '⏎',
          virtualKeyCode: 0x1C,
          type: KeyType.function,
          action: 'enter'),
    ],
  ];

  static const List<List<KeyDefinition>> symbolsLayout = [
    [
      KeyDefinition(label: '1', shiftLabel: '!'),
      KeyDefinition(label: '2', shiftLabel: '@'),
      KeyDefinition(label: '3', shiftLabel: '#'),
      KeyDefinition(label: '4', shiftLabel: '\$'),
      KeyDefinition(label: '5', shiftLabel: '%'),
      KeyDefinition(label: '6', shiftLabel: '^'),
      KeyDefinition(label: '7', shiftLabel: '&'),
      KeyDefinition(label: '8', shiftLabel: '*'),
      KeyDefinition(label: '9', shiftLabel: '('),
      KeyDefinition(label: '0', shiftLabel: ')'),
    ],
    [
      KeyDefinition(label: '-', shiftLabel: '_'),
      KeyDefinition(label: '=', shiftLabel: '+'),
      KeyDefinition(label: '[', shiftLabel: '{'),
      KeyDefinition(label: ']', shiftLabel: '}'),
      KeyDefinition(label: '\\', shiftLabel: '|'),
      KeyDefinition(label: ';', shiftLabel: ':'),
      KeyDefinition(label: "'", shiftLabel: '"'),
      KeyDefinition(label: ',', shiftLabel: '<'),
      KeyDefinition(label: '.', shiftLabel: '>'),
      KeyDefinition(label: '/', shiftLabel: '?'),
    ],
    [
      KeyDefinition(
          label: '⇧',
          virtualKeyCode: 0x2A,
          type: KeyType.modifier,
          size: KeySize.wide,
          action: 'shift'),
      KeyDefinition(label: '`', shiftLabel: '~'),
      KeyDefinition(label: 'Tab', virtualKeyCode: 0x0F, type: KeyType.function),
      KeyDefinition(label: 'Esc', virtualKeyCode: 0x01, type: KeyType.function),
      KeyDefinition(
          label: '⌫',
          virtualKeyCode: 0x0E,
          type: KeyType.function,
          action: 'backspace'),
    ],
    [
      KeyDefinition(
          label: 'ABC',
          action: 'english',
          type: KeyType.function,
          size: KeySize.wide),
      KeyDefinition(label: '⌨', action: 'function', type: KeyType.function),
      KeyDefinition(label: ' ', size: KeySize.extraWide, type: KeyType.space),
      KeyDefinition(
          label: 'Del',
          virtualKeyCode: 0x53,
          extended: true,
          type: KeyType.function,
          action: 'del_remote'),
      KeyDefinition(
          label: '⏎',
          virtualKeyCode: 0x1C,
          type: KeyType.function,
          action: 'enter'),
    ],
  ];

  static KeyDefinition _rdpKey(
    String catalogLabel, {
    String? label,
    String? action,
    KeyType type = KeyType.function,
    KeySize size = KeySize.normal,
  }) {
    final key = RdpKeyTestCatalog.byLabel(catalogLabel);
    return KeyDefinition(
      label: label ?? key.label,
      virtualKeyCode: key.scanCode,
      extended: key.extended,
      type: type,
      size: size,
      action: action,
    );
  }

  static List<List<KeyDefinition>> get functionLayout => [
        [
          _rdpKey('LCtrl',
              label: 'Ctrl',
              action: 'modifier_ctrl',
              type: KeyType.modifier,
              size: KeySize.wide),
          _rdpKey('LAlt',
              label: 'Alt', action: 'modifier_alt', type: KeyType.modifier),
          _rdpKey('LWin',
              label: 'Win', action: 'modifier_win', type: KeyType.modifier),
          _rdpKey('Esc'),
          _rdpKey('Tab'),
        ],
        [
          _rdpKey('Left', label: '←', size: KeySize.wide),
          _rdpKey('Up', label: '↑'),
          _rdpKey('Down', label: '↓'),
          _rdpKey('Right', label: '→', size: KeySize.wide),
        ],
        [
          _rdpKey('Home'),
          _rdpKey('End'),
          _rdpKey('PgUp'),
          _rdpKey('PgDn'),
          _rdpKey('Insert', label: 'Ins'),
          _rdpKey('Delete', label: 'Del'),
        ],
        [
          for (final key in RdpKeyTestCatalog.functionKeys.take(6))
            _rdpKey(key.label),
        ],
        [
          for (final key in RdpKeyTestCatalog.functionKeys.skip(6))
            _rdpKey(key.label),
        ],
      ];

  static List<List<KeyDefinition>> getLayout(KeyboardPage page) {
    if (page == KeyboardPage.english) return englishLayout;
    if (page == KeyboardPage.symbols) return symbolsLayout;
    if (page == KeyboardPage.function) return functionLayout;
    return englishLayout;
  }
}
