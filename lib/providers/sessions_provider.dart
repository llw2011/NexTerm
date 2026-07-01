import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/connection.dart';

class SessionTab {
  final String id;
  final Connection connection;
  final DateTime openedAt;
  SessionTab({required this.id, required this.connection, required this.openedAt});
}

class SessionsProvider extends ChangeNotifier {
  final List<SessionTab> _tabs = [];
  String? _activeTabId;

  List<SessionTab> get tabs => List.unmodifiable(_tabs);
  String? get activeTabId => _activeTabId;
  SessionTab? get activeTab => _tabs.where((t) => t.id == _activeTabId).firstOrNull;

  void openSession(Connection connection) {
    final tab = SessionTab(id: const Uuid().v4(), connection: connection, openedAt: DateTime.now());
    _tabs.add(tab);
    _activeTabId = tab.id;
    notifyListeners();
  }

  void closeSession(String id) {
    _tabs.removeWhere((t) => t.id == id);
    if (_activeTabId == id) {
      _activeTabId = _tabs.lastOrNull?.id;
    }
    notifyListeners();
  }

  void setActive(String id) {
    if (_activeTabId != id && _tabs.any((t) => t.id == id)) {
      _activeTabId = id;
      notifyListeners();
    }
  }
}
