import 'package:flutter/material.dart';
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

  static pw.Widget _pdfStatBox(String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF0F0F0),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 20, color: const PdfColor.fromInt(0xFF1A1A1A))),
            pw.SizedBox(height: 2),
            pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ),
    );
  }

  static Future<void> exportMonth(BuildContext context, DateTime month) async {
    final box = Hive.box('arbeitszeiten');
    final settingsBox = Hive.box('einstellungen');
    final fullName = settingsBox.get('name', defaultValue: 'Unbekannt') as String;
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
    final fullName = settingsBox.get('name', defaultValue: 'Unbekannt') as String;
    final datum = DateTime.parse(entry['datum']);
    final dateStr = DateFormat('dd.MM.yyyy').format(datum);
    final fileKey = DateFormat('yyyy-MM-dd').format(datum);

    await _buildAndShare([entry], fullName, dateStr, fileKey);
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
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
                    pw.Text('OpTimes', style: pw.TextStyle(font: fontBold, fontSize: 20, color: PdfColors.white)),
                    pw.SizedBox(height: 4),
                    pw.Text('Arbeitszeiterfassung', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey400)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(fullName, style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.white)),
                    pw.SizedBox(height: 4),
                    pw.Text(title, style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey400)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            children: [
              _pdfStatBox('Einträge', '${entries.length}', font, fontBold),
              pw.SizedBox(width: 10),
              _pdfStatBox('Vollständig', '${entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length}', font, fontBold),
              pw.SizedBox(width: 10),
              _pdfStatBox('Offen', '${entries.where((e) => (e['gehen'] ?? '').isEmpty).length}', font, fontBold),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A1A1A)),
            child: pw.Row(
              children: [
                pw.Expanded(flex: 2, child: pw.Text('Datum', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
                pw.Expanded(child: pw.Text('Kommen', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
                pw.Expanded(child: pw.Text('Gehen', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
                pw.Expanded(child: pw.Text('Dauer', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
                pw.Expanded(child: pw.Text('TKF', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
                pw.Expanded(flex: 2, child: pw.Text('Notiz', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
              ],
            ),
          ),
          ...entries.asMap().entries.map((e) {
            final i = e.key;
            final entry = e.value;
            final datum = DateTime.parse(entry['datum']);
            final datumStr = DateFormat('EEE dd.MM.yy', 'de').format(datum);
            final kommen = entry['kommen'] ?? '';
            final gehen = entry['gehen'] ?? '';
            final tkf = entry['TKF'] ?? '';
            final notiz = entry['notiz'] ?? '';
            final duration = _calcDuration(kommen, gehen);
            final bgColor = i.isEven ? const PdfColor.fromInt(0xFFF8F8F8) : PdfColors.white;
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(color: bgColor),
              child: pw.Row(
                children: [
                  pw.Expanded(flex: 2, child: pw.Text(datumStr, style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(child: pw.Text(kommen.isEmpty ? '--:--' : kommen, style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(child: pw.Text(gehen.isEmpty ? '--:--' : gehen, style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(child: pw.Text(duration, style: pw.TextStyle(font: fontBold, fontSize: 10))),
                  pw.Expanded(child: pw.Text(tkf, style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(flex: 2, child: pw.Text(notiz, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600))),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Text(
            'Erstellt am ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey500),
          ),
        ],
      ),
    );

    final safeName = fullName.replaceAll(' ', '_');
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'OpTimes_${safeName}_$fileKey.pdf',
    );
  }

  static Future<void> showMonthPickerAndExport(BuildContext context) async {
    final skin = AppTheme.of(context);
    DateTime selectedMonth = DateTime.now();
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: skin.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Monat auswählen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: skin.textPrimary),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: skin.bgBase,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: skin.borderMedium),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => setDialogState(() =>
                            selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1)),
                        icon: Icon(Icons.chevron_left, color: skin.primary),
                      ),
                      Text(
                        DateFormat('MMMM yyyy', 'de').format(selectedMonth),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary),
                      ),
                      IconButton(
                        onPressed: () => setDialogState(() =>
                            selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1)),
                        icon: Icon(Icons.chevron_right, color: skin.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
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
                              style: TextStyle(color: skin.textPrimary, fontWeight: FontWeight.w600),
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
                          PdfService.exportMonth(context, selectedMonth);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: skin.gradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'PDF erstellen',
                              style: TextStyle(color: skin.onGradient, fontWeight: FontWeight.w700),
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
      ),
    );
  }
}