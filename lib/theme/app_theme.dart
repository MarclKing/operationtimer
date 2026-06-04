import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppSkin – alle Farben & Werte eines Skins an einem Ort
// ─────────────────────────────────────────────────────────────────────────────

class AppSkin {
  final String key;
  final String displayName;

  // Backgrounds
  final Color bgBase;       // z.B. Scaffold-Hintergrund
  final Color bgCard;       // Kacheln / Cards
  final Color bgSheet;      // Bottom Sheets & Dialoge
  final Color bgInput;      // Eingabefelder

  // Akzente
  final Color primary;      // Haupt-Akzent (Button, Labels, Aktiv-Farbe)
  final Color secondary;    // Zweiter Akzent (Gradient-Ende oder Teal)
  final Color kommenColor;  // Kommen-Zeit-Karte
  final Color gehenColor;   // Gehen-Zeit-Karte

  // Texte
  final Color textPrimary;
  final Color textMuted;
  final Color textHint;

  // Borders
  final Color borderSubtle;
  final Color borderMedium;

  // Gradient – wird als LinearGradient gebaut
  final List<Color> gradientColors;

  // Sonderfälle
  final Color navActiveColor;   // aktive Tab-Farbe
  final Color statEntries;      // Stat-Karte "Einträge"
  final Color statComplete;     // Stat-Karte "Vollständig"
  final Color statOpen;         // Stat-Karte "Offen"
  final Color deleteColor;      // Lösch-Aktion
  final Color editColor;        // Bearbeiten-Aktion

  const AppSkin({
    required this.key,
    required this.displayName,
    required this.bgBase,
    required this.bgCard,
    required this.bgSheet,
    required this.bgInput,
    required this.primary,
    required this.secondary,
    required this.kommenColor,
    required this.gehenColor,
    required this.textPrimary,
    required this.textMuted,
    required this.textHint,
    required this.borderSubtle,
    required this.borderMedium,
    required this.gradientColors,
    required this.navActiveColor,
    required this.statEntries,
    required this.statComplete,
    required this.statOpen,
    required this.deleteColor,
    required this.editColor,
  });

  LinearGradient get gradient => LinearGradient(colors: gradientColors);

  // Hilfsmethoden für häufige Alpha-Varianten
  Color primaryWithAlpha(double a) => primary.withValues(alpha: a);
  Color secondaryWithAlpha(double a) => secondary.withValues(alpha: a);
  Color kommenWithAlpha(double a) => kommenColor.withValues(alpha: a);
  Color gehenWithAlpha(double a) => gehenColor.withValues(alpha: a);
  Color deleteWithAlpha(double a) => deleteColor.withValues(alpha: a);
  Color white(double a) => Colors.white.withValues(alpha: a);
}

// ─────────────────────────────────────────────────────────────────────────────
// SKIN: Chrome (Standard)
// ─────────────────────────────────────────────────────────────────────────────

const AppSkin skinChrome = AppSkin(
  key: 'chrome',
  displayName: 'Chrome',

  bgBase:   Color(0xFF0A0A0F),
  bgCard:   Color(0xFF141420),
  bgSheet:  Color(0xFF141420),
  bgInput:  Color(0xFF0A0A0F),

  primary:      Color(0xFF6C63FF),
  secondary:    Color(0xFF4ECDC4),
  kommenColor:  Color(0xFF4ECDC4),
  gehenColor:   Color(0xFFFF6B6B),

  textPrimary:  Colors.white,
  textMuted:    Color(0xFF555570),
  textHint:     Color(0xFF555570),

  borderSubtle: Color(0x14FFFFFF),   // white ~8 %
  borderMedium: Color(0x1AFFFFFF),   // white ~10 %

  gradientColors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],

  navActiveColor: Color(0xFF6C63FF),
  statEntries:    Color(0xFF6C63FF),
  statComplete:   Color(0xFF4ECDC4),
  statOpen:       Color(0xFFFF6B6B),
  deleteColor:    Color(0xFFFF6B6B),
  editColor:      Color(0xFF6C63FF),
);

// ─────────────────────────────────────────────────────────────────────────────
// SKIN: Space (Arctic Glass)
// ─────────────────────────────────────────────────────────────────────────────

const AppSkin skinSpace = AppSkin(
  key: 'space',
  displayName: 'Space',

  bgBase:   Color(0xFF080812),
  bgCard:   Color(0xFF0F0F1A),
  bgSheet:  Color(0xFF0F0F1A),
  bgInput:  Color(0xFF080812),

  primary:      Colors.white,          // Haupt-Akzent = Weiß
  secondary:    Color(0xFF3DD6C8),     // Teal nur für Kommen
  kommenColor:  Color(0xFF3DD6C8),
  gehenColor:   Color(0xFFFF6B8A),     // Rosé statt knallrot

  textPrimary:  Colors.white,
  textMuted:    Color(0xFF3A3A55),
  textHint:     Color(0xFF3A3A55),

  borderSubtle: Color(0x0FFFFFFF),     // white ~6 %
  borderMedium: Color(0x1AFFFFFF),     // white ~10 %

  gradientColors: [Colors.white, Color(0xFFD0D0FF)],  // fast weiß

  navActiveColor: Colors.white,
  statEntries:    Colors.white,
  statComplete:   Color(0xFF3DD6C8),
  statOpen:       Color(0xFFFF6B8A),
  deleteColor:    Color(0xFFFF6B8A),
  editColor:      Colors.white,
);

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme – globaler Zugriff & Hive-Key
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  static const String hiveKey = 'skin';

  static AppSkin fromKey(String key) {
    return key == 'space' ? skinSpace : skinChrome;
  }

  static AppSkin of(BuildContext context) {
    final skin = context
        .dependOnInheritedWidgetOfExactType<_SkinInheritedWidget>()
        ?.skin;
    return skin ?? skinChrome;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// InheritedWidget – stellt den Skin dem Widget-Tree zur Verfügung
// ─────────────────────────────────────────────────────────────────────────────

class SkinProvider extends StatelessWidget {
  final AppSkin skin;
  final Widget child;

  const SkinProvider({super.key, required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    return _SkinInheritedWidget(skin: skin, child: child);
  }
}

class _SkinInheritedWidget extends InheritedWidget {
  final AppSkin skin;

  const _SkinInheritedWidget({required this.skin, required super.child});

  @override
  bool updateShouldNotify(_SkinInheritedWidget old) => old.skin.key != skin.key;
}