import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as dartio;
import 'dart:convert';
import 'dart:typed_data';
import '../theme/app_theme.dart';
import 'package:archive/archive.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shift colour helper
// ─────────────────────────────────────────────────────────────────────────────

Color _shiftColor(String s, {required bool isChrome}) {
  final u = s.trim().toUpperCase();
  if (isChrome) {
    if (u == 'U' || u == 'DA' || u == 'X') return const Color(0xFF444444);
    if (u == 'VK' || u == 'IS') return const Color(0xFF999999);
    const workPrefixes = ['P1', 'P2', 'P', 'F1', 'F2', 'F', 'T'];
    for (final w in workPrefixes) {
      if (u == w) return const Color(0xFFDDDDDD);
    }
    if (u == 'L' || u == 'AUF') return const Color(0xFFBBBBBB);
    return const Color(0xFF777777);
  }
  const workShifts = ['P1', 'P2', 'P', 'F1', 'F2', 'F', 'T'];
  for (final w in workShifts) {
    if (u == w) return const Color(0xFF5B8DEF);
  }
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
    bool hasWork = false;
    bool hasFree = false;
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
    const w = ['P1','P2','P','F1','F2','F','IS','T','L','AUF'];
    return w.contains(s);
  }
  static bool _isFree(String s) => s == 'U' || s == 'DA' || s == 'X';

  bool get hasBirthday =>
      parts.any((p) => p.trim().toUpperCase() == 'GEB');
}

enum ShiftCategory { work, free, other, mixed }

// ─────────────────────────────────────────────────────────────────────────────
// PDF Parser
// ─────────────────────────────────────────────────────────────────────────────

class DienstplanParser {
  static const _monthNames = {
    'januar': 1, 'jan': 1,
    'februar': 2, 'feb': 2,
    'märz': 3, 'maerz': 3, 'mär': 3,
    'april': 4, 'apr': 4,
    'mai': 5,
    'juni': 6, 'jun': 6,
    'juli': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9,
    'oktober': 10, 'okt': 10,
    'november': 11, 'nov': 11,
    'dezember': 12, 'dez': 12,
  };

  static Future<Map<String, dynamic>> parse({
    String? filePath,
    List<int>? fileBytes,
    required String userName,
    required String fileName,
    required bool devMode,
  }) async {
    List<int> bytes;
    try {
      if (kIsWeb) {
        bytes = fileBytes ?? [];
      } else if (fileBytes != null && fileBytes.isNotEmpty) {
        bytes = fileBytes;
      } else if (filePath != null && filePath.isNotEmpty) {
        bytes = await dartio.File(filePath).readAsBytes();
      } else {
        bytes = [];
      }
    } catch (e) {
      return _errSimple(null, 'Datei konnte nicht gelesen werden.', devMode);
    }

    if (bytes.isEmpty) {
      return _errSimple(null, 'Keine Dateidaten empfangen.', devMode);
    }

    try {
      return _parseSync(
          bytes: bytes,
          userName: userName,
          fileName: fileName,
          devMode: devMode);
    } catch (e) {
      return _errSimple(null, 'Parsing-Fehler: $e', devMode);
    }
  }

  static Map<String, dynamic> _errSimple(
      DateTime? month, String msg, bool devMode) =>
      {'month': month, 'data': <String, String>{}, 'error': msg};

  static Map<String, dynamic> _parseSync({
    required List<int> bytes,
    required String userName,
    required String fileName,
    required bool devMode,
  }) {
    final log = StringBuffer();
    if (devMode) log.writeln('[DEV] Dateigröße: ${bytes.length} Bytes');

    final stream = _decompress(bytes, log, devMode);
    if (stream == null) {
      return _err(null,
          'PDF nicht lesbar. Bitte maschinenlesbaren Text sicherstellen.',
          devMode, log,
          devDetail: 'Kein FlateDecode-Stream mit BT/ET gefunden.');
    }

    final items = _extractCoordText(stream);
    final rows = _groupByY(items);
    final sortedYs = rows.keys.toList()..sort((a, b) => b.compareTo(a));

    final detectedMonth = _detectMonthFromText(rows, fileName);

    if (userName.trim().isEmpty) {
      return _err(detectedMonth,
          'Kein Name hinterlegt. Bitte Namen in den Einstellungen eintragen.',
          devMode, log);
    }

    final terms = _searchTerms(userName);
    final dateRow = _findDateRow(rows);
    final nameResult =
        _findPersonRow(rows, sortedYs, terms, userName, devMode, log);
    final nameY = nameResult?.$1;
    final shiftCells = nameResult?.$2;

    if (nameY == null || shiftCells == null || shiftCells.isEmpty) {
      return _err(detectedMonth,
          'Name nicht gefunden. Bitte Dienstplan-Namen in den Einstellungen prüfen.',
          devMode, log,
          devDetail: 'Suchbegriffe: ${terms.join(", ")}\n\n[DEV LOG]\n$log');
    }

    final result = <String, String>{};

    if (dateRow != null && detectedMonth != null) {
      final usedDateIndices = <int>{};
      for (final (sx, shift) in shiftCells) {
        int? bestIdx;
        double bestDist = double.infinity;
        for (int di = 0; di < dateRow.length; di++) {
          if (usedDateIndices.contains(di)) continue;
          final dist = (sx - dateRow[di].$1).abs();
          if (dist < bestDist) {
            bestDist = dist;
            bestIdx = di;
          }
        }
        if (bestIdx != null && bestDist <= 30.0) {
          usedDateIndices.add(bestIdx);
          final dateLabel = dateRow[bestIdx].$2;
          final parts = dateLabel.replaceAll(' ', '').split('.');
          if (parts.length >= 2) {
            final day = int.tryParse(parts[0]);
            final month = int.tryParse(parts[1]);
            if (day != null && month != null) {
              final key = DateFormat('yyyy-MM-dd')
                  .format(DateTime(detectedMonth.year, month, day));
              result[key] = shift.trim() == 'x' ? 'X' : shift.trim();
            }
          }
        }
      }
    } else if (detectedMonth != null) {
      final daysInMonth =
          DateUtils.getDaysInMonth(detectedMonth.year, detectedMonth.month);
      for (int i = 0; i < shiftCells.length && i < daysInMonth; i++) {
        final key = DateFormat('yyyy-MM-dd')
            .format(DateTime(detectedMonth.year, detectedMonth.month, i + 1));
        result[key] = shiftCells[i].$2.trim() == 'x'
            ? 'X'
            : shiftCells[i].$2.trim();
      }
    }

    if (detectedMonth != null) {
      final daysInMonth = DateUtils.getDaysInMonth(
          detectedMonth.year, detectedMonth.month);
      for (int day = 1; day <= daysInMonth; day++) {
        final key = DateFormat('yyyy-MM-dd')
            .format(DateTime(detectedMonth.year, detectedMonth.month, day));
        result.putIfAbsent(key, () => 'X');
      }
    }

    if (result.isEmpty) {
      return _err(detectedMonth, 'Dienste konnten nicht zugeordnet werden.',
          devMode, log, devDetail: '[DEV LOG]\n$log');
    }

    return {'month': detectedMonth, 'data': result, 'error': null};
  }

