import 'package:flutter/material.dart';

enum AccentTheme {
  streamBlue('Stream Blue', 'Clean IPTV blue', Color(0xFF3B82F6), Icons.check),
  cinemaRed('Cinema Red', 'Bold streaming red', Color(0xFFE50914), Icons.movie),
  primeGold('Prime Gold', 'Warm premium gold', Color(0xFFF59E0B), Icons.workspace_premium),
  neonPurple('Neon Purple', 'Arcade streaming', Color(0xFF8B5CF6), Icons.auto_awesome),
  cinemaPink('Cinema Pink', 'Modern poster pink', Color(0xFFEC4899), Icons.theater_comedy),
  emerald('Emerald', 'Fresh sports green', Color(0xFF10B981), Icons.play_circle);

  const AccentTheme(this.label, this.subtitle, this.color, this.icon);
  final String label, subtitle;
  final Color color;
  final IconData icon;
  static AccentTheme fromName(String? n) => values.firstWhere((t) => t.name == n, orElse: () => streamBlue);
}

const bgDeep = Color(0xFF030712);
const bgBase = Color(0xFF0B0F19);
const cardColor = Color(0xFF14171D);
const cardBorder = Color(0xFF22262E);
const pillColor = Color(0xFF1E2128);
const glass = Color(0x14FFFFFF);
const glassBorder = Color(0x1FFFFFFF);

ThemeData buildTheme(AccentTheme a) {
  final scheme = ColorScheme.fromSeed(seedColor: a.color, brightness: Brightness.dark, surface: bgBase)
      .copyWith(primary: a.color);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bgBase,
    canvasColor: bgBase,
    appBarTheme: const AppBarTheme(backgroundColor: bgBase, elevation: 0),
    focusColor: a.color.withValues(alpha: 0.35),
    popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1B1E25), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
  );
}