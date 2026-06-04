import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  int _deleteAfterMonths = 3;
  String _activeSkin = 'chrome';

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _nameController.text = box.get('name', defaultValue: '');
    _deleteAfterMonths = box.get('deleteAfterMonths', defaultValue: 3);
    _activeSkin = box.get('skin', defaultValue: 'chrome') as String;
    
    // Führe automatische Löschung beim Start aus
    _autoDeleteOldEntries();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _setSkin(String key) {
    setState(() => _activeSkin = key);
    Hive.box('einstellungen').put('skin', key);
  }

  String _capitalizeEachWord(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  void _onNameChanged(String value) {
    final cursorPosition = _nameController.selection.baseOffset;
    final formatted = _capitalizeEachWord(value);
    if (formatted != value) {
      _nameController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: cursorPosition > formatted.length
              ? formatted.length
              : cursorPosition,
        ),
      );
    }
  }

  void _saveSettings() {
    final box = Hive.box('einstellungen');
    final formattedName = _capitalizeEachWord(_nameController.text);
    _nameController.text = formattedName;
    box.put('name', formattedName);
    box.put('deleteAfterMonths', _deleteAfterMonths);
    
    // Nach Änderung der Löschdauer sofort alte Einträge löschen
    _autoDeleteOldEntries();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Einstellungen gespeichert ✓'),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _autoDeleteOldEntries() {
    final box = Hive.box('arbeitszeiten');
    final cutoffDays = _deleteAfterMonths * 30;
    final cutoff = DateTime.now().subtract(Duration(days: cutoffDays));
    
    final keysToDelete = box.keys.where((key) {
      try {
        final date = DateTime.parse(key.toString());
        return date.isBefore(cutoff);
      } catch (_) {
        return false;
      }
    }).toList();
    
    if (keysToDelete.isNotEmpty) {
      for (final key in keysToDelete) {
        box.delete(key);
      }
      debugPrint('${keysToDelete.length} alte Einträge automatisch gelöscht (älter als $_deleteAfterMonths Monate)');
    }
  }

  String _calcDuration(String kommen, String gehen) {
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

  Future<void> _exportPdf(DateTime month) async {
    final box = Hive.box('arbeitszeiten');
    final settingsBox = Hive.box('einstellungen');
    String fullName =
        settingsBox.get('name', defaultValue: 'Unbekannt') as String;
    fullName = _capitalizeEachWord(fullName);
    final monthKey = DateFormat('yyyy-MM').format(month);
    final monthName = DateFormat('MMMM yyyy', 'de').format(month);

    final List<Map<String, dynamic>> entries = [];
    for (final key in box.keys) {
      if (key.toString().startsWith(monthKey)) {
        final entry = box.get(key);
        if (entry != null) entries.add(Map<String, dynamic>.from(entry));
      }
    }
    entries.sort((a, b) => a['datum'].compareTo(b['datum']));

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
                    pw.Text('OperationTimer',
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
                    pw.Text(monthName,
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
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6C63FF)),
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
          ...entries.asMap().entries.map((e) {
            final i = e.key;
            final entry = e.value;
            final datum = DateTime.parse(entry['datum']);
            final datumStr = DateFormat('EEE dd.MM.yy', 'de').format(datum);
            final kommen = entry['kommen'] ?? '';
            final gehen = entry['gehen'] ?? '';
            final TKF = entry['TKF'] ?? '';
            final notiz = entry['notiz'] ?? '';
            final duration = _calcDuration(kommen, gehen);
            final bgColor = i.isEven
                ? const PdfColor.fromInt(0xFFF8F8FF)
                : PdfColors.white;

            return pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(color: bgColor),
              child: pw.Row(
                children: [
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text(datumStr,
                          style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(
                      child: pw.Text(kommen.isEmpty ? '--:--' : kommen,
                          style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(
                      child: pw.Text(gehen.isEmpty ? '--:--' : gehen,
                          style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(
                      child: pw.Text(duration,
                          style:
                              pw.TextStyle(font: fontBold, fontSize: 10))),
                  pw.Expanded(
                      child: pw.Text(TKF,
                          style: pw.TextStyle(font: font, fontSize: 10))),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text(notiz,
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 10,
                              color: PdfColors.grey600))),
                ],
              ),
            );
          }),
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
      filename: 'OperationTimer_${safeName}_$monthKey.pdf',
    );
  }

  pw.Widget _pdfStatBox(
      String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF0EFFF),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 20,
                    color: const PdfColor.fromInt(0xFF6C63FF))),
            pw.SizedBox(height: 2),
            pw.Text(label,
                style: pw.TextStyle(
                    font: font, fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ),
    );
  }

  Future<void> _selectMonthForExport() async {
    DateTime selectedMonth = DateTime.now();
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF141420),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Monat auswählen',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0F),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => setDialogState(() => selectedMonth =
                            DateTime(selectedMonth.year,
                                selectedMonth.month - 1)),
                        icon: const Icon(Icons.chevron_left,
                            color: Color(0xFF6C63FF)),
                      ),
                      Text(
                        DateFormat('MMMM yyyy', 'de').format(selectedMonth),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () => setDialogState(() => selectedMonth =
                            DateTime(selectedMonth.year,
                                selectedMonth.month + 1)),
                        icon: const Icon(Icons.chevron_right,
                            color: Color(0xFF6C63FF)),
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
                            color: const Color(0xFF1E1E35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text('Abbrechen',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _exportPdf(selectedMonth);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFF6C63FF),
                              Color(0xFF4ECDC4)
                            ]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text('PDF erstellen',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Einstellungen',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // ── BENUTZERNAME ──────────────────────────────────────────
                    _SettingsCard(
                      emoji: '👤',
                      title: 'Benutzername',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vor- und Nachname. Der Vorname erscheint in der Begrüßung, der vollständige Name im PDF.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4),
                                height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'z.B. Max Mustermann',
                                hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.25)),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: _onNameChanged,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '✓ Trage hier deinen Namen ein',
                            style: TextStyle(
                                fontSize: 11,
                                color: const Color(0xFF4ECDC4).withValues(alpha: 0.6)),
                          ),
                          const SizedBox(height: 12),
                          _GradientButton(
                              label: 'Speichern', onTap: _saveSettings),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── PDF EXPORT ────────────────────────────────────────────
                    _SettingsCard(
                      emoji: '📄',
                      title: 'PDF Export',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Exportiere deine Arbeitszeiten als PDF inkl. Notizen und teile sie per Mail, WhatsApp oder AirDrop.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4),
                                height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          _GradientButton(
                            label: '📤  Zeiten exportieren & teilen',
                            onTap: _selectMonthForExport,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── DATENVERWALTUNG ───────────────────────────────────────
                    _SettingsCard(
                      emoji: '🗑',
                      title: 'Datenverwaltung',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alte Einträge werden automatisch gelöscht nach:',
                            style: TextStyle(
                                fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [1, 3, 6, 12].map((months) {
                              final isSelected = _deleteAfterMonths == months;
                              return GestureDetector(
                                onTap: () => setState(
                                    () => _deleteAfterMonths = months),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: isSelected
                                        ? const LinearGradient(colors: [
                                            Color(0xFF6C63FF),
                                            Color(0xFF4ECDC4)
                                          ])
                                        : null,
                                    color: isSelected
                                        ? null
                                        : Colors.white
                                            .withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.transparent
                                          : Colors.white
                                              .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Text(
                                    '${months} Monat${months > 1 ? 'e' : ''}',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white
                                              .withValues(alpha: 0.4),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.white.withValues(alpha: 0.4),
                                    size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Einträge werden automatisch gelöscht, sobald sie älter als die ausgewählte Zeit sind.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── DESIGN / SKIN (4. Einstellung - GANZ UNTEN) ───────────
                    _SettingsCard(
                      emoji: '🎨',
                      title: 'Design',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wähle das Aussehen der App. Die Änderung wird sofort übernommen.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4),
                                height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _SimpleSkinOption(
                                  label: 'Chrome (Standard)',
                                  isSelected: _activeSkin == 'chrome',
                                  onTap: () => _setSkin('chrome'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _SimpleSkinOption(
                                  label: 'Space',
                                  isSelected: _activeSkin == 'space',
                                  onTap: () => _setSkin('space'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    Center(
                      child: Text(
                        'OperationTimer v1.0',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white.withValues(alpha: 0.15)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EINFACHE SKIN-AUSWAHL-KACHEL (OHNE VORSCHAU) - GEFIXT
// ─────────────────────────────────────────────────────────────────────────────

class _SimpleSkinOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SimpleSkinOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                )
              : null,
          color: isSelected
              ? null
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 16,
                ),
              if (isSelected) const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIEDERVERWENDBARE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final String emoji;
  final String title;
  final Widget child;

  const _SettingsCard(
      {required this.emoji, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GradientButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
        ),
      ),
    );
  }
}