  static String? _decompress(List<int> pdfBytes, StringBuffer log, bool devMode) {
    try {
      final data = Uint8List.fromList(pdfBytes);
      String? bestText;
      int bestLen = 0;
      final pdfAsLatin1 = latin1.decode(data, allowInvalid: true);
      int searchFrom = 0;
      int streamsChecked = 0;

      while (searchFrom < pdfAsLatin1.length) {
        final streamIdx = pdfAsLatin1.indexOf('stream', searchFrom);
        if (streamIdx == -1) break;
        if (streamIdx >= 3 &&
            pdfAsLatin1.substring(streamIdx - 3, streamIdx) == 'end') {
          searchFrom = streamIdx + 6;
          continue;
        }
        int dataStart;
        if (streamIdx + 7 < pdfAsLatin1.length &&
            pdfAsLatin1.codeUnitAt(streamIdx + 6) == 13 &&
            pdfAsLatin1.codeUnitAt(streamIdx + 7) == 10) {
          dataStart = streamIdx + 8;
        } else if (streamIdx + 6 < pdfAsLatin1.length &&
            pdfAsLatin1.codeUnitAt(streamIdx + 6) == 10) {
          dataStart = streamIdx + 7;
        } else {
          searchFrom = streamIdx + 6;
          continue;
        }
        final endIdx = pdfAsLatin1.indexOf('endstream', dataStart);
        if (endIdx == -1 || endIdx <= dataStart + 5) {
          searchFrom = streamIdx + 6;
          continue;
        }
        int dataEnd = endIdx;
        if (dataEnd > 0 && pdfAsLatin1.codeUnitAt(dataEnd - 1) == 10) dataEnd--;
        if (dataEnd > 0 && pdfAsLatin1.codeUnitAt(dataEnd - 1) == 13) dataEnd--;
        if (dataEnd <= dataStart + 5) {
          searchFrom = streamIdx + 6;
          continue;
        }
        streamsChecked++;
        try {
          final compressed = data.sublist(dataStart, dataEnd);
          final decompressed = ZLibDecoder().decodeBytes(compressed);
          final text = latin1.decode(Uint8List.fromList(decompressed),
              allowInvalid: true);
          if (text.length > bestLen && text.contains('BT') && text.contains('ET')) {
            bestLen = text.length;
            bestText = text;
          }
        } catch (_) {}
        searchFrom = streamIdx + 6;
      }
      if (devMode) {
        log.writeln('[DEV] Streams geprüft: $streamsChecked, bester: $bestLen Zeichen');
      }
      return bestText;
    } catch (_) {
      return null;
    }
  }

