import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_pickers.dart';

class PdfService {
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;
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

  static String _shortTz(String tzId) {
    final parts = tzId.split('/');
    return parts.last.replaceAll('_', ' ');
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

  static List<int> _computeBlocks(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return [];
    final blocks = List<int>.filled(entries.length, 0);
    int block = 0;
    blocks[0] = 0;
    for (int i = 1; i < entries.length; i++) {
      try {
        final prev = DateTime.parse(entries[i - 1]['datum']);
        final curr = DateTime.parse(entries[i]['datum']);
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
    _fontRegular ??= await PdfGoogleFonts.notoSansRegular();
    _fontBold ??= await PdfGoogleFonts.notoSansBold();
    final font = _fontRegular!;
    final fontBold = _fontBold!;

    final blocks = _computeBlocks(entries);
    final hasAnyZoneEntry = entries.any(
        (e) => e['gehenRaw'] != null && e['gehenRawTz'] != null);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFF0A0A0A),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('OpTimes',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 20,
                            color: PdfColors.white)),
                    pw.SizedBox(height: 3),
                    pw.Text('Arbeitszeiterfassung  ·  $title',
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 11,
                            color: const PdfColor.fromInt(0xFF888888))),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(fullName,
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 13,
                            color: PdfColors.white)),
                    pw.SizedBox(height: 3),
                     pw.Row(children: [
                      pw.Text('${entries.length} Einträge',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 10,
                              color: const PdfColor.fromInt(0xFF888888))),
                      pw.Text('  ·  ', style: pw.TextStyle(font: font, fontSize: 10,
                          color: const PdfColor.fromInt(0xFF555555))),
                      pw.Text('${entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length} vollst.',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 10,
                              color: const PdfColor.fromInt(0xFF888888))),
                      pw.Text('  ·  ', style: pw.TextStyle(font: font, fontSize: 10,
                          color: const PdfColor.fromInt(0xFF555555))),
                      pw.Text('${entries.where((e) => (e['gehen'] ?? '').isEmpty).length} offen',
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 10,
                              color: const PdfColor.fromInt(0xFF888888))),
                      if (hasAnyZoneEntry) ...[
                        pw.Text('  ·  ', style: pw.TextStyle(font: font, fontSize: 10,
                            color: const PdfColor.fromInt(0xFF555555))),
                        pw.Text(
                            '${entries.where((e) => e['gehenRaw'] != null && e['gehenRawTz'] != null).length} Zonen-Wechsel',
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 10,
                                color: const PdfColor.fromInt(0xFF5B8DEF))),
                      ],
                    ]),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1A1A2E)),
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
                    child: pw.Text('Bemerkung',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.white))),
              ],
            ),
          ),
          ...() {
            final widgets = <pw.Widget>[];
            for (int i = 0; i < entries.length; i++) {
              if (i > 0 && blocks[i] != blocks[i - 1]) {
                widgets.add(
                  pw.Container(
                    height: 2,
                    margin: const pw.EdgeInsets.symmetric(vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFF5B8DEF),
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
              final notiz = entry['Bemerkung'] ?? '';
              final duration = _calcDuration(kommen, gehen);

              // ── Reisemodus: Zeitzonen-Wechsel innerhalb dieses Eintrags ──
              final gehenRaw = entry['gehenRaw'] as String?;
              final gehenRawTz = entry['gehenRawTz'] as String?;
              final hasZoneCrossing = gehenRaw != null && gehenRawTz != null;

              int blockStart = i;
              while (blockStart > 0 && blocks[blockStart - 1] == blocks[i]) {
                blockStart--;
              }
              final rowInBlock = i - blockStart;
              final bgColor = hasZoneCrossing
                  ? const PdfColor.fromInt(0xFFEAF1FF)
                  : (rowInBlock.isEven
                      ? const PdfColor.fromInt(0xFFF2F4FF)
                      : PdfColors.white);

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
                          child: hasZoneCrossing
                              ? pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(gehen.isEmpty ? '--:--' : gehen,
                                        style: pw.TextStyle(font: font, fontSize: 10)),
                                    pw.SizedBox(height: 1),
                                    pw.Text(
                                        '$gehenRaw ${_shortTz(gehenRawTz!)}',
                                        style: pw.TextStyle(
                                            font: font,
                                            fontSize: 7.5,
                                            color: const PdfColor.fromInt(0xFF5B8DEF))),
                                  ],
                                )
                              : pw.Text(gehen.isEmpty ? '--:--' : gehen,
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
            'Erstellt mit OpTimes · ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(
                font: font, fontSize: 9, color: const PdfColor.fromInt(0xFF8B8B9E)),
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

  // ── Month picker als Glass-Dialog mit PDF-Export ───────────────────────────
  static Future<void> showMonthPickerAndExport(BuildContext context) async {
    final skin = AppTheme.of(context);
    DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black.withValues(alpha: 0.50),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void changeMonth(int delta) {
            setSheet(() => selectedMonth =
                DateTime(selectedMonth.year, selectedMonth.month + delta));
          }

          void showPicker() async {
            // Nutzt gemeinsamen showMonthYearPicker aus glass_pickers.dart
            final picked = await showMonthYearPicker(
              context: ctx,
              skin: skin,
              initialMonth: selectedMonth,
            );
            if (picked != null) setSheet(() => selectedMonth = picked);
          }

          final monthName =
              DateFormat('MMMM yyyy', 'de').format(selectedMonth);

          return Center(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                        sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                    child: Container(
                      decoration: BoxDecoration(
                        color: skin.isLight
                            ? Colors.white.withValues(alpha: 0.88)
                            : skin.bgCard.withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: skin.glassBorder, width: 1.0),
                        boxShadow: [
                          BoxShadow(
                              color: skin.glassShadow,
                              blurRadius: 40,
                              offset: const Offset(0, 12)),
                          BoxShadow(
                              color: skin.glassHighlight,
                              blurRadius: 0,
                              spreadRadius: -1,
                              offset: const Offset(0, 1)),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36, height: 4,
                            decoration: BoxDecoration(
                                color: skin.surface(0.18),
                                borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(height: 20),
                          Text('Monat auswählen',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: skin.textPrimary)),
                          const SizedBox(height: 16),

                          // ── Monats-Navigation ──
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: skin.glassBlur,
                                  sigmaY: skin.glassBlur),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: skin.isLight
                                      ? Colors.white
                                          .withValues(alpha: skin.glassOpacity)
                                      : skin.bgCard
                                          .withValues(alpha: skin.glassOpacity),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: skin.glassBorder, width: 1.0),
                                  boxShadow: [
                                    BoxShadow(
                                        color: skin.glassShadow,
                                        blurRadius: 24,
                                        offset: const Offset(0, 6)),
                                    BoxShadow(
                                        color: skin.glassHighlight,
                                        blurRadius: 0,
                                        spreadRadius: -1,
                                        offset: const Offset(0, 1)),
                                  ],
                                ),
                                child: Row(children: [
                                  GestureDetector(
                                    onTap: () => changeMonth(-1),
                                    child: const SizedBox(
                                        width: 44, height: 52,
                                        child: Center(
                                            child: Icon(Icons.chevron_left,
                                                size: 22))),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: showPicker,
                                      onDoubleTap: () {
                                        final now = DateTime.now();
                                        setSheet(() => selectedMonth =
                                            DateTime(now.year, now.month));
                                      },
                                      onHorizontalDragEnd: (d) {
                                        final v = d.primaryVelocity ?? 0;
                                        if (v < -300) changeMonth(1);
                                        if (v > 300) changeMonth(-1);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
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
                                                color: skin.surface(0.4),
                                                size: 18),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => changeMonth(1),
                                    child: SizedBox(
                                        width: 44, height: 52,
                                        child: Center(
                                            child: Icon(Icons.chevron_right,
                                                size: 22,
                                                color: skin.surface(0.5)))),
                                  ),
                                ]),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ── Buttons ──
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  final now = DateTime.now();
                                  setSheet(() => selectedMonth =
                                      DateTime(now.year, now.month));
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: skin.isLight
                                        ? Colors.white.withValues(alpha: 0.75)
                                        : Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: skin.glassBorder, width: 1.0),
                                  ),
                                  child: Center(
                                    child: Text('Aktuell',
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: skin.textPrimary)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(children: [
                                        const SizedBox(width: 2, height: 2),
                                        SizedBox(
                                          width: 16, height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text('PDF wird erstellt…'),
                                      ]),
                                      backgroundColor: skin.textMuted,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                      duration: const Duration(seconds: 10),
                                    ),
                                  );
                                  await PdfService.exportMonth(context, selectedMonth);
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: skin.isLight
                                        ? skin.primary.withValues(alpha: 0.13)
                                        : skin.primary.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: skin.isLight
                                          ? skin.primary.withValues(alpha: 0.28)
                                          : skin.primary.withValues(alpha: 0.45),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                          color: skin.glassShadow,
                                          blurRadius: 16,
                                          offset: const Offset(0, 4)),
                                      BoxShadow(
                                          color: skin.glassHighlight,
                                          blurRadius: 0,
                                          spreadRadius: -1,
                                          offset: const Offset(0, 1)),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text('PDF erstellen',
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: skin.isLight
                                                ? skin.primary
                                                    .withValues(alpha: 0.90)
                                                : skin.primary
                                                    .withValues(alpha: 0.85))),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}