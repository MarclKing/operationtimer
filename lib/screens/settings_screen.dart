import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';
import '../services/pdf_service.dart';  // 🔥 WICHTIG: PdfService importieren

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  int _deleteAfterMonths = 3;
  String _activeSkin = 'chrome';
  bool _nachtschichtModus = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _nameController.text = box.get('name', defaultValue: '');
    _deleteAfterMonths = box.get('deleteAfterMonths', defaultValue: 3);
    _activeSkin = box.get(AppTheme.hiveKey, defaultValue: 'chrome') as String;
    _nachtschichtModus = box.get('nachtschicht_modus', defaultValue: false) as bool;
    _autoDeleteOldEntries();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _setSkin(String key) {
    setState(() => _activeSkin = key);
    Hive.box('einstellungen').put(AppTheme.hiveKey, key);
  }

  void _setNachtschichtModus(bool value) {
    setState(() => _nachtschichtModus = value);
    Hive.box('einstellungen').put('nachtschicht_modus', value);
  }

  String _capitalizeEachWord(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  void _onNameChanged(String value) {
    final cursor = _nameController.selection.baseOffset;
    final formatted = _capitalizeEachWord(value);
    if (formatted != value) {
      _nameController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: cursor > formatted.length ? formatted.length : cursor,
        ),
      );
    }
  }

  void _saveSettings() {
    final box = Hive.box('einstellungen');
    final formatted = _capitalizeEachWord(_nameController.text);
    _nameController.text = formatted;
    box.put('name', formatted);
    box.put('deleteAfterMonths', _deleteAfterMonths);
    _autoDeleteOldEntries();
    final skin = AppTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Einstellungen gespeichert ✓'),
      backgroundColor: skin.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _autoDeleteOldEntries() {
    final box = Hive.box('arbeitszeiten');
    final cutoff = DateTime.now().subtract(Duration(days: _deleteAfterMonths * 30));
    final keysToDelete = box.keys.where((key) {
      try {
        return DateTime.parse(key.toString()).isBefore(cutoff);
      } catch (_) {
        return false;
      }
    }).toList();
    for (final key in keysToDelete) {
      box.delete(key);
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
    String fullName = settingsBox.get('name', defaultValue: 'Unbekannt') as String;
    fullName = _capitalizeEachWord(fullName);
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

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(pw.MultiPage(
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
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('OpTimes', style: pw.TextStyle(font: fontBold, fontSize: 20, color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text('Arbeitszeiterfassung', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey400)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(fullName, style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text(monthName, style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey400)),
              ]),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Row(children: [
          _pdfStatBox('Einträge', '${entries.length}', font, fontBold),
          pw.SizedBox(width: 10),
          _pdfStatBox('Vollständig', '${entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length}', font, fontBold),
          pw.SizedBox(width: 10),
          _pdfStatBox('Offen', '${entries.where((e) => (e['gehen'] ?? '').isEmpty).length}', font, fontBold),
        ]),
        pw.SizedBox(height: 20),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A1A1A)),
          child: pw.Row(children: [
            pw.Expanded(flex: 2, child: pw.Text('Datum', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
            pw.Expanded(child: pw.Text('Kommen', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
            pw.Expanded(child: pw.Text('Gehen', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
            pw.Expanded(child: pw.Text('Dauer', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
            pw.Expanded(child: pw.Text('TKF', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
            pw.Expanded(flex: 2, child: pw.Text('Notiz', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
          ]),
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
            child: pw.Row(children: [
              pw.Expanded(flex: 2, child: pw.Text(datumStr, style: pw.TextStyle(font: font, fontSize: 10))),
              pw.Expanded(child: pw.Text(kommen.isEmpty ? '--:--' : kommen, style: pw.TextStyle(font: font, fontSize: 10))),
              pw.Expanded(child: pw.Text(gehen.isEmpty ? '--:--' : gehen, style: pw.TextStyle(font: font, fontSize: 10))),
              pw.Expanded(child: pw.Text(duration, style: pw.TextStyle(font: fontBold, fontSize: 10))),
              pw.Expanded(child: pw.Text(tkf, style: pw.TextStyle(font: font, fontSize: 10))),
              pw.Expanded(flex: 2, child: pw.Text(notiz, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600))),
            ]),
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
    ));

    final safeName = fullName.replaceAll(' ', '_');
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'OpTimes_${safeName}_$monthKey.pdf',
    );
  }

  pw.Widget _pdfStatBox(String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF0F0F0),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(children: [
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 20, color: const PdfColor.fromInt(0xFF1A1A1A))),
          pw.SizedBox(height: 2),
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
        ]),
      ),
    );
  }

  // 🔥 GEÄNDERT: Jetzt ruft die zentrale Methode aus PdfService auf
  Future<void> _selectMonthForExport() async {
    await PdfService.showMonthPickerAndExport(context);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
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
                        color: skin.surface(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: skin.borderSubtle),
                      ),
                      child: Icon(Icons.arrow_back_ios_new, color: skin.textPrimary, size: 16),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Einstellungen',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: skin.textPrimary),
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

                    _SettingsCard(
                      emoji: '👤',
                      title: 'Benutzername',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vor- und Nachname. Der Vorname erscheint in der Begrüßung, der vollständige Name im PDF.',
                            style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: skin.surface(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: skin.borderSubtle),
                            ),
                            child: TextField(
                              controller: _nameController,
                              style: TextStyle(color: skin.textPrimary, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'z.B. Max Mustermann',
                                hintStyle: TextStyle(color: skin.textHint),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: _onNameChanged,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _GradientButton(label: 'Speichern', onTap: _saveSettings),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    _SettingsCard(
                      emoji: '🌙',
                      title: 'Nachtschicht-Modus',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wenn aktiviert, erkennt die App automatisch Nachtschichten (z.B. Kommen 22:00 → Gehen 02:00) und legt zwei Einträge an:\n\n'
                            '• Eintrag 1: Kommen bis 23:59 (selber Tag)\n'
                            '• Eintrag 2: 00:00 bis Gehen (nächster Tag)',
                            style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _nachtschichtModus ? '✅ Aktiviert' : '⬜ Deaktiviert',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _nachtschichtModus ? skin.statComplete : skin.textMuted,
                                ),
                              ),
                              Switch(
                                value: _nachtschichtModus,
                                onChanged: _setNachtschichtModus,
                                activeThumbColor: skin.statComplete,
                                activeTrackColor: skin.statComplete.withValues(alpha: 0.3),
                                inactiveThumbColor: skin.textMuted,
                                inactiveTrackColor: skin.surface(0.1),
                              ),
                            ],
                          ),
                          if (_nachtschichtModus) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: skin.statComplete.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: skin.statComplete.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Text('🌙', style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Beim Speichern wird ein Bestätigungs-Dialog angezeigt, bevor die zwei Einträge angelegt werden.',
                                      style: TextStyle(fontSize: 11, color: skin.statComplete.withValues(alpha: 0.8)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    _SettingsCard(
                      emoji: '📄',
                      title: 'PDF Export',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Exportiere deine Arbeitszeiten als PDF inkl. Notizen und teile sie per Mail, WhatsApp oder AirDrop.',
                            style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
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

                    _SettingsCard(
                      emoji: '🗑',
                      title: 'Datenverwaltung',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alte Einträge werden automatisch gelöscht nach:',
                            style: TextStyle(fontSize: 13, color: skin.textMuted),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [1, 3, 6, 12].map((months) {
                              final isSelected = _deleteAfterMonths == months;
                              return GestureDetector(
                                onTap: () => setState(() => _deleteAfterMonths = months),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: isSelected ? skin.gradient : null,
                                    color: isSelected ? null : skin.surface(0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? Colors.transparent : skin.borderSubtle,
                                    ),
                                  ),
                                  child: Text(
                                    '$months Monat${months > 1 ? 'e' : ''}',
                                    style: TextStyle(
                                      color: isSelected ? skin.onGradient : skin.textMuted,
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
                              color: skin.surface(0.03),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: skin.textMuted, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Einträge werden automatisch gelöscht, sobald sie älter als die ausgewählte Zeit sind.',
                                    style: TextStyle(fontSize: 11, color: skin.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    _SettingsCard(
                      emoji: '🎨',
                      title: 'Design',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wähle das Aussehen der App. Die Änderung wird sofort übernommen.',
                            style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _SimpleSkinOption(
                                  label: 'Chrome',
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
                        'OpTimes v1.0',
                        style: TextStyle(fontSize: 12, color: skin.textHint),
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
    final skin = AppTheme.of(context);
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? skin.gradient : null,
          color: isSelected ? null : skin.surface(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.transparent : skin.borderSubtle),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? skin.onGradient : skin.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String emoji;
  final String title;
  final Widget child;

  const _SettingsCard({required this.emoji, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: skin.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary),
              ),
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
    final skin = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: skin.gradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: skin.onGradient, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }
}