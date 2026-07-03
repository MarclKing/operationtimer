import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:home_widget/home_widget.dart' if (dart.library.html) '../home_widget_stub.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as dartio;
import 'dart:typed_data';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_pickers.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/swipe_animation_mixin.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'tasks_screen.dart' show TaskStore;
import '../services/sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entfernt: extension _AppSkinGlass   → jetzt AppSkinGlass in glass_kit.dart
// Entfernt: _GlassSurface             → jetzt GlassSurface in glass_kit.dart
// Entfernt: _GlassBottomSheet         → jetzt GlassSheet in glass_kit.dart
// Entfernt: _SheetHandle              → jetzt SheetHandle in glass_kit.dart
// Entfernt: _GlassPrimaryButton       → jetzt GlassPrimaryButton in glass_kit.dart
// Entfernt: _GlassSecondaryButton     → jetzt GlassSecondaryButton in glass_kit.dart
// Entfernt: _GlassStatCard            → jetzt GlassStatCard in glass_kit.dart
// Entfernt: _GlassIconBadge           → jetzt GlassIconBadge in glass_kit.dart
// Entfernt: _FadingListView           → jetzt FadingListView in glass_kit.dart
// _showMonthPicker → showMonthYearPicker aus glass_pickers.dart
// _showDeleteDialog in _deleteCurrentMonth → confirmDeleteDialog aus glass_dialogs.dart
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// DAY DOT
// ─────────────────────────────────────────────────────────────────────────────

class _DayDot extends StatelessWidget {
  final DateTime day;
  final AppSkin skin;
  final bool isChrome;
  final bool isChanged;

