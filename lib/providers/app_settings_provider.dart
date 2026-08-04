import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsProvider extends ChangeNotifier {
  static const _languageKey = 'app_language_code';
  static const _forceStartupUpdateKey = 'force_startup_update';
  static const defaultLanguageCode = 'en';

  String _languageCode = defaultLanguageCode;
  bool _forceStartupUpdate = false;

  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);
  bool get forceStartupUpdate => _forceStartupUpdate;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_languageKey);
    _languageCode = _normalize(saved);
    _forceStartupUpdate = prefs.getBool(_forceStartupUpdateKey) ?? false;
  }

  Future<void> setLanguage(String code) async {
    final next = _normalize(code);
    if (next == _languageCode) return;
    _languageCode = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, next);
  }

  Future<void> setForceStartupUpdate(bool value) async {
    if (value == _forceStartupUpdate) return;
    _forceStartupUpdate = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_forceStartupUpdateKey, value);
  }

  String _normalize(String? code) => code == 'zh' ? 'zh' : defaultLanguageCode;
}
