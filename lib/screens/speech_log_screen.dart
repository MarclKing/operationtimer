import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_dialogs.dart';
import '../services/speech_log.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // Nur EIN Eintrag darf gleichzeitig "aufgeschoben" (geöffnet) sein.
  // Identifiziert über den Millisekunden-Zeitstempel des Eintrags, weil das
  // innerhalb des Logs eindeutig ist. Tippt man irgendwo anders hin, wird
  // dieser Wert auf null gesetzt und alle Karten schließen sich automatisch.
  int? _openSwipedKey;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _closeOpenSwipe() {
    if (_openSwipedKey != null) setState(() => _openSwipedKey = null);
  }

  void _reload() {
    setState(() {
      _entries = SpeechLog.loadAll();
      _stats = SpeechLog.stats();
    });
  }

  void _clearLog(AppSkin skin) async {
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Log leeren?',
      message: 'Alle ${SpeechLog.loadAll().length} Einträge werden unwiderruflich gelöscht.',
      confirmLabel: 'Leeren',
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
        child: GestureDetector(
          // Globaler Schließen-Layer: Tippt man irgendwo hin, das NICHT von
          // einer Karte selbst behandelt wird (z.B. Header, Statistik-Kacheln,
          // Filter-Leiste, Leerraum), schließt sich ein offener Slider.
          // translucent sorgt dafür, dass Taps trotzdem an Kinder weitergehen.
          behavior: HitTestBehavior.translucent,
          onTap: _closeOpenSwipe,
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
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
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
                      color: skin.statEntries,
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      skin: skin,
                      label: 'Vollständig',
                      value: '${_stats['fullSuccess'] ?? 0}',
                      color: skin.statComplete,
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      skin: skin,
                      label: 'Kein Datum',
                      value: '${_stats['noDate'] ?? 0}',
                      color: skin.statOpen,
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      skin: skin,
                      label: 'Nicht erk.',
                      value: '${_stats['normalizerMiss'] ?? 0}',
                      color: skin.deleteColor,
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
                    GlassChip(
                      label: 'Alle',
                      active: _filter == _LogFilter.all,
                      onTap: () => setState(() => _filter = _LogFilter.all),
                    ),
                    const SizedBox(width: 6),
                    GlassChip(
                      label: 'Nicht erkannt',
                      active: _filter == _LogFilter.missed,
                      color: skin.deleteColor,
                      icon: Icons.close_rounded,
                      showIconWhenInactive: true,
                      onTap: () => setState(() => _filter = _LogFilter.missed),
                    ),
                    const SizedBox(width: 6),
                    GlassChip(
                      label: 'Kein Datum',
                      active: _filter == _LogFilter.noDate,
                      color: skin.statOpen,
                      icon: Icons.remove_rounded,
                      showIconWhenInactive: true,
                      onTap: () => setState(() => _filter = _LogFilter.noDate),
                    ),
                    const SizedBox(width: 6),
                    GlassChip(
                      label: 'Vollständig',
                      active: _filter == _LogFilter.success,
                      color: skin.statComplete,
                      icon: Icons.check_rounded,
                      showIconWhenInactive: true,
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
                          Icon(Icons.mic_none_rounded,
                              size: 46, color: skin.surface(0.18)),
                          const SizedBox(height: 12),
                          Text(
                            'Noch keine Einträge',
                            style: TextStyle(
                                color: skin.surface(0.3), fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Benutze die Diktierfunktion um\nEinträge zu erzeugen',
                            style:
                                TextStyle(color: skin.surface(0.22), fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Einträge für diesen Filter',
                            style:
                                TextStyle(color: skin.surface(0.3), fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final entry = filtered[i];
                            final entryKey = entry.timestamp.millisecondsSinceEpoch.toString();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LogEntryCard(
                                skin: skin,
                                entry: entry,
                                externallyOpen: _openSwipedKey?.toString(),
                                onSwiped: (opened) => setState(
                                    () => _openSwipedKey = opened ? int.parse(entryKey) : null),
                                onDeleted: _reload,
                              ),
                            );
                          },
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
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: skin.isLight ? 0.07 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.7)),
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
// Log-Eintrag-Karte
// ─────────────────────────────────────────────────────────────────────────────

class _LogEntryCard extends StatefulWidget {
  final AppSkin skin;
  final SpeechLogEntry entry;
  final String? externallyOpen;
  final void Function(bool opened) onSwiped;
  final VoidCallback onDeleted;

  const _LogEntryCard({
    required this.skin,
    required this.entry,
    required this.externallyOpen,
    required this.onSwiped,
    required this.onDeleted,
  });

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _expanded = false;

  Color get _statusColor {
    final skin = widget.skin;
    if (widget.entry.isFullSuccess) return skin.statComplete;
    if (widget.entry.normalizerHit && !widget.entry.hasDate) return skin.statOpen;
    return skin.deleteColor;
  }

  void _performDelete() {
    _deleteFromFirestore(widget.entry.firestoreId);
    SpeechLog.deleteEntry(widget.entry);
    widget.onDeleted();
  }

  Future<void> _deleteFromFirestore(String? firestoreId) async {
    if (firestoreId == null || firestoreId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('speech_logs')
          .doc(firestoreId)
          .delete();
    } catch (e) {
      debugPrint('SpeechLog: Firestore-Sync-Delete fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final entry = widget.entry;
    final color = _statusColor;
    final timeStr = DateFormat('dd.MM. HH:mm').format(entry.timestamp);
    final normalizerChanged = entry.rawText != entry.normalized;

    return GlassSwipeCard(
      cardKey: entry.timestamp.millisecondsSinceEpoch.toString(),
      externallyOpen: widget.externallyOpen,
      onDelete: () {}, // wird bei animateDelete+onDeleteAnimationDone nicht aufgerufen, aber Parameter ist required-kompatibel
      animateDelete: true,
      onDeleteAnimationDone: _performDelete,
      onTap: () => setState(() => _expanded = !_expanded),
      onCardSwiped: (openedKey) => widget.onSwiped(openedKey != null),
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
              boxShadow: [
                BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.28)),
                    ),
                    child: Text(entry.statusLabel,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
                  ),
                  const Spacer(),
                  Text(timeStr, style: TextStyle(fontSize: 11, color: skin.surface(0.35))),
                  const SizedBox(width: 6),
                  Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: skin.surface(0.3)),
                ]),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mic_none_rounded, size: 12, color: skin.surface(0.35)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('"${entry.rawText}"',
                            style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: skin.textPrimary.withValues(alpha: 0.85),
                                height: 1.35),
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis)),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Container(height: 0.5, color: skin.surface(0.10)),
                  const SizedBox(height: 10),
                  if (normalizerChanged)
                    _DetailRow(
                        skin: skin,
                        icon: Icons.auto_fix_high_outlined,
                        label: 'Normalizer',
                        value: entry.normalized,
                        valueColor: skin.primary)
                  else
                    _DetailRow(
                        skin: skin,
                        icon: Icons.auto_fix_off_outlined,
                        label: 'Normalizer',
                        value: 'Kein Muster erkannt',
                        valueColor: skin.deleteColor),
                  const SizedBox(height: 6),
                  _DetailRow(
                      skin: skin,
                      icon: Icons.task_alt_outlined,
                      label: 'Titel',
                      value: entry.parsedTitle,
                      valueColor: skin.textPrimary),
                  const SizedBox(height: 6),
                  _DetailRow(
                      skin: skin,
                      icon: Icons.calendar_today_outlined,
                      label: 'Datum',
                      value: entry.hasDate ? 'Erkannt' : 'Nicht erkannt',
                      valueColor: entry.hasDate ? skin.statComplete : skin.deleteColor),
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