  static List<(double, double, String)> _extractCoordText(String stream) {
    final result = <(double, double, String)>[];
    final btEt = RegExp(r'BT(.*?)ET', dotAll: true);
    final tmRe = RegExp(
        r'([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+Tm');
    final tjaRe = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
    final innerRe = RegExp(r'\(((?:[^)\\]|\\.)*)\)');
    final tjSimpleRe = RegExp(r'\(((?:[^)\\]|\\.)*)\)\s*Tj');

    for (final block in btEt.allMatches(stream)) {
      final b = block.group(1)!;
      final tm = tmRe.firstMatch(b);
      if (tm == null) continue;
      final cx = double.parse(tm.group(5)!);
      final cy = double.parse(tm.group(6)!);
      String text = '';
      final tja = tjaRe.firstMatch(b);
      if (tja != null) {
        final buf = StringBuffer();
        for (final it in innerRe.allMatches(tja.group(1)!)) {
          buf.write(_decodePdf(it.group(1)!));
        }
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
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')');

  static Map<double, List<(double, String)>> _groupByY(
      List<(double, double, String)> items,
      {double tol = 3.0}) {
    final rows = <double, List<(double, String)>>{};
    for (final (x, y, t) in items) {
      double? bucket;
      for (final k in rows.keys) {
        if ((k - y).abs() <= tol) { bucket = k; break; }
      }
      bucket ??= y;
      rows.putIfAbsent(bucket, () => []).add((x, t));
    }
    return rows;
  }

  static (double, List<(double, String)>)? _findPersonRow(
    Map<double, List<(double, String)>> rows,
    List<double> sortedYsDesc,
    List<String> searchTerms,
    String originalUserName,
    bool devMode,
    StringBuffer log,
  ) {
    final nameFragments = _buildNameFragments(originalUserName, searchTerms);
    double? nameY;
    for (final y in sortedYsDesc) {
      final rowItems = (rows[y]!.toList())
        ..sort((a, b) => a.$1.compareTo(b.$1));
      final rowText = rowItems.map((e) => e.$2.toLowerCase()).join(' ');
      bool matched = false;
      for (final term in searchTerms) {
        if (rowText.contains(term.toLowerCase())) { matched = true; break; }
      }
      if (!matched) continue;
      nameY = y;
      break;
    }
    if (nameY == null) return null;

    const maxGap = 25.0;
    final aboveRows = sortedYsDesc
        .where((y) => y > nameY! && (y - nameY!) <= maxGap)
        .toList()
      ..sort((a, b) => (a - nameY!).compareTo(b - nameY!));

    for (final candidateY in aboveRows) {
      final candidateItems = (rows[candidateY]!.toList())
        ..sort((a, b) => a.$1.compareTo(b.$1));
      final shiftCells = <(double, String)>[];
      for (final (x, text) in candidateItems) {
        if (_isNameElement(text, nameFragments, searchTerms)) continue;
        if (_looksLikeShift(text)) shiftCells.add((x, text));
      }
      if (shiftCells.isNotEmpty) return (candidateY, shiftCells);
    }
    return null;
  }

  static Set<String> _buildNameFragments(
      String originalUserName, List<String> searchTerms) {
    final fragments = <String>{};
    fragments.add(originalUserName.trim().toLowerCase());
    for (final t in searchTerms) fragments.add(t.toLowerCase());
    final parts = originalUserName
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p.toLowerCase())
        .toList();
    fragments.addAll(parts);
    return fragments;
  }

  static bool _isNameElement(
      String text, Set<String> nameFragments, List<String> searchTerms) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (nameFragments.contains(lower)) return true;
    for (final term in searchTerms) {
      if (lower.contains(term.toLowerCase()) ||
          term.toLowerCase().contains(lower)) {
        if (!_looksLikeShift(text)) return true;
      }
    }
    if (text.contains(',') && text.length > 3) return true;
    return false;
  }

  static List<(double, String)>? _findDateRow(
      Map<double, List<(double, String)>> rows) {
    final dateRe = RegExp(r'^\d{1,2}\.\d{2}\.$');
    for (final entry in rows.entries) {
      final matches = entry.value.where((e) => dateRe.hasMatch(e.$2)).length;
      if (matches >= 5) {
        final dateCells = entry.value
            .where((e) => dateRe.hasMatch(e.$2))
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
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
        final year = yearMatch != null
            ? int.parse('20${yearMatch.group(1)!}')
            : DateTime.now().year;
        return DateTime(year, entry.value);
      }
    }
    return null;
  }

