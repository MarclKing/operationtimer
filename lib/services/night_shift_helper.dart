import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../theme/app_theme.dart';
import 'travel_mode_service.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/glass_snackbar.dart';
import 'sync_service.dart';

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

  static Future<void> _saveEntriesForDay(DateTime date, List<Map<String, dynamic>> entries) async {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final box = Hive.box('arbeitszeiten');
    if (entries.isEmpty) {
      await box.delete(key);
    } else {
      entries.sort((a, b) {
        final aStart = _toMinutes(a['kommen'] ?? '00:00') ?? 0;
        final bStart = _toMinutes(b['kommen'] ?? '00:00') ?? 0;
        return aStart.compareTo(bStart);
      });
      await box.put(key, entries);
    }
    await box.flush();
    await SyncService.instance.pushArbeitszeit(key);
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

  static Future<void> _saveNormal(
    DateTime datum,
    String kommen,
    String gehen,
    String tkf,
    String notiz,
    [
      String? existingId,
      String? kommenTzOverride,
      String? gehenTzOverride,
    ]
  ) async {
    final existingEntries = getEntriesForDay(datum);

    // Referenzzone (Kommen-Zone): expliziter Override aus dem Picker hat
    // Vorrang, sonst gilt die aktuell aktive Zone.
    final kommenTzId = kommenTzOverride ?? TravelModeService.activeTzId;
    final kommenTzLabel = TravelModeService.offsetLabelFor(kommenTzId);

    // Gehen-Zone: ohne explizite Auswahl gilt sie als identisch zur
    // Kommen-Zone (Normalfall, keine Umrechnung).
    final gehenTzId = gehenTzOverride ?? kommenTzId;
    final zoneCrossing = TravelModeService.isEnabled &&
        gehen.isNotEmpty &&
        gehenTzId != kommenTzId;

    String finalGehen = gehen;
    String? gehenRaw;
    String? gehenRawTz;
    int? gehenDayShift;
    int? dauerMinuten;

    if (zoneCrossing) {
      final converted = TravelModeService.convertGehenToKommenTz(
        datum: datum,
        kommenHhmm: kommen,
        kommenTzId: kommenTzId,
        gehenHhmm: gehen,
        gehenTzId: gehenTzId,
      );
      if (converted != null) {
        gehenRaw = gehen;
        gehenRawTz = gehenTzId;
        finalGehen = converted;
      }
      final dur = TravelModeService.actualDuration(
        datum: datum,
        kommenHhmm: kommen,
        kommenTzId: kommenTzId,
        gehenHhmm: gehen,
        gehenTzId: gehenTzId,
      );
      if (dur != null) dauerMinuten = dur.inMinutes;

      // Tagesverschiebung nur informativ festhalten (für die Aufschlüsselung)
      try {
        final gParts = gehen.split(':');
        final gLoc = tz.getLocation(gehenTzId);
        final gDt = tz.TZDateTime(gLoc, datum.year, datum.month, datum.day,
            int.parse(gParts[0]), int.parse(gParts[1]));
        final kLoc = tz.getLocation(kommenTzId);
        final convertedDt = tz.TZDateTime.from(gDt, kLoc);
        gehenDayShift = DateTime(convertedDt.year, convertedDt.month, convertedDt.day)
            .difference(DateTime(datum.year, datum.month, datum.day))
            .inDays;
      } catch (_) {}
    } else if (kommen.isNotEmpty && gehen.isNotEmpty) {
      final dur = TravelModeService.actualDuration(
        datum: datum,
        kommenHhmm: kommen,
        kommenTzId: kommenTzId,
        gehenHhmm: gehen,
        gehenTzId: kommenTzId,
      );
      if (dur != null) dauerMinuten = dur.inMinutes;
    }

    final newEntry = {
      'kommen': kommen,
      'gehen': finalGehen,
      'TKF': tkf,
      'Bemerkung': notiz,
      'id': existingId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'createdAt': DateTime.now().toIso8601String(),
      'datum': DateFormat('yyyy-MM-dd').format(datum),
      'tz': kommenTzId,
      'tzOffsetLabel': kommenTzLabel,
      'kommenUtc': TravelModeService.toUtcIso(datum, kommen, kommenTzId),
      'gehenUtc': TravelModeService.toUtcIso(datum, finalGehen, kommenTzId),
      'physTzAtSave': TravelModeService.lastKnownDeviceTz,
      if (zoneCrossing) 'gehenTz': gehenTzId,
      if (gehenRaw != null) 'gehenRaw': gehenRaw,
      if (gehenRawTz != null) 'gehenRawTz': gehenRawTz,
      if (gehenDayShift != null && gehenDayShift != 0) 'gehenDayShift': gehenDayShift,
      if (dauerMinuten != null) 'dauerMinuten': dauerMinuten,
    };

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

    await _saveEntriesForDay(datum, existingEntries);
  }

  static Future<void> _saveSplit(
    DateTime datum,
    String kommen,
    String gehen,
    String tkf,
    String notiz,
    [
      String? existingId,
      String? kommenTz,
      String? gehenTz,
    ]
  ) async {
    // Erste Hälfte: Dienstbeginn (Kommen-Zone)
    await _saveNormal(datum, kommen, '23:59', tkf, notiz, existingId, kommenTz, null);

    // Zweite Hälfte: Fortsetzung, hier ist der echte Feierabend (Gehen-Zone)
    final nextDay = datum.add(const Duration(days: 1));
    await _saveNormal(nextDay, '00:00', gehen, tkf, notiz, null, null, gehenTz);
  }

  static Future<void> deleteEntry(DateTime datum, String entryId) async {
    final entries = getEntriesForDay(datum);
    entries.removeWhere((e) => e['id'] == entryId);
    await _saveEntriesForDay(datum, entries);
  }

  static Future<SaveResult> save({
    required BuildContext context,
    required DateTime datum,
    required String kommen,
    required String gehen,
    required String tkf,
    required String notiz,
    String? existingId,
    String? kommenTz,
    String? gehenTz,
  }) async {
    final kommenMin = _toMinutes(kommen);
    final gehenMin = _toMinutes(gehen);
    
    if (kommenMin == null || gehenMin == null) {
      await _saveNormal(datum, kommen, gehen, tkf, notiz, existingId, kommenTz, gehenTz);
      return SaveResult.saved;
    }

    // Zonen-Überquerung hat Vorrang vor der Nachtschicht-Konflikt-Prüfung,
    // da rohe Gehen-Zeit vor Umrechnung unabhängig von kommen/gehen-Reihenfolge ist.
    final zoneCrossing = TravelModeService.isEnabled &&
        gehenTz != null &&
        kommenTz != null &&
        gehenTz != kommenTz;

    if (!zoneCrossing && gehenMin < kommenMin) {
      if (!isNightShiftEnabled()) {
        if (context.mounted) await _showErrorDialog(context);
        return SaveResult.invalid;
      } else {
        if (!context.mounted) return SaveResult.cancelled;
        final confirmed = await _showSplitConfirmDialog(context, datum, kommen, gehen);
        if (!confirmed) return SaveResult.cancelled;
        await _saveSplit(datum, kommen, gehen, tkf, notiz, existingId, kommenTz, gehenTz);
        if (context.mounted) _showSplitSuccessSnackBar(context);
        return SaveResult.splitSaved;
      }
    }

    final existingEntries = getEntriesForDay(datum);
    if (!zoneCrossing && _hasConflict(existingEntries, kommen, gehen, existingId)) {
      if (context.mounted) await _showConflictDialog(context);
      return SaveResult.invalid;
    }

    await _saveNormal(datum, kommen, gehen, tkf, notiz, existingId, kommenTz, gehenTz);
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