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

  // ── NEU: Gemeinsame, bewusst kurze Presets — für BEIDE Modi identisch ──
  static const List<ReminderOption> sharedOptions = [
    ReminderOption(id: '10m', label: '10 Min.', fullLabelRelative: 'Hinweisen in 10 Minuten', fullLabelBeforeDeadline: '10 Minuten vorher', duration: Duration(minutes: 10)),
    ReminderOption(id: '30m', label: '30 Min.', fullLabelRelative: 'Hinweisen in 30 Minuten', fullLabelBeforeDeadline: '30 Minuten vorher', duration: Duration(minutes: 30)),
    ReminderOption(id: '1h', label: '1 Std.', fullLabelRelative: 'Hinweisen in 1 Stunde', fullLabelBeforeDeadline: '1 Stunde vorher', duration: Duration(hours: 1)),
    ReminderOption(id: '2h', label: '2 Std.', fullLabelRelative: 'Hinweisen in 2 Stunden', fullLabelBeforeDeadline: '2 Stunden vorher', duration: Duration(hours: 2)),
    ReminderOption(id: '12h', label: '12 Std.', fullLabelRelative: 'Hinweisen in 12 Stunden', fullLabelBeforeDeadline: '12 Stunden vorher', duration: Duration(hours: 12)),
    ReminderOption(id: '1d', label: '1 Tag', fullLabelRelative: 'Hinweisen in 1 Tag', fullLabelBeforeDeadline: '1 Tag vorher', duration: Duration(days: 1)),
    ReminderOption(id: '2d', label: '2 Tage', fullLabelRelative: 'Hinweisen in 2 Tagen', fullLabelBeforeDeadline: '2 Tage vorher', duration: Duration(days: 2)),
    ReminderOption(id: '1w', label: '1 Woche', fullLabelRelative: 'Hinweisen in 1 Woche', fullLabelBeforeDeadline: '1 Woche vorher', duration: Duration(days: 7)),
  ];

  // ── Beide Listen zeigen auf dieselbe gemeinsame Liste ──
  static const List<ReminderOption> relativeOptions = sharedOptions;
  static const List<ReminderOption> beforeDeadlineOptions = sharedOptions;

  // ── optionsFor liefert einfach die gemeinsame Liste ──
  static List<ReminderOption> optionsFor(ReminderMode mode) => sharedOptions;

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