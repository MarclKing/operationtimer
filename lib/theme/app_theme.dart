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
  final Color textOnSurface;

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

  double get glassBlur => 16.0;
  Color get glassBorder => isLight
      ? Colors.white.withValues(alpha: 0.55)
      : Colors.white.withValues(alpha: 0.14);
  Color get glassShadow => Colors.black.withValues(alpha: isLight ? 0.08 : 0.30);
  Color get glassHighlight => Colors.white.withValues(alpha: isLight ? 0.60 : 0.10);
  double get glassOpacity => isLight ? 0.82 : 0.55;
}

// ─────────────────────────────────────────────────────────────────────────────
// SKIN: Shield → Markenblau (Standard), basierend auf dem App-Icon
// ─────────────────────────────────────────────────────────────────────────────

const AppSkin skinShield = AppSkin(
  key: 'shield',
  displayName: 'Shield',

  bgBase:  Color(0xFF0A0B0F),
  bgCard:  Color(0xFF14161D),
  bgSheet: Color(0xFF14161D),
  bgInput: Color(0xFF0A0B0F),

  primary:     Color(0xFF2D6CFF),
  secondary:   Color(0xFF1746B8),

  kommenColor: Color(0xFF2D6CFF),
  gehenColor:  Color(0xFF7A8699),

  textPrimary:   Colors.white,
  textMuted:     Color(0xFF7E8696),
  textHint:      Color(0xFF4B5263),
  textOnSurface: Colors.white,

  borderSubtle: Color(0x14FFFFFF),
  borderMedium: Color(0x1FFFFFFF),

  gradientColors: [Color(0xFF2D6CFF), Color(0xFF1746B8)],

  navActiveColor: Color(0xFF2D6CFF),
  statEntries:    Color(0xFF2D6CFF),
  statComplete:   Color(0xFF3DD68C),
  statOpen:       Color(0xFF7A8699),
  deleteColor:    Color(0xFFEF5B5B),
  editColor:      Color(0xFF2D6CFF),
);

// ─────────────────────────────────────────────────────────────────────────────
// SKIN: Chrome → Mono Precision
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
  textOnSurface: Colors.black,

  borderSubtle: Color(0x12FFFFFF),
  borderMedium: Color(0x1FFFFFFF),

  gradientColors: [Color(0xFF333333), Color(0xFF555555)],

  navActiveColor: Colors.white,
  statEntries:    Colors.white,
  statComplete:   Color(0xFFCCCCCC),
  statOpen:       Color(0xFF888888),
  deleteColor:    Color(0xFFFF6B6B),
  editColor:      Colors.white,
);

// ─────────────────────────────────────────────────────────────────────────────
// SKIN: Crystal → Markenblau, hell (helle Schwester von Shield)
// ─────────────────────────────────────────────────────────────────────────────

const AppSkin skinCrystal = AppSkin(
  key: 'crystal',
  displayName: 'Crystal',
  isLight: true,

  bgBase:  Color(0xFFF0F2F7),
  bgCard:  Color(0xFFFFFFFF),
  bgSheet: Color(0xFFFFFFFF),
  bgInput: Color(0xFFF4F6FA),

  primary:     Color(0xFF2D6CFF),
  secondary:   Color(0xFF1746B8),

  kommenColor: Color(0xFF2D6CFF),
  gehenColor:  Color(0xFF6B7686),

  textPrimary:   Color(0xFF12141C),
  textMuted:     Color(0xFF6B7280),
  textHint:      Color(0xFFA6ACB9),
  textOnSurface: Color(0xFF12141C),

  borderSubtle: Color(0x14000000),
  borderMedium: Color(0x22000000),

  gradientColors: [Color(0xFF2D6CFF), Color(0xFF1746B8)],

  navActiveColor: Color(0xFF2D6CFF),
  statEntries:    Color(0xFF2D6CFF),
  statComplete:   Color(0xFF1E9E5A),
  statOpen:       Color(0xFF6B7686),
  deleteColor:    Color(0xFFD32F2F),
  editColor:      Color(0xFF2D6CFF),
);

// ─── SKIN: Arctic Titanium → Neutral · Präzise · Modern ──────────────────────
const AppSkin skinTitanium = AppSkin(
  key: 'titanium',
  displayName: 'Arctic Titanium',
  isLight: true,

  bgBase:  Color(0xFFEBEAED),
  bgCard:  Color(0xFFFFFFFF),
  bgSheet: Color(0xFFFFFFFF),
  bgInput: Color(0xFFF4F3F5),

  primary:   Color(0xFF4A5563),
  secondary: Color(0xFF6D7ADF),

  kommenColor: Color(0xFF4A5563),
  gehenColor:  Color(0xFF6D7ADF),

  textPrimary:   Color(0xFF1A1A2E),
  textMuted:     Color(0xFF6B7080),
  textHint:      Color(0xFFAAADB8),
  textOnSurface: Color(0xFF1A1A2E),

  borderSubtle: Color(0x18000000),
  borderMedium: Color(0x28000000),

  gradientColors: [Color(0xFF4A5563), Color(0xFF6D7ADF)],

  navActiveColor: Color(0xFF4A5563),
  statEntries:    Color(0xFF4A5563),
  statComplete:   Color(0xFF2E7D32),
  statOpen:       Color(0xFF6B7080),
  deleteColor:    Color(0xFFD32F2F),
  editColor:      Color(0xFF4A5563),
);

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  static const String hiveKey = 'skin';

  static AppSkin fromKey(String key) {
    switch (key) {
      case 'chrome':   return skinChrome;
      case 'crystal':  return skinCrystal;
      case 'titanium': return skinTitanium;
      default:         return skinShield; // Shield ist Standard
    }
  }

  static AppSkin of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SkinInheritedWidget>()
            ?.skin ??
        skinShield; // Shield ist Standard
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