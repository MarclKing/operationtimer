import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';

class PdfService {
  static String _calcDuration(String kommen, String gehen) {
    if (kommen.isEmpty || gehen.isEmpty) return '--';
    try {
      final k = kommen.split(':');
      final g = gehen.split(':');
      final start = Duration(hours: int.parse(k[0]), minutes: int.parse(k[1]));
      final end = Duration(hours: int.parse(g[0]), minutes: int.parse(g[1]));
      final diff = end - start;
      if (diff.isNegative) return '--';
      return '${diff.inHours}h ${(diff.inMinutes % 60).toString().padLeft(2, '0')}m';
    } catch (_) {
      return '--';
    }
  }

  static pw.Widget _pdfStatBox(
      String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF0F0F0),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 20,
                    color: const PdfColor.fromInt(0xFF1A1A1A))),
            pw.SizedBox(height: 2),
            pw.Text(label,
                style: pw.TextStyle(
                    font: font, fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ),
    );
  }

  static Future<void> exportMonth(
      BuildContext context, DateTime month) async {
    final box = Hive.box('arbeitszeiten');
    final settingsBox = Hive.box('einstellungen');
    final fullName =
        settingsBox.get('name', defaultValue: 'Unbekannt') as String;
    final monthKey = DateFormat('yyyy-MM').format(month);
    final monthName = DateFormat('MMMM yyyy', 'de').format(month);

    final List<Map<String, dynamic>> entries = [];
    for (final key in box.keys) {
      if (key.toString().startsWith(monthKey)) {
        final data = box.get(key);
        if (data != null) {
          if (data is List) {
            for (final entry in data) {
              final entryWithDatum = Map<String, dynamic>.from(entry);
              if (!entryWithDatum.containsKey('datum')) {
                entryWithDatum['datum'] = key.toString();
              }
              entries.add(entryWithDatum);
            }
          } else {
            final entry = Map<String, dynamic>.from(data);
            if (!entry.containsKey('datum')) {
              entry['datum'] = key.toString();
            }
            entries.add(entry);
          }
        }
      }
    }
    entries.sort((a, b) => a['datum'].compareTo(b['datum']));

    await _buildAndShare(entries, fullName, monthName, monthKey);
  }

  static Future<void> exportSingleEntry(Map<String, dynamic> entry) async {
    final settingsBox = Hive.box('einstellungen');
    final fullName =
        settingsBox.get('name', defaultValue: 'Unbekannt') as String;
    final datum = DateTime.parse(entry['datum']);
    final dateStr = DateFormat('dd.MM.yyyy').format(datum);
    final fileKey = DateFormat('yyyy-MM-dd').format(datum);

    await _buildAndShare([entry], fullName, dateStr, fileKey);
  }

  // ── Determines consecutive day blocks for PDF separators (change #9) ──────
  // Returns a list of block indices: entries[i] gets blockIndex[i].
  // Consecutive calendar days → same block; gap of ≥1 day → new block.
  static List<int> _computeBlocks(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return [];
    final blocks = List<int>.filled(entries.length, 0);
    int block = 0;
    blocks[0] = 0;
    for (int i = 1; i < entries.length; i++) {
      try {
        final prev = DateTime.parse(entries[i - 1]['datum']);
        final curr = DateTime.parse(entries[i]['datum']);
        // Same calendar day or next calendar day → same block
        final dayDiff = DateTime(curr.year, curr.month, curr.day)
            .difference(DateTime(prev.year, prev.month, prev.day))
            .inDays;
        if (dayDiff > 1) block++;
      } catch (_) {
        block++;
      }
      blocks[i] = block;
    }
    return blocks;
  }

  static Future<void> _buildAndShare(
    List<Map<String, dynamic>> entries,
    String fullName,
    String title,
    String fileKey,
  ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final blocks = _computeBlocks(entries);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // ── Header ────────────────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFF1A1A2E),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('OpTimes',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 20,
                            color: PdfColors.white)),
                    pw.SizedBox(height: 4),
                    pw.Text('Arbeitszeiterfassung',
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 12,
                            color: PdfColors.grey400)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(fullName,
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 14,
                            color: PdfColors.white)),
                    pw.SizedBox(height: 4),
                    pw.Text(title,
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 12,
                            color: PdfColors.grey400)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          // ── Stats ──────────────────────────────────────────────────────────
          pw.Row(
            children: [
              _pdfStatBox('Einträge', '${entries.length}', font, fontBold),
              pw.SizedBox(width: 10),
              _pdfStatBox(
                  'Vollständig',
                  '${entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length}',
                  font,
                  fontBold),
              pw.SizedBox(width: 10),
              _pdfStatBox(
                  'Offen',
                  '${entries.where((e) => (e['gehen'] ?? '').isEmpty).length}',
                  font,
                  fontBold),
            ],
          ),
          pw.SizedBox(height: 20),
          // ── Table header ───────────────────────────────────────────────────
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1A1A1A)),
            child: pw.Row(
              children: [
                pw.Expanded(
                    flex: 2,
                    child: pw.Text('Datum',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.white))),
                pw.Expanded(
                    child: pw.Text('Kommen',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.white))),
                pw.Expanded(
                    child: pw.Text('Gehen',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.white))),
                pw.Expanded(
                    child: pw.Text('Dauer',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.white))),
                pw.Expanded(
                    child: pw.Text('TKF',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.white))),
                pw.Expanded(
                    flex: 2,
                    child: pw.Text('Notiz',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.white))),
              ],
            ),
          ),

          // ── Rows with block separators (change #9) ─────────────────────────
          ...() {
            final widgets = <pw.Widget>[];
            for (int i = 0; i < entries.length; i++) {
              // Draw a separator line before the first entry of a new block
              // (but not before the very first entry)
              if (i > 0 && blocks[i] != blocks[i - 1]) {
                widgets.add(
                  pw.Container(
                    height: 2,
                    margin: const pw.EdgeInsets.symmetric(vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFF4A4A6A),
                      borderRadius: pw.BorderRadius.circular(1),
                    ),
                  ),
                );
              }

              final entry = entries[i];
              final datum = DateTime.parse(entry['datum']);
              final datumStr =
                  DateFormat('EEE dd.MM.yy', 'de').format(datum);
              final kommen = entry['kommen'] ?? '';
              final gehen = entry['gehen'] ?? '';
              final tkf = entry['TKF'] ?? '';
              final notiz = entry['notiz'] ?? '';
              final duration = _calcDuration(kommen, gehen);

              // Alternate row colours within each block; reset per block
              final posInBlock = i -
                  entries.indexWhere((e) => blocks[entries.indexOf(e)] == blocks[i]);
              // simpler: count from start of current block
              int blockStart = i;
              while (blockStart > 0 && blocks[blockStart - 1] == blocks[i]) {
                blockStart--;
              }
              final rowInBlock = i - blockStart;
              final bgColor = rowInBlock.isEven
                  ? const PdfColor.fromInt(0xFFF8F8F8)
                  : PdfColors.white;

              widgets.add(
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: pw.BoxDecoration(color: bgColor),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                          flex: 2,
                          child: pw.Text(datumStr,
                              style:
                                  pw.TextStyle(font: font, fontSize: 10))),
                      pw.Expanded(
                          child: pw.Text(
                              kommen.isEmpty ? '--:--' : kommen,
                              style:
                                  pw.TextStyle(font: font, fontSize: 10))),
                      pw.Expanded(
                          child: pw.Text(gehen.isEmpty ? '--:--' : gehen,
                              style:
                                  pw.TextStyle(font: font, fontSize: 10))),
                      pw.Expanded(
                          child: pw.Text(duration,
                              style: pw.TextStyle(
                                  font: fontBold, fontSize: 10))),
                      pw.Expanded(
                          child: pw.Text(tkf,
                              style:
                                  pw.TextStyle(font: font, fontSize: 10))),
                      pw.Expanded(
                          flex: 2,
                          child: pw.Text(notiz,
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 10,
                                  color: PdfColors.grey600))),
                    ],
                  ),
                ),
              );
            }
            return widgets;
          }(),

          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Text(
            'Erstellt am ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(
                font: font, fontSize: 9, color: PdfColors.grey500),
          ),
        ],
      ),
    );

    final safeName = fullName.replaceAll(' ', '_');
    await Printing.sharePdf(
  bytes: await pdf.save(),
  filename: 'Zeiterfassung_${title.replaceAll(' ', '_')}_${safeName}.pdf',
);
  }

  // ── Month picker dialog  (change #4 + #5) ─────────────────────────────────
  // • "Abbrechen" → "Aktuell" (jumps to current month)
  // • Picker controllers initialised correctly so displayed month matches state
  static Future<void> showMonthPickerAndExport(BuildContext context) async {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';
    DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            void changeMonth(int delta) {
              setDialogState(() {
                selectedMonth = DateTime(
                    selectedMonth.year, selectedMonth.month + delta);
              });
            }

            return GestureDetector(
              onHorizontalDragEnd: (DragEndDetails details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -300) changeMonth(1);
                if (velocity > 300) changeMonth(-1);
              },
              child: Dialog(
                backgroundColor: skin.bgCard,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Monat auswählen',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: skin.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: skin.bgBase,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: skin.borderMedium),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => changeMonth(-1),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(Icons.chevron_left,
                                    color: skin.primary, size: 24),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final newDate = await _showFullPicker(
                                    context, selectedMonth, skin);
                                if (newDate != null) {
                                  setDialogState(
                                      () => selectedMonth = newDate);
                                }
                              },
                              child: Text(
                                DateFormat('MMMM yyyy', 'de')
                                    .format(selectedMonth),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: skin.textPrimary,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => changeMonth(1),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(Icons.chevron_right,
                                    color: skin.primary, size: 24),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          // "Aktuell" instead of "Abbrechen"
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final now = DateTime.now();
                                setDialogState(() => selectedMonth =
                                    DateTime(now.year, now.month));
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: skin.surface(0.06),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'Aktuell',
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
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                PdfService.exportMonth(
                                    context, selectedMonth);
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  gradient: isChromeSkin
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF333333),
                                            Color(0xFF555555)
                                          ],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        )
                                      : skin.gradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'PDF erstellen',
                                    style: TextStyle(
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
              ),
            );
          },
        );
      },
    );
  }

  // ── Full month+year picker (change #5) ────────────────────────────────────
  // Controllers initialised to the ACTUAL current values, not a fixed offset
  // that drifts. Using offset = 1000 * period + actualIndex guarantees the
  // visible item matches state on open.
  static Future<DateTime?> _showFullPicker(
      BuildContext context, DateTime currentMonth, AppSkin skin) async {
    int pickedYear = currentMonth.year;
    int pickedMonth = currentMonth.month - 1; // 0-based
    final yearCount = DateTime.now().year - 2020 + 15;

    // Correct initial items so the displayed value matches currentMonth
    final monthCtrl = FixedExtentScrollController(
        initialItem: 1000 * 12 + pickedMonth);
    final yearCtrl = FixedExtentScrollController(
        initialItem: pickedYear - 2020);

    return await showDialog<DateTime>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setPickerState) {
            return Dialog(
              backgroundColor: skin.bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Monat & Jahr',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: skin.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CupertinoPicker(
                              scrollController: monthCtrl,
                              itemExtent: 44,
                              looping: true,
                              backgroundColor: Colors.transparent,
                              onSelectedItemChanged: (int index) {
                                setPickerState(
                                    () => pickedMonth = index % 12);
                              },
                              children: List.generate(
                                12,
                                (int index) => Center(
                                  child: Text(
                                    DateFormat('MMMM', 'de')
                                        .format(DateTime(2024, index + 1)),
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                        color: skin.textPrimary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: yearCtrl,
                              itemExtent: 44,
                              looping: false,
                              backgroundColor: Colors.transparent,
                              onSelectedItemChanged: (int index) {
                                setPickerState(
                                    () => pickedYear = 2020 + index);
                              },
                              children: List.generate(
                                yearCount,
                                (int index) => Center(
                                  child: Text(
                                    '${2020 + index}',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                        color: skin.textPrimary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // "Aktuell" instead of "Abbrechen"
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(
                                  ctx,
                                  DateTime(DateTime.now().year,
                                      DateTime.now().month));
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: skin.surface(0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'Aktuell',
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
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(
                                  ctx,
                                  DateTime(
                                      pickedYear, pickedMonth + 1));
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: skin.gradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'Übernehmen',
                                  style: TextStyle(
                                    color: skin.onGradient,
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
          },
        );
      },
    );
  }
}