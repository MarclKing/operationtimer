import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'travel_mode_service.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/glass_snackbar.dart';

enum SaveResult { saved, splitSaved, invalid, cancelled }

class NightShiftHelper {
  static bool isNightShiftEnabled() {
    final box = Hive.box('einstellungen');
    return box.get('nachtschicht_modus', defaultValue: false) as bool;
  }

  // Liest alle Einträge für einen Tag - sortiert nach Startzeit
  static List<Map<String, dynamic>> getEntriesForDay(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final box = Hive.box('arbeitszeiten');
    final data = box.get(key);
    
    List<Map<String, dynamic>> entries = [];
    
    if (data == null) return entries;
    
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          entries.add(Map<String, dynamic>.from(item));
        }
      }
    } else if (data is Map) {
      entries.add(Map<String, dynamic>.from(data));
    }
    
    entries.sort((a, b) {
      final aStart = _toMinutes(a['kommen'] ?? '00:00') ?? 0;
      final bStart = _toMinutes(b['kommen'] ?? '00:00') ?? 0;
      return aStart.compareTo(bStart);
    });
    
    return entries;
  }

  static void _saveEntriesForDay(DateTime date, List<Map<String, dynamic>> entries) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final box = Hive.box('arbeitszeiten');
    if (entries.isEmpty) {
      box.delete(key);
    } else {
      entries.sort((a, b) {
        final aStart = _toMinutes(a['kommen'] ?? '00:00') ?? 0;
        final bStart = _toMinutes(b['kommen'] ?? '00:00') ?? 0;
        return aStart.compareTo(bStart);
      });
      box.put(key, entries);
    }
  }

  static int? _toMinutes(String t) {
    if (t.isEmpty || t == '--:--') return null;
    try {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    } catch (_) {
      return null;
    }
  }

  static String _fromMinutes(int minutes) {
    final hour = (minutes ~/ 60) % 24;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static bool _hasConflict(List<Map<String, dynamic>> entries, String kommen, String gehen, [String? excludeId]) {
    final newStart = _toMinutes(kommen);
    final newEnd = _toMinutes(gehen);
    if (newStart == null || newEnd == null) return false;
    
    for (final entry in entries) {
      if (excludeId != null && entry['id'] == excludeId) continue;
      final entryStart = _toMinutes(entry['kommen']);
      final entryEnd = _toMinutes(entry['gehen']);
      if (entryStart == null || entryEnd == null) continue;
      
      if (!(newEnd <= entryStart || newStart >= entryEnd)) {
        return true;
      }
    }
    return false;
  }

  // NEU
static void _saveNormal(DateTime datum, String kommen, String gehen, String tkf, String notiz,
      [String? existingId, bool isDutyStart = true, bool isDutyEnd = true]) {
    final existingEntries = getEntriesForDay(datum);

    // Zeitzone auflösen: nur beim Start eines NEUEN Dienstes wird evtl.
    // eine bestätigte Zeitzone scharf geschaltet, sonst gilt die aktive Zone weiter.
    final tzInfo = isDutyStart
        ? TravelModeService.resolveTzForNewEntry()
        : TravelModeService.activeTz;

    final newEntry = {
      'kommen': kommen,
      'gehen': gehen,
      'TKF': tkf,
      'notiz': notiz,
      'id': existingId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'createdAt': DateTime.now().toIso8601String(),
      'datum': DateFormat('yyyy-MM-dd').format(datum),
      'tz': tzInfo.id,
      'tzOffsetLabel': tzInfo.offsetLabel,
      'kommenUtc': TravelModeService.toUtcIso(datum, kommen, tzInfo.id),
      'gehenUtc': TravelModeService.toUtcIso(datum, gehen, tzInfo.id),
      'physTzAtSave': TravelModeService.lastKnownDeviceTz,
    };

    // Echtes Dienstende → nächsten Wechsel scharf schalten
    if (isDutyEnd && gehen.isNotEmpty) {
      TravelModeService.armSwitchIfNeeded();
    }
    
    if (existingId != null) {
      final index = existingEntries.indexWhere((e) => e['id'] == existingId);
      if (index != -1) {
        existingEntries[index] = newEntry;
      } else {
        existingEntries.add(newEntry);
      }
    } else {
      existingEntries.add(newEntry);
    }
    
    _saveEntriesForDay(datum, existingEntries);
  }

  // NEU
static void _saveSplit(DateTime datum, String kommen, String gehen, String tkf, String notiz, [String? existingId]) {
    // Erste Hälfte: Dienstbeginn (Zone ggf. auflösen), aber kein echtes Dienstende
    _saveNormal(datum, kommen, '23:59', tkf, notiz, existingId, true, false);

    // Zweite Hälfte: Fortsetzung (gleiche Zone), hier ist der echte Feierabend
    final nextDay = datum.add(const Duration(days: 1));
    _saveNormal(nextDay, '00:00', gehen, tkf, notiz, null, false, true);
  }

  static void deleteEntry(DateTime datum, String entryId) {
    final entries = getEntriesForDay(datum);
    entries.removeWhere((e) => e['id'] == entryId);
    _saveEntriesForDay(datum, entries);
  }

  static Future<SaveResult> save({
    required BuildContext context,
    required DateTime datum,
    required String kommen,
    required String gehen,
    required String tkf,
    required String notiz,
    String? existingId,
  }) async {
    final kommenMin = _toMinutes(kommen);
    final gehenMin = _toMinutes(gehen);
    
    if (kommenMin == null || gehenMin == null) {
      _saveNormal(datum, kommen, gehen, tkf, notiz, existingId);
      return SaveResult.saved;
    }
    
    final nightShiftOn = isNightShiftEnabled();
    
    if (gehenMin < kommenMin) {
      if (!nightShiftOn) {
        if (context.mounted) await _showErrorDialog(context);
        return SaveResult.invalid;
      } else {
        if (!context.mounted) return SaveResult.cancelled;
        final confirmed = await _showSplitConfirmDialog(context, datum, kommen, gehen);
        if (!confirmed) return SaveResult.cancelled;
        _saveSplit(datum, kommen, gehen, tkf, notiz, existingId);
        if (context.mounted) _showSplitSuccessSnackBar(context);
        return SaveResult.splitSaved;
      }
    }
    
    final existingEntries = getEntriesForDay(datum);
    if (_hasConflict(existingEntries, kommen, gehen, existingId)) {
      if (context.mounted) await _showConflictDialog(context);
      return SaveResult.invalid;
    }
    
    _saveNormal(datum, kommen, gehen, tkf, notiz, existingId);
    return SaveResult.saved;
  }

  static Future<void> _showErrorDialog(BuildContext context) async {
    final skin = AppTheme.of(context);
    await infoDialog(
      context: context,
      skin: skin,
      title: 'Ungültige Zeit',
      message: '"Gehen" muss nach "Kommen" liegen.\n\nFür Nachtschichten aktiviere den Nachtschicht-Modus in den Einstellungen.',
      icon: Icons.error_outline_rounded,
      isError: true,
    );
  }

  static Future<void> _showConflictDialog(BuildContext context) async {
    final skin = AppTheme.of(context);
    await infoDialog(
      context: context,
      skin: skin,
      title: 'Zeitüberschneidung',
      message: 'Diese Zeit überschneidet sich mit einem bereits vorhandenen Eintrag.\n\nBitte bearbeite den bestehenden Eintrag in der Monatsübersicht.',
      icon: Icons.error_outline_rounded,
      isError: true,
    );
  }

  static Future<bool> _showSplitConfirmDialog(
    BuildContext context,
    DateTime datum,
    String kommen,
    String gehen,
  ) async {
    final skin = AppTheme.of(context);
    final nextDay = datum.add(const Duration(days: 1));
    final datumStr = DateFormat('dd.MM.', 'de').format(datum);
    final nextStr = DateFormat('dd.MM.', 'de').format(nextDay);

    final confirmed = await confirmActionDialog(
      context: context,
      skin: skin,
      title: '🌙 Nachtschicht erkannt',
      message: 'Die App legt automatisch zwei Einträge an:\n\n'
          '📅 $datumStr  $kommen → 23:59\n'
          '📅 $nextStr  00:00 → $gehen',
      icon: Icons.nightlight_round,
      confirmLabel: 'Speichern',
    );
    return confirmed == true;
  }

  static void _showSplitSuccessSnackBar(BuildContext context) {
    showGlassSnackBar(
      context,
      'Nachtschicht als zwei Einträge gespeichert',
      type: GlassSnackBarType.success,
      duration: const Duration(seconds: 2),
    );
  }
}