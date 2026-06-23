import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';
import '../screens/speech_log_screen.dart';
import '../screens/admin_rules_screen.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DICTATION HELP SCREEN v4
// Kompaktes Design: Kernmuster prominent, Natürliche Sprache & Dringend
// als Mini-Kacheln, Datum/Zeit als 2-Spalten-Referenz, Admin-Block
// nur für Admins sichtbar.
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
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
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
                  const SizedBox(width: 8),
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
              padding: const EdgeInsets.only(left: 70, bottom: 14),
              child: Text(
                'Muster · Datum · Dringend · Selbstlernend',
                style: TextStyle(fontSize: 12.5, color: skin.textMuted),
              ),
            ),

            // ── Inhalt ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [

                  // ── Lern-Banner ──────────────────────────────────────────
                  _LearnBanner(skin: skin),
                  const SizedBox(height: 10),

                  // ── Admin-Block (nur für Admins) ──────────────────────────
                  if (AuthService.instance.isAdmin) ...[
                    _AdminCard(skin: skin),
                    const SizedBox(height: 10),
                  ],

                  // ── Kernmuster-Label ──────────────────────────────────────
                  _SectionLabel(
                    label: 'KERNMUSTER — FUNKTIONIEREN IMMER ZUVERLÄSSIG',
                    skin: skin,
                  ),
                  const SizedBox(height: 6),

                  // ── Muster 1 ─────────────────────────────────────────────
                  _PatternCard(
                    skin: skin,
                    number: '1',
                    numBg: const Color(0xFFEEF3FF),
                    numBorder: const Color(0xFFA5B8F8),
                    numColor: const Color(0xFF2D5BE3),
                    icon: Icons.add_circle_outline,
                    title: 'Aufgabe hinzufügen',
                    subtitle: 'Auch: Trage · Ergänze · Neue Aufgabe: · Todo:',
                    templateSegments: const [
                      _Seg('Füge die Aufgabe', _SegType.cmd),
                      _Seg('Titel', _SegType.task),
                      _Seg('hinzu', _SegType.cmd),
                    ],
                    examples: const [
                      _Example(
                        input: '„Füge die Aufgabe Marcel schreiben hinzu"',
                        taskBadge: 'Marcel schreiben',
                      ),
                    ],
                    deadlineLabel: 'Mit Frist oder Uhrzeit',
                    deadlineTemplates: const [
                      [
                        _Seg('Füge die Aufgabe', _SegType.cmd),
                        _Seg('Titel', _SegType.task),
                        _Seg('für', _SegType.kw),
                        _Seg('Datum · Uhrzeit', _SegType.date),
                        _Seg('hinzu', _SegType.cmd),
                      ],
                      [
                        _Seg('Füge die Aufgabe', _SegType.cmd),
                        _Seg('Titel', _SegType.task),
                        _Seg('mit Frist', _SegType.kw),
                        _Seg('Datum · Uhrzeit', _SegType.date),
                        _Seg('hinzu', _SegType.cmd),
                      ],
                    ],
                    deadlineExamples: const [
                      _Example(
                        input: '„Füge die Aufgabe Dienstplan erstellen für morgen hinzu"',
                        taskBadge: 'Dienstplan erstellen',
                        dateBadge: 'morgen',
                      ),
                      _Example(
                        input: '„Füge die Aufgabe Dienstplan erstellen für morgen 9 Uhr hinzu"',
                        taskBadge: 'Dienstplan erstellen',
                        dateBadge: 'morgen · 09:00',
                        dateIsTime: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Muster 2 ─────────────────────────────────────────────
                  _PatternCard(
                    skin: skin,
                    number: '2',
                    numBg: const Color(0xFFEAF8F2),
                    numBorder: const Color(0xFF7DD4B0),
                    numColor: const Color(0xFF0D6E4F),
                    icon: Icons.notifications_outlined,
                    title: 'Erinnere mich',
                    subtitle: 'Auch: Bitte erinnere · Kannst du mich … erinnern',
                    templateSegments: const [
                      _Seg('Erinnere mich', _SegType.cmd),
                      _Seg('Datum · Uhrzeit', _SegType.date),
                      _Seg('an:', _SegType.cmd),
                      _Seg('Titel', _SegType.task),
                    ],
                    examples: const [
                      _Example(
                        input: '„Erinnere mich an: Auto waschen"',
                        taskBadge: 'Auto waschen',
                      ),
                      _Example(
                        input: '„Erinnere mich morgen 9 Uhr an: Auto waschen"',
                        taskBadge: 'Auto waschen',
                        dateBadge: 'morgen · 09:00',
                        dateIsTime: true,
                      ),
                    ],
                    deadlineLabel: 'Mehr Datums-Varianten',
                    deadlineTemplates: const [],
                    deadlineExamples: const [
                      _Example(
                        input: '„Erinnere mich am Freitag an: Reisepass"',
                        taskBadge: 'Reisepass',
                        dateBadge: 'Freitag',
                      ),
                      _Example(
                        input: '„Kannst du mich am 15. März an: Zahnarzt erinnern"',
                        taskBadge: 'Zahnarzt',
                        dateBadge: '15.03.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Außerdem erkannt ──────────────────────────────────────
                  _SectionLabel(label: 'AUSSERDEM ERKANNT', skin: skin),
                  const SizedBox(height: 6),

                  // ── Natürliche Sprache ────────────────────────────────────
                  _NaturalCard(skin: skin),
                  const SizedBox(height: 8),

                  // ── Dringend ──────────────────────────────────────────────
                  _UrgentCard(skin: skin),
                  const SizedBox(height: 14),

                  // ── Datum & Uhrzeit Referenz ──────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _DateRefCard(skin: skin)),
                      const SizedBox(width: 8),
                      Expanded(child: _TimeRefCard(skin: skin)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Tipp ──────────────────────────────────────────────────
                  _TipCard(skin: skin),
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
// LERN-BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _LearnBanner extends StatelessWidget {
  final AppSkin skin;
  const _LearnBanner({required this.skin});

  static const _green = Color(0xFF3DD68C);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: skin.isLight ? 0.07 : 0.11),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _green.withValues(alpha: 0.30)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _green.withValues(alpha: 0.28)),
                ),
                child: const Center(
                  child: Icon(Icons.auto_awesome_rounded, size: 16, color: _green),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lernt automatisch dazu',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _green,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nicht erkannte Sätze werden analysiert — die App lernt deine Formulierungen mit der Zeit.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _green.withValues(alpha: 0.80),
                        height: 1.4,
                      ),
                    ),
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
// ADMIN CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AdminCard extends StatelessWidget {
  final AppSkin skin;
  const _AdminCard({required this.skin});

  static const _purple = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _purple.withValues(alpha: skin.isLight ? 0.07 : 0.11),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _purple.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.admin_panel_settings_outlined, size: 16, color: _purple),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Admin-Tools',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _AdminLink(
                      skin: skin,
                      icon: Icons.bar_chart_rounded,
                      label: 'Sprach-Log',
                      onTap: () => Navigator.push(context,
                          CupertinoPageRoute(builder: (_) => const SpeechLogScreen())),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AdminLink(
                      skin: skin,
                      icon: Icons.auto_awesome_outlined,
                      label: 'Sprach-Analyse',
                      onTap: () => Navigator.push(context,
                          CupertinoPageRoute(builder: (_) => const AdminRulesScreen())),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminLink extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AdminLink({required this.skin, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: skin.primary),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: skin.textPrimary)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _SectionLabel({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: skin.surface(0.38), letterSpacing: 0.9),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEGMENT-TYPEN
// ─────────────────────────────────────────────────────────────────────────────

enum _SegType { cmd, task, date, kw }

class _Seg {
  final String text;
  final _SegType type;
  const _Seg(this.text, this.type);
}

class _Example {
  final String input;
  final String taskBadge;
  final String? dateBadge;
  final bool dateIsTime;
  const _Example({
    required this.input,
    required this.taskBadge,
    this.dateBadge,
    this.dateIsTime = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PATTERN CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PatternCard extends StatefulWidget {
  final AppSkin skin;
  final String number;
  final Color numBg, numBorder, numColor;
  final IconData icon;
  final String title, subtitle;
  final List<_Seg> templateSegments;
  final List<_Example> examples;
  final String deadlineLabel;
  final List<List<_Seg>> deadlineTemplates;
  final List<_Example> deadlineExamples;

  const _PatternCard({
    required this.skin,
    required this.number,
    required this.numBg,
    required this.numBorder,
    required this.numColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.templateSegments,
    required this.examples,
    required this.deadlineLabel,
    required this.deadlineTemplates,
    required this.deadlineExamples,
  });

  @override
  State<_PatternCard> createState() => _PatternCardState();
}

class _PatternCardState extends State<_PatternCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 0),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: widget.numBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: widget.numBorder),
                      ),
                      child: Center(
                        child: Text(widget.number,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: widget.numColor)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(widget.icon, size: 13, color: widget.numColor),
                              const SizedBox(width: 5),
                              Text(widget.title,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(widget.subtitle,
                              style: TextStyle(fontSize: 11, color: skin.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Template
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: widget.templateSegments.map((s) => _SegChip(seg: s, skin: skin)).toList(),
                ),
              ),
              // Divider + Beispiele
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
                child: Container(height: 0.5, color: skin.surface(0.10)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
                child: Text('BEISPIELE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: skin.surface(0.32), letterSpacing: 1.0)),
              ),
              ...widget.examples.map((e) => _ExampleRow(ex: e, skin: skin)),
              const SizedBox(height: 4),
              // Aufklappbar: Frist/Datum-Varianten
              GestureDetector(
                onTap: () => setState(() => _open = !_open),
                child: Container(
                  color: skin.isLight ? Colors.black.withValues(alpha: 0.025) : Colors.white.withValues(alpha: 0.04),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 13, color: _open ? widget.numColor : skin.surface(0.38)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.deadlineLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _open ? widget.numColor : skin.surface(0.45),
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: skin.surface(0.35)),
                      ),
                    ],
                  ),
                ),
              ),
              if (_open) ...[
                Container(height: 0.5, color: skin.surface(0.08)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...widget.deadlineTemplates.map((segs) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: segs.map((s) => _SegChip(seg: s, skin: skin)).toList(),
                            ),
                          )),
                      if (widget.deadlineTemplates.isNotEmpty) const SizedBox(height: 4),
                      Text('BEISPIELE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: skin.surface(0.32), letterSpacing: 1.0)),
                    ],
                  ),
                ),
                ...widget.deadlineExamples.map((e) => _ExampleRow(ex: e, skin: skin)),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEGMENT CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _SegChip extends StatelessWidget {
  final _Seg seg;
  final AppSkin skin;
  const _SegChip({required this.seg, required this.skin});

  @override
  Widget build(BuildContext context) {
    Color bg, border, text;
    bool italic = false;

    switch (seg.type) {
      case _SegType.cmd:
        bg = skin.isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.08);
        border = skin.surface(0.12);
        text = skin.textPrimary;
        break;
      case _SegType.task:
        bg = const Color(0xFFEEF3FF);
        border = const Color(0xFFA5B8F8);
        text = const Color(0xFF2D5BE3);
        italic = true;
        break;
      case _SegType.date:
        bg = const Color(0xFFEAF8F2);
        border = const Color(0xFF7DD4B0);
        text = const Color(0xFF0D6E4F);
        italic = true;
        break;
      case _SegType.kw:
        bg = const Color(0xFFFFF7EA);
        border = const Color(0xFFF5C97A);
        text = const Color(0xFF8A5C00);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        seg.text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: text,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXAMPLE ROW
// ─────────────────────────────────────────────────────────────────────────────

class _ExampleRow extends StatelessWidget {
  final _Example ex;
  final AppSkin skin;
  const _ExampleRow({required this.ex, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 6, 13, 0),
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
                  ex.input,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: skin.textPrimary.withValues(alpha: 0.70),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded, size: 10, color: skin.primary.withValues(alpha: 0.45)),
                    const SizedBox(width: 5),
                    _TaskBadge(label: ex.taskBadge, skin: skin),
                    if (ex.dateBadge != null) ...[
                      const SizedBox(width: 5),
                      _DateBadge(label: ex.dateBadge!, isTime: ex.dateIsTime, skin: skin),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskBadge extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _TaskBadge({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FF),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFA5B8F8), width: 0.8),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF2D5BE3))),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final String label;
  final bool isTime;
  final AppSkin skin;
  const _DateBadge({required this.label, required this.isTime, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8F2),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF7DD4B0), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isTime ? Icons.schedule_outlined : Icons.calendar_today_outlined,
              size: 10, color: const Color(0xFF0D6E4F)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0D6E4F))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NATÜRLICHE SPRACHE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _NaturalCard extends StatelessWidget {
  final AppSkin skin;
  const _NaturalCard({required this.skin});

  static const _examples = [
    'Ich muss noch Zahnarzt anrufen',
    'Nicht vergessen: Reisepass verlängern',
    'Ruf morgen Marcel an',
    'Morgen früh Auto waschen',
    'Ich sollte noch Angebot schreiben',
    'Denk daran nächste Woche einkaufen',
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 8),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3DD68C).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF3DD68C).withValues(alpha: 0.28)),
                      ),
                      child: const Center(
                        child: Icon(Icons.auto_fix_high_outlined, size: 13, color: Color(0xFF3DD68C)),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text('Natürliche Sprache',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3DD68C).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF3DD68C).withValues(alpha: 0.28)),
                      ),
                      child: const Text('LERNEND',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700,
                              color: Color(0xFF3DD68C), letterSpacing: 0.7)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 4),
                child: Text(
                  'Einfach so sprechen — die App erkennt und lernt.',
                  style: TextStyle(fontSize: 11.5, color: skin.textMuted),
                ),
              ),
              Container(height: 0.5, color: skin.surface(0.08)),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 8, 13, 10),
                child: Column(
                  children: _examples.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.30)),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text('„$e"',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: skin.textPrimary.withValues(alpha: 0.68))),
                            ),
                          ],
                        ),
                      )).toList(),
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
// DRINGEND CARD
// ─────────────────────────────────────────────────────────────────────────────

