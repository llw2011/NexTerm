import 'package:flutter/material.dart';

const _cyan = Color(0xFF00D4FF);
const _bg = Color(0xFF1A1A2E);
const _surface = Color(0xFF16213E);
const _card = Color(0xFF0F3460);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(
        primary: _cyan,
        secondary: Color(0xFF7B2FF7),
        surface: _surface,
        onPrimary: Colors.black,
        onSurface: Colors.white,
      ),
      cardTheme: const CardTheme(
        color: _card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _cyan,
        foregroundColor: Colors.black,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _cyan, width: 1.5),
        ),
      ),
    );
