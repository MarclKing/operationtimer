import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIQUID GLASS DESIGN SYSTEM — zentrale Quelle für alle Screens
//
// Vorher war diese Extension + alle Widgets unten in 6+ Dateien dupliziert
// (home_screen.dart, fahrtenbuch_screen.dart, month_screen.dart,
//  schedule_screen.dart, pdf_service.dart, main.dart).
// Jetzt: einmal hier definiert, überall importiert.
//
// WICHTIG beim Umstellen der bestehenden Screens:
//   1. Lokale "extension _AppSkinGlass on AppSkin { ... }" entfernen
//   2. Lokale private Klassen (_GlassSheet, _SheetHandle, _GlassPrimaryButton,
//      _GlassSecondaryButton/_GlassButton, _GlassSurface, _GlassIconBadge,
//      _GlassStatCard) entfernen
//   3. import '../widgets/glass_kit.dart'; hinzufügen
//   4. Aufrufstellen anpassen: _GlassSheet → GlassSheet, _SheetHandle →
//      SheetHandle, _GlassPrimaryButton → GlassPrimaryButton, usw.
//      (einfaches Such-&-Ersetzen, da Konstruktor-Parameter identisch sind)
// ─────────────────────────────────────────────────────────────────────────────

extension AppSkinGlass on AppSkin {
  double get glassBlur => isLight ? 18.0 : 22.0;
  double get glassOpacity => isLight ? 0.62 : 0.55;
  Color get glassHighlight =>
      isLight ? Colors.white.withValues(alpha: 0.70) : Colors.white.withValues(alpha: 0.12);
  Color get glassBorder =>
      isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.16);
  Color get glassShadow => Colors.black.withValues(alpha: isLight ? 0.08 : 0.35);
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SURFACE — die zentrale Glas-Karte (entspricht der bisherigen
// GlassSurface aus home_screen.dart bzw. den lokalen _GlassSurface-Klassen)
// ─────────────────────────────────────────────────────────────────────────────

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool useBlur;
  final bool highlighted;
  final Color? overrideColor;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.useBlur = true,
    this.highlighted = false,
    this.overrideColor,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final br = BorderRadius.circular(borderRadius);
    final baseColor = overrideColor ??
        (skin.isLight
            ? Colors.white.withValues(alpha: skin.glassOpacity)
            : skin.bgCard.withValues(alpha: skin.glassOpacity));

    final decoration = BoxDecoration(
      color: baseColor,
      borderRadius: br,
      border: Border.all(
        color: highlighted ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder,
        width: highlighted ? 1.5 : 1.0,
      ),
      boxShadow: [
        BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
        BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
      ],
    );

    final inner = Container(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: decoration,
      child: child,
    );

    if (!useBlur) return ClipRRect(borderRadius: br, child: inner);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: inner,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SHEET — Bottom-Sheet-Wrapper
// (vorher: _GlassSheet in home_screen.dart/fahrtenbuch_screen.dart,
//  _GlassBottomSheet in month_screen.dart/schedule_screen.dart — identisch)
// ─────────────────────────────────────────────────────────────────────────────

class GlassSheet extends StatelessWidget {
  final AppSkin skin;
  final Widget child;
  const GlassSheet({super.key, required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: 0.82) : skin.bgSheet.withValues(alpha: 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: skin.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Alias, falls an Aufrufstellen bisher `_GlassBottomSheet` verwendet wurde.
/// Entspricht 1:1 [GlassSheet] — vermeidet Übersetzungsfehler beim Umstellen.
typedef GlassBottomSheet = GlassSheet;

// ─────────────────────────────────────────────────────────────────────────────
// SHEET HANDLE — der kleine Balken oben im Bottom-Sheet
// ─────────────────────────────────────────────────────────────────────────────

class SheetHandle extends StatelessWidget {
  final AppSkin skin;
  const SheetHandle({super.key, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(color: skin.surface(0.18), borderRadius: BorderRadius.circular(2)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS PRIMARY BUTTON — der hervorgehobene Aktions-Button
// ─────────────────────────────────────────────────────────────────────────────

class GlassPrimaryButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool large;

  const GlassPrimaryButton({
    super.key,
    required this.skin,
    required this.label,
    required this.onTap,
    this.icon,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = skin.isLight ? skin.primary.withValues(alpha: 0.13) : skin.primary.withValues(alpha: 0.22);
    final borderColor = skin.isLight ? skin.primary.withValues(alpha: 0.28) : skin.primary.withValues(alpha: 0.45);
    final textColor = skin.isLight ? skin.primary.withValues(alpha: 0.90) : skin.primary.withValues(alpha: 0.85);
    final iconColor = skin.isLight ? skin.primary.withValues(alpha: 0.65) : skin.primary.withValues(alpha: 0.70);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: large ? 17 : 14, horizontal: 20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(large ? 20 : 14),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
            BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor, size: large ? 20 : 17),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: large ? 16 : 15, fontWeight: FontWeight.w700, color: textColor, letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SECONDARY BUTTON
// (vorher: _GlassSecondaryButton in fahrtenbuch_/month_/schedule_screen.dart;
//  _GlassButton in home_screen.dart hatte denselben Look, nur anderer Name)
// ─────────────────────────────────────────────────────────────────────────────

class GlassSecondaryButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final VoidCallback onTap;
  const GlassSecondaryButton({super.key, required this.skin, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: skin.isLight ? Colors.white.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.glassBorder, width: 1.0),
          boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6))],
        ),
        child: Center(
          child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary)),
        ),
      ),
    );
  }
}

/// Alias für Aufrufstellen, die bisher `_GlassButton(...)` aus home_screen.dart nutzten.
typedef GlassButton = GlassSecondaryButton;

// ─────────────────────────────────────────────────────────────────────────────
// GLASS ICON BADGE — kleines Icon ohne Rahmen (z. B. Datums-Pfeile, Edit-Stift)
// ─────────────────────────────────────────────────────────────────────────────

class GlassIconBadge extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final VoidCallback? onTap;
  const GlassIconBadge({super.key, required this.skin, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Icon(icon, size: 16, color: skin.surface(0.45)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS STAT CARD — die kleinen Statistik-Kacheln oben in den Listen-Screens
// ─────────────────────────────────────────────────────────────────────────────

class GlassStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const GlassStatCard({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: skin.isLight ? 0.10 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, color: skin.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Alias, da fahrtenbuch_screen.dart die identische Karte `_StatCard` nannte.
typedef StatCard = GlassStatCard;

// ─────────────────────────────────────────────────────────────────────────────
// FADING LIST VIEW — Verlaufender Schatten am Listenende (vor Bottom-Nav)
// (vorher 1:1 dupliziert in fahrtenbuch_screen.dart, month_screen.dart,
//  schedule_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

class FadingListView extends StatelessWidget {
  final Widget child;
  final double fadeFromBottom;
  const FadingListView({super.key, required this.child, required this.fadeFromBottom});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        final h = bounds.height;
        final startStop = ((h - (fadeFromBottom - 30)) / h).clamp(0.0, 1.0);
        final endStop = ((h - (fadeFromBottom - 70)) / h).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.white, Colors.white, Colors.black26, Colors.transparent, Colors.transparent],
          stops: [0.0, startStop, (startStop + endStop) / 2, endStop, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}