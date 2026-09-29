import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import '../screens/tasks_screen.dart' show TaskStore;
import '../services/sync_service.dart';

/// Bereiche mit einstellbarer Aufbewahrungsfrist.
enum RetentionArea { zeit, dienstplan, fahrtenbuch, tasks }

/// Ergebnis der Trockenrechnung: Was würde gelöscht?
class RetentionPreview {
  final DateTime? cutoff; // Stichtag (bei Aufgaben null)
  final int items;        // Tage / Einträge / Fahrten / Aufgaben
  final int notes;        // nur Dienstplan-Notizen
  final int kept;         // nur Fahrtenbuch: alt, aber nicht eingetragen → bleibt
  const RetentionPreview({this.cutoff, this.items = 0, this.notes = 0, this.kept = 0});
  bool get isEmpty => items == 0 && notes == 0;
}

class _Plan {
  final Box box;
  final List<dynamic> deleteKeys = [];
  final Map<dynamic, dynamic> rewrites = {};
  final List<String> photoPaths = [];
  final List<String> removedTaskIds = [];
  int items = 0, notes = 0, kept = 0;
  _Plan(this.box);
}

class DataRetention {
  DataRetention._();

  static const int defaultMonths = 3;
  static const String defaultTaskRule = '1d';

  /// true = nur als "eingetragen" markierte Fahrten werden gelöscht.
  static const bool fahrtenOnlyEntered = true;

  static final _dayRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

  // ── Stichtag: exakt N Monate vor heute (Tag wird bei kurzen Monaten gekürzt) ──
  static DateTime cutoffForMonths(int months, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final target = DateTime(n.year, n.month - months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, n.day > lastDay ? lastDay : n.day);
  }

