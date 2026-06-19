import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GEMEINSAME BESTÄTIGUNGSDIALOGE
//
// Vorher: der "Löschen?"-Dialog (Icon-Badge + Titel, Erklärtext, zwei Buttons,
// Glass-Look mit BackdropFilter) war als eigener showGeneralDialog-Block mit
// 40-50 Zeilen dupliziert in:
//   - fahrtenbuch_screen.dart  (_showDiscardAlert, _confirmDiscard, _confirmDelete)
//   - month_screen.dart        (kein eigener, nutzte direktes Löschen)
//   - schedule_screen.dart     (_showDeleteDialog)
//   - main.dart                (_KfzVerwaltungSheet._deleteEntry,
//                                 _showImportConfirmDialog)
//
// Jetzt: ein Aufruf von confirmDeleteDialog(...) bzw. confirmActionDialog(...).
// Beide geben Future<bool?> zurück — true = bestätigt, false/null = abgebrochen.
// ─────────────────────────────────────────────────────────────────────────────

/// Zeigt einen destruktiven Bestätigungsdialog im einheitlichen Glass-Look
/// (rotes Mülleimer-Icon, Titel, Erklärtext, "Abbrechen"/[confirmLabel]-Button).
///
/// Beispiel (ersetzt z. B. fahrtenbuch_screen.dart _confirmDelete):
/// ```dart
/// final confirmed = await confirmDeleteDialog(
///   context: context,
///   skin: skin,
///   title: 'Fahrt löschen',
///   message: 'Diese Fahrt wird unwiderruflich gelöscht. Diese Aktion kann '
///       'nicht rückgängig gemacht werden.',
/// );
/// if (confirmed == true) { ... }
/// ```
Future<bool?> confirmDeleteDialog({
  required BuildContext context,
  required AppSkin skin,
  required String title,
  required String message,
  String cancelLabel = 'Abbrechen',
  String confirmLabel = 'Löschen',
  Widget? extraContent,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Schließen',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
      return ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved), child: FadeTransition(opacity: anim, child: child));
    },
    pageBuilder: (ctx, _, __) => Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: skin.isLight ? Colors.white.withValues(alpha: 0.92) : skin.bgCard.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: skin.glassBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration:
                          BoxDecoration(color: skin.deleteColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.delete_outline, color: skin.deleteColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(title,
                            style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 12),
                  Text(message, style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.45)),
                  if (extraContent != null) ...[
                    const SizedBox(height: 12),
                    extraContent,
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: GlassSecondaryButton(skin: skin, label: cancelLabel, onTap: () => Navigator.pop(ctx, false))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: skin.deleteColor,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: skin.deleteColor.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4))
                          ],
                        ),
                        child: Center(
                            child: Text(confirmLabel,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
                      ),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Zeigt einen neutralen (nicht-destruktiven) Bestätigungsdialog im selben
/// Glass-Look, aber mit Primary-Button statt rotem Lösch-Button und frei
/// wählbarem Icon. Für Fälle wie "Dienstplan importieren?" in main.dart.
Future<bool?> confirmActionDialog({
  required BuildContext context,
  required AppSkin skin,
  required String title,
  required String message,
  IconData icon = Icons.help_outline,
  String cancelLabel = 'Abbrechen',
  String confirmLabel = 'Bestätigen',
  Widget? extraContent,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Schließen',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
      return ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved), child: FadeTransition(opacity: anim, child: child));
    },
    pageBuilder: (ctx, _, __) => Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: skin.isLight ? Colors.white.withValues(alpha: 0.92) : skin.bgCard.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: skin.glassBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration:
                          BoxDecoration(color: skin.primaryWithAlpha(0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: skin.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(title,
                            style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 12),
                  Text(message, style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.45)),
                  if (extraContent != null) ...[
                    const SizedBox(height: 12),
                    extraContent,
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: GlassSecondaryButton(skin: skin, label: cancelLabel, onTap: () => Navigator.pop(ctx, false))),
                    const SizedBox(width: 10),
                    Expanded(child: GlassPrimaryButton(skin: skin, label: confirmLabel, onTap: () => Navigator.pop(ctx, true))),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}