class _UrgentCard extends StatelessWidget {
  final AppSkin skin;
  const _UrgentCard({required this.skin});

  static const _red = Color(0xFFEF5B5B);
  static const _examples = [
    'Dringend: Reisepass verlängern',
    'Erinnere mich dringend an: Arzttermin',
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: skin.isLight ? 0.06 : 0.10),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: _red.withValues(alpha: 0.18), width: 0.5)),
                ),
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
                child: Row(
                  children: [
                    Icon(Icons.priority_high_rounded, size: 15, color: _red),
                    const SizedBox(width: 7),
                    Text('Dringend',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _red)),
                    const SizedBox(width: 6),
                    Text('— überall im Satz erkannt',
                        style: TextStyle(fontSize: 11, color: _red.withValues(alpha: 0.70))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 8, 13, 10),
                child: Column(
                  children: _examples.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.30)),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text('„$e"',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: skin.textPrimary.withValues(alpha: 0.68))),
                            ),
                          ],
                        ),
                      )).toList(),
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
// DATUM REFERENZ CARD
// ─────────────────────────────────────────────────────────────────────────────

class _DateRefCard extends StatelessWidget {
  final AppSkin skin;
  const _DateRefCard({required this.skin});

  @override
  Widget build(BuildContext context) {
    return _RefCard(
      skin: skin,
      icon: Icons.calendar_today_outlined,
      title: 'Datum',
      groups: const [
        _RefGroup('Relativ', ['heute', 'morgen', 'übermorgen', 'nächste Woche', 'übernächste Woche', 'Monatsende']),
        _RefGroup('Wochentag', ['Mo–So', 'nächsten Di', 'übernächsten Fr']),
        _RefGroup('Exakt', ['23.10.', '15. März', '15.3.2026']),
        _RefGroup('Abstand', ['in 3 Tagen', 'in 2 Wochen', 'in 1 Monat']),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UHRZEIT REFERENZ CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TimeRefCard extends StatelessWidget {
  final AppSkin skin;
  const _TimeRefCard({required this.skin});

  @override
  Widget build(BuildContext context) {
    return _RefCard(
      skin: skin,
      icon: Icons.schedule_outlined,
      title: 'Uhrzeit',
      groups: const [
        _RefGroup('Standard', ['15 Uhr', '15:30 Uhr', 'um 9', 'gegen 14']),
        _RefGroup('Umgangsspr.', ['halb drei', 'viertel nach 9', 'viertel vor 10', 'dreiviertel 10']),
        _RefGroup('Benannt', ['morgens→08:00', 'mittags→12:00', 'abends→19:00', 'nachts→22:00']),
      ],
    );
  }
}

class _RefGroup {
  final String label;
  final List<String> items;
  const _RefGroup(this.label, this.items);
}

class _RefCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String title;
  final List<_RefGroup> groups;
  const _RefCard({required this.skin, required this.icon, required this.title, required this.groups});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.all(12),
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
              Row(
                children: [
                  Icon(icon, size: 13, color: skin.primary.withValues(alpha: 0.70)),
                  const SizedBox(width: 6),
                  Text(title,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                ],
              ),
              const SizedBox(height: 9),
              ...groups.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.label,
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: skin.surface(0.35),
                                letterSpacing: 0.3)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: g.items.map((item) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: skin.surface(0.05),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: skin.glassBorder, width: 0.7),
                                ),
                                child: Text(item,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: skin.textMuted,
                                        fontWeight: FontWeight.w500)),
                              )).toList(),
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

// ─────────────────────────────────────────────────────────────────────────────
// TIPP CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TipCard extends StatelessWidget {
  final AppSkin skin;
  const _TipCard({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: skin.surface(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.surface(0.10), width: 0.7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 14, color: skin.surface(0.40)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Einfach sprechen wie mit einem Assistenten — je öfter du diktierst, desto besser lernt die App deine Formulierungen.',
              style: TextStyle(fontSize: 12, color: skin.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}