import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import '../models/relationship_style.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
// ONBOARDING-EINSTIEG
//
// Zeigt — falls noch kein Name gespeichert ist — Sheet 1 (Name) und direkt
// danach Sheet 2 (Anrede/Umgangsform), beide im identischen Glass-Design.
// Sheet 2 wird zusätzlich isoliert gezeigt, falls zwar schon ein Name
// existiert, aber noch keine Anrede-Wahl getroffen wurde (z.B. bei Updates
// von Bestandsnutzern ohne diese Einstellung).
// ─────────────────────────────────────────────────────────────────────────────

Future<void> maybeShowWelcomeDialog(BuildContext context) async {
  final box = Hive.box('einstellungen');
  final existingName = (box.get('name', defaultValue: '') as String).trim();

  if (existingName.isEmpty) {
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: false,
      builder: (_) => const _WelcomeSheet(),
    );
  }

  // Direkt im Anschluss (oder isoliert, falls Name schon vorhanden war):
  // Anrede abfragen, falls noch keine Wahl getroffen wurde.
  if (!RelationshipStyleStore.hasChosen) {
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: false,
      builder: (_) => const _RelationshipSheet(),
    );
  }
}

String _capitalizeEachWord(String text) {
  if (text.isEmpty) return text;
  return text
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET 1 — NAME
// (identisch zu vorher, nur Button-Text "Los geht's" → "Weiter", da nun
// noch ein zweiter Schritt folgt)
// ─────────────────────────────────────────────────────────────────────────────

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
      canPop: false,
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
                              // NEU: "Weiter" statt "Los geht's" — es folgt noch Sheet 2
                              'Weiter',
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

// ─────────────────────────────────────────────────────────────────────────────
// SHEET 2 — ANREDE / UMGANGSFORM
//
// Identisches Glass-Design zu Sheet 1. Statt Textfeld gibt es hier 3
// auswählbare Karten (Bro / Vorname / Familie). Auswahl wird sofort optisch
// hervorgehoben (wie die Skin-Auswahl in den Settings), Button bestätigt
// und speichert.
// ─────────────────────────────────────────────────────────────────────────────

class _RelationshipSheet extends StatefulWidget {
  const _RelationshipSheet();

  @override
  State<_RelationshipSheet> createState() => _RelationshipSheetState();
}

class _RelationshipSheetState extends State<_RelationshipSheet> {
  RelationshipStyle? _selected;

  String get _fullName =>
      (Hive.box('einstellungen').get('name', defaultValue: '') as String).trim();

  void _submit() {
    if (_selected == null) return;
    RelationshipStyleStore.save(_selected!);
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final fullName = _fullName;
    final vorname = firstNameFrom(fullName);
    final nachname = lastNameFrom(fullName);

    return PopScope(
      canPop: false,
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

                // ── Icon ──────────────────────────────────────────────────
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: skin.primary.withValues(alpha: skin.isLight ? 0.12 : 0.18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.chat_bubble_outline_rounded, color: skin.primary, size: 26),
                ),
                const SizedBox(height: 18),

                // ── Frage ─────────────────────────────────────────────────
                Text(
                  'Wie würdest Du unser\nVerhältnis beschreiben?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: skin.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '(Dies beeinflusst, wie Benachrichtigungen von\nOpTimes formuliert werden)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: skin.textMuted, height: 1.5),
                ),
                const SizedBox(height: 22),

                // ── 3 Auswahlkarten ───────────────────────────────────────
                _RelationshipOptionCard(
                  skin: skin,
                  icon: Icons.bolt_rounded,
                  text: 'Hilf mir einfach bei der Arbeit, Bro!',
                  selected: _selected == RelationshipStyle.bro,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = RelationshipStyle.bro);
                  },
                ),
                const SizedBox(height: 10),
                _RelationshipOptionCard(
                  skin: skin,
                  icon: Icons.waving_hand_outlined,
                  text: vorname.isEmpty
                      ? 'Du kannst meinen Vornamen zu mir sagen!'
                      : 'Du kannst $vorname zu mir sagen!',
                  selected: _selected == RelationshipStyle.vorname,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = RelationshipStyle.vorname);
                  },
                ),
                const SizedBox(height: 10),
                _RelationshipOptionCard(
                  skin: skin,
                  icon: Icons.workspace_premium_outlined,
                  text: nachname.isEmpty
                      ? 'Für Dich gehöre ich zur Familie!'
                      : 'Für Dich gehöre ich zur Familie, $nachname!',
                  selected: _selected == RelationshipStyle.familie,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = RelationshipStyle.familie);
                  },
                ),
                const SizedBox(height: 18),

                // ── Primary Button (deaktiviert ohne Auswahl) ────────────────
                GestureDetector(
                  onTap: _submit,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _selected != null ? 1.0 : 0.4,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EINZELNE AUSWAHLKARTE für Sheet 2 — wiederverwendet in den Settings für
// die nachträgliche Änderung (siehe settings_screen.dart).
// ─────────────────────────────────────────────────────────────────────────────

class RelationshipOptionCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const RelationshipOptionCard({
    super.key,
    required this.skin,
    required this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? skin.primary.withValues(alpha: skin.isLight ? 0.10 : 0.16)
              : (skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? skin.primary.withValues(alpha: 0.55) : skin.glassBorder,
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(color: skin.glassShadow, blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? skin.primary : skin.surface(0.45)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? skin.textPrimary : skin.textMuted,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: selected ? 1.0 : 0.0,
              child: Icon(Icons.check_circle_rounded, color: skin.primary, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// Privater Alias, damit das Sheet oben dieselbe Karte ohne Export-Konflikt
// nutzen kann (gleiche Klasse, nur intern referenziert).
typedef _RelationshipOptionCard = RelationshipOptionCard;