  const _DayDot({
    required this.day, required this.skin,
    required this.isChrome, required this.isChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isChanged) {
      return Container(width: 7, height: 7,
          decoration: const BoxDecoration(color: Color(0xFFFFB347), shape: BoxShape.circle));
    }
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    Color color;
    if (isChrome) {
      color = isWeekend ? const Color(0xFFCCCCCC) : const Color(0xFF555555);
    } else {
      color = isWeekend ? skin.primary.withValues(alpha: 0.65) : skin.surface(0.22);
    }
    return Container(width: 7, height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shift colour helper
// ─────────────────────────────────────────────────────────────────────────────

Color _shiftColor(String s, {required bool isChrome}) {
  final u = s.trim().toUpperCase();
  if (isChrome) {
    if (u == 'U' || u == 'DA' || u == 'X') return const Color(0xFF444444);
    if (u == 'VK' || u == 'IS') return const Color(0xFF999999);
    const workPrefixes = ['P1', 'P2', 'P', 'F1', 'F2', 'F', 'T'];
    for (final w in workPrefixes) { if (u == w) return const Color(0xFFDDDDDD); }
    if (u == 'L' || u == 'AUF') return const Color(0xFFBBBBBB);
    return const Color(0xFF777777);
  }
  const workShifts = ['P1', 'P2', 'P', 'F1', 'F2', 'F', 'T'];
  for (final w in workShifts) { if (u == w) return const Color(0xFF5B8DEF); }
  if (u == 'VK' || u == 'IS') return const Color(0xFFEF5B5B);
  if (u == 'U' || u == 'DA' || u == 'X') return const Color(0xFF6B7280);
  if (u == 'L' || u == 'AUF') return const Color(0xFFEFBB5B);
  return const Color(0xFF8B8B9E);
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule Entry
// ─────────────────────────────────────────────────────────────────────────────

class ScheduleEntry {
  final String shift;
  final List<String> parts;
  final ShiftCategory category;

  ScheduleEntry(this.shift)
      : parts = shift.split('/').map((s) => s.trim()).toList(),
        category = _categorize(shift);

  static ShiftCategory _categorize(String raw) {
    final parts = raw.split('/').map((s) => s.trim().toUpperCase()).toList();
    bool hasWork = false, hasFree = false;
    for (final p in parts) {
      if (_isFree(p)) hasFree = true;
      else if (_isWork(p)) hasWork = true;
    }
    if (hasWork && hasFree) return ShiftCategory.mixed;
    if (hasWork) return ShiftCategory.work;
    if (hasFree) return ShiftCategory.free;
    return ShiftCategory.other;
  }

  static bool _isWork(String s) {
    const w = ['P1', 'P2', 'P', 'F1', 'F2', 'F', 'IS', 'T', 'L', 'AUF'];
    return w.contains(s);
  }

  static bool _isFree(String s) => s == 'U' || s == 'DA' || s == 'X';
  bool get hasBirthday => parts.any((p) => p.trim().toUpperCase() == 'GEB');
}

enum ShiftCategory { work, free, other, mixed }

// ─────────────────────────────────────────────────────────────────────────────
// Changed-days helper
// ─────────────────────────────────────────────────────────────────────────────

class _ChangedDays {
  static String _hiveKey(String monthKey) => 'schedule_changed_$monthKey';

  static void save(String monthKey, Set<String> days) {
    Hive.box('einstellungen').put(_hiveKey(monthKey), days.toList());
  }

  static Set<String> load(String monthKey) {
    final raw = Hive.box('einstellungen').get(_hiveKey(monthKey));
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return {};
  }

  static void clear(String monthKey) {
    Hive.box('einstellungen').delete(_hiveKey(monthKey));
  }

  static Set<String> diff(Map<String, String> oldData, Map<String, String> newData) {
    final changed = <String>{};
    final allKeys = {...oldData.keys, ...newData.keys};
    for (final k in allKeys) {
      final oldVal = (oldData[k] ?? '').trim().toUpperCase();
      final newVal = (newData[k] ?? '').trim().toUpperCase();
      if (oldVal != newVal) changed.add(k);
    }
    return changed;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF Parser
// ─────────────────────────────────────────────────────────────────────────────

class DienstplanParser {
  static const _monthNames = {
    'januar': 1, 'jan': 1, 'februar': 2, 'feb': 2,
    'märz': 3, 'maerz': 3, 'mär': 3, 'april': 4, 'apr': 4,
    'mai': 5, 'juni': 6, 'jun': 6, 'juli': 7, 'jul': 7,
    'august': 8, 'aug': 8, 'september': 9, 'sep': 9,
    'oktober': 10, 'okt': 10, 'november': 11, 'nov': 11,
    'dezember': 12, 'dez': 12,
  };

  static Future<Map<String, dynamic>> parse({
    String? filePath, List<int>? fileBytes,
    required String userName, required String fileName, required bool devMode,
  }) async {
    List<int> bytes;
    try {
      if (kIsWeb) { bytes = fileBytes ?? []; }
      else if (fileBytes != null && fileBytes.isNotEmpty) { bytes = fileBytes; }
      else if (filePath != null && filePath.isNotEmpty) { bytes = await dartio.File(filePath).readAsBytes(); }
      else { bytes = []; }
    } catch (e) { return _errSimple(null, 'Datei konnte nicht gelesen werden.', devMode); }
    if (bytes.isEmpty) return _errSimple(null, 'Keine Dateidaten empfangen.', devMode);
    try {
      return _parseSync(bytes: bytes, userName: userName, fileName: fileName, devMode: devMode);
    } catch (e) { return _errSimple(null, 'Parsing-Fehler: $e', devMode); }
  }

  static Map<String, dynamic> _errSimple(DateTime? month, String msg, bool devMode) =>
      {'month': month, 'data': <String, String>{}, 'error': msg};

  static Map<String, dynamic> _parseSync({
    required List<int> bytes, required String userName,
    required String fileName, required bool devMode,
  }) {
    final log = StringBuffer();
    if (devMode) log.writeln('[DEV] Dateigröße: ${bytes.length} Bytes');
    final stream = _decompress(bytes, log, devMode);
    if (stream == null) {
      return _err(null, 'PDF nicht lesbar. Bitte maschinenlesbaren Text sicherstellen.',
          devMode, log, devDetail: 'Kein FlateDecode-Stream mit BT/ET gefunden.');
    }
    final items = _extractCoordText(stream);
    final rows = _groupByY(items);
    final sortedYs = rows.keys.toList()..sort((a, b) => b.compareTo(a));
    final detectedMonth = _detectMonthFromText(rows, fileName);
    if (userName.trim().isEmpty) {
      return _err(detectedMonth,
          'Kein Name hinterlegt. Bitte Namen in den Einstellungen eintragen.', devMode, log);
    }
    final terms = _searchTerms(userName);
    final dateRow = _findDateRow(rows);
    final nameResult = _findPersonRow(rows, sortedYs, terms, userName, devMode, log);
    final nameY = nameResult?.$1;
    final shiftCells = nameResult?.$2;
    if (nameY == null || shiftCells == null || shiftCells.isEmpty) {
      return _err(detectedMonth,
          'Name nicht gefunden. Bitte Dienstplan-Namen in den Einstellungen prüfen.',
          devMode, log, devDetail: 'Suchbegriffe: ${terms.join(", ")}\n\n[DEV LOG]\n$log');
    }
    final result = <String, String>{};
    if (dateRow != null && detectedMonth != null) {
      final usedDateIndices = <int>{};
      for (final (sx, shift) in shiftCells) {
        int? bestIdx; double bestDist = double.infinity;
        for (int di = 0; di < dateRow.length; di++) {
          if (usedDateIndices.contains(di)) continue;
          final dist = (sx - dateRow[di].$1).abs();
          if (dist < bestDist) { bestDist = dist; bestIdx = di; }
        }
        if (bestIdx != null && bestDist <= 30.0) {
          usedDateIndices.add(bestIdx);
          final dateLabel = dateRow[bestIdx].$2;
          final parts = dateLabel.replaceAll(' ', '').split('.');
          if (parts.length >= 2) {
            final day = int.tryParse(parts[0]);
            final month = int.tryParse(parts[1]);
            if (day != null && month != null) {
              final key = DateFormat('yyyy-MM-dd').format(DateTime(detectedMonth.year, month, day));
              result[key] = shift.trim() == 'x' ? 'X' : shift.trim();
            }
          }
        }
      }
    } else if (detectedMonth != null) {
      final daysInMonth = DateUtils.getDaysInMonth(detectedMonth.year, detectedMonth.month);
      for (int i = 0; i < shiftCells.length && i < daysInMonth; i++) {
        final key = DateFormat('yyyy-MM-dd').format(DateTime(detectedMonth.year, detectedMonth.month, i + 1));
        result[key] = shiftCells[i].$2.trim() == 'x' ? 'X' : shiftCells[i].$2.trim();
      }
    }
    if (detectedMonth != null) {
      final daysInMonth = DateUtils.getDaysInMonth(detectedMonth.year, detectedMonth.month);
      for (int day = 1; day <= daysInMonth; day++) {
        final key = DateFormat('yyyy-MM-dd').format(DateTime(detectedMonth.year, detectedMonth.month, day));
        result.putIfAbsent(key, () => 'X');
      }
    }
    if (result.isEmpty) {
      return _err(detectedMonth, 'Dienste konnten nicht zugeordnet werden.', devMode, log,
          devDetail: '[DEV LOG]\n$log');
    }
    return {'month': detectedMonth, 'data': result, 'error': null};
  }

  static Map<String, Map<String, String>> parseAllColleagues({
    required List<int> bytes, required String fileName,
    required String ownUserName, bool devMode = false, StringBuffer? debugLog,
  }) {
    final log = debugLog ?? StringBuffer();
    try {
      final innerLog = StringBuffer();
      final stream = _decompress(bytes, innerLog, devMode);
      if (devMode) log.write(innerLog);
      if (stream == null) { if (devMode) log.writeln('[KOLLEGEN] Stream konnte nicht dekomprimiert werden.'); return {}; }
      final items = _extractCoordText(stream);
      final rows = _groupByY(items);
      final sortedYsDesc = rows.keys.toList()..sort((a, b) => b.compareTo(a));
      final detectedMonth = _detectMonthFromText(rows, fileName);
      if (detectedMonth == null) { if (devMode) log.writeln('[KOLLEGEN] Monat konnte nicht erkannt werden.'); return {}; }
      final dateRow = _findDateRow(rows);
      double? dateRowY;
      {
        final dateRe = RegExp(r'^\d{1,2}\.\d{2}\.$');
        for (final y in sortedYsDesc) {
          final rowItems = rows[y]!;
          final matches = rowItems.where((e) => dateRe.hasMatch(e.$2)).length;
          if (matches >= 5) { dateRowY = y; break; }
        }
      }
      if (dateRowY == null) return {};
      final List<(double, List<(double, String)>)> shiftRows = [];
      for (final y in sortedYsDesc) {
        if (y >= dateRowY) continue;
        final rowItems = (rows[y]!.toList())..sort((a, b) => a.$1.compareTo(b.$1));
        final rowText = rowItems.map((e) => e.$2).join(' ');
        if (rowText.contains('Personal') || rowText.contains('Reserve') || rowText.contains('Kalenderwoche')) continue;
        final shiftTokens = rowItems.where((e) => _looksLikeShift(e.$2)).toList();
        if (shiftTokens.isEmpty) continue;
        final relevantShifts = ['P', 'P1', 'P2', 'F', 'F1', 'F2', 'VK', 'GEB'];
        bool hasRelevant = shiftTokens.any((sc) {
          final u = sc.$2.trim().toUpperCase();
          return u.split('/').map((s) => s.trim()).any((p) => relevantShifts.contains(p));
        });
        if (!hasRelevant) continue;
        shiftRows.add((y, shiftTokens));
      }
      final List<(double, String)> nameTokens = [];
      final nameRowRe = RegExp(r'^[A-ZÄÖÜ][a-zA-ZäöüÄÖÜ\-]+,');
      for (final y in sortedYsDesc) {
        final rowItems = rows[y]!;
        for (final (x, text) in rowItems) {
          if (nameRowRe.hasMatch(text.trim())) {
            final lastName = text.split(',').first.trim();
            if (lastName.length >= 2) nameTokens.add((y, lastName));
          }
        }
      }
      nameTokens.sort((a, b) => b.$1.compareTo(a.$1));
      final result = <String, Map<String, String>>{};
      final usedNameIndices = <int>{};
      for (int si = 0; si < shiftRows.length; si++) {
        final (shiftY, shiftTokens) = shiftRows[si];
        int bestNameIdx = -1; double bestDist = double.infinity;
        for (int ni = 0; ni < nameTokens.length; ni++) {
          if (usedNameIndices.contains(ni)) continue;
          final dist = (nameTokens[ni].$1 - shiftY).abs();
          if (dist < bestDist) { bestDist = dist; bestNameIdx = ni; }
        }
        if (bestNameIdx == -1 || bestDist > 50.0) continue;
        usedNameIndices.add(bestNameIdx);
        final lastName = nameTokens[bestNameIdx].$2;
        if (dateRow != null) {
          final usedDateIndices = <int>{};
          for (final (sx, shift) in shiftTokens) {
            int? bestIdx; double bestDateDist = double.infinity;
            for (int di = 0; di < dateRow.length; di++) {
              if (usedDateIndices.contains(di)) continue;
              final dist = (sx - dateRow[di].$1).abs();
              if (dist < bestDateDist) { bestDateDist = dist; bestIdx = di; }
            }
            if (bestIdx != null && bestDateDist <= 30.0) {
              usedDateIndices.add(bestIdx);
              final dateLabel = dateRow[bestIdx].$2;
              final parts = dateLabel.replaceAll(' ', '').split('.');
              if (parts.length >= 2) {
                final day = int.tryParse(parts[0]);
                final month = int.tryParse(parts[1]);
                if (day != null && month != null) {
                  final key = DateFormat('yyyy-MM-dd').format(DateTime(detectedMonth.year, month, day));
                  final normalizedShift = shift.trim().toLowerCase() == 'x' ? 'X' : shift.trim().toUpperCase();
                  final finalShift = normalizedShift.toUpperCase() == 'GEB' ? 'GEB' : normalizedShift;
                  result.putIfAbsent(key, () => {})[lastName] = finalShift;
                }
              }
            }
          }
        }
      }
      return result;
    } catch (e, stack) {
      if (devMode) { log.writeln('[KOLLEGEN] FEHLER: $e'); log.writeln('Stack: $stack'); }
      return {};
    }
  }

  static Map<String, String> parseEvents({
    required List<int> bytes, required String fileName, bool devMode = false,
  }) {
    try {
      final log = StringBuffer();
      final stream = _decompress(bytes, log, devMode);
      if (stream == null) return {};
      final items = _extractCoordText(stream);
      final rows = _groupByY(items);
      final sortedYsDesc = rows.keys.toList()..sort((a, b) => b.compareTo(a));
      final dateRow = _findDateRow(rows);
      if (dateRow == null || dateRow.isEmpty) return {};
      double? dateRowY;
      final dateRe = RegExp(r'^\d{1,2}\.\d{2}\.$');
      for (final y in sortedYsDesc) {
        final matches = rows[y]!.where((e) => dateRe.hasMatch(e.$2)).length;
        if (matches >= 5) { dateRowY = y; break; }
      }
      if (dateRowY == null) return {};
      final calWords = {
        'MO','DI','MI','DO','FR','SA','SO','MON','DIE','MIT','DON','FRE','SAM','SON',
        'KW','KALENDERWOCHE','JUNI','JULI','AUGUST','SEPTEMBER','OKTOBER',
        'NOVEMBER','DEZEMBER','JANUAR','FEBRUAR','MÄRZ','APRIL','MAI','NAME','RESERVE','PERSONAL',
      };
      final aboveYs = sortedYsDesc.where((y) => y > dateRowY! + 5).toList();
      List<(double, String)>? eventRow;
      for (final y in aboveYs) {
        final rowItems = rows[y]!;
        final texts = rowItems.map((e) => e.$2.trim()).toList();
        final meaningful = texts.where((t) =>
          t.length >= 2 && !calWords.contains(t.toUpperCase()) &&
          !RegExp(r'^\d{1,2}\.\d{2}\.$').hasMatch(t) &&
          !RegExp(r'^\d{4}$').hasMatch(t) && !RegExp(r'^\d{1,2}$').hasMatch(t)
        ).toList();
        if (meaningful.length >= 2) { eventRow = rowItems.toList(); break; }
      }
      if (eventRow == null) return {};
      final result = <String, String>{};
      for (final (ex, eText) in eventRow) {
        final trimmed = eText.trim();
        if (trimmed.isEmpty) continue;
        if (calWords.contains(trimmed.toUpperCase())) continue;
        if (RegExp(r'^\d{1,2}\.\d{2}\.$').hasMatch(trimmed)) continue;
        if (RegExp(r'^\d{4}$').hasMatch(trimmed)) continue;
        double bestDist = double.infinity;
        (double, String)? bestDate;
        for (final dateCell in dateRow) {
          final dist = (ex - dateCell.$1).abs();
          if (dist < bestDist) { bestDist = dist; bestDate = dateCell; }
        }
        if (bestDate == null || bestDist > 60.0) continue;
        final parts = bestDate.$2.replaceAll(' ', '').split('.');
        if (parts.length < 2) continue;
        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        if (day == null || month == null) continue;
        final detectedMonth = _detectMonthFromText(rows, fileName);
        if (detectedMonth == null) continue;
        final key = DateFormat('yyyy-MM-dd').format(DateTime(detectedMonth.year, month, day));
        if (result.containsKey(key)) { result[key] = '${result[key]}, $trimmed'; }
        else { result[key] = trimmed; }
      }
      return result;
    } catch (e) { return {}; }
  }

  static String? _decompress(List<int> pdfBytes, StringBuffer log, bool devMode) {
    try {
      final data = Uint8List.fromList(pdfBytes);
      String? bestText; int bestLen = 0;
      final pdfAsLatin1 = latin1.decode(data, allowInvalid: true);
      int searchFrom = 0; int streamsChecked = 0;
      while (searchFrom < pdfAsLatin1.length) {
        final streamIdx = pdfAsLatin1.indexOf('stream', searchFrom);
        if (streamIdx == -1) break;
        if (streamIdx >= 3 && pdfAsLatin1.substring(streamIdx - 3, streamIdx) == 'end') { searchFrom = streamIdx + 6; continue; }
        int dataStart;
        if (streamIdx + 7 < pdfAsLatin1.length && pdfAsLatin1.codeUnitAt(streamIdx + 6) == 13 && pdfAsLatin1.codeUnitAt(streamIdx + 7) == 10) { dataStart = streamIdx + 8; }
        else if (streamIdx + 6 < pdfAsLatin1.length && pdfAsLatin1.codeUnitAt(streamIdx + 6) == 10) { dataStart = streamIdx + 7; }
        else { searchFrom = streamIdx + 6; continue; }
        final endIdx = pdfAsLatin1.indexOf('endstream', dataStart);
        if (endIdx == -1 || endIdx <= dataStart + 5) { searchFrom = streamIdx + 6; continue; }
        int dataEnd = endIdx;
        if (dataEnd > 0 && pdfAsLatin1.codeUnitAt(dataEnd - 1) == 10) dataEnd--;
        if (dataEnd > 0 && pdfAsLatin1.codeUnitAt(dataEnd - 1) == 13) dataEnd--;
        if (dataEnd <= dataStart + 5) { searchFrom = streamIdx + 6; continue; }
        streamsChecked++;
        try {
          final compressed = data.sublist(dataStart, dataEnd);
          final decompressed = ZLibDecoder().decodeBytes(compressed);
          final text = latin1.decode(Uint8List.fromList(decompressed), allowInvalid: true);
          if (text.length > bestLen && text.contains('BT') && text.contains('ET')) { bestLen = text.length; bestText = text; }
        } catch (_) {}
        searchFrom = streamIdx + 6;
      }
      if (devMode) log.writeln('[DEV] Streams geprüft: $streamsChecked, bester: $bestLen Zeichen');
      return bestText;
    } catch (_) { return null; }
  }

  static List<(double, double, String)> _extractCoordText(String stream) {
    final result = <(double, double, String)>[];
    final btEt = RegExp(r'BT(.*?)ET', dotAll: true);
    final tmRe = RegExp(r'([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+Tm');
    final tjaRe = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
    final innerRe = RegExp(r'\(((?:[^)\\]|\\.)*)\)');
    final tjSimpleRe = RegExp(r'\(((?:[^)\\]|\\.)*)\)\s*Tj');
    for (final block in btEt.allMatches(stream)) {
      final b = block.group(1)!;
      final tm = tmRe.firstMatch(b);
      if (tm == null) continue;
      final cx = double.parse(tm.group(5)!); final cy = double.parse(tm.group(6)!);
      String text = '';
      final tja = tjaRe.firstMatch(b);
      if (tja != null) {
        final buf = StringBuffer();
        for (final it in innerRe.allMatches(tja.group(1)!)) buf.write(_decodePdf(it.group(1)!));
        text = buf.toString().trim();
      } else {
        final tjS = tjSimpleRe.firstMatch(b);
        if (tjS != null) text = _decodePdf(tjS.group(1)!).trim();
      }
      if (text.isNotEmpty) result.add((cx, cy, text));
    }
    return result;
  }

  static String _decodePdf(String s) => s
      .replaceAll(r'\n', '\n').replaceAll(r'\r', '\r').replaceAll(r'\t', '\t')
      .replaceAll(r'\\', r'\').replaceAll(r'\(', '(').replaceAll(r'\)', ')');

  static Map<double, List<(double, String)>> _groupByY(
      List<(double, double, String)> items, {double tol = 3.0}) {
    final rows = <double, List<(double, String)>>{};
    for (final (x, y, t) in items) {
      double? bucket;
      for (final k in rows.keys) { if ((k - y).abs() <= tol) { bucket = k; break; } }
      bucket ??= y;
      rows.putIfAbsent(bucket, () => []).add((x, t));
    }
    return rows;
  }

  static (double, List<(double, String)>)? _findPersonRow(
    Map<double, List<(double, String)>> rows, List<double> sortedYsDesc,
    List<String> searchTerms, String originalUserName, bool devMode, StringBuffer log) {
    final nameFragments = _buildNameFragments(originalUserName, searchTerms);
    double? nameY;
    for (final y in sortedYsDesc) {
      final rowItems = (rows[y]!.toList())..sort((a, b) => a.$1.compareTo(b.$1));
      final rowText = rowItems.map((e) => e.$2.toLowerCase()).join(' ');
      bool matched = false;
      for (final term in searchTerms) { if (rowText.contains(term.toLowerCase())) { matched = true; break; } }
      if (!matched) continue;
      nameY = y; break;
    }
    if (nameY == null) return null;
    const maxGap = 25.0;
    final aboveRows = sortedYsDesc.where((y) => y > nameY! && (y - nameY!) <= maxGap).toList()
      ..sort((a, b) => (a - nameY!).compareTo(b - nameY!));
    for (final candidateY in aboveRows) {
      final candidateItems = (rows[candidateY]!.toList())..sort((a, b) => a.$1.compareTo(b.$1));
      final shiftCells = <(double, String)>[];
      for (final (x, text) in candidateItems) {
        if (_isNameElement(text, nameFragments, searchTerms)) continue;
        if (_looksLikeShift(text)) shiftCells.add((x, text));
      }
      if (shiftCells.isNotEmpty) return (candidateY, shiftCells);
    }
    return null;
  }

  static Set<String> _buildNameFragments(String originalUserName, List<String> searchTerms) {
    final fragments = <String>{};
    fragments.add(originalUserName.trim().toLowerCase());
    for (final t in searchTerms) fragments.add(t.toLowerCase());
    final parts = originalUserName.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).map((p) => p.toLowerCase()).toList();
    fragments.addAll(parts);
    return fragments;
  }

  static bool _isNameElement(String text, Set<String> nameFragments, List<String> searchTerms) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (nameFragments.contains(lower)) return true;
    for (final term in searchTerms) {
      if (lower.contains(term.toLowerCase()) || term.toLowerCase().contains(lower)) { if (!_looksLikeShift(text)) return true; }
    }
    if (text.contains(',') && text.length > 3) return true;
    return false;
  }

  static List<(double, String)>? _findDateRow(Map<double, List<(double, String)>> rows) {
    final dateRe = RegExp(r'^\d{1,2}\.\d{2}\.$');
    for (final entry in rows.entries) {
      final matches = entry.value.where((e) => dateRe.hasMatch(e.$2)).length;
      if (matches >= 5) {
        final dateCells = entry.value.where((e) => dateRe.hasMatch(e.$2)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
        return dateCells;
      }
    }
    return null;
  }

  static DateTime? _monthFromFilename(String filename) {
    final fn = filename.toLowerCase();
    for (final entry in _monthNames.entries) {
      if (fn.contains(entry.key)) {
        final yearMatch = RegExp(r'20(\d{2})').firstMatch(filename);
        final year = yearMatch != null ? int.parse('20${yearMatch.group(1)!}') : DateTime.now().year;
        return DateTime(year, entry.value);
      }
    }
    return null;
  }

  static DateTime? _detectMonthFromText(Map<double, List<(double, String)>> rows, String fileName) {
    final fromFilename = _monthFromFilename(fileName);
    if (fromFilename != null) return fromFilename;
    final allText = rows.values.expand((r) => r.map((e) => e.$2)).join(' ').toLowerCase();
    for (final entry in _monthNames.entries) {
      final idx = allText.indexOf(entry.key);
      if (idx != -1) {
        final region = allText.substring((idx - 5).clamp(0, allText.length), (idx + entry.key.length + 15).clamp(0, allText.length));
        final yearM = RegExp(r'20\d{2}').firstMatch(region);
        if (yearM != null) return DateTime(int.parse(yearM.group(0)!), entry.value);
      }
    }
    for (final row in rows.values) {
      for (final (_, text) in row) {
        final m = RegExp(r'\d{2}\.(\d{2})\.').firstMatch(text);
        if (m != null) {
          final monthNum = int.tryParse(m.group(1)!);
          if (monthNum != null && monthNum >= 1 && monthNum <= 12) return DateTime(DateTime.now().year, monthNum);
        }
      }
    }
    return null;
  }

  static List<String> _searchTerms(String fullName) {
    final terms = <String>{};
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return [];
    terms.add(trimmed.toLowerCase());
    final parts = trimmed.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return terms.toList();
    String lastName, firstName;
    if (fullName.contains(',')) { lastName = parts[0]; firstName = parts.length > 1 ? parts[1] : ''; }
    else { lastName = parts.last; firstName = parts.first; }
    final ln = lastName.toLowerCase(); final fn = firstName.toLowerCase();
    terms.add(ln);
    if (fn.length >= 2) { terms.add('${ln}, ${fn.substring(0, 2)}'); terms.add('${ln},${fn.substring(0, 2)}'); terms.add('${ln}, ${fn.substring(0, 2).toLowerCase()}'); }
    if (fn.length >= 3) { terms.add('${ln}, ${fn.substring(0, 3)}'); terms.add('${ln},${fn.substring(0, 3)}'); }
    if (fn.isNotEmpty) { terms.add('$ln, $fn'); terms.add('$ln,$fn'); }
    return terms.toList();
  }

  static bool _looksLikeShift(String s) {
    final u = s.trim().toUpperCase();
    if (u.isEmpty || u.length > 10) return false;
    if (RegExp(r'^\d+$').hasMatch(u)) return false;
    if (RegExp(r'^\d{1,2}\.\d{1,2}\.?$').hasMatch(u)) return false;
    const calWords = ['MO','DI','MI','DO','FR','SA','SO','MON','DIE','MIT','DON','FRE','SAM','SON',
        'NAME','RESERVE','JUNI','JULI','AUGUST','SEPTEMBER','OKTOBER','NOVEMBER','DEZEMBER',
        'JANUAR','FEBRUAR','MÄRZ','APRIL','MAI','KW','KALENDERWOCHE'];
    if (calWords.contains(u)) return false;
    if (RegExp(r'^\d{4}$').hasMatch(u)) return false;
    if (u.contains(',')) return false;
    if (u.length > 8 && RegExp(r'^[A-ZÄÖÜ]+$').hasMatch(u)) return false;
    const known = ['P1','P2','P','F1','F2','F','IS','T','L','AUF','U','DA','X','VK','RES','KDFT','GEB','LÜ','LUE','AF'];
    for (final k in known) {
      if (u == k) return true;
      if (u.startsWith('$k/') || u.endsWith('/$k')) return true;
    }
    return RegExp(r'^[A-ZÄÖÜ][A-ZÄÖÜ0-9]{0,4}(?:/[A-ZÄÖÜ][A-ZÄÖÜ0-9]{0,4})?$').hasMatch(u);
  }

  static Map<String, dynamic> _err(DateTime? month, String userMsg, bool devMode, StringBuffer log, {String? devDetail}) {
    final msg = devMode ? '$userMsg${devDetail != null ? '\n\n$devDetail' : (log.isNotEmpty ? '\n\n[DEV LOG]\n$log' : '')}' : userMsg;
    return {'month': month, 'data': <String, String>{}, 'error': msg};
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notizen-Daten Helfer
// ─────────────────────────────────────────────────────────────────────────────

class _NoteData {
  String phone;
  String text;
  _NoteData({this.phone = '', this.text = ''});
 
  static String _hiveKey(String dateKey) => 'schedule_note_$dateKey';
 
  static _NoteData load(String dateKey) {
    final box = Hive.box('einstellungen');
    final raw = box.get(_hiveKey(dateKey));
    if (raw is Map) {
      return _NoteData(
        phone: (raw['phone'] ?? '') as String,
        text: (raw['text'] ?? '') as String,
      );
    }
    return _NoteData();
  }
 
  // NEU: static Future<void> statt void, und await flush()
  static Future<void> save(String dateKey, String phone, String text) async {
    final box = Hive.box('einstellungen');
    await box.put(_hiveKey(dateKey), {'phone': phone, 'text': text});
    await box.flush(); // ← await ist entscheidend!
  }
 
  bool get isEmpty => phone.isEmpty && text.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// KOLLEGEN-SUCHE: Datenhilfen + zuletzt Ausgewählter
// ─────────────────────────────────────────────────────────────────────────────

/// Liefert alle im Dienstplan-PDF erkannten Kollegen-Nachnamen für einen Monat.
List<String> colleagueNamesForMonth(String monthKey) {
  final box = Hive.box('einstellungen');
  final raw = box.get('colleagues_$monthKey');
  if (raw is! String || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final names = <String>{};
    for (final dayEntry in decoded.values) {
      if (dayEntry is Map) {
        names.addAll(dayEntry.keys.map((k) => k.toString()));
      }
    }
    return names.toList()..sort();
  } catch (_) {
    return [];
  }
}

/// Liefert den kompletten Dienstplan (dateKey → Schicht) eines Kollegen für einen Monat.
Map<String, String> foreignScheduleFor(String name, String monthKey) {
  final box = Hive.box('einstellungen');
  final raw = box.get('colleagues_$monthKey');
  if (raw is! String || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = <String, String>{};
    for (final entry in decoded.entries) {
      final dayData = entry.value;
      if (dayData is Map && dayData.containsKey(name)) {
        result[entry.key] = dayData[name].toString();
      }
    }
    return result;
  } catch (_) {
    return {};
  }
}

/// Zwischenspeicher für den zuletzt gesuchten Kollegen (übersteht Neustart).
class LastColleagueSearch {
  static const _key = 'last_colleague_search';
  static String? load() => Hive.box('einstellungen').get(_key) as String?;
  static void save(String name) => Hive.box('einstellungen').put(_key, name);
  static void clear() => Hive.box('einstellungen').delete(_key);
}

// NEU (einfügen nach der LastColleagueSearch-Klasse)
String _ownDisplayName() {
  final box = Hive.box('einstellungen');
  final scheduleName = (box.get('dienstplan_name') as String?) ?? '';
  final mainName = (box.get('name') as String?) ?? '';
  final fullName = scheduleName.isNotEmpty ? scheduleName : mainName;
  if (fullName.contains(',')) return fullName.split(',').first.trim();
  final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  return parts.isNotEmpty ? parts.last : '';
}

// ─────────────────────────────────────────────────────────────────────────────
// KOLLEGEN-SUCHE SHEET
// ─────────────────────────────────────────────────────────────────────────────

class ColleagueSearchSheet extends StatefulWidget {
  final AppSkin skin;
  final DateTime initialMonth;
  final void Function(String name, DateTime month) onConfirm;

  const ColleagueSearchSheet({
    super.key, required this.skin, required this.initialMonth, required this.onConfirm,
  });

  @override
  State<ColleagueSearchSheet> createState() => _ColleagueSearchSheetState();
}

class _ColleagueSearchSheetState extends State<ColleagueSearchSheet> {
  late DateTime _month;
  List<String> _names = [];
  String? _selected;

  AppSkin get skin => widget.skin;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    _loadNames();
  }

  void _loadNames() {
    final monthKey = DateFormat('yyyy-MM').format(_month);
    List<String> names = [];
    try {
      names = colleagueNamesForMonth(monthKey);
      names.removeWhere((n) => n.toLowerCase() == _ownDisplayName().toLowerCase());
    } catch (_) {
      names = [];
    }
    final last = LastColleagueSearch.load();
    if (last != null && names.contains(last)) {
      names.remove(last);
      names.insert(0, last);
    }
    setState(() {
      _names = names;
      _selected = names.isNotEmpty ? names.first : null;
    });
  }

  bool get _isDevMode => Hive.box('einstellungen').get('dienstplan_dev_placeholder', defaultValue: false) as bool;

  String _debugInfo(String monthKey) {
    final box = Hive.box('einstellungen');
    final raw = box.get('colleagues_$monthKey');
    if (raw == null) return '[DEV] colleagues_$monthKey: nicht vorhanden';
    if (raw is! String) return '[DEV] colleagues_$monthKey: falscher Typ (${raw.runtimeType})';
    if (raw.isEmpty) return '[DEV] colleagues_$monthKey: leerer String';
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return '[DEV] colleagues_$monthKey: ${decoded.length} Tage gespeichert';
    } catch (e) {
      return '[DEV] colleagues_$monthKey: JSON-Fehler: $e';
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadNames();
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheet(
      skin: skin,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: SheetHandle(skin: skin)),
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.people_outline, color: skin.primary, size: 20),
              const SizedBox(width: 10),
              Text('Kollege suchen',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: skin.textPrimary)),
            ]),
            const SizedBox(height: 18),

            // ── Monat (wiederverwendet: GlassNavCard aus glass_kit.dart) ──
            GlassNavCard(
              onPrevious: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
              child: Text(DateFormat('MMMM yyyy', 'de').format(_month),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary)),
            ),
            const SizedBox(height: 16),

            if (_names.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(children: [
                    Icon(Icons.people_outline, size: 28, color: skin.textMuted.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text('Keine Kollegen-Daten für diesen Monat.',
                        style: TextStyle(color: skin.textMuted, fontSize: 13), textAlign: TextAlign.center),
                    if (_isDevMode) ...[
                      const SizedBox(height: 6),
                      Text(_debugInfo(DateFormat('yyyy-MM').format(_month)),
                          style: TextStyle(color: skin.textMuted.withValues(alpha: 0.6), fontSize: 10),
                          textAlign: TextAlign.center),
                    ],
                  ]),
                ),
              )
            else ...[
              Text('Kollegen (zuletzt Ausgewählter zuerst)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 0.6)),
              const SizedBox(height: 8),

              // ── Kachel-Slider ──
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _names.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final name = _names[i];
                    final isSelected = name == _selected;
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = name);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 72,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? skin.primary.withValues(alpha: 0.14) : skin.surface(0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? skin.primary.withValues(alpha: 0.5) : skin.glassBorder,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? skin.primary : skin.surface(0.10),
                            ),
                            child: Center(
                              child: Text(initial,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                      color: isSelected ? Colors.white : skin.textMuted)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? skin.primary : skin.textPrimary)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),

              // ── Dropdown als Alternative (wiederverwendet: GlassDropdownButton aus glass_kit.dart) ──
              GlassSurface(
                padding: EdgeInsets.zero,
                child: GlassDropdownButton<String>(
                  value: _selected ?? _names.first,
                  items: _names.map((n) => GlassDropdownItem(value: n, label: n)).toList(),
                  onChanged: (v) => setState(() => _selected = v),
                  label: 'Oder auswählen',
                  displayBuilder: (v) => v,
                  icon: Icons.list_alt_outlined,
                  isLast: true,
                ),
              ),
              const SizedBox(height: 20),
            ],

            Row(children: [
              Expanded(
                child: GlassSecondaryButton(
                  skin: skin, label: 'Abbrechen', onTap: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassPrimaryButton(
                  skin: skin,
                  label: 'Anzeigen',
                  onTap: _selected == null
                      ? () {}
                      : () {
                          LastColleagueSearch.save(_selected!);
                          Navigator.pop(context);
                          widget.onConfirm(_selected!, _month);
                        },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScheduleScreen
// ─────────────────────────────────────────────────────────────────────────────

class ScheduleScreen extends StatefulWidget {
  final VoidCallback onNavigateToHome;
  final VoidCallback onNavigateToMonth;
  final void Function(DateTime)? onMonthChanged;
  final ValueNotifier<bool>? dayCardDragging;
  final void Function(bool)? onForeignViewChanged;

  const ScheduleScreen({
    super.key, required this.onNavigateToHome, required this.onNavigateToMonth,
    this.onMonthChanged, this.dayCardDragging, this.onForeignViewChanged,
  });

  @override
  State<ScheduleScreen> createState() => ScheduleScreenState();
}

class ScheduleScreenState extends State<ScheduleScreen> {
  late DateTime _selectedMonth;
  Map<String, String> _scheduleData = {};
  Map<String, String> _eventsData = {};
  String? _activeNoteKey;
  bool _noteOverlayVisible = false;
  String? _activeColleaguesKey;
  bool _colleaguesOverlayVisible = false;
  String? _colleaguesViewerName;
  String? _openSwipedCardKey;

  // ── NEU: Kollegen-Fremdansicht ──
  String? _viewingColleague;
  DateTime? _viewingColleagueMonth;
  bool get isForeignView => _viewingColleague != null;

  final ScrollController _listScrollController = ScrollController();
  final Map<String, double> _scrollPositions = {};

  static Future<void> pushScheduleToWidget() async {
    if (kIsWeb) return;
    try {
      final box = Hive.box('einstellungen');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month);
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final entries = <Map<String, String>>[];
      for (int offset = 0; offset <= 2; offset++) {
        final month = DateTime(today.year, today.month + offset);
        final monthKey = DateFormat('yyyy-MM').format(month);
        final raw = box.get('schedule_$monthKey');
        if (raw is Map) {
          for (final e in raw.entries) {
            final dateKey = e.key.toString();
            final noteRaw = box.get('schedule_note_$dateKey');
            bool hasNote = false;
            if (noteRaw is Map) {
              final phone = (noteRaw['phone'] ?? '') as String;
              final text = (noteRaw['text'] ?? '') as String;
              hasNote = phone.isNotEmpty || text.isNotEmpty;
            }
            entries.add({'date': dateKey, 'shift': e.value.toString(), if (hasNote) 'hasNote': 'true'});
          }
        }
      }
      final filtered = entries.where((e) => (e['date'] ?? '').compareTo(todayStr) >= 0).toList()
        ..sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));
      final json = jsonEncode(filtered);
      const _widgetChannel = MethodChannel('de.marcel.optimes/widget');
      await _widgetChannel.invokeMethod('updateSchedule', {'json': json});
    } catch (e) { debugPrint('❌ Widget push ERROR: $e'); }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    loadScheduleData();
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    _scrollPositions[monthKey] = 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
  }

  @override
  void dispose() { _listScrollController.dispose(); super.dispose(); }

  void scrollToTop() {
    if (_listScrollController.hasClients) {
      _listScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  bool get _isDevMode {
    final box = Hive.box('einstellungen');
    return box.get('dienstplan_dev_placeholder', defaultValue: false) as bool;
  }

  void loadScheduleData() {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final raw = box.get('schedule_$monthKey');
    setState(() {
      _scheduleData = {};
      if (raw is Map) { for (final entry in raw.entries) { _scheduleData[entry.key.toString()] = entry.value.toString(); } }
      _eventsData = {};
      final eventsRaw = box.get('events_$monthKey');
      if (eventsRaw is String) {
        try {
          final decoded = jsonDecode(eventsRaw) as Map<String, dynamic>;
          for (final e in decoded.entries) { _eventsData[e.key] = e.value.toString(); }
        } catch (_) {}
      }
    });
  }

  void refreshTaskMarkers() => setState(() {});

  void scrollToToday() {
    final now = DateTime.now();
    if (_selectedMonth.year != now.year || _selectedMonth.month != now.month) return;
    if (!_listScrollController.hasClients) return;
    final todayIndex = now.day - 1;
    const cardHeight = 68.0;
    final offset = (todayIndex * cardHeight).clamp(0.0, _listScrollController.position.maxScrollExtent);
    _listScrollController.animateTo(offset, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  void _setMonth(DateTime month) {
    if (_listScrollController.hasClients) {
      final currentKey = DateFormat('yyyy-MM').format(_selectedMonth);
      _scrollPositions[currentKey] = _listScrollController.offset;
    }
    setState(() => _selectedMonth = month);
    widget.onMonthChanged?.call(month);
    loadScheduleData();
    final monthKey = DateFormat('yyyy-MM').format(month);
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listScrollController.hasClients) return;
      if (isCurrentMonth && !_scrollPositions.containsKey(monthKey)) {
        scrollToToday();
      } else {
        _listScrollController.animateTo(
          _scrollPositions[monthKey] ?? 0.0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  void scrollToCurrentMonth() {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final monthKey = DateFormat('yyyy-MM').format(currentMonth);
    _scrollPositions.remove(monthKey);
    _setMonth(currentMonth);
  }

  void _changeMonth(int delta) => _setMonth(DateTime(_selectedMonth.year, _selectedMonth.month + delta));

  // ── NEU: Anzeige-Daten (eigener Plan ODER Kollegen-Fremdansicht) ──
  Map<String, String> get _displayScheduleData {
    if (isForeignView) {
      final monthKey = DateFormat('yyyy-MM').format(_viewingColleagueMonth ?? _selectedMonth);
      return foreignScheduleFor(_viewingColleague!, monthKey);
    }
    return _scheduleData;
  }

  bool get _hasSchedule => _displayScheduleData.isNotEmpty;
  int get _workDays => _displayScheduleData.values.where((v) { final cat = ScheduleEntry(v).category; return cat == ShiftCategory.work || cat == ShiftCategory.mixed; }).length;
  int get _freeDays => _displayScheduleData.values.where((v) => ScheduleEntry(v).category == ShiftCategory.free).length;
  int get _sonderDays => _displayScheduleData.values.where((v) {
  final parts = v.trim().toUpperCase().split('/').map((p) => p.trim());
  return parts.contains('VK') || parts.contains('IS');
}).length;

  List<DateTime> get _daysInMonth {
    final base = isForeignView ? (_viewingColleagueMonth ?? _selectedMonth) : _selectedMonth;
    final year = base.year; final month = base.month;
    final count = DateUtils.getDaysInMonth(year, month);
    return List.generate(count, (i) => DateTime(year, month, i + 1));
  }

  // ── Monatspicker: jetzt über showMonthYearPicker aus glass_pickers.dart ──
  Future<void> _showMonthPicker() async {
    final skin = AppTheme.of(context);
    final result = await showMonthYearPicker(
      context: context, skin: skin, initialMonth: _selectedMonth);
    if (result != null) _setMonth(result);
  }

  // ── NEU: Kollegen-Suche öffnen / verlassen ──
  Future<void> openColleagueSearch() async {
    final skin = AppTheme.of(context);
    closeOverlays();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ColleagueSearchSheet(
        skin: skin,
        initialMonth: isForeignView ? (_viewingColleagueMonth ?? _selectedMonth) : _selectedMonth,
        onConfirm: (name, month) {
          setState(() {
            _viewingColleague = name;
            _viewingColleagueMonth = month;
          });
          widget.onForeignViewChanged?.call(true);
        },
      ),
    );
  }

  void leaveColleagueView() {
    setState(() {
      _viewingColleague = null;
      _viewingColleagueMonth = null;
    });
    widget.onForeignViewChanged?.call(false);
  }

  void openNoteOverlay(String dateKey) {
    HapticFeedback.lightImpact();
    setState(() { _activeNoteKey = dateKey; _noteOverlayVisible = true; });
  }

  void _closeNoteOverlay() => setState(() { _noteOverlayVisible = false; _activeNoteKey = null; });

  void openColleaguesOverlay(String dateKey, {String? viewerName}) {
    HapticFeedback.lightImpact();
    setState(() {
      _activeColleaguesKey = dateKey;
      _colleaguesOverlayVisible = true;
      _colleaguesViewerName = viewerName;
    });
  }

  void _closeColleaguesOverlay() => setState(() {
    _colleaguesOverlayVisible = false;
    _activeColleaguesKey = null;
    _colleaguesViewerName = null;
  });

  void closeOverlays() {
    if (_noteOverlayVisible) _closeNoteOverlay();
    if (_colleaguesOverlayVisible) _closeColleaguesOverlay();
    if (_openSwipedCardKey != null) setState(() => _openSwipedCardKey = null);
  }

  Future<void> _deleteCurrentMonth(AppSkin skin) async {
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final displayMonth = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);

    // ── confirmDeleteDialog aus glass_dialogs.dart ──
    final confirmed = await confirmDeleteDialog(
      context: context, skin: skin,
      title: 'Monat löschen',
      message: 'Alle Dienstplan-Daten werden unwiderruflich gelöscht.',
      extraContent: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: skin.surface(0.05), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: skin.glassBorder),
            ),
            child: Row(children: [
              Icon(Icons.calendar_month_outlined, color: skin.deleteColor, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(displayMonth,
                  style: TextStyle(color: skin.textPrimary, fontSize: 13, fontWeight: FontWeight.w500))),
            ]),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final box = Hive.box('einstellungen');
    box.delete('schedule_$monthKey');
    _ChangedDays.clear(monthKey);
    await ScheduleScreenState.pushScheduleToWidget();
    if (mounted) {
      loadScheduleData();
      showGlassSnackBar(
  context,
  'Dienstplan $displayMonth gelöscht',
  type: GlassSnackBarType.error,
  duration: const Duration(seconds: 3),
);
}
}

  void _onCardSwiped(String? dateKey) => setState(() => _openSwipedCardKey = dateKey);

  // ── NEU: Banner für die Kollegen-Fremdansicht ──
  Widget _buildForeignBanner(AppSkin skin) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: skin.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.primary.withValues(alpha: 0.32)),
          ),
          child: Row(children: [
            Icon(Icons.visibility_outlined, color: skin.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Ansicht: ', style: TextStyle(fontSize: 14, color: skin.primary.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
                  TextSpan(text: _viewingColleague, style: TextStyle(fontSize: 15, color: skin.primary, fontWeight: FontWeight.w700)),
                ]),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: leaveColleagueView,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: skin.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Verlassen',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.close_rounded, color: skin.primary, size: 14),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isChrome = skin.key == 'chrome';
    final displayMonth = isForeignView ? (_viewingColleagueMonth ?? _selectedMonth) : _selectedMonth;
    final monthName = DateFormat('MMMM yyyy', 'de').format(displayMonth);
    final days = _daysInMonth;
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final changedDays = isForeignView ? <String>{} : _ChangedDays.load(monthKey);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: GestureDetector(
        onTap: () { if (_openSwipedCardKey != null) setState(() => _openSwipedCardKey = null); },
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: ColoredBox(
                color: skin.bgBase,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 50),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isForeignView)
                            _buildForeignBanner(skin)
                          else
                            Row(children: [
                            Text('Dienstplan',
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                            const SizedBox(width: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.4)),
                                  ),
                                  child: const Text('BETA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFFB347), letterSpacing: 0.8)),
                                ),
                              ),
                            ),
                            if (_isDevMode) ...[
                              const SizedBox(width: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF5B5B).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFEF5B5B).withValues(alpha: 0.4)),
                                    ),
                                    child: const Text('DEV', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFEF5B5B), letterSpacing: 0.8)),
                                  ),
                                ),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 16),