  static DateTime? _dayFromKey(String k) {
    final m = _dayRe.firstMatch(k);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _monthsFor(RetentionArea area) {
    final key = switch (area) {
      RetentionArea.zeit => 'deleteAfterMonths_zeit',
      RetentionArea.dienstplan => 'deleteAfterMonths_dienstplan',
      RetentionArea.fahrtenbuch => 'deleteAfterMonths_fahrtenbuch',
      RetentionArea.tasks => '',
    };
    return Hive.box('einstellungen').get(key, defaultValue: defaultMonths) as int;
  }

  static String _taskRule() =>
      Hive.box('einstellungen').get('task_auto_delete', defaultValue: defaultTaskRule) as String;

  // ── Öffentliche API ─────────────────────────────────────────────────────

  /// Rechnet nur, löscht nichts. [months]/[taskRule] = noch nicht gespeicherter Kandidat.
  static RetentionPreview preview(RetentionArea area, {int? months, String? taskRule}) {
    final (plan, cutoff) = _build(area, months: months, taskRule: taskRule);
    return RetentionPreview(
        cutoff: cutoff, items: plan.items, notes: plan.notes, kept: plan.kept);
  }

  /// Löscht sofort, nach den GESPEICHERTEN Einstellungen (bzw. Überschreibung).
  static Future<void> apply(RetentionArea area, {int? months, String? taskRule}) async {
    final (plan, _) = _build(area, months: months, taskRule: taskRule);
    if (plan.deleteKeys.isNotEmpty) await plan.box.deleteAll(plan.deleteKeys);
    if (plan.rewrites.isNotEmpty) await plan.box.putAll(plan.rewrites);
    for (final p in plan.photoPaths) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    if (area == RetentionArea.tasks && plan.removedTaskIds.isNotEmpty) {
      TaskStore.changesSignal.value++;
      for (final id in plan.removedTaskIds) {
        unawaited(SyncService.instance.pushTask(id)); // Task fehlt lokal → Cloud-Delete
      }
    }
  }

  // ── Planung ─────────────────────────────────────────────────────────────

  static (_Plan, DateTime?) _build(RetentionArea area, {int? months, String? taskRule}) {
    final cutoff = area == RetentionArea.tasks
        ? null
        : cutoffForMonths(months ?? _monthsFor(area));
    final plan = switch (area) {
      RetentionArea.zeit => _planZeit(cutoff!),
      RetentionArea.dienstplan => _planDienstplan(cutoff!),
      RetentionArea.fahrtenbuch => _planFahrten(cutoff!),
      RetentionArea.tasks => _planTasks(taskRule ?? _taskRule()),
    };
    return (plan, cutoff);
  }

  static _Plan _planZeit(DateTime cutoff) {
    final box = Hive.box('arbeitszeiten');
    final plan = _Plan(box);
    for (final key in box.keys) {
      final day = _dayFromKey(key.toString());
      if (day == null || !day.isBefore(cutoff)) continue;
      plan.deleteKeys.add(key);
      final v = box.get(key);
      plan.items += v is List ? v.length : 1;
    }
    return plan;
  }

  static _Plan _planDienstplan(DateTime cutoff) {
    final box = Hive.box('einstellungen');
    final plan = _Plan(box);
    final monthRe = RegExp(r'^schedule_(\d{4})-(\d{2})$');
    final derivedRe = RegExp(r'^(schedule_changed_|colleagues_|events_)(\d{4})-(\d{2})$');

        for (final key in box.keys) {
      final k = key.toString();

      // Dienstplan-Monat: NUR ganze Monate löschen, die komplett vor dem
      // Stichtag liegen. Der aktuelle Monat (und der Stichtag-Monat) bleibt
      // vollständig erhalten, damit man sieht, wann man wie gearbeitet hat.
      final mm = monthRe.firstMatch(k);
      if (mm != null) {
        final monthEnd = DateTime(int.parse(mm[1]!), int.parse(mm[2]!) + 1, 0);
        if (!monthEnd.isBefore(cutoff)) continue;
        final raw = box.get(key);
        plan.items += raw is Map ? raw.length : 1;
        plan.deleteKeys.add(key);
        continue;
      }

      // Notizen: gleiche Regel — nur wenn der ganze Monat vor dem Stichtag liegt
      if (k.startsWith('schedule_note_')) {
        final day = _dayFromKey(k.substring('schedule_note_'.length));
        if (day != null) {
          final monthEnd = DateTime(day.year, day.month + 1, 0);
          if (monthEnd.isBefore(cutoff)) {
            plan.deleteKeys.add(key);
            plan.notes++;
          }
        }
        continue;
      }

      // Abgeleitete Daten: nur weg, wenn der ganze Monat vor dem Stichtag liegt
      final dm = derivedRe.firstMatch(k);
      if (dm != null) {
        final monthEnd = DateTime(int.parse(dm[2]!), int.parse(dm[3]!) + 1, 0);
        if (monthEnd.isBefore(cutoff)) plan.deleteKeys.add(key);
      }
    }
    return plan;
  }

  static _Plan _planFahrten(DateTime cutoff) {
    final box = Hive.box('einstellungen');
    final plan = _Plan(box);
    final monthRe = RegExp(r'^fahrten_(\d{4})-(\d{2})$');

    for (final key in box.keys) {
      if (!monthRe.hasMatch(key.toString())) continue;
      final raw = box.get(key);
      if (raw is! List) continue;

      final keep = <dynamic>[];
      var removed = 0;
      for (final e in raw) {
        if (e is! Map) {
          keep.add(e);
          continue;
        }
        final m = Map<String, dynamic>.from(e);
        final d = DateTime.tryParse((m['datum'] ?? '').toString());
        final isOld = d != null && _day(d).isBefore(cutoff);
        final entered = m['uebertragen'] == true;
        if (isOld && (!fahrtenOnlyEntered || entered)) {
          removed++;
          for (final p in [m['fotoStartPath'], m['fotoEndPath']]) {
            if (p is String && p.isNotEmpty) plan.photoPaths.add(p);
          }
        } else {
          if (isOld) plan.kept++;
          keep.add(m);
        }
      }
      if (removed == 0) continue;
      plan.items += removed;
      if (keep.isEmpty) {
        plan.deleteKeys.add(key);
      } else {
        plan.rewrites[key] = keep;
      }
    }
    return plan;
  }

  static _Plan _planTasks(String rule) {
    final box = Hive.box('einstellungen');
    final plan = _Plan(box);
    final duration = switch (rule) {
      '1d' => const Duration(days: 1),
      '2d' => const Duration(days: 2),
      '1w' => const Duration(days: 7),
      '1m' => const Duration(days: 30),
      _ => null, // 'never'
    };
    if (duration == null) return plan;

    final cutoff = DateTime.now().subtract(duration);
    final raw = box.get('tasks');
    if (raw is! String || raw.isEmpty) return plan;
    try {
      final decoded = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final filtered = decoded.where((t) {
        if (!(t['done'] as bool? ?? false)) return true;
        final completed = DateTime.tryParse((t['completedAt'] as String?) ?? '');
        if (completed == null) return false;
        return completed.isAfter(cutoff);
      }).toList();
      final removed = decoded.length - filtered.length;
      if (removed > 0) {
        plan.items = removed;
        plan.rewrites['tasks'] = jsonEncode(filtered);
        final keptIds = filtered.map((t) => t['id']?.toString()).toSet();
        plan.removedTaskIds.addAll(decoded
            .map((t) => t['id']?.toString())
            .whereType<String>()
            .where((id) => !keptIds.contains(id)));
      }
    } catch (_) {}
    return plan;
  }
}

/// Automatische Bereinigung nach den gespeicherten Einstellungen
/// (App-Start + Stunden-Timer in main.dart).
Future<void> runAutoCleanup() async {
  for (final area in RetentionArea.values) {
    try {
      await DataRetention.apply(area);
    } catch (_) {}
  }
}