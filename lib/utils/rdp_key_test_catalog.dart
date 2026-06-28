class RdpKeyTestDefinition {
  final String label;
  final int scanCode;
  final bool extended;
  final String group;

  const RdpKeyTestDefinition({
    required this.label,
    required this.scanCode,
    required this.group,
    this.extended = false,
  });

  String get scanHex => '0x${scanCode.toRadixString(16).padLeft(2, '0')}';
}

class RdpKeyTestCatalog {
  static RdpKeyTestDefinition byLabel(String label) {
    return all.firstWhere(
      (key) => key.label == label,
      orElse: () => throw ArgumentError.value(label, 'label'),
    );
  }

  static bool containsScanPair(int scanCode, bool extended) {
    return all.any(
      (key) => key.scanCode == scanCode && key.extended == extended,
    );
  }

  static const navigation = [
    RdpKeyTestDefinition(
      label: 'Left',
      scanCode: 0x4B,
      extended: true,
      group: 'Nav',
    ),
    RdpKeyTestDefinition(
      label: 'Up',
      scanCode: 0x48,
      extended: true,
      group: 'Nav',
    ),
    RdpKeyTestDefinition(
      label: 'Down',
      scanCode: 0x50,
      extended: true,
      group: 'Nav',
    ),
    RdpKeyTestDefinition(
      label: 'Right',
      scanCode: 0x4D,
      extended: true,
      group: 'Nav',
    ),
    RdpKeyTestDefinition(
      label: 'Home',
      scanCode: 0x47,
      extended: true,
      group: 'Nav',
    ),
    RdpKeyTestDefinition(
      label: 'End',
      scanCode: 0x4F,
      extended: true,
      group: 'Nav',
    ),
    RdpKeyTestDefinition(
      label: 'PgUp',
      scanCode: 0x49,
      extended: true,
      group: 'Nav',
    ),
    RdpKeyTestDefinition(
      label: 'PgDn',
      scanCode: 0x51,
      extended: true,
      group: 'Nav',
    ),
  ];

  static const editing = [
    RdpKeyTestDefinition(label: 'Esc', scanCode: 0x01, group: 'Edit'),
    RdpKeyTestDefinition(label: 'Tab', scanCode: 0x0F, group: 'Edit'),
    RdpKeyTestDefinition(label: 'Back', scanCode: 0x0E, group: 'Edit'),
    RdpKeyTestDefinition(label: 'Enter', scanCode: 0x1C, group: 'Edit'),
    RdpKeyTestDefinition(
      label: 'Insert',
      scanCode: 0x52,
      extended: true,
      group: 'Edit',
    ),
    RdpKeyTestDefinition(
      label: 'Delete',
      scanCode: 0x53,
      extended: true,
      group: 'Edit',
    ),
  ];

  static const modifiers = [
    RdpKeyTestDefinition(label: 'LShift', scanCode: 0x2A, group: 'Mods'),
    RdpKeyTestDefinition(label: 'LCtrl', scanCode: 0x1D, group: 'Mods'),
    RdpKeyTestDefinition(label: 'LAlt', scanCode: 0x38, group: 'Mods'),
    RdpKeyTestDefinition(
      label: 'RCtrl',
      scanCode: 0x1D,
      extended: true,
      group: 'Mods',
    ),
    RdpKeyTestDefinition(
      label: 'RAlt',
      scanCode: 0x38,
      extended: true,
      group: 'Mods',
    ),
    RdpKeyTestDefinition(
      label: 'LWin',
      scanCode: 0x5B,
      extended: true,
      group: 'Mods',
    ),
    RdpKeyTestDefinition(
      label: 'RWin',
      scanCode: 0x5C,
      extended: true,
      group: 'Mods',
    ),
  ];

  static const functionKeys = [
    RdpKeyTestDefinition(label: 'F1', scanCode: 0x3B, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F2', scanCode: 0x3C, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F3', scanCode: 0x3D, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F4', scanCode: 0x3E, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F5', scanCode: 0x3F, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F6', scanCode: 0x40, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F7', scanCode: 0x41, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F8', scanCode: 0x42, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F9', scanCode: 0x43, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F10', scanCode: 0x44, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F11', scanCode: 0x57, group: 'Fn'),
    RdpKeyTestDefinition(label: 'F12', scanCode: 0x58, group: 'Fn'),
  ];

  static const all = [
    ...navigation,
    ...editing,
    ...modifiers,
    ...functionKeys,
  ];
}
