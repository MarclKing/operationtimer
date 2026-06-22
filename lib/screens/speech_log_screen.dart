import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/speech_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SPEECH LOG SCREEN
//
// Zeigt alle gespeicherten Spracheingaben in einer Liste.
// Öffnet sich über den "Log anzeigen"-Button unten im DictationHelpScreen.
//
// Features:
//   - Statistik-Kacheln oben (Total / Erkannt / Kein Datum / Nicht erkannt)
//   - Filter-Chips: Alle / Nicht erkannt / Kein Datum / Vollständig
//   - Pro Eintrag: Raw-Text, was normalisiert wurde, Titel + Datum erkannt?
//   - Clear-Button oben rechts
// ─────────────────────────────────────────────────────────────────────────────

enum _LogFilter { all, missed, noDate, success }

class SpeechLogScreen extends StatefulWidget {
  const SpeechLogScreen({super.key});

  @override
  State<SpeechLogScreen> createState() => _SpeechLogScreenState();
}

class _SpeechLogScreenState extends State<SpeechLogScreen> {
  List<SpeechLogEntry> _entries = [];
  Map<String, int> _stats = {};
  _LogFilter _filter = _LogFilter.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _entries = SpeechLog.loadAll();
      _stats = SpeechLog.stats();
    });
  }

  void _clearLog(AppSkin skin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmClearDialog(skin: skin),
    );
    if (confirmed == true) {
      SpeechLog.clear();
      _reload();
    }
  }

  List<SpeechLogEntry> get _filtered {
    switch (_filter) {
      case _LogFilter.all:
        return _entries;
      case _LogFilter.missed:
        return _entries.where((e) => !e.normalizerHit).toList();
      case _LogFilter.noDate:
        return _entries.where((e) => e.normalizerHit && !e.hasDate).toList();
      case _LogFilter.success:
        return _entries.where((e) => e.isFullSuccess).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
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
                      'Sprach-Log',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: skin.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (_entries.isNotEmpty)
                    GestureDetector(
                      onTap: () => _clearLog(skin),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: skin.surface(0.12)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 14, color: skin.surface(0.45)),
                            const SizedBox(width: 5),
                            Text(
                              'Leeren',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: skin.surface(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 70, bottom: 16),
              child: Text(
                '${_entries.length} Einträge gespeichert',
                style: TextStyle(fontSize: 12.5, color: skin.textMuted),
              ),
            ),

            // ── Statistik-Kacheln ──
            if (_entries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Row(
                  children: [
                    _StatTile(
                      skin: skin,
                      label: 'Gesamt',
                      value: '${_stats['total'] ?? 0}',
                      color: skin.primary,
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      skin: skin,
                      label: 'Vollständig',
                      value: '${_stats['fullSuccess'] ?? 0}',
                      color: const Color(0xFF5BCB8F),
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      skin: skin,
                      label: 'Kein Datum',
                      value: '${_stats['noDate'] ?? 0}',
                      color: const Color(0xFFFFB347),
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      skin: skin,
                      label: 'Nicht erk.',
                      value: '${_stats['normalizerMiss'] ?? 0}',
                      color: const Color(0xFFEF5B5B),
                    ),
                  ],
                ),
              ),

              // ── Filter-Chips ──
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _FilterChip(
                      skin: skin,
                      label: 'Alle',
                      active: _filter == _LogFilter.all,
                      onTap: () => setState(() => _filter = _LogFilter.all),
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      skin: skin,
                      label: '✗ Nicht erkannt',
                      active: _filter == _LogFilter.missed,
                      color: const Color(0xFFEF5B5B),
                      onTap: () => setState(() => _filter = _LogFilter.missed),
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      skin: skin,
                      label: '~ Kein Datum',
                      active: _filter == _LogFilter.noDate,
                      color: const Color(0xFFFFB347),
                      onTap: () => setState(() => _filter = _LogFilter.noDate),
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      skin: skin,
                      label: '✓ Vollständig',
                      active: _filter == _LogFilter.success,
                      color: const Color(0xFF5BCB8F),
                      onTap: () => setState(() => _filter = _LogFilter.success),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Liste ──
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic_none_rounded, size: 46, color: skin.surface(0.18)),
                          const SizedBox(height: 12),
                          Text(
                            'Noch keine Einträge',
                            style: TextStyle(color: skin.surface(0.3), fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Benutze die Diktierfunktion um\nEinträge zu erzeugen',
                            style: TextStyle(color: skin.surface(0.22), fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Einträge für diesen Filter',
                            style: TextStyle(color: skin.surface(0.3), fontSize: 14),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _LogEntryCard(
                            skin: skin,
                            entry: filtered[i],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Statistik-Kachel
// ─────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.skin, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: skin.isLight ? 0.07 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.7)),
                  textAlign: TextAlign.center,
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
// Filter-Chip
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip({required this.skin, required this.label, required this.active, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? skin.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.14) : skin.surface(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? c.withValues(alpha: 0.45) : skin.surface(0.12),
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? c : skin.surface(0.45),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log-Eintrag-Karte
// ─────────────────────────────────────────────────────────────────────────────

class _LogEntryCard extends StatefulWidget {
  final AppSkin skin;
  final SpeechLogEntry entry;
  const _LogEntryCard({required this.skin, required this.entry});

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _expanded = false;

  Color get _statusColor {
    if (widget.entry.isFullSuccess) return const Color(0xFF5BCB8F);
    if (widget.entry.normalizerHit && !widget.entry.hasDate) return const Color(0xFFFFB347);
    return const Color(0xFFEF5B5B);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final entry = widget.entry;
    final color = _statusColor;
    final timeStr = DateFormat('dd.MM. HH:mm').format(entry.timestamp);
    final normalizerChanged = entry.rawText != entry.normalized;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _expanded ? color.withValues(alpha: 0.35) : skin.glassBorder,
                width: _expanded ? 1.3 : 1.0,
              ),
              boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Zeile 1: Status + Zeitstempel + Expand-Icon ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        entry.statusLabel,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeStr,
                      style: TextStyle(fontSize: 11, color: skin.surface(0.35)),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: skin.surface(0.3),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Zeile 2: Raw-Text ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.35)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '"${entry.rawText}"',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: skin.textPrimary.withValues(alpha: 0.85),
                          height: 1.35,
                        ),
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // ── Ausgeklappt: Details ──
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Container(height: 0.5, color: skin.surface(0.10)),
                  const SizedBox(height: 10),

                  // Normalizer-Ergebnis (nur wenn anders)
                  if (normalizerChanged) ...[
                    _DetailRow(
                      skin: skin,
                      icon: Icons.auto_fix_high_outlined,
                      label: 'Normalizer',
                      value: entry.normalized,
                      valueColor: skin.primary,
                    ),
                    const SizedBox(height: 6),
                  ] else ...[
                    _DetailRow(
                      skin: skin,
                      icon: Icons.auto_fix_off_outlined,
                      label: 'Normalizer',
                      value: 'Kein Muster erkannt — Original weitergegeben',
                      valueColor: const Color(0xFFEF5B5B),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Parser-Ergebnis: Titel
                  _DetailRow(
                    skin: skin,
                    icon: Icons.task_alt_outlined,
                    label: 'Titel',
                    value: entry.parsedTitle,
                    valueColor: skin.textPrimary,
                  ),
                  const SizedBox(height: 6),

                  // Parser-Ergebnis: Datum
                  _DetailRow(
                    skin: skin,
                    icon: Icons.calendar_today_outlined,
                    label: 'Datum',
                    value: entry.hasDate ? 'Erkannt' : 'Nicht erkannt',
                    valueColor: entry.hasDate ? const Color(0xFF5BCB8F) : const Color(0xFFEF5B5B),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  const _DetailRow({
    required this.skin,
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: skin.surface(0.35)),
        const SizedBox(width: 6),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.surface(0.38)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: valueColor, height: 1.35),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bestätigungs-Dialog zum Leeren des Logs
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmClearDialog extends StatelessWidget {
  final AppSkin skin;
  const _ConfirmClearDialog({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 36),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.94)
                    : skin.bgCard.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: skin.glassBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Log leeren?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: skin.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Alle ${SpeechLog.loadAll().length} Einträge werden unwiderruflich gelöscht.',
                    style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: skin.surface(0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: skin.surface(0.12)),
                            ),
                            child: Center(
                              child: Text('Abbrechen',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF5B5B).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEF5B5B).withValues(alpha: 0.35)),
                            ),
                            child: const Center(
                              child: Text('Leeren',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFEF5B5B))),
                            ),
                          ),
                        ),
                      ),
                    ],
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