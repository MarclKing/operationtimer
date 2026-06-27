import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

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

  static void _saveNormal(DateTime datum, String kommen, String gehen, String tkf, String notiz, [String? existingId]) {
    final existingEntries = getEntriesForDay(datum);
    
    final newEntry = {
      'kommen': kommen,
      'gehen': gehen,
      'TKF': tkf,
      'notiz': notiz,
      'id': existingId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'createdAt': DateTime.now().toIso8601String(),
      'datum': DateFormat('yyyy-MM-dd').format(datum),
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
    
    _saveEntriesForDay(datum, existingEntries);
  }

  static void _saveSplit(DateTime datum, String kommen, String gehen, String tkf, String notiz, [String? existingId]) {
    _saveNormal(datum, kommen, '23:59', tkf, notiz, existingId);
    
    final nextDay = datum.add(const Duration(days: 1));
    _saveNormal(nextDay, '00:00', gehen, tkf, notiz, null);
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
    final isChromeSkin = skin.key == 'chrome';
    
    await showDialog(
      context: context,
      builder: (_) => _NightShiftDialog(
        title: 'Ungültige Zeit',
        message: '"Gehen" muss nach "Kommen" liegen.\n\nFür Nachtschichten aktiviere den Nachtschicht-Modus in den Einstellungen.',
        confirmLabel: 'OK',
        isError: true,
        onConfirm: () {},
        skin: skin,
        isChromeSkin: isChromeSkin,
      ),
    );
  }

  static Future<void> _showConflictDialog(BuildContext context) async {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';
    
    await showDialog(
      context: context,
      builder: (_) => _NightShiftDialog(
        title: 'Zeitüberschneidung',
        message: 'Diese Zeit überschneidet sich mit einem bereits vorhandenen Eintrag.\n\nBitte bearbeite den bestehenden Eintrag in der Monatsübersicht.',
        confirmLabel: 'OK',
        isError: true,
        onConfirm: () {},
        skin: skin,
        isChromeSkin: isChromeSkin,
      ),
    );
  }

  static Future<bool> _showSplitConfirmDialog(
    BuildContext context,
    DateTime datum,
    String kommen,
    String gehen,
  ) async {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';
    final nextDay = datum.add(const Duration(days: 1));
    final datumStr = DateFormat('dd.MM.', 'de').format(datum);
    final nextStr = DateFormat('dd.MM.', 'de').format(nextDay);

    bool confirmed = false;
    await showDialog(
      context: context,
      builder: (_) => _NightShiftDialog(
        title: '🌙 Nachtschicht erkannt',
        message: 'Die App legt automatisch zwei Einträge an:\n\n'
            '📅 $datumStr  $kommen → 23:59\n'
            '📅 $nextStr  00:00 → $gehen',
        confirmLabel: 'Speichern',
        isError: false,
        onConfirm: () => confirmed = true,
        skin: skin,
        isChromeSkin: isChromeSkin,
      ),
    );
    return confirmed;
  }

  static void _showSplitSuccessSnackBar(BuildContext context) {
    final skin = AppTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('✓ Nachtschicht als zwei Einträge gespeichert'),
        backgroundColor: skin.statComplete,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog-Widget mit Skin-Unterstützung
// ─────────────────────────────────────────────────────────────────────────────

class _NightShiftDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool isError;
  final VoidCallback onConfirm;
  final AppSkin skin;
  final bool isChromeSkin;

  const _NightShiftDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.isError,
    required this.onConfirm,
    required this.skin,
    required this.isChromeSkin,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: skin.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: skin.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: skin.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (!isError) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Abbrechen',
                            style: TextStyle(
                              color: skin.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      onConfirm();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: isError
                            ? null
                            : (isChromeSkin
                                ? const LinearGradient(
                                    colors: [Color(0xFF333333), Color(0xFF555555)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  )
                                : skin.gradient),
                        color: isError ? skin.deleteColor : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}