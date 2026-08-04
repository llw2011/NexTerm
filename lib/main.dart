import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'i18n/app_localizations.dart';
import 'providers/app_settings_provider.dart';
import 'providers/connections_provider.dart';
import 'providers/sessions_provider.dart';
import 'screens/desktop/desktop_shell.dart';
import 'screens/startup/startup_update_gate.dart';
import 'utils/router.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connectionsProvider = ConnectionsProvider();
  final settingsProvider = AppSettingsProvider();
  await Future.wait([
    connectionsProvider.load(),
    settingsProvider.load(),
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connectionsProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(create: (_) => SessionsProvider()),
      ],
      child: const NexTermApp(),
    ),
  );
}

class NexTermApp extends StatelessWidget {
  const NexTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final localizationsDelegates = [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

    if (Platform.isWindows) {
      return MaterialApp(
        title: 'NexTerm',
        theme: buildTheme(),
        locale: settings.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: localizationsDelegates,
        debugShowCheckedModeBanner: false,
        home: const DesktopShell(),
      );
    }

    return MaterialApp.router(
      title: 'NexTerm',
      theme: buildTheme(),
      routerConfig: router,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => StartupUpdateGate(
        child: child ?? const SizedBox.shrink(),
      ),
      localizationsDelegates: localizationsDelegates,
      debugShowCheckedModeBanner: false,
    );
  }
}
