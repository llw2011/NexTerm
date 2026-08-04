import 'dart:io';
import 'package:go_router/go_router.dart';
import '../models/connection.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/edit_connection_screen.dart';
import '../screens/rdp/rdp_screen.dart';
import '../screens/rdp/rdp_screen_windows.dart';
import '../screens/ssh/ssh_screen.dart';
import '../screens/settings/settings_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/connection/new/:type',
      builder: (ctx, state) {
        final type = state.pathParameters['type'] == 'rdp'
            ? ConnectionType.rdp
            : ConnectionType.ssh;
        return EditConnectionScreen(type: type);
      },
    ),
    GoRoute(
      path: '/connection/edit',
      builder: (ctx, state) {
        final conn = state.extra as Connection;
        return EditConnectionScreen(existing: conn, type: conn.type);
      },
    ),
    GoRoute(
      path: '/rdp',
      builder: (ctx, state) => Platform.isWindows
          ? RdpScreenWindows(connection: state.extra as Connection)
          : RdpScreen(connection: state.extra as Connection),
    ),
    GoRoute(
      path: '/ssh',
      builder: (ctx, state) => SshScreen(connection: state.extra as Connection),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
  ],
);
