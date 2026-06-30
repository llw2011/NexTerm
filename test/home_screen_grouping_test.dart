import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/i18n/app_localizations.dart';
import 'package:nexterm/models/connection.dart';
import 'package:nexterm/providers/connections_provider.dart';
import 'package:nexterm/screens/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home screen groups connections and searches by group',
      (tester) async {
    final provider = ConnectionsProvider();
    await provider.load();

    await provider.add(
      const Connection(
        id: 'alpha',
        name: 'Alpha',
        group: 'Platform',
        host: 'alpha.example.com',
        port: 22,
        username: 'root',
        type: ConnectionType.ssh,
      ),
    );
    await provider.add(
      const Connection(
        id: 'beta',
        name: 'Beta',
        group: 'Database',
        host: 'beta.example.com',
        port: 22,
        username: 'root',
        type: ConnectionType.ssh,
      ),
    );
    await provider.add(
      const Connection(
        id: 'gamma',
        name: 'Gamma',
        host: 'gamma.example.com',
        port: 3389,
        username: 'admin',
        type: ConnectionType.rdp,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData.dark(useMaterial3: true),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Platform'), findsOneWidget);
    expect(find.text('Database'), findsOneWidget);
    expect(find.text('Ungrouped'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'database');
    await tester.pumpAndSettle();

    expect(find.text('Database'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Platform'), findsNothing);
    expect(find.text('Ungrouped'), findsNothing);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Gamma'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'connection search');

    await tester.tap(find.text('Database'));
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('connection search'),
    );
  });
}
