import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/connections_provider.dart';
import 'utils/router.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final provider = ConnectionsProvider();
  await provider.load();
  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const NexTermApp(),
    ),
  );
}

class NexTermApp extends StatelessWidget {
  const NexTermApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'NexTerm',
        theme: buildTheme(),
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      );
}
