import 'package:flutter/material.dart';
import '../../models/connection.dart';

class SshScreen extends StatelessWidget {
  final Connection connection;
  const SshScreen({super.key, required this.connection});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(connection.name),
          actions: [
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ],
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terminal, size: 64, color: Colors.white24),
              SizedBox(height: 16),
              Text('SSH terminal — coming soon',
                  style: TextStyle(color: Colors.white38)),
            ],
          ),
        ),
      );
}