  static DateTime? _detectMonthFromText(
      Map<double, List<(double, String)>> rows, String fileName) {
    final fromFilename = _monthFromFilename(fileName);
    if (fromFilename != null) return fromFilename;
    final allText = rows.values
        .expand((r) => r.map((e) => e.$2))
        .join(' ')
        .toLowerCase();
    for (final entry in _monthNames.entries) {
      final idx = allText.indexOf(entry.key);
      if (idx != -1) {
        final region = allText.substring(
          (idx - 5).clamp(0, allText.length),
          (idx + entry.key.length + 15).clamp(0, allText.length),
        );
        final yearM = RegExp(r'20\d{2}').firstMatch(region);
        if (yearM != null) {
          return DateTime(int.parse(yearM.group(0)!), entry.value);
        }
      }
    }
    for (final row in rows.values) {
      for (final (_, text) in row) {
        final m = RegExp(r'\d{2}\.(\d{2})\.').firstMatch(text);
        if (m != null) {
          final monthNum = int.tryParse(m.group(1)!);
          if (monthNum != null && monthNum >= 1 && monthNum <= 12) {
            return DateTime(DateTime.now().year, monthNum);
          }
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
    final parts = trimmed
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return terms.toList();
    String lastName, firstName;
    if (fullName.contains(',')) {
      lastName = parts[0];
      firstName = parts.length > 1 ? parts[1] : '';
    } else {
      lastName = parts.last;
      firstName = parts.first;
    }
    final ln = lastName.toLowerCase();
    final fn = firstName.toLowerCase();
    terms.add(ln);
    if (fn.length >= 2) {
      terms.add('${ln}, ${fn.substring(0, 2)}');
      terms.add('${ln},${fn.substring(0, 2)}');
      terms.add('${ln}, ${fn.substring(0, 2).toLowerCase()}');
    }
    if (fn.length >= 3) {
      terms.add('${ln}, ${fn.substring(0, 3)}');
      terms.add('${ln},${fn.substring(0, 3)}');
    }
    if (fn.isNotEmpty) {
      terms.add('$ln, $fn');
      terms.add('$ln,$fn');
    }
    return terms.toList();
  }

  static bool _looksLikeShift(String s) {
    final u = s.trim().toUpperCase();
    if (u.isEmpty || u.length > 10) return false;
    if (RegExp(r'^\d+$').hasMatch(u)) return false;
    if (RegExp(r'^\d{1,2}\.\d{1,2}\.?$').hasMatch(u)) return false;
    const calWords = [
      'MO','DI','MI','DO','FR','SA','SO',
      'MON','DIE','MIT','DON','FRE','SAM','SON',
      'NAME','RESERVE','JUNI','JULI','AUGUST',
      'SEPTEMBER','OKTOBER','NOVEMBER','DEZEMBER',
      'JANUAR','FEBRUAR','MÄRZ','APRIL','MAI',
      'KW','KALENDERWOCHE',
    ];
    if (calWords.contains(u)) return false;
    if (RegExp(r'^\d{4}$').hasMatch(u)) return false;
    if (u.contains(',')) return false;
    if (u.length > 8 && RegExp(r'^[A-ZÄÖÜ]+$').hasMatch(u)) return false;
    const known = [
      'P1','P2','P','F1','F2','F','IS','T','L','AUF',
      'U','DA','X','VK','RES','KDFT','GEB','LÜ','LUE','AF',
    ];
    for (final k in known) {
      if (u == k) return true;
      if (u.startsWith('$k/') || u.endsWith('/$k')) return true;
    }
    return RegExp(
            r'^[A-ZÄÖÜ][A-ZÄÖÜ0-9]{0,4}(?:/[A-ZÄÖÜ][A-ZÄÖÜ0-9]{0,4})?$')
        .hasMatch(u);
  }

  static Map<String, dynamic> _err(
    DateTime? month,
    String userMsg,
    bool devMode,
    StringBuffer log, {
    String? devDetail,
  }) {
    final msg = devMode
        ? '$userMsg${devDetail != null ? '\n\n$devDetail' : (log.isNotEmpty ? '\n\n[DEV LOG]\n$log' : '')}'
        : userMsg;
    return {'month': month, 'data': <String, String>{}, 'error': msg};
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScheduleScreen
// ─────────────────────────────────────────────────────────────────────────────

class ScheduleScreen extends StatefulWidget {
  final VoidCallback onNavigateToHome;
  final VoidCallback onNavigateToMonth;
  final void Function(DateTime)? onMonthChanged;

  const ScheduleScreen({
    super.key,
    required this.onNavigateToHome,
    required this.onNavigateToMonth,
    this.onMonthChanged,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late DateTime _selectedMonth;
  Map<String, String> _scheduleData = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadScheduleData();
  }

  bool get _isDevMode {
    final box = Hive.box('einstellungen');
    return box.get('dienstplan_dev_placeholder', defaultValue: false) as bool;
  }

  void _loadScheduleData() {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final raw = box.get('schedule_$monthKey');
    setState(() {
      _scheduleData = {};
      if (raw is Map) {
        for (final entry in raw.entries) {
          _scheduleData[entry.key.toString()] = entry.value.toString();
        }
      }
    });
  }

  void _setMonth(DateTime month) {
    setState(() => _selectedMonth = month);
    widget.onMonthChanged?.call(month);
    _loadScheduleData();
  }

  void _changeMonth(int delta) {
    _setMonth(DateTime(_selectedMonth.year, _selectedMonth.month + delta));
  }

  bool get _hasSchedule => _scheduleData.isNotEmpty;

  int get _workDays => _scheduleData.values.where((v) {
        final cat = ScheduleEntry(v).category;
        return cat == ShiftCategory.work || cat == ShiftCategory.mixed;
      }).length;

  int get _freeDays => _scheduleData.values
      .where((v) => ScheduleEntry(v).category == ShiftCategory.free)
      .length;

  int get _vkDays => _scheduleData.values
      .where((v) => v.trim().toUpperCase() == 'VK')
      .length;

  List<DateTime> get _daysInMonth {
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final count = DateUtils.getDaysInMonth(year, month);
    return List.generate(count, (i) => DateTime(year, month, i + 1));
  }

  void _showMonthPicker() {
    final skin = AppTheme.of(context);
    int pickedYear = _selectedMonth.year;
    int pickedMonth = _selectedMonth.month - 1;
    final yearCount = DateTime.now().year - 2020 + 2;
    final monthCtrl =
        FixedExtentScrollController(initialItem: 1000 * 12 + pickedMonth);
    final yearCtrl =
        FixedExtentScrollController(initialItem: pickedYear - 2020);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: skin.bgSheet,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: skin.borderMedium),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: skin.surface(0.2),
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Text('Monat & Jahr',
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: CupertinoPicker(
                      scrollController: monthCtrl,
                      itemExtent: 44,
                      looping: true,
                      backgroundColor: Colors.transparent,
                      onSelectedItemChanged: (i) =>
                          setSheet(() => pickedMonth = i % 12),
                      children: List.generate(
                          12,
                          (i) => Center(
                                child: Text(
                                    DateFormat('MMMM', 'de')
                                        .format(DateTime(2024, i + 1)),
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                        color: skin.textPrimary)),
                              )),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: yearCtrl,
                      itemExtent: 44,
                      looping: false,
                      backgroundColor: Colors.transparent,
                      onSelectedItemChanged: (i) => setSheet(() =>
                          pickedYear = 2020 + i.clamp(0, yearCount - 1)),
                      children: List.generate(
                          yearCount,
                          (i) => Center(
                                child: Text('${2020 + i}',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                        color: skin.textPrimary)),
                              )),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final now = DateTime.now();
                      _setMonth(DateTime(now.year, now.month));
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: Text('Aktuell',
                              style: TextStyle(
                                  color: skin.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _setMonth(DateTime(pickedYear, pickedMonth + 1));
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          gradient: skin.gradient,
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: Text('Auswählen',
                              style: TextStyle(
                                  color: skin.onGradient,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700))),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isChrome = skin.key == 'chrome';
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    final days = _daysInMonth;
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;

    return ValueListenableBuilder(
      valueListenable: Hive.box('einstellungen').listenable(),
      builder: (context, box, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadScheduleData();
        });

        return Scaffold(
          backgroundColor: skin.bgBase,
          body: SafeArea(
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
                        Row(children: [
                          Text('Dienstplan',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: skin.textPrimary)),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB347)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFFFFB347)
                                      .withValues(alpha: 0.4)),
                            ),
                            child: const Text('BETA',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFFB347),
                                    letterSpacing: 0.8)),
                          ),
                          if (_isDevMode) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF5B5B)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFFEF5B5B)
                                        .withValues(alpha: 0.4)),
                              ),
                              child: const Text('DEV',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFEF5B5B),
                                      letterSpacing: 0.8)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          _MonthNavBtn(
                              icon: Icons.chevron_left,
                              onTap: () => _changeMonth(-1)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _showMonthPicker,
                              onDoubleTap: () {
                                HapticFeedback.selectionClick();
                                final now = DateTime.now();
                                _setMonth(DateTime(now.year, now.month));
                              },
                              onHorizontalDragEnd: (d) {
                                final v = d.primaryVelocity ?? 0;
                                if (v < -300) _changeMonth(1);
                                if (v > 300) _changeMonth(-1);
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                decoration: BoxDecoration(
                                  color: skin.bgCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: skin.primaryWithAlpha(0.35)),
                                ),
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(monthName,
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: skin.textPrimary)),
                                      const SizedBox(width: 6),
                                      Icon(Icons.expand_more,
                                          color: skin.primary, size: 18),
                                    ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _MonthNavBtn(
                              icon: Icons.chevron_right,
                              onTap: () => _changeMonth(1)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          _StatCard(
                              label: 'Arbeit',
                              value: '$_workDays',
                              color: isChrome
                                  ? const Color(0xFFDDDDDD)
                                  : const Color(0xFF5B8DEF)),
                          const SizedBox(width: 10),
                          _StatCard(
                              label: 'Frei',
                              value: '$_freeDays',
                              color: isChrome
                                  ? const Color(0xFF666666)
                                  : const Color(0xFF6B7280)),
                          const SizedBox(width: 10),
                          _StatCard(
                              label: 'VK',
                              value: '$_vkDays',
                              color: isChrome
                                  ? const Color(0xFF999999)
                                  : const Color(0xFFEF5B5B)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: !_hasSchedule
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('📋',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text('Kein Dienstplan hinterlegt',
                                    style: TextStyle(
                                        color: skin.white(0.3),
                                        fontSize: 15)),
                                const SizedBox(height: 8),
                                Text(
                                    'Tippe oben auf ☰ → Dienstplan importieren',
                                    style: TextStyle(
                                        color: skin.white(0.2),
                                        fontSize: 12),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          )
                        : _FadingListView(
                            fadeFromBottom: bottomNavHeight + 20,
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                  24, 4, 24, bottomNavHeight + 40),
                              itemCount: days.length,
                              itemBuilder: (context, index) {
                                final day = days[index];
                                final key =
                                    DateFormat('yyyy-MM-dd').format(day);
                                final shift = _scheduleData[key] ?? '';
                                final entry = shift.isEmpty
                                    ? null
                                    : ScheduleEntry(shift);
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: _DayCard(
                                      day: day,
                                      entry: entry,
                                      skin: skin,
                                      isChrome: isChrome),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Day Card
// ─────────────────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final DateTime day;
  final ScheduleEntry? entry;
  final AppSkin skin;
  final bool isChrome;

  const _DayCard(
      {required this.day,
      required this.entry,
      required this.skin,
      required this.isChrome});

  Color _color(String part) => _shiftColor(part, isChrome: isChrome);

  bool get _isBirthdayDay => entry?.hasBirthday ?? false;

  Color get _cardBorderColor {
    if (_isBirthdayDay) return Colors.transparent;
    if (entry == null) return skin.white(0.06);
    switch (entry!.category) {
      case ShiftCategory.work:
        return _color(entry!.parts.first).withValues(alpha: 0.3);
      case ShiftCategory.free:
        return skin.white(0.06);
      case ShiftCategory.mixed:
        return (isChrome
                ? const Color(0xFF888888)
                : const Color(0xFFFFB347))
            .withValues(alpha: 0.35);
      case ShiftCategory.other:
        return skin.white(0.08);
    }
  }

  Color get _cardBgColor {
    if (_isBirthdayDay)
      return const Color(0xFFFF6B9D).withValues(alpha: 0.06);
    if (entry == null) return skin.bgCard;
    switch (entry!.category) {
      case ShiftCategory.work:
        return _color(entry!.parts.first).withValues(alpha: 0.05);
      case ShiftCategory.free:
      case ShiftCategory.other:
        return skin.bgCard;
      case ShiftCategory.mixed:
        return (isChrome
                ? const Color(0xFF888888)
                : const Color(0xFFFFB347))
            .withValues(alpha: 0.04);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeekend = day.weekday == DateTime.saturday ||
        day.weekday == DateTime.sunday;
    final dayName = DateFormat('EEE', 'de').format(day);
    final dayNum = DateFormat('dd', 'de').format(day);
    final monthAbbr = DateFormat('MMM', 'de').format(day);
    final weekendAccent =
        isChrome ? const Color(0xFFCCCCCC) : skin.primary;

    Widget cardContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dayName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _isBirthdayDay
                        ? const Color(0xFFFF6B9D).withValues(alpha: 0.8)
                        : isWeekend
                            ? weekendAccent
                            : skin.white(0.38),
                    letterSpacing: 0.8,
                  )),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(dayNum,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: skin.textPrimary,
                          height: 1)),
                  const SizedBox(width: 3),
                  Text(monthAbbr,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: skin.white(0.3))),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: skin.white(0.07),
        ),
        Expanded(
          child: entry == null || entry!.shift.isEmpty
              ? Text('—',
                  style: TextStyle(fontSize: 16, color: skin.white(0.18)))
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: entry!.parts.map((part) {
                    final isGeb = part.trim().toUpperCase() == 'GEB';
                    if (isGeb) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B9D),
                              Color(0xFFFFB347)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF6B9D)
                                  .withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text('GEB',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                            SizedBox(width: 4),
                            Text('🎂',
                                style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      );
                    }
                    final color = _color(part);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text(part,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    );
                  }).toList(),
                ),
        ),
        if (entry != null && entry!.shift.isNotEmpty) ...[
          const SizedBox(width: 8),
          _isBirthdayDay
              ? const SizedBox(width: 7, height: 7)
              : _CategoryDot(
                  category: entry!.category,
                  skin: skin,
                  isChrome: isChrome),
        ],
      ],
    );

    if (_isBirthdayDay) {
      return Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFFF6B9D),
              Color(0xFFFFB347),
              Color(0xFFFF6B9D)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(15.5),
        ),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _cardBgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: cardContent,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isWeekend
            ? weekendAccent.withValues(alpha: 0.045)
            : _cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWeekend
              ? weekendAccent.withValues(alpha: 0.18)
              : _cardBorderColor,
        ),
      ),
      child: cardContent,
    );
  }
}

