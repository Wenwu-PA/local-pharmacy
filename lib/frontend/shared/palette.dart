import 'package:flutter/material.dart';

enum PharmacyColor {
  background,
  shade,
  card,
  glass,
  raised,
  ink,
  secondary,
  border,
  accent,
  coral,
  nav,
}

const _light = [
  Color(0xfff3e7d8),
  Color(0xffeee0cf),
  Color(0xfffff8ef),
  Color(0xfff9f1e7),
  Color(0xffe4ebd9),
  Color(0xff344539),
  Color(0xff58695b),
  Color(0xffa0af9e),
  Color(0xff6d8d75),
  Color(0xff8d5443),
  Color(0xfffff9f0),
];

const _dark = [
  Color(0xff22332b),
  Color(0xff1a2923),
  Color(0xff2d4136),
  Color(0xff384d40),
  Color(0xff3c5345),
  Color(0xfff2e7d9),
  Color(0xffb5c3b5),
  Color(0xff546d5c),
  Color(0xffb9d1b1),
  Color(0xffd9a98d),
  Color(0xff30453a),
];

const _darkButtonOutline = Color(0xff18261f);

extension PharmacyTheme on BuildContext {
  Color get buttonOutline =>
      dark ? _darkButtonOutline : color(PharmacyColor.border);
  bool get dark => Theme.of(this).brightness == Brightness.dark;
  Color color(PharmacyColor key) => (dark ? _dark : _light)[key.index];
}

ThemeData pharmacyTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? _dark : _light;
  Color color(PharmacyColor key) => colors[key.index];
  final scheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: color(PharmacyColor.accent),
    surface: color(PharmacyColor.card),
    onSurface: color(PharmacyColor.ink),
    primary: dark ? color(PharmacyColor.accent) : const Color(0xff4e6e56),
    onPrimary: dark ? _light[PharmacyColor.ink.index] : Colors.white,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color(PharmacyColor.border)),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: color(PharmacyColor.background),
    chipTheme: ChipThemeData(
      side: dark ? const BorderSide(color: _darkButtonOutline) : null,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: color(PharmacyColor.card),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
  );
}
