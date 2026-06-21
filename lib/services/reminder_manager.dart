import 'package:hive_flutter/hive_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REMINDER OPTIONS MANAGER — analog zu FahrtTypManager in fahrtenbuch_screen.dart
//
// Zwei getrennte Options-Sets, da die Semantik unterschiedlich ist:
//   - OHNE Deadline: absolute Verzögerung ab "jetzt" ("Hinweisen in X")
//   - MIT Deadline:  relativer Vorlauf vor der Deadline ("X vorher")
//
// MRU (Most Recently/Frequently Used) wird GETRENNT pro Modus geführt,
// damit "1 Tag vorher" (Deadline-Modus) nicht die Sortierung von
// "in 1 Tag" (kein-Deadline-Modus) beeinflusst — beide haben zwar
// denselben Duration-Wert, aber unterschiedliche Bedeutung.
// ─────────────────────────────────────────────────────────────────────────────

enum ReminderMode { relative, beforeDeadline }

class ReminderOption {
  final String id; // stabiler Schlüssel für MRU-Speicherung, z. B. "1d", "2h"
  final String label; // Kurzlabel für Chips, z. B. "1 Tag"
  final String fullLabelRelative; // "Hinweisen in 1 Tag"
  final String fullLabelBeforeDeadline; // "1 Tag vorher"
  final Duration duration;

  const ReminderOption({
    required this.id,
    required this.label,
    required this.fullLabelRelative,
    required this.fullLabelBeforeDeadline,
    required this.duration,
  });
}

class ReminderManager {
  static const _mruRelativeKey = 'reminder_mru_relative';
  static const _mruBeforeDeadlineKey = 'reminder_mru_before_deadline';
  static const maxSelectable = 3;

  // ── Presets für Aufgaben OHNE Deadline ("Hinweisen in X") ──
  static const List<ReminderOption> relativeOptions = [
    ReminderOption(id: '15m', label: '15 Min.', fullLabelRelative: 'Hinweisen in 15 Minuten', fullLabelBeforeDeadline: '15 Minuten vorher', duration: Duration(minutes: 15)),
    ReminderOption(id: '30m', label: '30 Min.', fullLabelRelative: 'Hinweisen in 30 Minuten', fullLabelBeforeDeadline: '30 Minuten vorher', duration: Duration(minutes: 30)),
    ReminderOption(id: '1h', label: '1 Std.', fullLabelRelative: 'Hinweisen in 1 Stunde', fullLabelBeforeDeadline: '1 Stunde vorher', duration: Duration(hours: 1)),
    ReminderOption(id: '3h', label: '3 Std.', fullLabelRelative: 'Hinweisen in 3 Stunden', fullLabelBeforeDeadline: '3 Stunden vorher', duration: Duration(hours: 3)),
    ReminderOption(id: '12h', label: '12 Std.', fullLabelRelative: 'Hinweisen in 12 Stunde', fullLabelBeforeDeadline: '12 Stunde vorher', duration: Duration(hours: 12)),
    ReminderOption(id: '1d', label: '1 Tag', fullLabelRelative: 'Hinweisen in 1 Tag', fullLabelBeforeDeadline: '1 Tag vorher', duration: Duration(days: 1)),
    ReminderOption(id: '2d', label: '2 Tage', fullLabelRelative: 'Hinweisen in 2 Tagen', fullLabelBeforeDeadline: '2 Tage vorher', duration: Duration(days: 2)),
    ReminderOption(id: '3d', label: '3 Tage', fullLabelRelative: 'Hinweisen in 3 Tagen', fullLabelBeforeDeadline: '3 Tage vorher', duration: Duration(days: 3)),
    ReminderOption(id: '1w', label: '1 Woche', fullLabelRelative: 'Hinweisen in 1 Woche', fullLabelBeforeDeadline: '1 Woche vorher', duration: Duration(days: 7)),
    ReminderOption(id: '2w', label: '2 Wochen', fullLabelRelative: 'Hinweisen in 2 Wochen', fullLabelBeforeDeadline: '2 Wochen vorher', duration: Duration(days: 14)),
    ReminderOption(id: '1mo', label: '1 Monat', fullLabelRelative: 'Hinweisen in 1 Monat', fullLabelBeforeDeadline: '1 Monat vorher', duration: Duration(days: 30)),
  ];

