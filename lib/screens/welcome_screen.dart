import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIQUID GLASS EXTENSION (gleiche Werte wie im Rest der App)
// ─────────────────────────────────────────────────────────────────────────────

extension _AppSkinGlass on AppSkin {
  double get glassBlur => isLight ? 18.0 : 22.0;
  double get glassOpacity => isLight ? 0.62 : 0.55;
  Color get glassHighlight =>
      isLight ? Colors.white.withValues(alpha: 0.70) : Colors.white.withValues(alpha: 0.12);
  Color get glassBorder =>
      isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.16);
  Color get glassShadow => Colors.black.withValues(alpha: isLight ? 0.08 : 0.35);
}

/// Zeigt – falls noch kein Name gespeichert ist – einen nicht schließbaren
/// Begrüßungsdialog, der den Namen abfragt und in der Hive-Box
/// 'einstellungen' unter dem Key 'name' speichert (gleicher Key wie in den
/// Einstellungen, dadurch ist alles weiterhin konsistent).
///
/// Aufruf z.B. in MainScreen.initState() via:
///   WidgetsBinding.instance.addPostFrameCallback((_) => maybeShowWelcomeDialog(context));
Future<void> maybeShowWelcomeDialog(BuildContext context) async {
  final box = Hive.box('einstellungen');
  final existingName = (box.get('name', defaultValue: '') as String).trim();
  if (existingName.isNotEmpty) return; // schon vorhanden -> nichts zu tun
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false, // kein Tap-Outside
    enableDrag: false, // kein Wegwischen
    useSafeArea: false,
    builder: (_) => const _WelcomeSheet(),
  );
}

String _capitalizeEachWord(String text) {
  if (text.isEmpty) return text;
  return text
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

class _WelcomeSheet extends StatefulWidget {
  const _WelcomeSheet();

  @override
  State<_WelcomeSheet> createState() => _WelcomeSheetState();
}

class _WelcomeSheetState extends State<_WelcomeSheet> {
  final _nameCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool get _canSubmit => _nameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    // Tastatur direkt öffnen, fühlt sich einladender an
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _focusNode.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    final formatted = _capitalizeEachWord(_nameCtrl.text.trim());
    Hive.box('einstellungen').put('name', formatted);
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return PopScope(
      canPop: false, // Android-Zurück-Button blockieren -> Pflichtfeld bleibt Pflicht
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.90)
                    : skin.bgSheet.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: skin.glassBorder),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: skin.surface(0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // ── Icon ──────────────────────────────────────────────────
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: skin.primary.withValues(alpha: skin.isLight ? 0.12 : 0.18),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.front_hand_outlined, color: skin.primary, size: 28),
                  ),
                  const SizedBox(height: 18),

                  // ── Begrüßung ─────────────────────────────────────────────
                  Text(
                    'Willkommen bei OpTimes',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: skin.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wie heißt du? Dein Name erscheint in der Begrüßung,\nim PDF-Export und hilft bei der Dienstplan-Erkennung.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 22),

                  // ── Eingabefeld (Glass-Stil wie restliche App) ───────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: skin.isLight
                              ? Colors.white.withValues(alpha: skin.glassOpacity)
                              : skin.bgCard.withValues(alpha: skin.glassOpacity),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _focusNode.hasFocus
                                ? skin.primary.withValues(alpha: 0.45)
                                : skin.glassBorder,
                            width: _focusNode.hasFocus ? 1.5 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 18, color: skin.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _nameCtrl,
                                focusNode: _focusNode,
                                textCapitalization: TextCapitalization.words,
                                autocorrect: false,
                                style: TextStyle(
                                  color: skin.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'z.B. Max Mustermann',
                                  hintStyle: TextStyle(color: skin.surface(0.3), fontSize: 16),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Primary Button (deaktiviert solange leer) ────────────────
                  GestureDetector(
                    onTap: _submit,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _canSubmit ? 1.0 : 0.4,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: skin.isLight
                              ? skin.primary.withValues(alpha: 0.13)
                              : skin.primary.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: skin.isLight
                                ? skin.primary.withValues(alpha: 0.28)
                                : skin.primary.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(color: skin.glassShadow, blurRadius: 24, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Los geht's",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: skin.isLight
                                    ? skin.primary.withValues(alpha: 0.90)
                                    : skin.primary.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: skin.isLight
                                  ? skin.primary.withValues(alpha: 0.65)
                                  : skin.primary.withValues(alpha: 0.70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}