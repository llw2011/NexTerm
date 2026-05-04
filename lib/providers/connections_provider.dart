import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection.dart';
import '../utils/secure_storage.dart';

const _kPrefKey = 'connections';

class ConnectionsProvider extends ChangeNotifier {
  List<Connection> _list = [];
  List<Connection> get list => List.unmodifiable(_list);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefKey);
    if (raw != null) _list = Connection.listFromJson(raw);
    notifyListeners();
  }

  Future<void> add(Connection c) async {
    _list.add(c);
    await _save();
    notifyListeners();
  }

  Future<void> update(Connection c) async {
    final i = _list.indexWhere((e) => e.id == c.id);
    if (i >= 0) _list[i] = c;
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _list.removeWhere((e) => e.id == id);
    await deletePassword(id);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, Connection.listToJson(_list));
  }
}
