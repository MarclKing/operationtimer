import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DICTATION HELP SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class DictationHelpScreen extends StatelessWidget {
  const DictationHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header — identisch zu _SettingsHeader ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Center(
                        child: Icon(Icons.arrow_back_ios_new, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Diktieren & Sprachbefehle',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: skin.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 78, bottom: 8),
              child: Text(
                'So funktioniert die Spracheingabe',
                style: TextStyle(fontSize: 13, color: skin.textMuted),
              ),
            ),
            // ── Inhalt ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  _InfoCard(
                    skin: skin,
                    icon: Icons.mic_rounded,
                    title: 'Aufgabe per Sprache anlegen',
                    body:
                        'Halte den Mikrofon-Button in der Aufgaben-Liste gedrückt und sprich deine Aufgabe. Loslassen startet die Erkennung. '
                        'Links wischen während des Haltens bricht ab.',
                  ),
                  const SizedBox(height: 14),
                  _PhraseGroup(
                    skin: skin,
                    label: 'ERINNERUNGEN',
                    icon: Icons.notifications_outlined,
                    phrases: [
                      _Phrase(
                        example: 'Erinnere mich morgen um 14:30 Uhr an mein Auto zu waschen',
                        result: 'Autowaschen · morgen 14:30',
                        tip: 'Datum und Uhrzeit können überall im Satz stehen.',
                      ),
                      _Phrase(
                        example: 'Erinnere mich daran, Martin zu schreiben',
                        result: 'Martin schreiben',
                        tip: '"daran" und ähnliche Füllwörter werden ignoriert.',
                      ),
                      _Phrase(
                        example: 'Erinnere mich morgen früh bitte an den Arzttermin',
                        result: 'Arzttermin · morgen 08:00',
                      ),
                      _Phrase(
                        example: 'Erinnere mich nächsten Dienstag um 10 Uhr an das Meeting',
                        result: 'Meeting · nächster Dienstag 10:00',
                      ),
                      _Phrase(
                        example: 'Kannst du mich daran erinnern, die Wäsche zu waschen?',
                        result: 'Wäsche waschen',
                      ),
                      _Phrase(
                        example: 'Ich brauche eine Erinnerung an meinen Zahnarzt am Freitag',
                        result: 'Zahnarzt · Freitag',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PhraseGroup(
                    skin: skin,
                    label: 'AUFGABE HINZUFÜGEN',
                    icon: Icons.add_task_outlined,
                    phrases: [
                      _Phrase(
                        example: 'Füge die Aufgabe Martin schreiben für Dienstag 15 Uhr ein',
                        result: 'Martin schreiben · Dienstag 15:00',
                        tip: 'Der nächste Dienstag wird automatisch gewählt.',
                      ),
                      _Phrase(
                        example: 'Ergänze die Aufgabe Einkaufen gehen für morgen',
                        result: 'Einkaufen · morgen',
                      ),
                      _Phrase(
                        example: 'Trage die Aufgabe Steuererklärung machen ein',
                        result: 'Steuererklärung',
                      ),
                      _Phrase(
                        example: 'Neue Aufgabe: Kühlschrank reinigen bis Freitag',
                        result: 'Kühlschrank reinigen · Freitag',
                      ),
                      _Phrase(
                        example: 'Ich muss noch die Wäsche waschen',
                        result: 'Wäsche waschen',
                        tip: 'Selbstgespräche werden ebenfalls erkannt.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PhraseGroup(
                    skin: skin,
                    label: 'MIT DATUM & UHRZEIT',
                    icon: Icons.schedule_outlined,
                    phrases: [
                      _Phrase(
                        example: 'Trage für den 24. um 15 Uhr Autowaschen ein',
                        result: 'Autowaschen · 24. 15:00',
                        tip: '"für den 24. um 15 Uhr" wird vollständig als Datum/Zeit erkannt.',
                      ),
                      _Phrase(
                        example: 'Trage für morgen 14:30 Uhr ein: Müll rausbringen',
                        result: 'Müll rausbringen · morgen 14:30',
                      ),
                      _Phrase(
                        example: 'Füge für den 15. März Hausaufgaben machen ein',
                        result: 'Hausaufgaben · 15. März',
                      ),
                      _Phrase(
                        example: 'Erstelle eine Aufgabe für übermorgen 9 Uhr: Sport machen',
                        result: 'Sport machen · übermorgen 09:00',
                      ),
                      _Phrase(
                        example: 'In drei Tagen muss ich zum Arzt',
                        result: 'Arzttermin · in 3 Tagen',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PhraseGroup(
                    skin: skin,
                    label: 'SELBSTGESPRÄCH & KURZFORM',
                    icon: Icons.record_voice_over_outlined,
                    phrases: [
                      _Phrase(
                        example: 'Nicht vergessen: Müll rausbringen',
                        result: 'Müll rausbringen',
                      ),
                      _Phrase(
                        example: 'Ich muss unbedingt noch die Steuererklärung machen',
                        result: 'Steuererklärung',
                      ),
                      _Phrase(
                        example: 'Denk daran, Martin morgen anzurufen',
                        result: 'Martin anrufen · morgen',
                      ),
                      _Phrase(
                        example: 'Das darf ich nicht vergessen: Reisepass verlängern',
                        result: 'Reisepass verlängern',
                      ),
                      _Phrase(
                        example: 'Todo: Kühlschrank reinigen',
                        result: 'Kühlschrank reinigen',
                      ),
                      _Phrase(
                        example: 'Unbedingt Wäsche waschen heute Abend',
                        result: 'Wäsche waschen · heute 19:00',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PhraseGroup(
                    skin: skin,
                    label: 'WIEDERHOLUNG & PRIORITÄT',
                    icon: Icons.repeat_rounded,
                    phrases: [
                      _Phrase(
                        example: 'Erinnere mich täglich an Sport machen',
                        result: 'Sport machen · täglich',
                      ),
                      _Phrase(
                        example: 'Ich muss jeden Montag die Zeiterfassung einreichen',
                        result: 'Zeiterfassung einreichen · jeden Montag',
                      ),
                      _Phrase(
                        example: 'Dringend: Reisepass verlängern bis Freitag',
                        result: '🔴 Reisepass verlängern · Freitag (Dringend)',
                        tip: 'Stichworte wie "dringend", "asap", "sofort" setzen hohe Priorität.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _TipCard(
                    skin: skin,
                    icon: Icons.calendar_today_outlined,
                    title: 'Unterstützte Datumsformate',
                    items: [
                      'morgen, übermorgen, heute',
                      'nächsten / am Dienstag',
                      '15. März / am 15.3. / den 24.',
                      'in 3 Tagen / in einer Woche',
                      'nächste Woche, Ende des Monats',
                      'dieses Wochenende',
                    ],
                  ),
                  const SizedBox(height: 14),
                  _TipCard(
                    skin: skin,
                    icon: Icons.access_time_rounded,
                    title: 'Unterstützte Uhrzeiten',
                    items: [
                      'um 14 Uhr / 14:30 Uhr',
                      'halb drei (→ 14:30)',
                      'viertel nach 9 (→ 09:15)',
                      'viertel vor 10 (→ 09:45)',
                      'dreiviertel 10 (→ 09:45)',
                      'kurz nach 10 (→ 10:05)',
                      'morgens, mittags, abends, nachts',
                      'von 9 bis 11 Uhr',
                    ],
                  ),
                  const SizedBox(height: 14),
                  _TipCard(
                    skin: skin,
                    icon: Icons.auto_fix_high_outlined,
                    title: 'Automatische Titel-Bereinigung',
                    items: [
                      '"auto zu waschen" → Autowaschen',
                      '"einkaufen gehen" → Einkaufen',
                      '"zum Zahnarzt gehen" → Zahnarzt',
                      '"Müll rauszubringen" → Müll rausbringen',
                      '"Hausaufgaben zu machen" → Hausaufgaben',
                      '"Martin schreiben" bleibt Martin schreiben',
                    ],
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO CARD
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.skin,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: skin.primary.withValues(alpha: skin.isLight ? 0.08 : 0.13),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: skin.primary.withValues(alpha: 0.28), width: 1.2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: skin.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: skin.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: skin.textPrimary)),
                    const SizedBox(height: 4),
                    Text(body,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: skin.textMuted,
                            height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PHRASE GROUP
// ─────────────────────────────────────────────────────────────────────────────

class _Phrase {
  final String example;
  final String result;
  final String? tip;
  const _Phrase({required this.example, required this.result, this.tip});
}

class _PhraseGroup extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final IconData icon;
  final List<_Phrase> phrases;

  const _PhraseGroup({
    required this.skin,
    required this.label,
    required this.icon,
    required this.phrases,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 12, color: skin.primary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: skin.primary,
                  letterSpacing: 1.0)),
          const SizedBox(width: 8),
          Expanded(
              child: Container(height: 0.5, color: skin.primary.withValues(alpha: 0.2))),
        ]),
        const SizedBox(height: 8),
        ...phrases.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PhraseCard(skin: skin, phrase: p),
            )),
      ],
    );
  }
}

class _PhraseCard extends StatelessWidget {
  final AppSkin skin;
  final _Phrase phrase;

  const _PhraseCard({required this.skin, required this.phrase});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.mic_none_rounded, size: 13, color: skin.surface(0.38)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '„${phrase.example}"',
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: skin.textPrimary,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  const SizedBox(width: 19),
                  Icon(Icons.arrow_forward_rounded,
                      size: 11, color: skin.primary.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      phrase.result,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: skin.primary),
                    ),
                  ),
                ],
              ),
              if (phrase.tip != null) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 19),
                    Icon(Icons.info_outline_rounded, size: 11, color: skin.surface(0.35)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        phrase.tip!,
                        style: TextStyle(
                            fontSize: 11, color: skin.surface(0.4), height: 1.35),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIP CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TipCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String title;
  final List<String> items;

  const _TipCard({
    required this.skin,
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity * 0.9)
                : skin.bgCard.withValues(alpha: skin.glassOpacity * 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 14, color: skin.primary.withValues(alpha: 0.75)),
                const SizedBox(width: 7),
                Text(title,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: skin.textPrimary)),
              ]),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: items
                    .map((item) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: skin.surface(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: skin.glassBorder, width: 0.8),
                          ),
                          child: Text(item,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: skin.textMuted,
                                  fontWeight: FontWeight.w500)),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}