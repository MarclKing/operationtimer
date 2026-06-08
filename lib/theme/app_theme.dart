import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppSkin
// ─────────────────────────────────────────────────────────────────────────────

class AppSkin {
  final String key;
  final String displayName;

  final Color bgBase;
  final Color bgCard;
  final Color bgSheet;
  final Color bgInput;

  final Color primary;
  final Color secondary;
  final Color kommenColor;
  final Color gehenColor;

  final Color textPrimary;
  final Color textMuted;
  final Color textHint;
  final Color textOnSurface; // 🔥 NEU: Textfarbe auf hellen Oberflächen

  final Color borderSubtle;
  final Color borderMedium;

  final List<Color> gradientColors;

  final Color navActiveColor;
  final Color statEntries;
  final Color statComplete;
  final Color statOpen;
  final Color deleteColor;
  final Color editColor;

  final bool isLight;

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
    required this.textOnSurface,
    required this.borderSubtle,
    required this.borderMedium,
    required this.gradientColors,
    required this.navActiveColor,
    required this.statEntries,
    required this.statComplete,
    required this.statOpen,
    required this.deleteColor,
    required this.editColor,
    this.isLight = false,
  });

  LinearGradient get gradient => LinearGradient(colors: gradientColors);

  Color get onGradient => isLight ? Colors.black : Colors.white;

  Color primaryWithAlpha(double a) => primary.withValues(alpha: a);
  Color secondaryWithAlpha(double a) => secondary.withValues(alpha: a);
  Color kommenWithAlpha(double a) => kommenColor.withValues(alpha: a);
  Color gehenWithAlpha(double a) => gehenColor.withValues(alpha: a);
  Color deleteWithAlpha(double a) => deleteColor.withValues(alpha: a);
  Color white(double a) => Colors.white.withValues(alpha: a);
  
  Color surface(double a) => isLight
      ? Colors.black.withValues(alpha: a)
      : Colors.white.withValues(alpha: a);
}

// ─────────────────────────────────────────────────────────────────────────────
// SKIN: Chrome → Mono Precision (Standard)
// 🔥 Dunkle Karten, aber helle Akzente mit dunkler Schrift auf Buttons
// ─────────────────────────────────────────────────────────────────────────────

const AppSkin skinChrome = AppSkin(
  key: 'chrome',
  displayName: 'Chrome',

  bgBase:  Color(0xFF0A0A0A),
  bgCard:  Color(0xFF1A1A1A),
  bgSheet: Color(0xFF1A1A1A),
  bgInput: Color(0xFF0A0A0A),

  primary:     Colors.white,
  secondary:   Color(0xFFAAAAAA),

  kommenColor: Color(0xFFE0E0E0),
  gehenColor:  Color(0xFF888888),

  textPrimary:   Colors.white,
  textMuted:     Color(0xFF888888),
  textHint:      Color(0xFF555555),
  textOnSurface: Colors.black, // 🔥 Für Buttons & ausgewählte Elemente

  borderSubtle: Color(0x12FFFFFF),
  borderMedium: Color(0x1FFFFFFF),

  gradientColors: [Color(0xFF333333), Color(0xFF555555)], // 🔥 Dunklerer Gradient für besseren Kontrast

  navActiveColor: Colors.white,
  statEntries:    Colors.white,
  statComplete:   Color(0xFFCCCCCC),
  statOpen:       Color(0xFF888888),
  deleteColor:    Color(0xFFFF6B6B),
  editColor:      Colors.white,
);

// ─────────────────────────────────────────────────────────────────────────────
// SKIN: Space → Lila + Teal
// ─────────────────────────────────────────────────────────────────────────────

const AppSkin skinSpace = AppSkin(
  key: 'space',
  displayName: 'Space',

  bgBase:  Color(0xFF0A0A0F),
  bgCard:  Color(0xFF141420),
  bgSheet: Color(0xFF141420),
  bgInput: Color(0xFF0A0A0F),

  primary:     Color(0xFF6C63FF),
  secondary:   Color(0xFF4ECDC4),
  kommenColor: Color(0xFF4ECDC4),
  gehenColor:  Color(0xFFFF6B6B),

  textPrimary:   Colors.white,
  textMuted:     Color(0xFF555570),
  textHint:      Color(0xFF555570),
  textOnSurface: Colors.white, // 🔥 Space: weiße Schrift auf hellen Flächen

  borderSubtle: Color(0x14FFFFFF),
  borderMedium: Color(0x1AFFFFFF),

  gradientColors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],

  navActiveColor: Color(0xFF6C63FF),
  statEntries:    Color(0xFF6C63FF),
  statComplete:   Color(0xFF4ECDC4),
  statOpen:       Color(0xFFFF6B6B),
  deleteColor:    Color(0xFFFF6B6B),
  editColor:      Color(0xFF6C63FF),
);

// ─── SKIN: Paper → Warmes Licht ───────────────────────────────────────────
const AppSkin skinPaper = AppSkin(
  key: 'paper',
  displayName: 'Paper',
  isLight: true,   // ← wichtig! steuert onGradient und surface()

  bgBase:  Color(0xFFF5F0E8),
  bgCard:  Color(0xFFEDE8DC),
  bgSheet: Color(0xFFEDE8DC),
  bgInput: Color(0xFFE8E2D4),

  primary:     Color(0xFFB45309),   // Bernstein-Braun
  secondary:   Color(0xFF78716C),   // Warm-Grau

  kommenColor: Color(0xFFB45309),   // gleicher Bernstein
  gehenColor:  Color(0xFF78716C),   // Grau für Gehen

  textPrimary:   Color(0xFF2C2417),  // Sehr dunkles Braun
  textMuted:     Color(0xFF78716C),
  textHint:      Color(0xFFA8937A),
  textOnSurface: Color(0xFF2C2417), // Dunkle Schrift auf hellen Flächen

  borderSubtle: Color(0x22000000),   // Dezentes Schwarz-Alpha
  borderMedium: Color(0x33000000),

  gradientColors: [Color(0xFFB45309), Color(0xFF92400E)],

  navActiveColor: Color(0xFFB45309),
  statEntries:    Color(0xFFB45309),
  statComplete:   Color(0xFF15803D),  // Grün für "vollständig"
  statOpen:       Color(0xFF78716C),
  deleteColor:    Color(0xFFDC2626),
  editColor:      Color(0xFFB45309),
);


// ─────────────────────────────────────────────────────────────────────────────
// AppTheme
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  static const String hiveKey = 'skin';

  static AppSkin fromKey(String key) {
  switch (key) {
    case 'space': return skinSpace;
    case 'paper': return skinPaper;   // ← neu
    default:      return skinChrome;
  }
}

  static AppSkin of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SkinInheritedWidget>()
            ?.skin ??
        skinChrome;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SkinProvider / InheritedWidget
// ─────────────────────────────────────────────────────────────────────────────

class SkinProvider extends StatelessWidget {
  final AppSkin skin;
  final Widget child;
  const SkinProvider({super.key, required this.skin, required this.child});

  @override
  Widget build(BuildContext context) =>
      _SkinInheritedWidget(skin: skin, child: child);
}

class _SkinInheritedWidget extends InheritedWidget {
  final AppSkin skin;
  const _SkinInheritedWidget({required this.skin, required super.child});

  @override
  bool updateShouldNotify(_SkinInheritedWidget old) =>
      old.skin.key != skin.key;
}