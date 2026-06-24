import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';
import '../screens/speech_log_screen.dart';
import '../screens/admin_rules_screen.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DICTATION HELP SCREEN v6
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
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 44, height: 44,
                      child: Center(child: Icon(Icons.arrow_back_ios_new, size: 18)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sprachbefehle',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                                color: skin.textPrimary, letterSpacing: -0.5)),
                        Text('Muster · Datum · Dringend · Selbstlernend',
                            style: TextStyle(fontSize: 12, color: skin.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [

                  // ── LERN-BANNER — groß, satt grün, Hauptfeature ──────────
                  _LearnBanner(skin: skin),
                  const SizedBox(height: 12),

                  // ── Tools-Zeile ───────────────────────────────────────────
                  _ToolsRow(skin: skin),
                  const SizedBox(height: 14),

                  // ── Muster 1 ─────────────────────────────────────────────
                  _PatternCard(
                    skin: skin,
                    number: '1',
                    accentColor: const Color(0xFF2D6CFF),
                    icon: Icons.sync_rounded,
                    iconLabel: 'AUFGABE HINZUFÜGEN',
                    subtitle: 'Statt „Füge die Aufgabe" auch: Trage · Ergänze · Neue Aufgabe: · Todo:',
                    templateSegments: const [
                      _Seg('Füge die Aufgabe', _SegType.cmd),
                      _Seg('Titel', _SegType.task),
                      _Seg('hinzu', _SegType.cmd),
                    ],
                    examples: const [
                      _Example(input: '„Füge die Aufgabe Marcel schreiben hinzu"', taskBadge: 'Marcel schreiben'),
                      _Example(input: '„Füge die Aufgabe Dienstplan erstellen hinzu"', taskBadge: 'Dienstplan erstellen'),
                      _Example(input: '„Neue Aufgabe: Auto Liste"', taskBadge: 'Auto Liste'),
                    ],
                    deadlineLabel: 'Mit Frist / Datum',
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
                        taskBadge: 'Dienstplan erstellen', dateBadge: 'morgen',
                      ),
                      _Example(
                        input: '„… für morgen 9 Uhr hinzu"',
                        taskBadge: 'Dienstplan erstellen', dateBadge: 'morgen · 09:00', dateIsTime: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Muster 2 ─────────────────────────────────────────────
                  _PatternCard(
                    skin: skin,
                    number: '2',
                    accentColor: const Color(0xFF3DD68C),
                    icon: Icons.notifications_outlined,
                    iconLabel: 'ERINNERE MICH',
                    subtitle: 'Auch: Bitte erinnere · Kannst du mich … erinnern',
                    templateSegments: const [
                      _Seg('Erinnere mich', _SegType.cmd),
                      _Seg('Datum · Uhrzeit', _SegType.date),
                      _Seg('an:', _SegType.cmd),
                      _Seg('Titel', _SegType.task),
                    ],
                    examples: const [
                      _Example(input: '„Erinnere mich an: Auto waschen"', taskBadge: 'Auto waschen'),
                      _Example(input: '„Erinnere mich an: Meeting mit Sarah"', taskBadge: 'Meeting mit Sarah'),
                    ],
                    deadlineLabel: 'Mit Frist / Datum',
                    deadlineTemplates: const [],
                    deadlineExamples: const [
                      _Example(
                        input: '„Erinnere mich morgen 9 Uhr an: Auto waschen"',
                        taskBadge: 'Auto waschen', dateBadge: 'morgen · 09:00', dateIsTime: true,
                      ),
                      _Example(
                        input: '„Kannst du mich am 15. März an: Zahnarzt erinnern"',
                        taskBadge: 'Zahnarzt', dateBadge: '15.03.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Muster 3: Natürliche Sprache ─────────────────────────
                  _NaturalCard(skin: skin),
                  const SizedBox(height: 8),

                  // ── Dringend ─────────────────────────────────────────────
                  _UrgentCard(skin: skin),
                  const SizedBox(height: 14),

                  // ── Datum & Zeit Referenz ─────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _DateRefCard(skin: skin)),
                      const SizedBox(width: 8),
                      Expanded(child: _TimeRefCard(skin: skin)),
                    ],
                  ),
                  const SizedBox(height: 10),

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
// LERN-BANNER — satt grün, Hauptfeature, exakt wie altes Design
// ─────────────────────────────────────────────────────────────────────────────

class _LearnBanner extends StatelessWidget {
  final AppSkin skin;
  const _LearnBanner({required this.skin});

  static const _green = Color(0xFF2A9D5C);
static const _greenDark = Color(0xFF1E7A45);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A9D5C), Color(0xFF1A7A42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header-Zeile ──
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
                  ),
                  child: const Center(
                    child: Icon(Icons.auto_awesome_rounded, size: 17, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Lernt automatisch dazu',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Spracherkennung passt sich an dich an',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.82))),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 11),
            Container(height: 0.8, color: Colors.white.withValues(alpha: 0.22)),
            const SizedBox(height: 11),

            // ── Beschreibungstext ──
            const Text(
              'Nicht erkannte Sätze werden analysiert — so lernt die App deine Ausdrucksweise und erkennt sie beim nächsten Mal direkt.',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white, height: 1.45,
              ),
            ),

            const SizedBox(height: 12),

            // ── Drei grüne Chips wie im Bild ──
            Row(
              children: [
                _GreenChip(icon: Icons.mic_none_rounded, label: 'Einfach diktieren'),
                const SizedBox(width: 7),
                _GreenChip(icon: Icons.psychology_outlined, label: 'App lernt'),
                const SizedBox(width: 7),
                _GreenChip(icon: Icons.check_rounded, label: 'Wird besser'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GreenChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GreenChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOOLS ROW — Speech Log immer, Admin Rules nur für Admins
// ─────────────────────────────────────────────────────────────────────────────

class _ToolsRow extends StatelessWidget {
  final AppSkin skin;
  const _ToolsRow({required this.skin});

  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService.instance.isAdmin;

    return Row(
      children: [
        Expanded(
          child: _ToolTile(
            skin: skin,
            icon: Icons.bar_chart_rounded,
            label: 'Sprach-Log',
            color: skin.primary,
            onTap: () => Navigator.push(context,
                CupertinoPageRoute(builder: (_) => const SpeechLogScreen())),
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _ToolTile(
              skin: skin,
              icon: Icons.auto_awesome_outlined,
              label: 'Sprach-Analyse',
              color: const Color(0xFF8B5CF6),
              onTap: () => Navigator.push(context,
                  CupertinoPageRoute(builder: (_) => const AdminRulesScreen())),
            ),
          ),
        ],
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ToolTile({required this.skin, required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
            decoration: BoxDecoration(
              color: color.withValues(alpha: skin.isLight ? 0.10 : 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: color.withValues(alpha: 0.60)),
              ],
            ),
          ),
        ),
      ),
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
  const _Example({required this.input, required this.taskBadge,
      this.dateBadge, this.dateIsTime = false});
}

// ─────────────────────────────────────────────────────────────────────────────
// PATTERN CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PatternCard extends StatefulWidget {
  final AppSkin skin;
  final String number;
  final Color accentColor;
  final IconData icon;
  final String iconLabel, subtitle;
  final List<_Seg> templateSegments;
  final List<_Example> examples;
  final String deadlineLabel;
  final List<List<_Seg>> deadlineTemplates;
  final List<_Example> deadlineExamples;

  const _PatternCard({
    required this.skin, required this.number, required this.accentColor,
    required this.icon, required this.iconLabel, required this.subtitle,
    required this.templateSegments, required this.examples,
    required this.deadlineLabel, required this.deadlineTemplates,
    required this.deadlineExamples,
  });

  @override
  State<_PatternCard> createState() => _PatternCardState();
}

class _PatternCardState extends State<_PatternCard> {
  bool _open = false;
  AppSkin get skin => widget.skin;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;

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
              // ── Farbige Header-Leiste ──
              Container(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: skin.isLight ? 0.08 : 0.12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.20))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: accent.withValues(alpha: 0.45)),
                      ),
                      child: Center(
                        child: Text(widget.number,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(widget.icon, size: 13, color: accent),
                    const SizedBox(width: 5),
                    Text(widget.iconLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: accent, letterSpacing: 0.4)),
                  ],
                ),
              ),

              // ── Template Chips ──
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
                child: Wrap(
                  spacing: 4, runSpacing: 4,
                  children: widget.templateSegments.map((s) => _SegChip(seg: s, skin: skin)).toList(),
                ),
              ),

              // ── Subtitle ──
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 5, 13, 0),
                child: Text(widget.subtitle,
                    style: TextStyle(fontSize: 11, color: skin.textMuted)),
              ),

              // ── Divider + Beispiele ──
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 0),
                child: Container(height: 0.5, color: skin.surface(0.10)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 7, 13, 0),
                child: Text('BEISPIELE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: skin.surface(0.32), letterSpacing: 1.0)),
              ),
              ...widget.examples.map((e) => _ExampleRow(ex: e, skin: skin)),
              const SizedBox(height: 4),

              // ── Aufklappbar ──
              GestureDetector(
                onTap: () => setState(() => _open = !_open),
                child: Container(
                  color: skin.isLight
                      ? Colors.black.withValues(alpha: 0.025)
                      : Colors.white.withValues(alpha: 0.04),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 13,
                          color: _open ? accent : skin.surface(0.38)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(widget.deadlineLabel,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                                color: _open ? accent : skin.surface(0.45))),
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
                            child: Wrap(spacing: 4, runSpacing: 4,
                                children: segs.map((s) => _SegChip(seg: s, skin: skin)).toList()),
                          )),
                      if (widget.deadlineTemplates.isNotEmpty) const SizedBox(height: 4),
                      Text('BEISPIELE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                              color: skin.surface(0.32), letterSpacing: 1.0)),
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
        // Dunkle Chip wie im alten Design
        bg = skin.isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.12);
        border = skin.surface(0.18);
        text = skin.textPrimary;
        break;
      case _SegType.task:
        bg = const Color(0xFF2D6CFF).withValues(alpha: 0.18);
        border = const Color(0xFF2D6CFF).withValues(alpha: 0.55);
        text = skin.isLight ? const Color(0xFF1746B8) : const Color(0xFF7AAEFF);
        italic = true;
        break;
      case _SegType.date:
        bg = const Color(0xFF3DD68C).withValues(alpha: 0.15);
        border = const Color(0xFF3DD68C).withValues(alpha: 0.50);
        text = skin.isLight ? const Color(0xFF0D6E4F) : const Color(0xFF3DD68C);
        italic = true;
        break;
      case _SegType.kw:
        bg = const Color(0xFFFFB347).withValues(alpha: 0.15);
        border = const Color(0xFFFFB347).withValues(alpha: 0.50);
        text = skin.isLight ? const Color(0xFF8A5C00) : const Color(0xFFFFB347);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.9),
      ),
      child: Text(seg.text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
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
                Text(ex.input,
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic,
                        color: skin.textPrimary.withValues(alpha: 0.70), height: 1.35)),
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
        color: const Color(0xFF2D6CFF).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF2D6CFF).withValues(alpha: 0.50), width: 0.9),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
              color: skin.isLight ? const Color(0xFF1746B8) : const Color(0xFF7AAEFF))),
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
        color: const Color(0xFF3DD68C).withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF3DD68C).withValues(alpha: 0.45), width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isTime ? Icons.schedule_outlined : Icons.calendar_today_outlined,
              size: 10, color: const Color(0xFF3DD68C)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3DD68C))),
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

  static const _green = Color(0xFF3DD68C);
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
              // Header mit grünem Akzent
              Container(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: skin.isLight ? 0.07 : 0.10),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: _green.withValues(alpha: 0.20))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _green.withValues(alpha: 0.45)),
                      ),
                      child: const Center(
                        child: Text('3',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _green)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.auto_fix_high_outlined, size: 13, color: _green),
                    const SizedBox(width: 5),
                    Text('NATÜRLICHE SPRACHE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: _green, letterSpacing: 0.4)),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _green.withValues(alpha: 0.40)),
                      ),
                      child: const Text('LERNEND',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700,
                              color: _green, letterSpacing: 0.7)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 0),
                child: Text(
                  'Formulierungen die nicht Muster 1 oder 2 entsprechen, werden automatisch analysiert und der App beigebracht. Einfach natürlich sprechen — die Erkennung verbessert sich mit der Zeit.',
                  style: TextStyle(fontSize: 11.5, color: skin.textMuted, height: 1.4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 0),
                child: Container(height: 0.5, color: skin.surface(0.10)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 7, 13, 0),
                child: Text('WIRD AUTOMATISCH ERKANNT',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: skin.surface(0.32), letterSpacing: 1.0)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 6, 13, 10),
                child: Column(
                  children: _examples.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.30)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text('„$e"',
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic,
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
                  color: _red.withValues(alpha: skin.isLight ? 0.07 : 0.12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: _red.withValues(alpha: 0.22), width: 0.5)),
                ),
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
                child: Row(
                  children: [
                    Icon(Icons.priority_high_rounded, size: 15, color: _red),
                    const SizedBox(width: 7),
                    const Text('Dringend',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _red)),
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
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic,
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
// DATUM & UHRZEIT REFERENZ
// ─────────────────────────────────────────────────────────────────────────────

class _DateRefCard extends StatelessWidget {
  final AppSkin skin;
  const _DateRefCard({required this.skin});

  @override
  Widget build(BuildContext context) => _RefCard(
    skin: skin, icon: Icons.calendar_today_outlined, title: 'Datum',
    groups: const [
      _RefGroup('Relativ', ['heute', 'morgen', 'übermorgen', 'nächste Woche', 'Monatsende']),
      _RefGroup('Wochentag', ['Mo–So', 'nächsten Di', 'übernächsten Fr']),
      _RefGroup('Exakt', ['23.10.', '15. März', '15.3.2026']),
      _RefGroup('Abstand', ['in 3 Tagen', 'in 2 Wochen', 'in 1 Monat']),
    ],
  );
}

class _TimeRefCard extends StatelessWidget {
  final AppSkin skin;
  const _TimeRefCard({required this.skin});

  @override
  Widget build(BuildContext context) => _RefCard(
    skin: skin, icon: Icons.schedule_outlined, title: 'Uhrzeit',
    groups: const [
      _RefGroup('Standard', ['15 Uhr', '15:30 Uhr', 'um 9', 'gegen 14']),
      _RefGroup('Umgangsspr.', ['halb drei', 'viertel nach 9', 'viertel vor 10']),
      _RefGroup('Benannt', ['morgens→08:00', 'mittags→12:00', 'abends→19:00', 'nachts→22:00']),
    ],
  );
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
              Row(children: [
                Icon(icon, size: 13, color: skin.primary.withValues(alpha: 0.70)),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.textPrimary)),
              ]),
              const SizedBox(height: 9),
              ...groups.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                        color: skin.surface(0.35), letterSpacing: 0.3)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4, runSpacing: 4,
                      children: g.items.map((item) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: skin.surface(0.05),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: skin.glassBorder, width: 0.7),
                        ),
                        child: Text(item, style: TextStyle(fontSize: 10.5,
                            color: skin.textMuted, fontWeight: FontWeight.w500)),
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