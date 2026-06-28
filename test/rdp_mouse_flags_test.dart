import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/rdp_service.dart';

void main() {
  test('RDP mouse wheel flags match FreeRDP pointer flags', () {
    expect(MouseFlags.wheelUp, 0x0200);
    expect(MouseFlags.wheelDown, 0x0200 | 0x0100);
  });
}