class _CategoryDot extends StatelessWidget {
  final ShiftCategory category;
  final AppSkin skin;
  final bool isChrome;
  const _CategoryDot(
      {required this.category, required this.skin, required this.isChrome});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (isChrome) {
      switch (category) {
        case ShiftCategory.work:
          color = const Color(0xFFDDDDDD);
          break;
        case ShiftCategory.free:
          color = const Color(0xFF555555);
          break;
        case ShiftCategory.mixed:
          color = const Color(0xFF999999);
          break;
        case ShiftCategory.other:
          color = const Color(0xFF444444);
          break;
      }
    } else {
      switch (category) {
        case ShiftCategory.work:
          color = const Color(0xFF5B8DEF);
          break;
        case ShiftCategory.free:
          color = const Color(0xFF6B7280);
          break;
        case ShiftCategory.mixed:
          color = const Color(0xFFFFB347);
          break;
        case ShiftCategory.other:
          color = skin.white(0.2);
          break;
      }
    }
    return Container(
        width: 7,
        height: 7,
        decoration:
            BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DienstplanUploadSheet
// ─────────────────────────────────────────────────────────────────────────────

class DienstplanUploadSheet extends StatefulWidget {
  final AppSkin skin;
  final DateTime initialMonth;
  final DateTime selectedMonth;
  final VoidCallback onImported;
  final String? preloadedFilePath;
  final String? preloadedFileName;
  final List<int>? preloadedBytes;

  const DienstplanUploadSheet({
    super.key,
    required this.skin,
    required this.initialMonth,
    required this.selectedMonth,
    required this.onImported,
    this.preloadedFilePath,
    this.preloadedFileName,
    this.preloadedBytes,
  });

  @override
  State<DienstplanUploadSheet> createState() =>
      _DienstplanUploadSheetState();
}

class _DienstplanUploadSheetState extends State<DienstplanUploadSheet> {
  String? _selectedFileName;
  String? _selectedFilePath;
  List<int>? _selectedFileBytes;
  bool _isLoading = false;
  String? _errorMessage;
  bool _errorCopied = false;

  bool get _hasFile =>
      _selectedFilePath != null || _selectedFileBytes != null;
  AppSkin get skin => widget.skin;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedFilePath != null) {
      _selectedFilePath  = widget.preloadedFilePath;
      _selectedFileName  = widget.preloadedFileName ?? 'Geteilte PDF';
      _selectedFileBytes = widget.preloadedBytes;
    }
  }

