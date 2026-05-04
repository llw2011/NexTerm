import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NexTermApp());
    expect(find.text('NexTerm'), findsOneWidget);
  });
}
