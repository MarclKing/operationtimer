import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DICTATION HELP SCREEN v3
// Zeigt alle unterstützten Eingabe-Muster + Lern-Hinweis oben.
// Speech-Log-Button wurde entfernt (jetzt in Einstellungen → Aufgaben).
// ─────────────────────────────────────────────────────────────────────────────

class DictationHelpScreen extends StatelessWidget {
  const DictationHelpScreen({super.key});

  static const _urgentRed = Color(0xFFEF5B5B);
  static const _learnGreen = Color(0xFF3DD68C);

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sprachbefehle',
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
              padding: const EdgeInsets.only(left: 74, bottom: 16),
              child: Text(
                'Muster · Datum · Dringend · Selbstlernend',
                style: TextStyle(fontSize: 12.5, color: skin.textMuted),
              ),
            ),

            // ── Inhalt ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
                children: [

                  // ── NEU: Lern-Banner ──────────────────────────────────────
                  _LearnBanner(skin: skin),
                  const SizedBox(height: 20),

                  // ── Muster 1 ─────────────────────────────────────────────
                  _PatternBlock(
                    skin: skin,
                    number: '1',
                    label: 'AUFGABE HINZUFÜGEN',
                    icon: Icons.add_task_outlined,
                    template: [
                      _Segment('Füge die Aufgabe ', SegmentType.command),
                      _Segment('Titel', SegmentType.task),
                      _Segment(' hinzu', SegmentType.command),
                    ],
                    templateNote:
                        'Statt „Füge die Aufgabe" auch: Trage, Ergänze, Neue Aufgabe:, Todo:',
                    variants: [
                      _Variant(
                        input: 'Füge die Aufgabe Marcel schreiben hinzu',
                        output: 'Marcel schreiben',
                        date: null,
                      ),
                      _Variant(
                        input: 'Füge die Aufgabe Dienstplan erstellen hinzu',
                        output: 'Dienstplan erstellen',
                        date: null,
                      ),
                      _Variant(
                        input: 'Neue Aufgabe: Auto Liste',
                        output: 'Auto Liste',
                        date: null,
                      ),
                    ],
                    deadlineBlock: _PatternDeadlineBlock(
                      skin: skin,
                      intro:
                          'Optional: Frist anhängen — mit einem dieser zwei Schlüsselwörter:',
                      templates: [
                        [
                          _Segment('Füge die Aufgabe ', SegmentType.command),
                          _Segment('Titel', SegmentType.task),
                          _Segment(' mit Frist ', SegmentType.keyword),
                          _Segment('Datum Uhrzeit', SegmentType.datetime),
                          _Segment(' hinzu', SegmentType.command),
                        ],
                        [
                          _Segment('Füge die Aufgabe ', SegmentType.command),
                          _Segment('Titel', SegmentType.task),
                          _Segment(' für ', SegmentType.keyword),
                          _Segment('Datum Uhrzeit', SegmentType.datetime),
                          _Segment(' hinzu', SegmentType.command),
                        ],
                      ],
                      variants: [
                        _Variant(
                          input:
                              'Füge die Aufgabe Marcel schreiben mit Frist 23.10. 15 Uhr hinzu',
                          output: 'Marcel schreiben',
                          date: '23.10. · 15:00',
                        ),
                        _Variant(
                          input:
                              'Füge die Aufgabe Dienstplan erstellen für morgen 9 Uhr hinzu',
                          output: 'Dienstplan erstellen',
                          date: 'morgen · 09:00',
                        ),
                        _Variant(
                          input: 'Todo: Auto Liste für Freitag',
                          output: 'Auto Liste',
                          date: 'Freitag',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Muster 2 ─────────────────────────────────────────────
                  _PatternBlock(
                    skin: skin,
                    number: '2',
                    label: 'ERINNERE MICH',
                    icon: Icons.notifications_outlined,
                    template: [
                      _Segment('Erinnere mich an: ', SegmentType.command),
                      _Segment('Titel', SegmentType.task),
                    ],
                    templateNote:
                        'Alles nach „an:" wird 1:1 als Aufgabentitel übernommen.',
                    variants: [
                      _Variant(
                        input: 'Erinnere mich an: Auto waschen',
                        output: 'Auto waschen',
                        date: null,
                      ),
                      _Variant(
                        input: 'Erinnere mich an: Meeting mit Sarah',
                        output: 'Meeting mit Sarah',
                        date: null,
                      ),
                    ],
                    deadlineBlock: _PatternDeadlineBlock(
                      skin: skin,
                      intro:
                          'Optional: Datum & Uhrzeit zwischen „mich" und „an:" einfügen:',
                      templates: [
                        [
                          _Segment('Erinnere mich ', SegmentType.command),
                          _Segment('am Datum um Uhrzeit', SegmentType.datetime),
                          _Segment(' an: ', SegmentType.command),
                          _Segment('Titel', SegmentType.task),
                        ],
                      ],
                      variants: [
                        _Variant(
                          input:
                              'Erinnere mich am 23.10. um 18:30 Uhr an: Auto waschen',
                          output: 'Auto waschen',
                          date: '23.10. · 18:30',
                        ),
                        _Variant(
                          input:
                              'Erinnere mich morgen um 9 Uhr an: Zahnarzt',
                          output: 'Zahnarzt',
                          date: 'morgen · 09:00',
                        ),
                        _Variant(
                          input:
                              'Erinnere mich am Freitag an: Reisepass verlängern',
                          output: 'Reisepass verlängern',
                          date: 'Freitag',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Muster 3: Natürliche Sprache ─────────────────────────
                  _NaturalLanguageBlock(skin: skin),

                  const SizedBox(height: 16),

                  // ── Dringend ─────────────────────────────────────────────
                  _UrgentBlock(skin: skin),

                  const SizedBox(height: 16),

                  // ── Datum/Zeit Referenz ───────────────────────────────────
                  _ReferenceCard(
                    skin: skin,
                    icon: Icons.calendar_today_outlined,
                    title: 'Datum-Formate',
                    groups: [
                      _RefGroup('Relativ', [
                        'morgen',
                        'übermorgen',
                        'heute',
                        'nächste Woche'
                      ]),
                      _RefGroup('Wochentag', [
                        'Montag … Sonntag',
                        'nächsten Dienstag'
                      ]),
                      _RefGroup(
                          'Exakt', ['23.10.', '15. März', '15.3.2026']),
                      _RefGroup('Abstand', [
                        'in 3 Tagen',
                        'in 2 Wochen'
                      ]),
                    ],
                  ),

                  const SizedBox(height: 10),

                  _ReferenceCard(
                    skin: skin,
                    icon: Icons.access_time_rounded,
                    title: 'Uhrzeit-Formate',
                    groups: [
                      _RefGroup(
                          'Standard', ['15 Uhr', '15:30 Uhr', 'um 9']),
                      _RefGroup('Umgangsspr.', [
                        'halb drei',
                        'viertel nach 9',
                        'viertel vor 10',
                        'dreiviertel 10'
                      ]),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ── Natürliche Sprache Tipp ───────────────────────────────
                  _NaturalTipCard(skin: skin),

                  const SizedBox(height: 8),
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
// LEARN BANNER — prominent oben, erklärt das Selbstlernen
// ─────────────────────────────────────────────────────────────────────────────

class _LearnBanner extends StatelessWidget {
  final AppSkin skin;
  const _LearnBanner({required this.skin});

  static const _green = Color(0xFF3DD68C);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: skin.isLight ? 0.07 : 0.11),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _green.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: _green.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _green.withValues(alpha: 0.30)),
                    ),
                    child: const Center(
                      child: Icon(Icons.auto_awesome_rounded,
                          size: 18, color: _green),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lernt automatisch dazu',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _green,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Spracherkennung passt sich an dich an',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _green.withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 0.5,
                color: _green.withValues(alpha: 0.20),
              ),
              const SizedBox(height: 12),
              Text(
                'Die Diktierfunktion merkt sich, welche Formulierungen du verwendest. Sätze, die nicht sofort erkannt werden, werden sicher analysiert — so lernt die App mit der Zeit deine persönliche Ausdrucksweise und erkennt sie beim nächsten Mal direkt.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: skin.textPrimary.withValues(alpha: 0.75),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _LearnChip(label: '🎙 Einfach diktieren', green: _green, skin: skin),
                  const SizedBox(width: 6),
                  _LearnChip(label: '🧠 App lernt mit', green: _green, skin: skin),
                  const SizedBox(width: 6),
                  _LearnChip(label: '✓ Wird besser', green: _green, skin: skin),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LearnChip extends StatelessWidget {
  final String label;
  final Color green;
  final AppSkin skin;
  const _LearnChip({required this.label, required this.green, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: green.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: green.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NATÜRLICHE SPRACHE BLOCK — Muster 3
// ─────────────────────────────────────────────────────────────────────────────

class _NaturalLanguageBlock extends StatelessWidget {
  final AppSkin skin;
  const _NaturalLanguageBlock({required this.skin});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [
              BoxShadow(color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 5))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: skin.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: skin.primary.withValues(alpha: 0.25)),
                      ),
                      child: Center(
                        child: Text(
                          '3',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: skin.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.auto_fix_high_outlined, size: 13, color: skin.primary),
                    const SizedBox(width: 6),
                    Text(
                      'NATÜRLICHE SPRACHE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: skin.primary,
                          letterSpacing: 1.0),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3DD68C).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF3DD68C).withValues(alpha: 0.30)),
                      ),
                      child: Text(
                        'LERNEND',
                        style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF3DD68C),
                            letterSpacing: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Text(
                  'Formulierungen die nicht Muster 1 oder 2 entsprechen, werden automatisch analysiert und der App beigebracht. Einfach natürlich sprechen — die Erkennung verbessert sich mit der Zeit.',
                  style: TextStyle(
                      fontSize: 12, color: skin.surface(0.45), height: 1.45),
                ),
              ),
              Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: skin.surface(0.08)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  'WIRD AUTOMATISCH ERKANNT',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: skin.surface(0.32),
                      letterSpacing: 1.1),
                ),
              ),
              _NaturalVariant(
                  skin: skin,
                  input: 'Ich muss noch Zahnarzt anrufen',
                  output: 'Zahnarzt anrufen'),
              _NaturalVariant(
                  skin: skin,
                  input: 'Nicht vergessen: Reisepass verlängern',
                  output: 'Reisepass verlängern'),
              _NaturalVariant(
                  skin: skin,
                  input: 'Morgen früh Auto waschen',
                  output: 'Auto waschen',
                  date: 'morgen'),
              _NaturalVariant(
                  skin: skin,
                  input: 'Kannst du mich an das Meeting erinnern',
                  output: 'Meeting'),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _NaturalVariant extends StatelessWidget {
  final AppSkin skin;
  final String input;
  final String output;
  final String? date;
  const _NaturalVariant(
      {required this.skin,
      required this.input,
      required this.output,
      this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.30)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '„$input"',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: skin.textPrimary.withValues(alpha: 0.70),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.arrow_forward_rounded,
                      size: 10, color: skin.primary.withValues(alpha: 0.5)),
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: skin.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: skin.primary.withValues(alpha: 0.22)),
                    ),
                    child: Text(output,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: skin.primary)),
                  ),
                  if (date != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B9EF5).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF5B9EF5).withValues(alpha: 0.28)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.schedule_outlined,
                            size: 10, color: const Color(0xFF3B7ED4)),
                        const SizedBox(width: 3),
                        Text(date!,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3B7ED4))),
                      ]),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NaturalTipCard extends StatelessWidget {
  final AppSkin skin;
  const _NaturalTipCard({required this.skin});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: skin.primary.withValues(alpha: skin.isLight ? 0.05 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 15, color: skin.primary.withValues(alpha: 0.70)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Tipp: Sprich einfach so, wie du es einem Assistenten sagen würdest. Je mehr du die Diktierfunktion nutzt, desto besser wird die Erkennung für deine Formulierungen.',
                  style: TextStyle(
                      fontSize: 12,
                      color: skin.textMuted,
                      height: 1.5),
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
// Ab hier: alle bisherigen Hilfsklassen bleiben identisch erhalten
// (Segment-Typen, _Variant, _PatternDeadlineBlock, _PatternBlock,
//  _DeadlineSection, _TemplateRow, _VariantRow, _UrgentBlock,
//  _UrgentVariantRow, _ReferenceCard, _RefGroup)
// ─────────────────────────────────────────────────────────────────────────────

enum SegmentType { command, task, datetime, keyword }

class _Segment {
  final String text;
  final SegmentType type;
  const _Segment(this.text, this.type);
}

class _Variant {
  final String input;
  final String output;
  final String? date;
  const _Variant({required this.input, required this.output, this.date});
}

class _PatternDeadlineBlock {
  final AppSkin skin;
  final String intro;
  final List<List<_Segment>> templates;
  final List<_Variant> variants;
  const _PatternDeadlineBlock({
    required this.skin,
    required this.intro,
    required this.templates,
    required this.variants,
  });
}

class _PatternBlock extends StatefulWidget {
  final AppSkin skin;
  final String number;
  final String label;
  final IconData icon;
  final List<_Segment> template;
  final String templateNote;
  final List<_Variant> variants;
  final _PatternDeadlineBlock deadlineBlock;

  const _PatternBlock({
    required this.skin,
    required this.number,
    required this.label,
    required this.icon,
    required this.template,
    required this.templateNote,
    required this.variants,
    required this.deadlineBlock,
  });

  @override
  State<_PatternBlock> createState() => _PatternBlockState();
}

class _PatternBlockState extends State<_PatternBlock> {
  bool _showDeadline = false;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [
              BoxShadow(
                  color: skin.glassShadow,
                  blurRadius: 20,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: skin.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: skin.primary.withValues(alpha: 0.25)),
                    ),
                    child: Center(
                      child: Text(widget.number,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: skin.primary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(widget.icon, size: 13, color: skin.primary),
                  const SizedBox(width: 6),
                  Text(widget.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: skin.primary,
                          letterSpacing: 1.0)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _TemplateRow(skin: skin, segments: widget.template),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 12),
                child: Text(widget.templateNote,
                    style: TextStyle(
                        fontSize: 11, color: skin.surface(0.38), height: 1.4)),
              ),
              Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: skin.surface(0.08)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('BEISPIELE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: skin.surface(0.32),
                        letterSpacing: 1.1)),
              ),
              ...widget.variants.map((v) => _VariantRow(skin: skin, variant: v)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _showDeadline = !_showDeadline),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: _showDeadline
                        ? skin.primary.withValues(alpha: 0.08)
                        : skin.surface(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _showDeadline
                          ? skin.primary.withValues(alpha: 0.28)
                          : skin.surface(0.10),
                    ),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13,
                        color: _showDeadline
                            ? skin.primary
                            : skin.surface(0.4)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('Mit Frist / Datum',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _showDeadline
                                    ? skin.primary
                                    : skin.surface(0.45)))),
                    Icon(
                        _showDeadline
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                        color: _showDeadline
                            ? skin.primary
                            : skin.surface(0.3)),
                  ]),
                ),
              ),
              if (_showDeadline) ...[
                Container(
                    height: 0.5,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: skin.surface(0.08)),
                _DeadlineSection(skin: skin, block: widget.deadlineBlock),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeadlineSection extends StatelessWidget {
  final AppSkin skin;
  final _PatternDeadlineBlock block;
  const _DeadlineSection({required this.skin, required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(block.intro,
              style: TextStyle(
                  fontSize: 12, color: skin.surface(0.45), height: 1.4)),
          const SizedBox(height: 10),
          ...block.templates.map((segs) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TemplateRow(skin: skin, segments: segs),
              )),
          const SizedBox(height: 6),
          Text('BEISPIELE',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: skin.surface(0.32),
                  letterSpacing: 1.1)),
          const SizedBox(height: 6),
          ...block.variants.map((v) => _VariantRow(skin: skin, variant: v)),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  final AppSkin skin;
  final List<_Segment> segments;
  const _TemplateRow({required this.skin, required this.segments});

  Color _bgColor(_Segment seg, AppSkin skin) {
    switch (seg.type) {
      case SegmentType.command:
        return skin.surface(0.07);
      case SegmentType.task:
        return skin.primary.withValues(alpha: 0.13);
      case SegmentType.datetime:
        return const Color(0xFF5B9EF5).withValues(alpha: 0.13);
      case SegmentType.keyword:
        return const Color(0xFF5BCB8F).withValues(alpha: 0.15);
    }
  }

  Color _textColor(_Segment seg, AppSkin skin) {
    switch (seg.type) {
      case SegmentType.command:
        return skin.textPrimary;
      case SegmentType.task:
        return skin.primary;
      case SegmentType.datetime:
        return const Color(0xFF3B7ED4);
      case SegmentType.keyword:
        return const Color(0xFF2BA86A);
    }
  }

  Color _borderColor(_Segment seg, AppSkin skin) {
    switch (seg.type) {
      case SegmentType.command:
        return skin.surface(0.12);
      case SegmentType.task:
        return skin.primary.withValues(alpha: 0.28);
      case SegmentType.datetime:
        return const Color(0xFF5B9EF5).withValues(alpha: 0.32);
      case SegmentType.keyword:
        return const Color(0xFF5BCB8F).withValues(alpha: 0.35);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: segments.map((seg) {
        final isPlaceholder =
            seg.type == SegmentType.task || seg.type == SegmentType.datetime;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _bgColor(seg, skin),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _borderColor(seg, skin), width: 0.9),
          ),
          child: Text(
            seg.text.trim(),
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  isPlaceholder ? FontWeight.w700 : FontWeight.w500,
              color: _textColor(seg, skin),
              fontStyle:
                  isPlaceholder ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _VariantRow extends StatelessWidget {
  final AppSkin skin;
  final _Variant variant;
  const _VariantRow({required this.skin, required this.variant});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.30)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '„${variant.input}"',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: skin.textPrimary.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.arrow_forward_rounded,
                      size: 10,
                      color: skin.primary.withValues(alpha: 0.5)),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: skin.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: skin.primary.withValues(alpha: 0.22)),
                    ),
                    child: Text(variant.output,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: skin.primary)),
                  ),
                  if (variant.date != null) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B9EF5).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF5B9EF5)
                                .withValues(alpha: 0.28)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.schedule_outlined,
                            size: 10, color: const Color(0xFF3B7ED4)),
                        const SizedBox(width: 3),
                        Text(variant.date!,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3B7ED4))),
                      ]),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgentBlock extends StatelessWidget {
  final AppSkin skin;
  const _UrgentBlock({required this.skin});

  static const _red = Color(0xFFEF5B5B);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: _red.withValues(alpha: skin.isLight ? 0.05 : 0.09),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _red.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _red.withValues(alpha: 0.28)),
                    ),
                    child: const Center(
                      child: Icon(Icons.priority_high_rounded,
                          size: 15, color: _red),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('DRINGEND',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _red,
                          letterSpacing: 1.1)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Text(
                  'Das Wort „dringend" irgendwo im Satz markiert die Aufgabe als dringend — sie erscheint dann ganz oben in der Liste, optisch abgehoben.',
                  style: TextStyle(
                      fontSize: 12.5, color: skin.textMuted, height: 1.45),
                ),
              ),
              Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: _red.withValues(alpha: 0.15)),
              const SizedBox(height: 10),
              _UrgentVariantRow(
                  skin: skin,
                  input: 'Dringend: Reisepass verlängern',
                  output: 'Reisepass verlängern'),
              _UrgentVariantRow(
                  skin: skin,
                  input:
                      'Füge die Aufgabe dringend Angebot schreiben hinzu',
                  output: 'Angebot schreiben'),
              _UrgentVariantRow(
                  skin: skin,
                  input: 'Erinnere mich dringend an: Arzttermin',
                  output: 'Arzttermin'),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrgentVariantRow extends StatelessWidget {
  final AppSkin skin;
  final String input;
  final String output;
  const _UrgentVariantRow(
      {required this.skin, required this.input, required this.output});

  static const _red = Color(0xFFEF5B5B);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.30)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('„$input"',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        color: skin.textPrimary.withValues(alpha: 0.75),
                        height: 1.35)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.arrow_forward_rounded,
                      size: 10, color: _red.withValues(alpha: 0.5)),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: _red.withValues(alpha: 0.28)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.priority_high_rounded,
                          size: 10, color: _red),
                      const SizedBox(width: 3),
                      Text(output,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _red)),
                    ]),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RefGroup {
  final String label;
  final List<String> items;
  const _RefGroup(this.label, this.items);
}

class _ReferenceCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String title;
  final List<_RefGroup> groups;
  const _ReferenceCard({
    required this.skin,
    required this.icon,
    required this.title,
    required this.groups,
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
                ? Colors.white.withValues(alpha: skin.glassOpacity * 0.85)
                : skin.bgCard.withValues(alpha: skin.glassOpacity * 0.75),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon,
                    size: 13,
                    color: skin.primary.withValues(alpha: 0.70)),
                const SizedBox(width: 7),
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: skin.textPrimary)),
              ]),
              const SizedBox(height: 10),
              ...groups.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(g.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: skin.surface(0.35),
                                  letterSpacing: 0.3)),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: g.items
                                .map((item) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: skin.surface(0.06),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                            color: skin.glassBorder,
                                            width: 0.8),
                                      ),
                                      child: Text(item,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: skin.textMuted,
                                              fontWeight: FontWeight.w500)),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}