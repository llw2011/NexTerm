import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/connection.dart';
import '../utils/secure_storage.dart';

const _kPrefKey = 'connections';

class ConnectionsProvider extends ChangeNotifier {
  List<Connection> _list = [];
  List<Connection> get list => List.unmodifiable(_sorted(_list));

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
    await deletePrivateKey(id);
    await deleteKeyPassphrase(id);
    await _save();
    notifyListeners();
  }

  Future<Connection?> markOpened(String id) async {
    final i = _list.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    final updated = _list[i].copyWith(lastOpenedAt: DateTime.now().toUtc());
    _list[i] = updated;
    await _save();
    notifyListeners();
    return updated;
  }

  Future<void> toggleFavorite(String id) async {
    final i = _list.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _list[i] = _list[i].copyWith(isFavorite: !_list[i].isFavorite);
    await _save();
    notifyListeners();
  }

  Future<Connection?> duplicate(String id, {String? name}) async {
    final index = _list.indexWhere((e) => e.id == id);
    final source = index >= 0 ? _list[index] : null;
    if (source == null) return null;

    final copyId = const Uuid().v4();
    final copy = Connection(
      id: copyId,
      name: name ?? '${source.name} Copy',
      group: source.group,
      host: source.host,
      port: source.port,
      username: source.username,
      type: source.type,
      domain: source.domain,
      width: source.width,
      height: source.height,
      rdpSecurity: source.rdpSecurity,
      sshAuthType: source.sshAuthType,
      sshJumpHostId: source.sshJumpHostId,
      sshTunnels: source.sshTunnels,
    );

    await savePassword(copyId, await loadPassword(source.id));
    final privateKey = await loadPrivateKey(source.id);
    if (privateKey != null && privateKey.isNotEmpty) {
      await savePrivateKey(copyId, privateKey);
    }
    final passphrase = await loadKeyPassphrase(source.id);
    if (passphrase != null && passphrase.isNotEmpty) {
      await saveKeyPassphrase(copyId, passphrase);
    }

    _list.add(copy);
    await _save();
    notifyListeners();
    return copy;
  }

  Future<({int added, int updated})> mergeConnections(
      List<Connection> connections) async {
    var added = 0;
    var updated = 0;
    for (final connection in connections) {
      final index = _list.indexWhere((e) => e.id == connection.id);
      if (index >= 0) {
        _list[index] = connection;
        updated++;
      } else {
        _list.add(connection);
        added++;
      }
    }
    await _save();
    notifyListeners();
    return (added: added, updated: updated);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, Connection.listToJson(_list));
  }

  static List<Connection> _sorted(List<Connection> input) {
    final sorted = [...input];
    sorted.sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      final aOpened = a.lastOpenedAt;
      final bOpened = b.lastOpenedAt;
      if (aOpened != null || bOpened != null) {
        if (aOpened == null) return 1;
        if (bOpened == null) return -1;
        final recent = bOpened.compareTo(aOpened);
        if (recent != 0) return recent;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }
}