  // ── Presets für Aufgaben MIT Deadline ("X vorher") ──
  // Bewusst feingranularer im kurzfristigen Bereich (Minuten/Stunden),
  // da Erinnerungen vor einer konkreten Frist meist kurzfristiger gebraucht
  // werden als bei freien Erinnerungen ohne Frist.
  static const List<ReminderOption> beforeDeadlineOptions = [
    ReminderOption(id: '5m', label: '5 Min.', fullLabelRelative: 'Hinweisen in 5 Minuten', fullLabelBeforeDeadline: '5 Minuten vorher', duration: Duration(minutes: 5)),
    ReminderOption(id: '15m', label: '15 Min.', fullLabelRelative: 'Hinweisen in 15 Minuten', fullLabelBeforeDeadline: '15 Minuten vorher', duration: Duration(minutes: 15)),
    ReminderOption(id: '30m', label: '30 Min.', fullLabelRelative: 'Hinweisen in 30 Minuten', fullLabelBeforeDeadline: '30 Minuten vorher', duration: Duration(minutes: 30)),
    ReminderOption(id: '1h', label: '1 Std.', fullLabelRelative: 'Hinweisen in 1 Stunde', fullLabelBeforeDeadline: '1 Stunde vorher', duration: Duration(hours: 1)),
    ReminderOption(id: '2h', label: '2 Std.', fullLabelRelative: 'Hinweisen in 2 Stunden', fullLabelBeforeDeadline: '2 Stunden vorher', duration: Duration(hours: 2)),
    ReminderOption(id: '3h', label: '3 Std.', fullLabelRelative: 'Hinweisen in 3 Stunden', fullLabelBeforeDeadline: '3 Stunden vorher', duration: Duration(hours: 3)),
    ReminderOption(id: '6h', label: '6 Std.', fullLabelRelative: 'Hinweisen in 6 Stunden', fullLabelBeforeDeadline: '6 Stunden vorher', duration: Duration(hours: 6)),
    ReminderOption(id: '12h', label: '12 Std.', fullLabelRelative: 'Hinweisen in 12 Stunden', fullLabelBeforeDeadline: '12 Stunden vorher', duration: Duration(hours: 12)),
    ReminderOption(id: '1d', label: '1 Tag', fullLabelRelative: 'Hinweisen in 1 Tag', fullLabelBeforeDeadline: '1 Tag vorher', duration: Duration(days: 1)),
    ReminderOption(id: '2d', label: '2 Tage', fullLabelRelative: 'Hinweisen in 2 Tagen', fullLabelBeforeDeadline: '2 Tage vorher', duration: Duration(days: 2)),
    ReminderOption(id: '3d', label: '3 Tage', fullLabelRelative: 'Hinweisen in 3 Tagen', fullLabelBeforeDeadline: '3 Tage vorher', duration: Duration(days: 3)),
    ReminderOption(id: '1w', label: '1 Woche', fullLabelRelative: 'Hinweisen in 1 Woche', fullLabelBeforeDeadline: '1 Woche vorher', duration: Duration(days: 7)),
  ];

  static List<ReminderOption> optionsFor(ReminderMode mode) =>
      mode == ReminderMode.relative ? relativeOptions : beforeDeadlineOptions;

  static String _mruKeyFor(ReminderMode mode) =>
      mode == ReminderMode.relative ? _mruRelativeKey : _mruBeforeDeadlineKey;

  static List<String> _loadMru(ReminderMode mode) {
    final box = Hive.box('einstellungen');
    final raw = box.get(_mruKeyFor(mode));
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).toList();
  }

  static void recordUsage(ReminderMode mode, String id) {
    final box = Hive.box('einstellungen');
    final mru = _loadMru(mode);
    mru.remove(id);
    mru.insert(0, id);
    box.put(_mruKeyFor(mode), mru.take(10).toList());
  }

  /// Liefert alle Optionen sortiert nach MRU (zuletzt/häufig genutzt zuerst).
  static List<ReminderOption> getSorted(ReminderMode mode) {
    final mru = _loadMru(mode);
    final all = optionsFor(mode);
    final sorted = List<ReminderOption>.from(all);
    sorted.sort((a, b) {
      final ai = mru.indexOf(a.id);
      final bi = mru.indexOf(b.id);
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.duration.compareTo(b.duration);
    });
    return sorted;
  }

  static ReminderOption? byId(ReminderMode mode, String id) {
    try {
      return optionsFor(mode).firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }
}