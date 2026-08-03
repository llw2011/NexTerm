import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/i18n/app_localizations.dart';
import 'package:nexterm/providers/app_settings_provider.dart';
import 'package:nexterm/screens/startup/startup_update_gate.dart';
import 'package:nexterm/utils/ota_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _release = ReleaseInfo(
  version: '9.9.9',
  downloadUrl: 'https://example.com/app-release.apk',
  releaseNotes: 'Test release',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('check failure remains skippable when updates are required',
      (tester) async {
    final settings = await _settings(force: true);
    var checkCalls = 0;

    await tester.pumpWidget(
      _testApp(
        settings: settings,
        checkUpdate: () async {
          checkCalls++;
          throw const OtaException('check failed');
        },
        downloadAndInstall: (_, {onProgress}) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update check failed'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(checkCalls, 2);
  });

  testWidgets('required download failure cannot skip and retries download',
      (tester) async {
    final settings = await _settings(force: true);
    var checkCalls = 0;
    var installCalls = 0;

    await tester.pumpWidget(
      _testApp(
        settings: settings,
        checkUpdate: () async {
          checkCalls++;
          return _release;
        },
        downloadAndInstall: (_, {onProgress}) async {
          installCalls++;
          throw const OtaException('download failed');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(find.text('Update download failed'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(checkCalls, 1);
    expect(installCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(checkCalls, 1);
    expect(installCalls, 2);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('optional download failure can continue into the app',
      (tester) async {
    final settings = await _settings(force: false);

    await tester.pumpWidget(
      _testApp(
        settings: settings,
        checkUpdate: () async => _release,
        downloadAndInstall: (_, {onProgress}) async {
          throw const OtaException('download failed');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();

    expect(find.text('Update download failed'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('App ready'), findsOneWidget);
  });
}

Future<AppSettingsProvider> _settings({required bool force}) async {
  final settings = AppSettingsProvider();
  await settings.load();
  await settings.setForceStartupUpdate(force);
  return settings;
}

Widget _testApp({
  required AppSettingsProvider settings,
  required StartupUpdateChecker checkUpdate,
  required StartupUpdateInstaller downloadAndInstall,
}) {
  return ChangeNotifierProvider.value(
    value: settings,
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
      home: StartupUpdateGate(
        checkUpdate: checkUpdate,
        downloadAndInstall: downloadAndInstall,
        child: const Text('App ready'),
      ),
    ),
  );
}
