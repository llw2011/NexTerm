import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/main.dart';
import 'package:nexterm/providers/app_settings_provider.dart';
import 'package:nexterm/providers/connections_provider.dart';
import 'package:nexterm/providers/sessions_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    final connectionsProvider = ConnectionsProvider();
    final settingsProvider = AppSettingsProvider();
    await settingsProvider.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: connectionsProvider),
          ChangeNotifierProvider.value(value: settingsProvider),
          ChangeNotifierProvider(create: (_) => SessionsProvider()),
        ],
        child: const NexTermApp(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(NexTermApp), findsOneWidget);
  });
}
