import 'package:flutter/material.dart';
import '../../models/connection.dart';
import '../../providers/sessions_provider.dart';
import '../rdp/rdp_screen_windows.dart';
import '../ssh/ssh_screen.dart';

class SessionHost extends StatelessWidget {
  final SessionTab tab;
  const SessionHost({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    if (tab.connection.type == ConnectionType.rdp) {
      return RdpScreenWindows(connection: tab.connection, embedded: true);
    }
    return SshScreen(connection: tab.connection, embedded: true);
  }
}