                          GlassNavCard(
  onPrevious: () => _changeMonth(-1),
  onNext: () => _changeMonth(1),
  onTap: isForeignView ? null : _showMonthPicker,
  onDoubleTap: isForeignView ? null : () {
  HapticFeedback.selectionClick();
  final now = DateTime.now();
  final isAlreadyCurrentMonth =
      _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  if (isAlreadyCurrentMonth) {
    scrollToToday();
  } else {
    scrollToCurrentMonth();
  }
},
  onSwipe: isForeignView ? null : (v) {
    if (v < -300) _changeMonth(1);
    if (v > 300) _changeMonth(-1);
  },
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(monthName,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: skin.textPrimary)),
      if (!isForeignView) ...[
        const SizedBox(width: 6),
        Icon(Icons.expand_more, color: skin.primary, size: 18),
      ],
    ],
  ),
),
                          const SizedBox(height: 12),

                          // ── GlassStatCard aus glass_kit.dart ──
                          Row(children: [
                            GlassStatCard(label: 'Arbeit', value: '$_workDays',
                                color: isChrome ? const Color(0xFFDDDDDD) : const Color(0xFF5B8DEF)),
                            const SizedBox(width: 10),
                            GlassStatCard(label: 'Frei', value: '$_freeDays',
                                color: isChrome ? const Color(0xFF666666) : const Color(0xFF6B7280)),
                            const SizedBox(width: 10),
                            GlassStatCard(label: 'Sonder', value: '$_sonderDays',
                                color: isChrome ? const Color(0xFF999999) : const Color(0xFFEF5B5B)),
                          ]),

                          if (_hasSchedule) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              const SizedBox(width: 5),
                              Text(
                                  isForeignView
                                      ? 'Doppeltippen · Kollegen aus dieser Sicht ansehen'
                                      : 'Wischen  ·  Gedrückt Halten · Doppeltippen',
                                  style: TextStyle(fontSize: 11, color: skin.surface(0.28))),
                            ]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Expanded(
                      child: !_hasSchedule
                          ? Center(
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Text('📋', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                    isForeignView
                                        ? 'Kein Dienstplan für $_viewingColleague in diesem Monat'
                                        : 'Kein Dienstplan hinterlegt',
                                    style: TextStyle(color: skin.surface(0.3), fontSize: 15)),
                                const SizedBox(height: 8),
                                Text(
                                    isForeignView
                                        ? 'Tippe oben auf das Banner, um zurückzukehren'
                                        : 'Tippe oben auf ☰ → Dienstplan importieren',
                                    style: TextStyle(color: skin.surface(0.2), fontSize: 12), textAlign: TextAlign.center),
                              ]),
                            )
                          // ── FadingListView aus glass_kit.dart ──
                          : FadingListView(
                              fadeFromBottom: bottomNavHeight + 20,
                              child: ListView.builder(
                                controller: _listScrollController,
                                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                                itemCount: days.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == days.length) {
                                    final bool isLeaveButton = isForeignView;
                                    return Padding(
                                      padding: EdgeInsets.only(top: 8, bottom: bottomNavHeight + 40),
                                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        GestureDetector(
                                          onTap: isLeaveButton ? leaveColleagueView : () => _deleteCurrentMonth(skin),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 20),
                                                decoration: BoxDecoration(
                                                  color: isLeaveButton
                                                      ? skin.primary.withValues(alpha: 0.07)
                                                      : skin.deleteColor.withValues(alpha: 0.07),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: isLeaveButton
                                                          ? skin.primary.withValues(alpha: 0.22)
                                                          : skin.deleteColor.withValues(alpha: 0.22)),
                                                ),
                                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  if (isLeaveButton) ...[
                                                    Text('Ansicht verlassen',
                                                        style: TextStyle(color: skin.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                                                    const SizedBox(width: 7),
                                                    Icon(Icons.close_rounded, color: skin.primary, size: 16),
                                                  ] else ...[
                                                    Icon(Icons.delete_outline, color: skin.deleteColor, size: 16),
                                                    const SizedBox(width: 7),
                                                    Text('Aktuellen Monat löschen',
                                                        style: TextStyle(color: skin.deleteColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                                  ],
                                                ]),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ]),
                                    );
                                  }
                                  final day = days[index];
                                  final key = DateFormat('yyyy-MM-dd').format(day);
                                  final shift = _displayScheduleData[key] ?? '';
                                  final entry = shift.isEmpty ? null : ScheduleEntry(shift);
                                                                    return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _DayCard(
                                      day: day, entry: entry, skin: skin, isChrome: isChrome,
                                      dateKey: key, isChanged: changedDays.contains(key),
                                      externallyOpenKey: _openSwipedCardKey,
                                      onCardSwiped: _onCardSwiped,
                                      onOpenNote: () => openNoteOverlay(key),
                                      onNoteChanged: () => setState(() {}),
                                      onOpenColleagues: () => openColleaguesOverlay(
                                        key,
                                        viewerName: isForeignView ? _viewingColleague : null,
                                      ),
                                      dayCardDragging: widget.dayCardDragging,
                                      eventText: _eventsData[key],
                                      hasTask: !isForeignView && entry != null && TaskStore.hasOpenTaskOnDay(day), // NEU
                                      foreignMode: isForeignView, // NEU
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            if (_noteOverlayVisible && _activeNoteKey != null)
              _NoteOverlay(dateKey: _activeNoteKey!, skin: skin, onClose: _closeNoteOverlay),

            if (_colleaguesOverlayVisible && _activeColleaguesKey != null)
              _ColleaguesOverlay(
                dateKey: _activeColleaguesKey!, skin: skin, onClose: _closeColleaguesOverlay,
                viewerName: _colleaguesViewerName,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTE OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _NoteOverlay extends StatefulWidget {
  final String dateKey;
  final AppSkin skin;
  final VoidCallback onClose;
  const _NoteOverlay({required this.dateKey, required this.skin, required this.onClose});

  @override
  State<_NoteOverlay> createState() => _NoteOverlayState();
}

class _NoteOverlayState extends State<_NoteOverlay> with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;
  final _phoneCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _textFocus = FocusNode();
  bool _copiedPhone = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
    _opacityAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    final note = _NoteData.load(widget.dateKey);
    _phoneCtrl.text = note.phone;
    _textCtrl.text = note.text;
    _ctrl.forward();
    _phoneFocus.addListener(() => setState(() {}));
    _textFocus.addListener(() => setState(() {}));
    _textCtrl.addListener(() => setState(() {}));
    _phoneCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose(); _phoneCtrl.dispose(); _textCtrl.dispose();
    _phoneFocus.dispose(); _textFocus.dispose();
    super.dispose();
  }

  Future<void> _saveAndClose() async {
    await _NoteData.save(widget.dateKey, _phoneCtrl.text.trim(), _textCtrl.text.trim());
    await ScheduleScreenState.pushScheduleToWidget();
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onClose();
  }

  void _dismissKeyboard() { _phoneFocus.unfocus(); _textFocus.unfocus(); }

  void _copyPhone() {
    if (_phoneCtrl.text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _phoneCtrl.text.trim()));
    setState(() => _copiedPhone = true);
    HapticFeedback.selectionClick();
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _copiedPhone = false); });
  }

  AppSkin get skin => widget.skin;

  Widget _buildTasksSection() {
  final day = DateTime.tryParse(widget.dateKey);
  if (day == null) return const SizedBox.shrink();

  final tasks = TaskStore.loadAll().where((t) =>
    !t.done &&
    t.dueDate != null &&
    t.dueDate!.year == day.year &&
    t.dueDate!.month == day.month &&
    t.dueDate!.day == day.day,
  ).toList();

  if (tasks.isEmpty) return const SizedBox.shrink();

  final skin = widget.skin;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Divider(color: skin.glassBorder, height: 1),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.task_alt_outlined, size: 11, color: skin.primary),
              const SizedBox(width: 4),
              Text('AUFGABEN', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: skin.primary, letterSpacing: 0.8,
              )),
            ]),
            const SizedBox(height: 10),
            ...tasks.map((t) {
              final isToday = t.isToday;
              final isOverdue = t.isOverdue;
              Color timeColor = skin.primary;
              if (isOverdue) timeColor = const Color(0xFFEF5B5B);
              else if (isToday) timeColor = const Color(0xFFFFB347);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: skin.surface(0.28), width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(t.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: skin.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (t.hasTime) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${t.dueDate!.hour.toString().padLeft(2,'0')}:${t.dueDate!.minute.toString().padLeft(2,'0')}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: timeColor,
                        ),
                      ),
                    ] else if (isOverdue) ...[
                      const SizedBox(width: 8),
                      Text('überfällig', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: const Color(0xFFEF5B5B),
                      )),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final safeTop = MediaQuery.of(context).padding.top;
    final cardTop = (safeTop + 56.0).clamp(safeTop + 48.0, screenH * 0.3);
    final maxCardHeight = screenH - cardTop - keyboardH - 32.0;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Stack(
          children: [
            GestureDetector(
              onTap: _saveAndClose,
              onVerticalDragUpdate: (d) { if (d.delta.dy > 8) _dismissKeyboard(); },
              child: Opacity(
                opacity: _opacityAnim.value * 0.55,
                child: Container(color: Colors.black, width: double.infinity, height: double.infinity),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180), curve: Curves.easeOut,
              top: cardTop, left: 20, right: 20,
              child: Transform.scale(
                scale: 0.85 + _scaleAnim.value * 0.15,
                child: Opacity(opacity: _opacityAnim.value.clamp(0.0, 1.0), child: child!),
              ),
            ),
          ],
        );
      },
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 180.0, maxHeight: maxCardHeight.clamp(180.0, screenH * 0.6)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                child: Container(
                  decoration: BoxDecoration(
                    color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: skin.glassBorder, width: 1.0),
                    boxShadow: [
                      BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                      BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                          child: Row(children: [
                            Icon(Icons.sticky_note_2_outlined, size: 18, color: skin.primary),
                            const SizedBox(width: 10),
                            Expanded(child: Text('NOTIZEN',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 1.0))),
                            GestureDetector(
                              onTap: _saveAndClose,
                              // ── GlassIconBadge aus glass_kit.dart ──
                              child: GlassIconBadge(skin: skin, icon: Icons.close),
                            ),
                          ]),
                        ),
                        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Divider(color: skin.glassBorder, height: 1)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(Icons.phone_outlined, size: 11, color: skin.primary),
                              const SizedBox(width: 4),
                              Text('TELEFONNUMMER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 0.8)),
                            ]),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _phoneCtrl, focusNode: _phoneFocus,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]'))],
                              style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: '+49 123 456789', hintStyle: TextStyle(color: skin.surface(0.22), fontSize: 17),
                                border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                                suffixIcon: _phoneCtrl.text.trim().isEmpty ? null : GestureDetector(
                                  onTap: _copyPhone,
                                  child: Padding(padding: const EdgeInsets.only(right: 4),
                                      child: Icon(_copiedPhone ? Icons.check_rounded : Icons.copy_outlined,
                                          size: 16, color: _copiedPhone ? skin.statComplete : skin.surface(0.45))),
                                ),
                                suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _dismissKeyboard(),
                            ),
                          ]),
                        ),
                        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Divider(color: skin.glassBorder, height: 1)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(Icons.notes_outlined, size: 11, color: skin.primary),
                              const SizedBox(width: 4),
                              Text('NOTIZ', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 0.8)),
                            ]),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _textCtrl, focusNode: _textFocus, maxLines: null,
                              style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: 'Notiz eingeben...', hintStyle: TextStyle(color: skin.surface(0.22), fontSize: 17),
                                border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                              ),
                              textCapitalization: TextCapitalization.sentences, textInputAction: TextInputAction.newline,
                            ),
                          ]),
                        ),
                        _buildTasksSection(),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KOLLEGEN OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _ColleaguesOverlay extends StatefulWidget {
  final String dateKey;
  final AppSkin skin;
  final VoidCallback onClose;
  /// NEU: Wenn gesetzt, wird dieser Name als "isSelf" markiert statt des
  /// echten App-Nutzers – für die Fremdansicht aus Sicht eines Kollegen.
  final String? viewerName;
  const _ColleaguesOverlay({
    required this.dateKey, required this.skin, required this.onClose, this.viewerName,
  });

  @override
  State<_ColleaguesOverlay> createState() => _ColleaguesOverlayState();
}

