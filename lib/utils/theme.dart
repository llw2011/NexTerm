import 'package:flutter/material.dart';

const _primary = Color(0xFF37D6C2);
const _secondary = Color(0xFFA78BFA);
const _tertiary = Color(0xFFF4C95D);
const _bg = Color(0xFF101418);
const _surface = Color(0xFF151A20);
const _surfaceHigh = Color(0xFF1B222A);
const _border = Color(0xFF27313B);

ThemeData buildTheme() {
  final scheme = const ColorScheme.dark(
    primary: _primary,
    secondary: _secondary,
    tertiary: _tertiary,
    surface: _surface,
    surfaceContainerHighest: _surfaceHigh,
    onPrimary: Colors.black,
    onSurface: Color(0xFFE8EEF2),
    outline: _border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bg,
    colorScheme: scheme,
    cardTheme: CardTheme(
      color: _surfaceHigh,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _bg,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _primary,
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xFFB5C2CC),
      textColor: Color(0xFFE8EEF2),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        side: const WidgetStatePropertyAll(BorderSide(color: _border)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
    ),
  );
}
