import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

/// Löscht alte Zeiterfassungs- und Dienstplan-Einträge basierend auf der
/// in den Einstellungen gespeicherten "deleteAfterMonths"-Auswahl.
Future<void> runAutoCleanup() async {
  final settingsBox = Hive.box('einstellungen');
  final deleteAfterMonths =
      settingsBox.get('deleteAfterMonths', defaultValue: 3) as int;

  final now = DateTime.now();
  final cutoffMonth = DateTime(now.year, now.month - deleteAfterMonths);

  // Arbeitszeiten
  final zeitBox = Hive.box('arbeitszeiten');
  final zeitKeysToDelete = zeitBox.keys.where((key) {
    try {
      final date = DateTime.parse(key.toString());
      final entryMonth = DateTime(date.year, date.month);
      return entryMonth.isBefore(cutoffMonth);
    } catch (_) {
      return false;
    }
  }).toList();
  for (final key in zeitKeysToDelete) {
    zeitBox.delete(key);
  }

  // Dienstpläne (schedule_YYYY-MM), ohne die Notizen
  final scheduleKeysToDelete = settingsBox.keys.where((key) {
    final k = key.toString();
    if (!k.startsWith('schedule_') || k.startsWith('schedule_note_')) {
      return false;
    }
    try {
      final monthStr = k.substring('schedule_'.length);
      final parts = monthStr.split('-');
      if (parts.length < 2) return false;
      final entryMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      return entryMonth.isBefore(cutoffMonth);
    } catch (_) {
      return false;
    }
  }).toList();
  for (final key in scheduleKeysToDelete) {
    settingsBox.delete(key);
  }

  // Dienstplan-Notizen (schedule_note_YYYY-MM-DD)
  final noteKeysToDelete = settingsBox.keys.where((key) {
    final k = key.toString();
    if (!k.startsWith('schedule_note_')) return false;
    try {
      final dateStr = k.substring('schedule_note_'.length);
      final date = DateTime.parse(dateStr);
      final entryMonth = DateTime(date.year, date.month);
      return entryMonth.isBefore(cutoffMonth);
    } catch (_) {
      return false;
    }
  }).toList();
  for (final key in noteKeysToDelete) {
    settingsBox.delete(key);
  }

  // NEU: Fahrtenbuch-Einträge löschen
final fahrtKeys = settingsBox.keys.where((key) {
  final k = key.toString();
  if (!k.startsWith('fahrten_')) return false;
  try {
    final monthStr = k.substring('fahrten_'.length);
    final parts = monthStr.split('-');
    if (parts.length < 2) return false;
    final entryMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    return entryMonth.isBefore(cutoffMonth);
  } catch (_) {
    return false;
  }
}).toList();
for (final key in fahrtKeys) {
  settingsBox.delete(key);
}
// Erledigte Aufgaben automatisch löschen
  final taskAutoDelete =
      settingsBox.get('task_auto_delete', defaultValue: 'never') as String;
  if (taskAutoDelete != 'never') {
    Duration? cutoffDuration;
    switch (taskAutoDelete) {
      case '1d': cutoffDuration = const Duration(days: 1); break;
      case '2d': cutoffDuration = const Duration(days: 2); break;
      case '1w': cutoffDuration = const Duration(days: 7); break;
      case '1m': cutoffDuration = const Duration(days: 30); break;
    }
    if (cutoffDuration != null) {
      final tasksCutoff = now.subtract(cutoffDuration);
      final tasksRaw = settingsBox.get('tasks');
      if (tasksRaw is String && tasksRaw.isNotEmpty) {
        try {
          final decoded = List<Map<String, dynamic>>.from(
              (jsonDecode(tasksRaw) as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)));
          final filtered = decoded.where((t) {
            final done = t['done'] as bool? ?? false;
            if (!done) return true; // offene Tasks nie löschen
            final completedStr = t['completedAt'] as String?;
            if (completedStr == null) return false; // kein Zeitstempel → löschen
            final completed = DateTime.tryParse(completedStr);
            if (completed == null) return false;
            return completed.isAfter(tasksCutoff); // noch innerhalb der Frist
          }).toList();
          settingsBox.put('tasks', jsonEncode(filtered));
        } catch (_) {}
      }
    }
  }
  
}