  bool get _isDevMode {
    final box = Hive.box('einstellungen');
    return box.get('dienstplan_dev_placeholder', defaultValue: false) as bool;
  }

  Future<void> _pickFile() async {
    setState(() {
      _errorMessage = null;
      _errorCopied = false;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      final path = kIsWeb ? null : picked.path;

      if (bytes == null && path == null) {
        setState(() => _errorMessage =
            'Datei konnte nicht gelesen werden. Bitte erneut versuchen.');
        return;
      }

      setState(() {
        _selectedFileName  = picked.name;
        _selectedFileBytes = bytes?.toList();
        _selectedFilePath  = path;
        _errorMessage      = null;
      });
    } on Exception catch (e) {
      setState(() => _errorMessage =
          'Dateiauswahl konnte nicht geöffnet werden.\n'
          'Bitte Dateizugriff in den iOS-Einstellungen erlauben.\n\nDetail: $e');
    }
  }

  void _clearFile() {
    setState(() {
      _selectedFileName  = null;
      _selectedFilePath  = null;
      _selectedFileBytes = null;
      _errorMessage      = null;
      _errorCopied       = false;
    });
  }

  Future<void> _importPdf() async {
    if (!_hasFile) return;
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
      _errorCopied  = false;
    });

    try {
      final settingsBox = Hive.box('einstellungen');
      final scheduleName =
          settingsBox.get('dienstplan_name', defaultValue: '') as String;
      final mainName =
          settingsBox.get('name', defaultValue: '') as String;
      final userName =
          scheduleName.isNotEmpty ? scheduleName : mainName;

      List<int>? bytes = _selectedFileBytes;
      if ((bytes == null || bytes.isEmpty) && _selectedFilePath != null) {
        try {
          bytes =
              await dartio.File(_selectedFilePath!).readAsBytes();
        } catch (_) {
          bytes = null;
        }
      }

      final result = await DienstplanParser.parse(
        filePath: bytes != null ? null : _selectedFilePath,
        fileBytes: bytes,
        userName: userName,
        fileName: _selectedFileName ?? '',
        devMode: _isDevMode,
      );

      final String? error = result['error'] as String?;
      if (error != null && error.isNotEmpty) {
        setState(() {
          _errorMessage = error;
          _isLoading    = false;
        });
        return;
      }

      DateTime? month = result['month'] as DateTime?;
      final Map<String, String> data =
          Map<String, String>.from(result['data'] as Map? ?? {});

      if (data.isEmpty) {
        setState(() {
          _errorMessage = 'Keine Dienste gefunden.';
          _isLoading    = false;
        });
        return;
      }

      if (month == null) {
        month = await _askForMonth();
        if (month == null) {
          setState(() => _isLoading = false);
          return;
        }
      }

      final monthKey = DateFormat('yyyy-MM').format(month);
      settingsBox.put('schedule_$monthKey', data);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '✓ Dienstplan ${DateFormat('MMMM yyyy', 'de').format(month)} '
            'importiert (${data.length} Tage)'),
        backgroundColor: skin.statComplete,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(seconds: 3),
      ));

      widget.onImported();
    } catch (e) {
      setState(() => _errorMessage = 'Fehler beim Importieren: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<DateTime?> _askForMonth() async {
    int pickedYear  = widget.initialMonth.year;
    int pickedMonth = widget.initialMonth.month - 1;
    final yearCount = DateTime.now().year - 2020 + 2;
    final monthCtrl =
        FixedExtentScrollController(initialItem: 1000 * 12 + pickedMonth);
    final yearCtrl =
        FixedExtentScrollController(initialItem: pickedYear - 2020);

    return await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: skin.bgSheet,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: skin.borderMedium),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, 24 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: skin.surface(0.2),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text('Für welchen Monat gilt diese PDF?',
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Der Monat konnte nicht automatisch erkannt werden.',
                  style: TextStyle(fontSize: 13, color: skin.textMuted),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: Row(children: [
                  Expanded(
                      flex: 2,
                      child: CupertinoPicker(
                        scrollController: monthCtrl,
                        itemExtent: 44,
                        looping: true,
                        backgroundColor: Colors.transparent,
                        onSelectedItemChanged: (i) =>
                            setSheet(() => pickedMonth = i % 12),
                        children: List.generate(
                            12,
                            (i) => Center(
                                child: Text(
                                    DateFormat('MMMM', 'de')
                                        .format(DateTime(2024, i + 1)),
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: skin.textPrimary)))),
                      )),
                  Expanded(
                      child: CupertinoPicker(
                    scrollController: yearCtrl,
                    itemExtent: 44,
                    looping: false,
                    backgroundColor: Colors.transparent,
                    onSelectedItemChanged: (i) => setSheet(() =>
                        pickedYear = 2020 + i.clamp(0, yearCount - 1)),
                    children: List.generate(
                        yearCount,
                        (i) => Center(
                            child: Text('${2020 + i}',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: skin.textPrimary)))),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                        color: skin.surface(0.06),
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(
                        child: Text('Abbrechen',
                            style: TextStyle(
                                color: skin.textPrimary,
                                fontWeight: FontWeight.w600))),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: GestureDetector(
                  onTap: () => Navigator.pop(
                      ctx, DateTime(pickedYear, pickedMonth + 1)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                        gradient: skin.gradient,
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(
                        child: Text('Übernehmen',
                            style: TextStyle(
                                color: skin.onGradient,
                                fontWeight: FontWeight.w700))),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteSelectedMonth() async {
    final displayMonth =
        DateFormat('MMMM yyyy', 'de').format(widget.selectedMonth);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: skin.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Monat löschen',
            style: TextStyle(
                color: skin.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
            'Alle Dienstplan-Daten für $displayMonth werden gelöscht.',
            style: TextStyle(color: skin.textMuted, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Abbrechen',
                  style: TextStyle(color: skin.textMuted))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Löschen',
                  style: TextStyle(
                      color: skin.deleteColor,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(widget.selectedMonth);
    box.delete('schedule_$monthKey');
    Navigator.pop(context);
    widget.onImported();
  }

  void _copyError() {
    if (_errorMessage == null) return;
    Clipboard.setData(ClipboardData(text: _errorMessage!));
    setState(() => _errorCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _errorCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isChrome = skin.key == 'chrome';
    final gradientDeco = BoxDecoration(
      gradient: isChrome
          ? const LinearGradient(
              colors: [Color(0xFF333333), Color(0xFF555555)])
          : skin.gradient,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: skin.primaryWithAlpha(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4))
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: skin.bgSheet,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: skin.borderMedium),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: skin.surface(0.2),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: skin.primaryWithAlpha(0.12),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.upload_file_outlined,
                  color: skin.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text('Dienstplan importieren',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: skin.textPrimary)),
              const SizedBox(height: 3),
              Text('PDF-Datei auswählen & importieren',
                  style: TextStyle(fontSize: 12, color: skin.textMuted)),
            ])),
          ]),
          const SizedBox(height: 20),

          // Datei angezeigt
          if (_hasFile) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: skin.statComplete.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: skin.statComplete.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Icons.picture_as_pdf_outlined,
                    color: skin.statComplete, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                  _selectedFileName ?? 'Datei ausgewählt',
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
                GestureDetector(
                  onTap: _clearFile,
                  child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.close,
                          color: skin.deleteColor, size: 16)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // Fehler
          if (_errorMessage != null) ...[
            if (_isDevMode) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: skin.deleteColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: skin.deleteColor.withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
                      child: Row(children: [
                        Icon(Icons.error_outline,
                            color: skin.deleteColor, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text('Fehler',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: skin.deleteColor))),
                        GestureDetector(
                          onTap: _copyError,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _errorCopied
                                  ? skin.statComplete
                                      .withValues(alpha: 0.15)
                                  : skin.deleteColor
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _errorCopied
                                      ? skin.statComplete
                                          .withValues(alpha: 0.4)
                                      : skin.deleteColor
                                          .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      _errorCopied
                                          ? Icons.check_rounded
                                          : Icons.copy_outlined,
                                      size: 13,
                                      color: _errorCopied
                                          ? skin.statComplete
                                          : skin.deleteColor),
                                  const SizedBox(width: 4),
                                  Text(
                                      _errorCopied
                                          ? 'Kopiert'
                                          : 'Kopieren',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _errorCopied
                                              ? skin.statComplete
                                              : skin.deleteColor)),
                                ]),
                          ),
                        ),
                      ]),
                    ),
                    Divider(
                        height: 1,
                        color: skin.deleteColor.withValues(alpha: 0.15)),
                    Flexible(
                        child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Text(_errorMessage!,
                          style: TextStyle(
                              fontSize: 11,
                              color: skin.deleteColor,
                              height: 1.4)),
                    )),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.error_outline,
                      color: skin.deleteColor, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                          fontSize: 13,
                          color: skin.deleteColor,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
          ],

          // Buttons
          if (!_hasFile)
            GestureDetector(
              onTap: _isLoading ? null : _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: gradientDeco,
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_outlined,
                          color: skin.onGradient, size: 20),
                      const SizedBox(width: 10),
                      Text('Dokument auswählen',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: skin.onGradient,
                              letterSpacing: 0.3)),
                    ]),
              ),
            ),

          if (_hasFile) ...[
            GestureDetector(
              onTap: _isLoading ? null : _importPdf,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: gradientDeco,
                child: _isLoading
                    ? Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: skin.onGradient)))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline,
                              color: skin.onGradient, size: 20),
                          const SizedBox(width: 10),
                          Text('Dokument importieren',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: skin.onGradient,
                                  letterSpacing: 0.3)),
                        ]),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _isLoading ? null : _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                    color: skin.surface(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: skin.borderSubtle)),
                child: Center(
                    child: Text('Andere Datei wählen',
                        style: TextStyle(
                            color: skin.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w500))),
              ),
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: skin.borderSubtle),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: _deleteSelectedMonth,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                  color: skin.deleteColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: skin.deleteColor.withValues(alpha: 0.25))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline,
                        color: skin.deleteColor, size: 18),
                    const SizedBox(width: 8),
                    Text('Aktuellen Monat löschen',
                        style: TextStyle(
                            color: skin.deleteColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ]),
            ),
          ),

          const SizedBox(height: 8),
          Text(
              'Unterstützt: PDF-Dateien mit maschinenlesbarem Text',
              style: TextStyle(fontSize: 11, color: skin.textHint),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MonthNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MonthNavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: skin.surface(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: skin.borderSubtle)),
          child: Icon(icon, color: skin.primary)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11, color: skin.textMuted)),
        ]),
      ),
    );
  }
}

class _FadingListView extends StatelessWidget {
  final Widget child;
  final double fadeFromBottom;
  const _FadingListView(
      {required this.child, required this.fadeFromBottom});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        final h = bounds.height;
        final startStop =
            ((h - (fadeFromBottom - 30)) / h).clamp(0.0, 1.0);
        final endStop =
            ((h - (fadeFromBottom - 70)) / h).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.white,
            Colors.white,
            Colors.black26,
            Colors.transparent,
            Colors.transparent
          ],
          stops: [
            0.0,
            startStop,
            (startStop + endStop) / 2,
            endStop,
            1.0
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}