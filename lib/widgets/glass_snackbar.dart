import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SNACK BAR
//
// Ersetzt alle ScaffoldMessenger.of(context).showSnackBar(...) Aufrufe
// in der App durch einen einheitlichen Glass-Look.
//
// Verwendung:
//   showGlassSnackBar(context, 'Eintrag gespeichert', GlassSnackBarType.success);
//   showGlassSnackBar(context, 'Eintrag gelöscht', GlassSnackBarType.error);
//   showGlassSnackBar(context, 'PDF wird erstellt…', GlassSnackBarType.loading);
// ─────────────────────────────────────────────────────────────────────────────

enum GlassSnackBarType { success, error, warning, info, loading }

void showGlassSnackBar(
  BuildContext context,
  String message, {
  GlassSnackBarType type = GlassSnackBarType.info,
  Duration duration = const Duration(milliseconds: 2500),
}) {
  final skin = AppTheme.of(context);

  final Color color = switch (type) {
    GlassSnackBarType.success => skin.statComplete,
    GlassSnackBarType.error   => skin.deleteColor,
    GlassSnackBarType.warning => const Color(0xFFFFB347),
    GlassSnackBarType.info    => skin.primary,
    GlassSnackBarType.loading => skin.textMuted,
  };

  final bgColor = skin.isLight
      ? Colors.white.withValues(alpha: 0.92)
      : const Color(0xFF14161D).withValues(alpha: 0.95);

  final borderColor = color.withValues(alpha: skin.isLight ? 0.35 : 0.30);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: type == GlassSnackBarType.loading
          ? const Duration(seconds: 30)
          : duration,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: skin.isLight ? 0.10 : 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (type == GlassSnackBarType.loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: skin.isLight ? skin.textPrimary : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Shortcut zum Ausblenden – z.B. nach PDF-Erstellung
void hideGlassSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
}