class _ColleaguesOverlayState extends State<_ColleaguesOverlay> with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;
  bool _expanded = false;
  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;
  Map<String, String> _colleagues = {};
  String? _eventText;
  List<String> _ownShiftParts = []; // eigener (oder Fremd-)Dienst des Tages, gesplittet an "/"
  String _ownName = '';             // eigener (oder Fremd-)Anzeigename
  String? _debugLog;
  bool _debugLogCopied = false;
  double _dragStartGlobalY = 0.0;
  bool _isDraggingExpand = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
    _opacityAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    _expandCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    _ctrl.forward();
    _loadData();
  }

  @override
  void dispose() { _ctrl.dispose(); _expandCtrl.dispose(); super.dispose(); }

  void _loadData() {
    final box = Hive.box('einstellungen');
    final monthKey = widget.dateKey.substring(0, 7);

    // ── Kollegen zuerst laden (wird für beide Fälle gebraucht) ──
    Map<String, String> colleagues = {};
    final raw = box.get('colleagues_$monthKey');
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final dayData = decoded[widget.dateKey];
        if (dayData is Map) {
          colleagues = Map<String, String>.from(dayData.map((k, v) => MapEntry(k.toString(), v.toString())));
        }
      } catch (_) {}
    }

    String ownShift;
    String ownDisplayName;

    if (widget.viewerName != null) {
      // ── Fremdansicht: "ich" bin der gesuchte Kollege ──
      ownDisplayName = widget.viewerName!;
      ownShift = colleagues[widget.viewerName] ?? '';
      colleagues.remove(widget.viewerName); // nicht doppelt in der generischen Liste anzeigen
    } else {
      // ── Normalfall: echter App-Nutzer ──
      final scheduleRaw = box.get('schedule_$monthKey');
      ownShift = '';
      if (scheduleRaw is Map) { ownShift = (scheduleRaw[widget.dateKey] ?? '').toString(); }
      ownDisplayName = _ownDisplayName();
      colleagues.removeWhere((k, v) => k.toLowerCase() == ownDisplayName.toLowerCase());
    }

    final evRaw = box.get('events_$monthKey');
    String? eventText;
    if (evRaw is String) {
      try {
        final decoded = jsonDecode(evRaw) as Map<String, dynamic>;
        final dayEvent = decoded[widget.dateKey];
        if (dayEvent is String && dayEvent.isNotEmpty) eventText = dayEvent;
      } catch (_) {}
    }

    final isDevMode = box.get('dienstplan_dev_placeholder', defaultValue: false) as bool;
    String? debugLog;
    if (isDevMode) {
      final debugRaw = box.get('colleagues_debug_$monthKey');
      if (debugRaw is String && debugRaw.isNotEmpty) debugLog = debugRaw;
    }

    setState(() {
      _colleagues = colleagues;
      _ownShiftParts = ownShift.trim().toUpperCase().split('/').map((s) => s.trim()).toList();
      _ownName = ownDisplayName;
      _eventText = eventText;
      _debugLog = debugLog;
    });
  }

  void _close() => _ctrl.reverse().then((_) => widget.onClose());
  void _expand() { setState(() => _expanded = true); _expandCtrl.animateTo(1.0, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic); }
  void _collapse() { _expandCtrl.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeInCubic).then((_) => setState(() => _expanded = false)); }

  void _onDragStart(DragStartDetails d) { _dragStartGlobalY = d.globalPosition.dy; _isDraggingExpand = true; }
  void _onDragUpdate(DragUpdateDetails d) {}
  void _onDragEnd(DragEndDetails d) {
    if (!_isDraggingExpand) return;
    _isDraggingExpand = false;
    final dy = d.globalPosition.dy - _dragStartGlobalY;
    final vel = d.primaryVelocity ?? 0;
    if ((dy > 30 || vel > 300) && !_expanded) { _expand(); }
    else if ((dy < -30 || vel < -300) && _expanded) { _collapse(); }
  }

  AppSkin get skin => widget.skin;

  List<({String name, bool isSelf})> _namesForShifts(List<String> shiftCodes) {
    final result = <({String name, bool isSelf})>[];
    final upperCodes = shiftCodes.map((c) => c.toUpperCase()).toList();
    for (final entry in _colleagues.entries) {
      final rawShift = entry.value.trim().toUpperCase();
      final shiftParts = rawShift.split('/').map((s) => s.trim()).toList();
      bool matches = false;
      for (final code in upperCodes) { if (shiftParts.contains(code)) { matches = true; break; } }
      if (matches) {
        final name = entry.key.contains(',') ? entry.key.split(',').first.trim() : entry.key.trim();
        result.add((name: name, isSelf: false));
      }
    }
    // eigenen (oder Fremd-)Dienst nahtlos mit einsortieren
    if (_ownName.isNotEmpty) {
      for (final code in upperCodes) {
        if (_ownShiftParts.contains(code)) { result.add((name: _ownName, isSelf: true)); break; }
      }
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<String> _birthdayNames() {
    return _colleagues.entries
        .where((e) => e.value.trim().toUpperCase().split('/').map((s) => s.trim()).contains('GEB'))
        .map((e) => e.key.contains(',') ? e.key.split(',').first.trim() : e.key.trim())
        .toList()..sort();
  }

  Widget _shiftGroup({required List<({String label, List<({String name, bool isSelf})> names, Color color})> slots}) {
    if (slots.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.glassBorder, width: 1.0),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < slots.length; i++) ...[
                if (i > 0)
                  Container(width: 0.5, height: 40, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), color: skin.glassBorder),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: slots[i].color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(slots[i].label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: slots[i].color, letterSpacing: 0.4)),
                    ),
                    const SizedBox(height: 5),
                    ...slots[i].names.map((n) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(child: Text(n.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: skin.textPrimary, height: 1.3))),
                            if (n.isSelf) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.person_rounded, size: 13, color: skin.primary),
                            ],
                          ]),
                        )),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    final isChrome = skin.key == 'chrome';
    final tColor = isChrome ? const Color(0xFFCCCCCC) : const Color(0xFF5B8DEF);
    const isColor = Color(0xFFEF5B5B);
    const aufColor = Color(0xFFEFBB5B);
    const daColor = Color(0xFF6B7280);
    const uColor = Color(0xFF8B8B9E);
    const xColor = Color(0xFF6B7280);

    final tNames = _namesForShifts(['T']);
    final isNames = _namesForShifts(['IS']);
    final aufNames = _namesForShifts(['AUF', 'AF']);
    final daNames = _namesForShifts(['DA']);
    final uNames = _namesForShifts(['U']);
    final xNames = _namesForShifts(['X']);

    final knownShifts = {'P1','P2','P','F1','F2','F','VK','GEB','T','IS','AUF','AF','DA','U','X'};
    final otherEntries = <String, List<({String name, bool isSelf})>>{};
    for (final entry in _colleagues.entries) {
      final rawShift = entry.value.trim().toUpperCase();
      final parts = rawShift.split('/').map((s) => s.trim()).toList();
      for (final p in parts) {
        if (!knownShifts.contains(p) && p.isNotEmpty && p != 'LÜ' && p != 'LUE') {
          final name = entry.key.contains(',') ? entry.key.split(',').first.trim() : entry.key.trim();
          otherEntries.putIfAbsent(p, () => []).add((name: name, isSelf: false));
        }
      }
    }
    // eigene (oder Fremd-)"sonstige" Dienste ebenfalls einmischen
    if (_ownName.isNotEmpty) {
      for (final p in _ownShiftParts) {
        if (!knownShifts.contains(p) && p.isNotEmpty && p != 'LÜ' && p != 'LUE') {
          otherEntries.putIfAbsent(p, () => []).add((name: _ownName, isSelf: true));
        }
      }
    }
    for (final k in otherEntries.keys) otherEntries[k]!.sort((a, b) => a.name.compareTo(b.name));

    final hasTGroup = tNames.isNotEmpty || isNames.isNotEmpty || aufNames.isNotEmpty;
    final hasFreeGroup = daNames.isNotEmpty || uNames.isNotEmpty || xNames.isNotEmpty;
    final hasOther = otherEntries.isNotEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Divider(color: skin.glassBorder, height: 1)),
      if (_eventText != null && _eventText!.isNotEmpty) ...[
        Row(children: [
          Icon(Icons.flag_rounded, size: 12, color: const Color(0xFFFFB347)),
          const SizedBox(width: 5),
          Text('INFOS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFFFFB347), letterSpacing: 0.8)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFFFB347).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.3))),
              child: Text(_eventText!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFFFB347), height: 1.4)),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (hasTGroup) ...[_shiftGroup(slots: [
        if (tNames.isNotEmpty) (label: 'T', names: tNames, color: tColor),
        if (isNames.isNotEmpty) (label: 'IS', names: isNames, color: isColor),
        if (aufNames.isNotEmpty) (label: 'AuF', names: aufNames, color: aufColor),
      ]), const SizedBox(height: 10)],
      if (hasFreeGroup) ...[_shiftGroup(slots: [
        if (daNames.isNotEmpty) (label: 'DA', names: daNames, color: daColor),
        if (uNames.isNotEmpty) (label: 'U', names: uNames, color: uColor),
        if (xNames.isNotEmpty) (label: 'X', names: xNames, color: xColor),
      ]), const SizedBox(height: 10)],
      if (hasOther) ...[_shiftGroup(slots: otherEntries.entries.map((e) => (label: e.key, names: e.value, color: skin.surface(0.45))).toList()), const SizedBox(height: 10)],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final safeTop = MediaQuery.of(context).padding.top;
    final cardTop = (safeTop + 56.0).clamp(safeTop + 48.0, screenH * 0.3);
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;
    final maxCardHeight = screenH - cardTop - keyboardH - bottomNavHeight - 16.0;

    final isChrome = skin.key == 'chrome';
    final workColor = isChrome ? const Color(0xFFCCCCCC) : const Color(0xFF5B8DEF);
    final fColor = isChrome ? const Color(0xFFAAAAAA) : const Color(0xFF5B8DEF);
    const vkColor = Color(0xFFEF5B5B);
    const gebColor = Color(0xFFFF6B9D);

    final p1Names = _namesForShifts(['P1']);
    final p2Names = _namesForShifts(['P2']);
    final pNames = _namesForShifts(['P']);
    final vkNames = _namesForShifts(['VK']);
    final f1Names = _namesForShifts(['F1']);
    final fNames = _namesForShifts(['F']);
    final f2Names = _namesForShifts(['F2']);
    final gebNames = _birthdayNames();

    final hasAny = [p1Names, p2Names, pNames, vkNames, f1Names, fNames, f2Names, gebNames].any((l) => l.isNotEmpty);
    final hasExpandable = _eventText != null || _namesForShifts(['T']).isNotEmpty || _namesForShifts(['IS']).isNotEmpty ||
        _namesForShifts(['AUF', 'AF']).isNotEmpty || _namesForShifts(['DA']).isNotEmpty ||
        _namesForShifts(['U']).isNotEmpty || _namesForShifts(['X']).isNotEmpty;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Stack(
          children: [
            GestureDetector(
              onTap: _close,
              child: Opacity(opacity: _opacityAnim.value * 0.55,
                  child: Container(color: Colors.black, width: double.infinity, height: double.infinity)),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180), curve: Curves.easeOut,
              top: cardTop, left: 20, right: 20,
              child: Transform.scale(scale: 0.85 + _scaleAnim.value * 0.15,
                  child: Opacity(opacity: _opacityAnim.value.clamp(0.0, 1.0), child: child!)),
            ),
          ],
        );
      },
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxCardHeight.clamp(180.0, screenH * 0.75)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                child: Container(
                  decoration: BoxDecoration(
                    color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: skin.glassBorder, width: 1.0),
                    boxShadow: [
                      BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                      BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          physics: _expanded ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                              child: Row(children: [
                                Icon(Icons.people_outline, size: 18, color: skin.primary),
                                const SizedBox(width: 10),
                                Expanded(child: Text('KOLLEGEN',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 1.0))),
                                GestureDetector(onTap: _close,
                                    // ── GlassIconBadge aus glass_kit.dart ──
                                    child: GlassIconBadge(skin: skin, icon: Icons.close)),
                              ]),
                            ),
                            Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Divider(color: skin.glassBorder, height: 1)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (_debugLog != null) ...[
                                  ClipRRect(borderRadius: BorderRadius.circular(10),
                                    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                      child: Container(constraints: const BoxConstraints(maxHeight: 200),
                                        decoration: BoxDecoration(color: const Color(0xFFEF5B5B).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEF5B5B).withValues(alpha: 0.28))),
                                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                          Padding(padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                                            child: Row(children: [
                                              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                decoration: BoxDecoration(color: const Color(0xFFEF5B5B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFEF5B5B).withValues(alpha: 0.35))),
                                                child: const Text('DEV', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFEF5B5B), letterSpacing: 0.8))),
                                              const SizedBox(width: 6),
                                              Expanded(child: Text('Parser-Log', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFEF5B5B)))),
                                              GestureDetector(
                                                onTap: () {
                                                  Clipboard.setData(ClipboardData(text: _debugLog!));
                                                  setState(() => _debugLogCopied = true);
                                                  HapticFeedback.selectionClick();
                                                  Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _debugLogCopied = false); });
                                                },
                                                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(color: _debugLogCopied ? skin.statComplete.withValues(alpha: 0.15) : const Color(0xFFEF5B5B).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
                                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                    Icon(_debugLogCopied ? Icons.check_rounded : Icons.copy_outlined, size: 12, color: _debugLogCopied ? skin.statComplete : const Color(0xFFEF5B5B)),
                                                    const SizedBox(width: 3),
                                                    Text(_debugLogCopied ? 'Kopiert' : 'Kopieren', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _debugLogCopied ? skin.statComplete : const Color(0xFFEF5B5B))),
                                                  ]),
                                                ),
                                              ),
                                            ]),
                                          ),
                                          Divider(height: 1, color: const Color(0xFFEF5B5B).withValues(alpha: 0.15)),
                                          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(10), child: Text(_debugLog!, style: const TextStyle(fontSize: 10, color: Color(0xFFEF5B5B), height: 1.4)))),
                                        ]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (!hasAny)
                                  Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Column(children: [
                                      Icon(Icons.people_outline, size: 32, color: skin.textMuted.withValues(alpha: 0.4)),
                                      const SizedBox(height: 8),
                                      Text('Keine Kollegen-Daten verfügbar.', style: TextStyle(color: skin.textMuted, fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                                      const SizedBox(height: 3),
                                      Text('Bitte Dienstplan erneut importieren.', style: TextStyle(color: skin.textMuted.withValues(alpha: 0.6), fontSize: 11), textAlign: TextAlign.center),
                                    ]),
                                  )),
                                if (hasAny) ...[
                                  if (p1Names.isNotEmpty || pNames.isNotEmpty || p2Names.isNotEmpty)
                                    _shiftGroup(slots: [
                                      if (p1Names.isNotEmpty) (label: 'P1', names: p1Names, color: workColor),
                                      if (pNames.isNotEmpty) (label: 'P', names: pNames, color: workColor),
                                      if (p2Names.isNotEmpty) (label: 'P2', names: p2Names, color: workColor),
                                    ]),
                                  if (vkNames.isNotEmpty) ...[const SizedBox(height: 10), _shiftGroup(slots: [(label: 'VK', names: vkNames, color: vkColor)])],
                                  if (f1Names.isNotEmpty || fNames.isNotEmpty || f2Names.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    _shiftGroup(slots: [
                                      if (f1Names.isNotEmpty) (label: 'F1', names: f1Names, color: fColor),
                                      if (fNames.isNotEmpty) (label: 'F', names: fNames, color: fColor),
                                      if (f2Names.isNotEmpty) (label: 'F2', names: f2Names, color: fColor),
                                    ]),
                                  ],
                                  if (gebNames.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    ClipRRect(borderRadius: BorderRadius.circular(10),
                                      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity), borderRadius: BorderRadius.circular(10), border: Border.all(color: skin.glassBorder, width: 1.0)),
                                          child: Row(children: [
                                            const Text('🎂', style: TextStyle(fontSize: 15)),
                                            const SizedBox(width: 8),
                                            Expanded(child: Text(gebNames.join(', '), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: gebColor))),
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                                if (_expanded)
                                  AnimatedBuilder(
                                    animation: _expandAnim,
                                    builder: (context, child) => ClipRect(
                                      child: Align(alignment: Alignment.topCenter, heightFactor: _expandAnim.value, child: child),
                                    ),
                                    child: _buildExpandedContent(),
                                  ),
                                const SizedBox(height: 8),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                      if (hasExpandable)
                        GestureDetector(
                          onVerticalDragStart: _onDragStart,
                          onVerticalDragUpdate: _onDragUpdate,
                          onVerticalDragEnd: _onDragEnd,
                          onTap: () { HapticFeedback.selectionClick(); if (_expanded) { _collapse(); } else { _expand(); } },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(border: Border(top: BorderSide(color: skin.glassBorder, width: 0.5))),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              AnimatedBuilder(
                                animation: _expandCtrl,
                                builder: (_, __) => Transform.rotate(
                                  angle: _expandCtrl.value * 3.14159,
                                  child: Icon(Icons.keyboard_arrow_down, size: 14, color: skin.surface(0.3)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(width: 36, height: 3.5,
                                  decoration: BoxDecoration(color: skin.surface(0.18), borderRadius: BorderRadius.circular(2))),
                              const SizedBox(height: 2),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DAY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _DayCard extends StatefulWidget {
  final DateTime day;
  final ScheduleEntry? entry;
  final AppSkin skin;
  final bool isChrome;
  final String dateKey;
  final bool isChanged;
  final String? externallyOpenKey;
  final void Function(String?) onCardSwiped;
  final VoidCallback onOpenNote;
  final VoidCallback onNoteChanged;
  final VoidCallback onOpenColleagues;
  final ValueNotifier<bool>? dayCardDragging;
  final String? eventText;
  final bool hasTask; // true, wenn an diesem Tag eine offene Aufgabe mit Deadline existiert
  /// NEU: true in der Kollegen-Fremdansicht. Deaktiviert Swipe (Notiz/Löschen)
  /// und Long-Press (Notiz) – nur Doppeltipp (Kollegen-Overlay) bleibt aktiv.
  final bool foreignMode;

  const _DayCard({
    required this.day, required this.entry, required this.skin, required this.isChrome,
    required this.dateKey, required this.isChanged, required this.externallyOpenKey,
    required this.onCardSwiped, required this.onOpenNote, required this.onNoteChanged,
    required this.onOpenColleagues, this.dayCardDragging, this.eventText,
    this.hasTask = false,
    this.foreignMode = false, // NEU
  });

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> with TickerProviderStateMixin, SwipeAnimationMixin {
  static const double _revealWidth = 180.0;
  static const double _snapThreshold = 65.0;
  bool _isOpen = false;
  bool _dragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;

  late AnimationController _lpCtrl;
  late Animation<double> _lpAnim;

  double get _revealProgress => (swipeOffset.abs() / _revealWidth).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    initSwipeAnimation(vsync: this);
    _lpCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _lpAnim = CurvedAnimation(parent: _lpCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    disposeSwipeAnimation();
    _lpCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externallyOpenKey != widget.dateKey && _isOpen) {
      animateSwipeTo(0);
      setState(() => _isOpen = false);
    }
  }

  Color _color(String part) => _shiftColor(part, isChrome: widget.isChrome);
  bool get _isBirthdayDay => widget.entry?.hasBirthday ?? false;
  bool get _hasNote => !widget.foreignMode && !_NoteData.load(widget.dateKey).isEmpty;

  void _onPanStart(DragStartDetails d) { _dragging = false; _dragStartX = d.globalPosition.dx; _dragStartY = d.globalPosition.dy; }

  void _onPanUpdate(DragUpdateDetails d) {
    final totalDx = d.globalPosition.dx - _dragStartX;
    final totalDy = (d.globalPosition.dy - _dragStartY).abs();
    if (!_dragging) {
      if (totalDy > totalDx.abs()) return;
      if (totalDx > 0) return;
      if (totalDx.abs() < 8) return;
      _dragging = true;
      widget.dayCardDragging?.value = true;
    }
    final newOffset = (swipeOffset + d.delta.dx).clamp(-_revealWidth, 0.0);
    setSwipeOffsetImmediate(newOffset);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    widget.dayCardDragging?.value = false;
    final v = d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx;
    if (swipeOffset < -_snapThreshold || v < -400) {
      animateSwipeTo(-_revealWidth);
      setState(() => _isOpen = true);
      widget.onCardSwiped(widget.dateKey);
    } else {
      animateSwipeTo(0); 
      if (_isOpen) { setState(() => _isOpen = false); widget.onCardSwiped(null); }
    }
  }

  void _close() {
    animateSwipeTo(0);
    if (mounted) { setState(() => _isOpen = false); widget.onCardSwiped(null); }
  }

  void _onLongPressStart(LongPressStartDetails _) => _lpCtrl.forward();
  void _onLongPress() { HapticFeedback.mediumImpact(); _lpCtrl.reverse(); _close(); Future.delayed(const Duration(milliseconds: 150), () { if (mounted) widget.onOpenNote(); }); }
  void _onLongPressCancel() => _lpCtrl.reverse();
  void _onLongPressEnd(LongPressEndDetails _) => _lpCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final isWeekend = widget.day.weekday == DateTime.saturday || widget.day.weekday == DateTime.sunday;
    final dayName = DateFormat('EEE', 'de').format(widget.day);
    final dayNum = DateFormat('dd', 'de').format(widget.day);
    final monthAbbr = DateFormat('MMM', 'de').format(widget.day);
    final weekendAccent = widget.isChrome ? const Color(0xFFCCCCCC) : skin.primary;
    final hasNote = _hasNote;
    final noteColor = widget.isChrome ? const Color(0xFF888888) : skin.primary.withValues(alpha: 0.85);
    final hasEvent = widget.eventText != null && widget.eventText!.isNotEmpty;

    Widget shiftContent;
    if (widget.entry == null || widget.entry!.shift.isEmpty) {
      shiftContent = Text('—', style: TextStyle(fontSize: 16, color: skin.surface(0.18)));
    } else {
      final parts = widget.entry!.parts;
      final List<Widget> chipWidgets = [];
      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        final isGeb = part.trim().toUpperCase() == 'GEB';
        if (isGeb) {
          chipWidgets.add(Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B9D), Color(0xFFFFB347)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: const Color(0xFFFF6B9D).withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Text('GEB', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              SizedBox(width: 4), Text('🎂', style: TextStyle(fontSize: 12)),
            ]),
          ));
        } else {
          final color = _color(part);
          chipWidgets.add(Text(part, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)));
        }
        if (i < parts.length - 1 && !isGeb && parts[i + 1].trim().toUpperCase() != 'GEB') {
          chipWidgets.add(Text(' / ', style: TextStyle(color: skin.surface(0.3), fontSize: 12)));
        }
      }
      shiftContent = Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ...chipWidgets,
        if (hasNote) Padding(padding: const EdgeInsets.only(left: 2),
            child: Icon(Icons.sticky_note_2_outlined, size: 13, color: skin.primary.withValues(alpha: 0.55))),
      ]);
    }

    Widget cardInner = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dayName.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8,
                color: _isBirthdayDay ? const Color(0xFFFF6B9D).withValues(alpha: 0.8) : isWeekend ? weekendAccent : skin.surface(0.38))),
            const SizedBox(height: 2),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(dayNum, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: skin.textPrimary, height: 1)),
              const SizedBox(width: 3),
              Text(monthAbbr, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: skin.surface(0.3))),
            ]),
          ]),
        ),
        Builder(builder: (context) {
          final isToday = DateFormat('yyyy-MM-dd').format(widget.day) == DateFormat('yyyy-MM-dd').format(DateTime.now());
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isToday ? 2.5 : 1, height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isToday ? skin.primary.withValues(alpha: 0.7) : skin.surface(0.07),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
                Expanded(child: shiftContent),
        // NACHHER:
if (widget.entry != null && widget.entry!.shift.isNotEmpty) ...[
  if (widget.hasTask) ...[
    Icon(Icons.task_alt_rounded, size: 11,
        color: widget.isChrome
            ? const Color(0xFFCCCCCC).withValues(alpha: 0.85)
            : skin.primary.withValues(alpha: 0.7)),
    const SizedBox(width: 5),
  ],
  if (hasEvent) ...[
    Icon(Icons.flag_rounded, size: 11,
        color: widget.isChrome
            ? const Color(0xFFFFB347).withValues(alpha: 0.75)
            : const Color(0xFFFFB347)),
    const SizedBox(width: 5),
  ],
  _isBirthdayDay
      ? const SizedBox(width: 7, height: 7)
      : _DayDot(day: widget.day, skin: skin, isChrome: widget.isChrome, isChanged: widget.isChanged),
],
      ],
    );

    Widget cardWidget;
    if (_isBirthdayDay) {
      cardWidget = Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF6B9D), Color(0xFFFFB347), Color(0xFFFF6B9D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(15.5),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: skin.glassBlur * 0.5, sigmaY: skin.glassBlur * 0.5),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity), borderRadius: BorderRadius.circular(14)),
              child: cardInner)),
        ),
      );
     } else {
      cardWidget = ClipRRect(borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Stack(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: skin.glassBorder, width: 1.0),
                boxShadow: [
                  BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                  BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                ],
              ),
              child: cardInner),
            if (widget.foreignMode)
              Positioned(
                left: 0, top: 0, bottom: 0, width: 3.0,
                child: Container(color: skin.primary.withValues(alpha: 0.9)),
              ),
          ]),
        ),
      );
    }

    Widget animatedCard = AnimatedBuilder(
      animation: _lpAnim,
      builder: (context, child) {
        final p = _lpAnim.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_isBirthdayDay ? 15.5 : 14),
            boxShadow: p > 0 ? [BoxShadow(color: skin.primary.withValues(alpha: 0.28 * p), blurRadius: 14 * p, spreadRadius: 2 * p)] : null,
          ),
          child: Stack(children: [
            Transform.scale(scale: 1.0 - 0.015 * p, child: child!),
            if (p > 0)
              Positioned.fill(child: IgnorePointer(child: Container(decoration: BoxDecoration(
                color: skin.primary.withValues(alpha: p * 0.18),
                borderRadius: BorderRadius.circular(_isBirthdayDay ? 15.5 : 14),
                border: Border.all(color: skin.primary.withValues(alpha: p * 0.7), width: 1.0 + p * 1.5),
              )))),
          ]),
        );
      },
      child: cardWidget,
    );

    return GestureDetector(
      onHorizontalDragStart: widget.foreignMode ? null : _onPanStart,
      onHorizontalDragUpdate: widget.foreignMode ? null : _onPanUpdate,
      onHorizontalDragEnd: widget.foreignMode ? null : _onPanEnd,
      onLongPressStart: widget.foreignMode ? null : _onLongPressStart,
      onLongPress: widget.foreignMode ? null : _onLongPress,
      onLongPressEnd: widget.foreignMode ? null : _onLongPressEnd,
      onLongPressCancel: widget.foreignMode ? null : _onLongPressCancel,
      onTap: _isOpen ? _close : null,
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        _close();
        Future.delayed(const Duration(milliseconds: 150), () { if (mounted) widget.onOpenColleagues(); });
      },
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          child: ClipRect(
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              if (!widget.foreignMode)
              Positioned(
                right: 0, top: 4, bottom: 4, width: _revealWidth,
                child: Row(children: [
                  const SizedBox(width: 6),
                  Expanded(child: Transform.scale(scale: _revealProgress, alignment: Alignment.center,
                    child: GestureDetector(onTap: () { _close(); widget.onOpenColleagues(); },
                      child: ClipRRect(borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(color: const Color(0xFF3DD6C8).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF3DD6C8).withValues(alpha: 0.25))),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.people_outline, color: const Color(0xFF3DD6C8), size: 22),
                              const SizedBox(height: 4),
                              Text('Kollegen', style: TextStyle(color: const Color(0xFF3DD6C8), fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  )),
                  Expanded(child: Transform.scale(scale: _revealProgress, alignment: Alignment.center,
                    child: GestureDetector(onTap: () { _close(); widget.onOpenNote(); },
                      child: ClipRRect(borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(decoration: BoxDecoration(color: noteColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: noteColor.withValues(alpha: 0.25))),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.sticky_note_2_outlined, color: noteColor, size: 22),
                              const SizedBox(height: 4),
                              Text('Notiz', style: TextStyle(color: noteColor, fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  )),
                ]),
              ),
Transform.translate(offset: Offset(widget.foreignMode ? 0 : swipeOffset, 0), child: animatedCard),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIENSTPLAN UPLOAD SHEET
// ─────────────────────────────────────────────────────────────────────────────

class DienstplanUploadSheet extends StatefulWidget {
  final AppSkin skin;
  final DateTime initialMonth;
  final DateTime selectedMonth;
  final VoidCallback onImported;
  final String? preloadedFilePath;
  final String? preloadedFileName;
  final List<int>? preloadedBytes;
  final String? autoImportError;

  const DienstplanUploadSheet({
    super.key, required this.skin, required this.initialMonth, required this.selectedMonth,
    required this.onImported, this.preloadedFilePath, this.preloadedFileName,
    this.preloadedBytes, this.autoImportError,
  });

  @override
  State<DienstplanUploadSheet> createState() => _DienstplanUploadSheetState();
}

class _DienstplanUploadSheetState extends State<DienstplanUploadSheet> {
  String? _selectedFileName;
  String? _selectedFilePath;
  List<int>? _selectedFileBytes;
  bool _isLoading = false;
  String? _errorMessage;
  bool _errorCopied = false;

  bool get _hasFile => _selectedFilePath != null || _selectedFileBytes != null;
  AppSkin get skin => widget.skin;

  bool get _hasScheduleForSelectedMonth {
    final monthKey = DateFormat('yyyy-MM').format(widget.selectedMonth);
    final box = Hive.box('einstellungen');
    final raw = box.get('schedule_$monthKey');
    if (raw is Map) return raw.isNotEmpty;
    return false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.preloadedFilePath != null) {
      _selectedFilePath = widget.preloadedFilePath;
      _selectedFileName = widget.preloadedFileName ?? 'Geteilte PDF';
      _selectedFileBytes = widget.preloadedBytes;
    }
    if (widget.autoImportError != null) _errorMessage = widget.autoImportError;
  }

  bool get _isDevMode {
    final box = Hive.box('einstellungen');
    return box.get('dienstplan_dev_placeholder', defaultValue: false) as bool;
  }

  Future<void> _pickFile() async {
    setState(() { _errorMessage = null; _errorCopied = false; });
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: false, withData: kIsWeb);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      List<int>? bytes;
      if (kIsWeb) {
        final raw = picked.bytes;
        if (raw == null || raw.isEmpty) { setState(() => _errorMessage = 'Datei konnte nicht gelesen werden.'); return; }
        bytes = raw.toList();
      } else {
        final path = picked.path;
        if (path == null) { setState(() => _errorMessage = 'Datei konnte nicht gelesen werden.'); return; }
        try { bytes = await dartio.File(path).readAsBytes(); } catch (_) { bytes = null; }
        if (bytes == null || bytes.isEmpty) { setState(() => _errorMessage = 'Datei konnte nicht gelesen werden.'); return; }
        setState(() => _selectedFilePath = path);
      }
      setState(() { _selectedFileName = picked.name; _selectedFileBytes = bytes; _errorMessage = null; });
    } on Exception catch (e) {
      setState(() => _errorMessage = 'Dateiauswahl konnte nicht geöffnet werden.\n\nDetail: $e');
    }
  }

  void _clearFile() => setState(() { _selectedFileName = null; _selectedFilePath = null; _selectedFileBytes = null; _errorMessage = null; _errorCopied = false; });

  Future<void> _importPdf() async {
    if (!_hasFile) return;
    setState(() { _isLoading = true; _errorMessage = null; _errorCopied = false; });
    try {
      final settingsBox = Hive.box('einstellungen');
      final scheduleName = settingsBox.get('dienstplan_name', defaultValue: '') as String;
      final mainName = settingsBox.get('name', defaultValue: '') as String;
      final userName = scheduleName.isNotEmpty ? scheduleName : mainName;
      List<int>? bytes = _selectedFileBytes;
      if ((bytes == null || bytes.isEmpty) && _selectedFilePath != null) {
        try { bytes = await dartio.File(_selectedFilePath!).readAsBytes(); } catch (_) { bytes = null; }
      }
      final result = await DienstplanParser.parse(
        filePath: bytes != null ? null : _selectedFilePath,
        fileBytes: bytes, userName: userName, fileName: _selectedFileName ?? '', devMode: _isDevMode);
      final String? error = result['error'] as String?;
      if (error != null && error.isNotEmpty) { setState(() { _errorMessage = error; _isLoading = false; }); return; }
      DateTime? month = result['month'] as DateTime?;
      final Map<String, String> newData = Map<String, String>.from(result['data'] as Map? ?? {});
      if (newData.isEmpty) { setState(() { _errorMessage = 'Keine Dienste gefunden.'; _isLoading = false; }); return; }
      if (month == null) { month = await _askForMonth(); if (month == null) { setState(() => _isLoading = false); return; } }
      final monthKey = DateFormat('yyyy-MM').format(month);
      final existingRaw = settingsBox.get('schedule_$monthKey');
      final Map<String, String> oldData = {};
      if (existingRaw is Map) { for (final e in existingRaw.entries) { oldData[e.key.toString()] = e.value.toString(); } }
      if (oldData.isNotEmpty) {
        final changed = _ChangedDays.diff(oldData, newData);
        if (changed.isNotEmpty) { final existing = _ChangedDays.load(monthKey); _ChangedDays.save(monthKey, {...existing, ...changed}); }
      }
      settingsBox.put('schedule_$monthKey', newData);
      SyncService.instance.pushScheduleMonth(monthKey);
      try {
        final List<int> bytesForColleagues = _selectedFileBytes ?? [];
        if (bytesForColleagues.isNotEmpty) {
          final sName = settingsBox.get('dienstplan_name', defaultValue: '') as String;
          final mName = settingsBox.get('name', defaultValue: '') as String;
          final uName = sName.isNotEmpty ? sName : mName;
          final colleaguesLog = StringBuffer();
          final colleagues = DienstplanParser.parseAllColleagues(
            bytes: bytesForColleagues, fileName: _selectedFileName ?? '', ownUserName: uName,
            devMode: _isDevMode, debugLog: colleaguesLog);
          settingsBox.put('colleagues_debug_$monthKey', colleaguesLog.toString());
          if (colleagues.isNotEmpty) {
            final encoded = jsonEncode(colleagues.map((k, v) => MapEntry(k, v)));
            settingsBox.put('colleagues_$monthKey', encoded);
          }
          final events = DienstplanParser.parseEvents(bytes: bytesForColleagues, fileName: _selectedFileName ?? '', devMode: _isDevMode);
          if (events.isNotEmpty) { settingsBox.put('events_$monthKey', jsonEncode(events)); }
        }
      } catch (e, stack) {
        if (_isDevMode) setState(() { _errorMessage = '⚠️ Fehler beim Kollegen-Import:\n$e\n\nStack:\n$stack'; });
        debugPrint('[DEV] Kollegen-Import Fehler: $e');
      }
      await ScheduleScreenState.pushScheduleToWidget();
      if (!mounted) return;
      Navigator.pop(context);
      showGlassSnackBar(
        context,
        'Dienstplan ${DateFormat('MMMM yyyy', 'de').format(month)} importiert (${newData.length} Tage)',
        type: GlassSnackBarType.success,
        duration: const Duration(seconds: 3),
      );
      widget.onImported();
    } catch (e) {
      setState(() => _errorMessage = 'Fehler beim Importieren: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<DateTime?> _askForMonth() async {
    int pickedYear = widget.initialMonth.year;
    int pickedMonth = widget.initialMonth.month - 1;
    final yearCount = DateTime.now().year - 2020 + 2;
    final monthCtrl = FixedExtentScrollController(initialItem: 1000 * 12 + pickedMonth);
    final yearCtrl = FixedExtentScrollController(initialItem: pickedYear - 2020);
    return await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) =>
        // ── GlassSheet aus glass_kit.dart ──
        GlassSheet(
          skin: skin,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).padding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetHandle(skin: skin),
              const SizedBox(height: 20),
              Text('Für welchen Monat gilt diese PDF?',
                  style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Der Monat konnte nicht automatisch erkannt werden.',
                  style: TextStyle(fontSize: 13, color: skin.textMuted), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: Row(children: [
                  Expanded(flex: 2, child: CupertinoPicker(
                    scrollController: monthCtrl, itemExtent: 44, looping: true, backgroundColor: Colors.transparent,
                    onSelectedItemChanged: (i) => setSheet(() => pickedMonth = i % 12),
                    children: List.generate(12, (i) => Center(child: Text(DateFormat('MMMM', 'de').format(DateTime(2024, i + 1)),
                        style: TextStyle(fontSize: 16, color: skin.textPrimary)))))),
                  Expanded(child: CupertinoPicker(
                    scrollController: yearCtrl, itemExtent: 44, looping: false, backgroundColor: Colors.transparent,
                    onSelectedItemChanged: (i) => setSheet(() => pickedYear = 2020 + i.clamp(0, yearCount - 1)),
                    children: List.generate(yearCount, (i) => Center(child: Text('${2020 + i}',
                        style: TextStyle(fontSize: 16, color: skin.textPrimary)))))),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                // ── GlassSecondaryButton aus glass_kit.dart ──
                Expanded(child: GlassSecondaryButton(skin: skin, label: 'Abbrechen', onTap: () => Navigator.pop(ctx, null))),
                const SizedBox(width: 12),
                // ── GlassPrimaryButton aus glass_kit.dart ──
                Expanded(child: GlassPrimaryButton(skin: skin, label: 'Übernehmen',
                    onTap: () => Navigator.pop(ctx, DateTime(pickedYear, pickedMonth + 1)))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  void _deleteSelectedMonth() async {
    final displayMonth = DateFormat('MMMM yyyy', 'de').format(widget.selectedMonth);

    // ── confirmDeleteDialog aus glass_dialogs.dart ──
    final confirmed = await confirmDeleteDialog(
      context: context, skin: skin,
      title: 'Monat löschen',
      message: 'Alle Dienstplan-Daten für diesen Monat werden unwiderruflich gelöscht.',
    );
    if (confirmed != true || !mounted) return;
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(widget.selectedMonth);
    box.delete('schedule_$monthKey');
    _ChangedDays.clear(monthKey);
    await ScheduleScreenState.pushScheduleToWidget();
    Navigator.pop(context);
    widget.onImported();
  }

  void _copyError() {
    if (_errorMessage == null) return;
    Clipboard.setData(ClipboardData(text: _errorMessage!));
    setState(() => _errorCopied = true);
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _errorCopied = false); });
  }

  @override
  Widget build(BuildContext context) {
    // ── GlassSheet-Aufbau direkt (kein wrapper nötig, da eigenes Styling) ──
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: 0.92) : skin.bgSheet.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: skin.glassBorder),
          ),
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── SheetHandle aus glass_kit.dart ──
              SheetHandle(skin: skin),
              const SizedBox(height: 20),
              Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: skin.primaryWithAlpha(0.12), borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.upload_file_outlined, color: skin.primary, size: 22)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dienstplan importieren', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                  const SizedBox(height: 3),
                  Text('PDF-Datei auswählen & importieren', style: TextStyle(fontSize: 12, color: skin.textMuted)),
                ])),
              ]),
              const SizedBox(height: 20),
              if (_hasFile) ...[
                ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: skin.statComplete.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: skin.statComplete.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Icon(Icons.picture_as_pdf_outlined, color: skin.statComplete, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_selectedFileName ?? 'Datei ausgewählt',
                            style: TextStyle(color: skin.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                        GestureDetector(onTap: _clearFile,
                            child: Container(padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: skin.deleteColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.close, color: skin.deleteColor, size: 16))),
                      ]),
                    ),
                  )),
                const SizedBox(height: 12),
              ],
              if (_errorMessage != null) ...[
                if (_isDevMode) ...[
                  ClipRRect(borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(color: skin.deleteColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: skin.deleteColor.withValues(alpha: 0.3))),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
                            child: Row(children: [
                              Icon(Icons.error_outline, color: skin.deleteColor, size: 18),
                              const SizedBox(width: 6),
                              Expanded(child: Text('Fehler', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: skin.deleteColor))),
                              GestureDetector(onTap: _copyError,
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(color: _errorCopied ? skin.statComplete.withValues(alpha: 0.15) : skin.deleteColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(_errorCopied ? Icons.check_rounded : Icons.copy_outlined, size: 13, color: _errorCopied ? skin.statComplete : skin.deleteColor),
                                    const SizedBox(width: 4),
                                    Text(_errorCopied ? 'Kopiert' : 'Kopieren', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _errorCopied ? skin.statComplete : skin.deleteColor)),
                                  ])),
                              ),
                            ])),
                          Divider(height: 1, color: skin.deleteColor.withValues(alpha: 0.15)),
                          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              child: Text(_errorMessage!, style: TextStyle(fontSize: 11, color: skin.deleteColor, height: 1.4)))),
                        ]),
                      ),
                    )),
                ] else ...[
                  Padding(padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: skin.deleteColor, size: 15),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_errorMessage!, style: TextStyle(fontSize: 13, color: skin.deleteColor, fontWeight: FontWeight.w500))),
                    ])),
                ],
                const SizedBox(height: 10),
              ],
              if (!_hasFile)
              // ── GlassPrimaryButton aus glass_kit.dart ──
                GlassPrimaryButton(skin: skin, label: 'Dokument auswählen', icon: Icons.folder_open_outlined, large: true, onTap: _isLoading ? () {} : _pickFile),
              if (_hasFile) ...[
                GlassPrimaryButton(skin: skin, label: 'Dokument importieren', icon: Icons.check_circle_outline, large: true, onTap: _isLoading ? () {} : _importPdf),
                const SizedBox(height: 10),
                // ── GlassSecondaryButton aus glass_kit.dart ──
                GlassSecondaryButton(skin: skin, label: 'Andere Datei wählen', onTap: _isLoading ? () {} : _pickFile),
              ],
              if (_hasScheduleForSelectedMonth) ...[
                const SizedBox(height: 16),
                Divider(color: skin.glassBorder),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _deleteSelectedMonth,
                  child: ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(color: skin.deleteColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25))),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.delete_outline, color: skin.deleteColor, size: 18),
                          const SizedBox(width: 8),
                          Text('Aktuellen Monat löschen', style: TextStyle(color: skin.deleteColor, fontSize: 14, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text('Unterstützt: PDF-Dateien mit maschinenlesbarem Text',
                  style: TextStyle(fontSize: 11, color: skin.textHint), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}