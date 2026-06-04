import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';
import '../services/night_shift_helper.dart';

class MonthScreen extends StatefulWidget {
  final VoidCallback onNavigateToHome;
  const MonthScreen({super.key, required this.onNavigateToHome});

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  DateTime _selectedMonth = DateTime.now();
  final Map<String, GlobalKey<_SlidableRowState>> _rowKeys = {};
  bool _dragOnInteractive = false;

  List<Map<String, dynamic>> _getEntriesForMonth() {
    final box = Hive.box('arbeitszeiten');
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
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
    
    entries.sort((a, b) {
      final aDatum = a['datum'] as String?;
      final bDatum = b['datum'] as String?;
      if (aDatum == null && bDatum == null) return 0;
      if (aDatum == null) return 1;
      if (bDatum == null) return -1;
      return aDatum.compareTo(bDatum);
    });
    
    return entries;
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

  void _closeAllRows() {
    for (final key in _rowKeys.values) {
      key.currentState?.close();
    }
  }

  void _changeMonth(int delta) {
    _closeAllRows();
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  void _deleteEntry(String datum, String entryId) {
    final date = DateTime.parse(datum);
    NightShiftHelper.deleteEntry(date, entryId);
    setState(() {});
    final skin = AppTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Eintrag gelöscht'),
      backgroundColor: skin.deleteColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    ));
  }

  void _editEntry(Map<String, dynamic> entry) {
    final datum = DateTime.parse(entry['datum']);
    final kommenCtrl = TextEditingController(text: entry['kommen'] ?? '');
    final gehenCtrl = TextEditingController(text: entry['gehen'] ?? '');
    final tkfCtrl = TextEditingController(text: entry['TKF'] ?? '');
    final notizCtrl = TextEditingController(text: entry['notiz'] ?? '');
    final entryId = entry['id'] as String;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditSheet(
        datum: datum,
        entryId: entryId,
        kommenCtrl: kommenCtrl,
        gehenCtrl: gehenCtrl,
        tkfCtrl: tkfCtrl,
        notizCtrl: notizCtrl,
        onSave: () async {
          await NightShiftHelper.save(
            context: context,
            datum: datum,
            kommen: kommenCtrl.text,
            gehen: gehenCtrl.text,
            tkf: tkfCtrl.text,
            notiz: notizCtrl.text,
            existingId: entryId,
          );
          setState(() {});
          Navigator.pop(context);
          final skin = AppTheme.of(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Aktualisiert ✓'),
            backgroundColor: skin.primary == Colors.white
                ? const Color(0xFF3DD6C8)
                : skin.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          ));
        },
      ),
    );
  }

  Future<void> _shareEntry(Map<String, dynamic> entry) async {
    final settingsBox = Hive.box('einstellungen');
    final fullName = settingsBox.get('name', defaultValue: 'Unbekannt') as String;
    final datum = DateTime.parse(entry['datum']);
    final datumStr = DateFormat('EEEE, dd.MM.yyyy', 'de').format(datum);
    final dateKey = DateFormat('yyyy-MM-dd').format(datum);
    final kommen = (entry['kommen'] ?? '').isEmpty ? '--:--' : entry['kommen'];
    final gehen = (entry['gehen'] ?? '').isEmpty ? '--:--' : entry['gehen'];
    final tkf = entry['TKF'] ?? '';
    final notiz = entry['notiz'] ?? '';

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFF1A1A2E),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('OperationTimer',
                    style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.white)),
                pw.Text(fullName,
                    style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.grey400)),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(datumStr, style: pw.TextStyle(font: fontBold, fontSize: 16)),
          pw.SizedBox(height: 16),
          pw.Row(children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFE8FDF9),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('KOMMEN',
                        style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.teal)),
                    pw.SizedBox(height: 4),
                    pw.Text(kommen, style: pw.TextStyle(font: fontBold, fontSize: 26)),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFEEEEFF),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GEHEN',
                        style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.red)),
                    pw.SizedBox(height: 4),
                    pw.Text(gehen, style: pw.TextStyle(font: fontBold, fontSize: 26)),
                  ],
                ),
              ),
            ),
          ]),
          if (tkf.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('TKF: $tkf', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700)),
          ],
          if (notiz.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Notiz: $notiz', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700)),
          ],
          pw.Spacer(),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 6),
          pw.Text(
            'Erstellt am ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey400),
          ),
        ],
      ),
    ));

    final safeName = fullName.replaceAll(' ', '_');
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'OperationTimer_${safeName}_$dateKey.pdf',
    );
  }

  // 🔥 KORRIGIERT: _showMonthPicker mit Skin-Design
  void _showMonthPicker() {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';
    int pickedYear = _selectedMonth.year;
    int pickedMonth = _selectedMonth.month - 1;
    final yearCount = DateTime.now().year - 2020 + 2;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: skin.bgSheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Monat & Jahr',
                style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(initialItem: pickedMonth + 1000),
                        itemExtent: 44,
                        looping: true,
                        backgroundColor: Colors.transparent,
                        onSelectedItemChanged: (i) => setSheet(() => pickedMonth = i % 12),
                        children: List.generate(
                          12,
                          (i) => Center(
                            child: Text(
                              DateFormat('MMMM', 'de').format(DateTime(2024, i + 1)),
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: skin.textPrimary),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(initialItem: pickedYear - 2020),
                        itemExtent: 44,
                        looping: false,
                        backgroundColor: Colors.transparent,
                        onSelectedItemChanged: (i) => setSheet(() => pickedYear = 2020 + i.clamp(0, yearCount - 1)),
                        children: List.generate(
                          yearCount,
                          (i) => Center(
                            child: Text(
                              '${2020 + i}',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: skin.textPrimary),
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
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Abbrechen',
                            style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedMonth = DateTime(pickedYear, pickedMonth + 1));
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: isChromeSkin
                              ? const LinearGradient(
                                  colors: [Color(0xFF333333), Color(0xFF555555)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                )
                              : skin.gradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Auswählen',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    final entries = _getEntriesForMonth();
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    
    final uniqueDays = <String>{};
    for (final entry in entries) {
      uniqueDays.add(entry['datum'] as String);
    }
    final complete = entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length;
    final open = entries.length - complete;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: GestureDetector(
        onTap: _closeAllRows,
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dragOnInteractive = false,
        onHorizontalDragEnd: (d) {
          if (_dragOnInteractive) return;
          final v = d.primaryVelocity ?? 0;
          if (v > 400) widget.onNavigateToHome();
        },
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 50),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monatsübersicht',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: skin.textPrimary),
                    ),
                    const SizedBox(height: 16),

                    Listener(
                      onPointerDown: (_) => _dragOnInteractive = true,
                      child: Row(
                        children: [
                          _MonthNavBtn(icon: Icons.chevron_left, onTap: () => _changeMonth(-1)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _showMonthPicker,
                              onHorizontalDragEnd: (d) {
                                final v = d.primaryVelocity ?? 0;
                                if (v < -300) _changeMonth(1);
                                if (v > 300) _changeMonth(-1);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                decoration: BoxDecoration(
                                  color: skin.bgCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: skin.primaryWithAlpha(0.35)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(monthName,
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                                    const SizedBox(width: 6),
                                    Icon(Icons.expand_more, color: skin.primary, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _MonthNavBtn(icon: Icons.chevron_right, onTap: () => _changeMonth(1)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard(label: 'Tage', value: '${uniqueDays.length}', color: skin.statEntries),
                        const SizedBox(width: 10),
                        _StatCard(label: 'Einträge', value: '${entries.length}', color: skin.statComplete),
                        const SizedBox(width: 10),
                        _StatCard(label: 'Offen', value: '$open', color: skin.statOpen),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '← Löschen  ·  → Bearbeiten / Teilen',
                      style: TextStyle(fontSize: 11, color: skin.white(0.3)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('📭', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('Keine Einträge für diesen Monat',
                                style: TextStyle(color: skin.white(0.3), fontSize: 15)),
                          ],
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (_) {
                          _closeAllRows();
                          return false;
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 100),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final datum = entry['datum'] as String;
                            final entryId = entry['id'] as String;
                            _rowKeys[entryId] ??= GlobalKey<_SlidableRowState>();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SlidableRow(
                                key: _rowKeys[entryId],
                                entry: entry,
                                entryId: entryId,
                                duration: _calcDuration(entry['kommen'] ?? '', entry['gehen'] ?? ''),
                                onEdit: () => _editEntry(entry),
                                onDelete: () => _deleteEntry(datum, entryId),
                                onShare: () => _shareEntry(entry),
                                onCloseOthers: () {
                                  for (final k in _rowKeys.entries) {
                                    if (k.key != entryId) {
                                      k.value.currentState?.close();
                                    }
                                  }
                                },
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDABLE ROW
// ─────────────────────────────────────────────────────────────────────────────

class _SlidableRow extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String entryId;
  final String duration;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onCloseOthers;

  const _SlidableRow({
    super.key,
    required this.entry,
    required this.entryId,
    required this.duration,
    required this.onEdit,
    required this.onDelete,
    required this.onShare,
    required this.onCloseOthers,
  });

  @override
  State<_SlidableRow> createState() => _SlidableRowState();
}

class _SlidableRowState extends State<_SlidableRow> {
  double _offset = 0;
  static const double _deleteReveal = 80.0;
  static const double _editReveal = 160.0;
  static const double _snap = 40.0;

  bool get _isOpen => _offset != 0;

  void close() => _animateTo(0);

  void _animateTo(double target) {
    if (!mounted) return;
    final start = _offset;
    final dist = target - start;
    int step = 0;
    const steps = 12;
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 12));
      if (!mounted) return false;
      step++;
      final t = step / steps;
      final eased = 1 - (1 - t) * (1 - t);
      setState(() => _offset = start + dist * eased);
      if (step >= steps) {
        if (mounted) setState(() => _offset = target);
        return false;
      }
      return true;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_deleteReveal, _editReveal);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_offset < -_snap || v < -500) {
      _animateTo(-_deleteReveal);
    } else if (_offset > _snap || v > 500) {
      _animateTo(_editReveal);
    } else {
      _animateTo(0);
    }
  }

  int _getEntryNumber() {
    try {
      final datum = DateTime.parse(widget.entry['datum']);
      final entries = NightShiftHelper.getEntriesForDay(datum);
      final index = entries.indexWhere((e) => e['id'] == widget.entryId);
      return index + 1;
    } catch (e) {
      return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final entry = widget.entry;
    final datum = DateTime.parse(entry['datum']);
    final dayName = DateFormat('EEE', 'de').format(datum);
    final dayNum = DateFormat('dd').format(datum);
    final kommen = entry['kommen'] ?? '';
    final gehen = entry['gehen'] ?? '';
    final tkf = entry['TKF'] ?? '';
    final notiz = entry['notiz'] ?? '';
    final isComplete = gehen.isNotEmpty;
    final borderColor = isComplete
        ? skin.statComplete.withValues(alpha: 0.3)
        : skin.statOpen.withValues(alpha: 0.3);
    
    final entryNumber = _getEntryNumber();
    final entriesForDay = NightShiftHelper.getEntriesForDay(datum);
    final showNumber = entriesForDay.length > 1;
    
    double rowHeight = 86.0;
    if (tkf.isNotEmpty) rowHeight += 14.0;

    return GestureDetector(
      onHorizontalDragStart: (_) => widget.onCloseOthers(),
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onTap: () {
        if (_isOpen) _animateTo(0);
      },
      child: SizedBox(
        height: rowHeight,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _editReveal,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _animateTo(0);
                        Future.delayed(const Duration(milliseconds: 200), widget.onEdit);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: skin.editColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_outlined,
                                color: skin.primary == Colors.white ? Colors.black : Colors.white,
                                size: 20),
                            const SizedBox(height: 2),
                            Text(
                              'Bearbeiten',
                              style: TextStyle(
                                color: skin.primary == Colors.white ? Colors.black : Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _animateTo(0);
                        Future.delayed(const Duration(milliseconds: 200), widget.onShare);
                      },
                      child: Container(
                        color: skin.statComplete,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.ios_share_outlined, color: Colors.white, size: 20),
                            SizedBox(height: 2),
                            Text('Teilen',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _deleteReveal,
              child: GestureDetector(
                onTap: () {
                  _animateTo(0);
                  Future.delayed(const Duration(milliseconds: 150), widget.onDelete);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: skin.deleteColor,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, color: Colors.white, size: 20),
                      SizedBox(height: 2),
                      Text('Löschen',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

            Positioned.fill(
              child: Transform.translate(
                offset: Offset(_offset, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: skin.bgCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: skin.primaryWithAlpha(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(dayName.toUpperCase(),
                                    style: TextStyle(fontSize: 9, color: skin.primary, fontWeight: FontWeight.w700)),
                                Text(dayNum,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                                if (showNumber)
                                  Container(
                                    margin: const EdgeInsets.only(top: 1),
                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: skin.primary.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${entryNumber}.',
                                      style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: skin.primary),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: skin.kommenColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        kommen.isEmpty ? '--:--' : kommen,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: skin.kommenColor),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_forward, size: 10, color: skin.white(0.3)),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: skin.gehenColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        gehen.isEmpty ? '--:--' : gehen,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: skin.gehenColor),
                                      ),
                                    ),
                                  ],
                                ),
                                
                                if (tkf.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '👤 $tkf',
                                    style: TextStyle(fontSize: 9, color: skin.white(0.4)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                
                                if (notiz.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.note_outlined, size: 10, color: skin.white(0.3)),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          notiz,
                                          style: TextStyle(fontSize: 9, color: skin.white(0.4)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.duration,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isComplete
                                      ? skin.statComplete.withValues(alpha: 0.12)
                                      : skin.statOpen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isComplete ? '✓ Ok' : '⏳ Offen',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: isComplete ? skin.statComplete : skin.statOpen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
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
// EDIT SHEET mit korrigiertem Speichern-Button
// ─────────────────────────────────────────────────────────────────────────────

class _EditSheet extends StatefulWidget {
  final DateTime datum;
  final String entryId;
  final TextEditingController kommenCtrl;
  final TextEditingController gehenCtrl;
  final TextEditingController tkfCtrl;
  final TextEditingController notizCtrl;
  final VoidCallback onSave;

  const _EditSheet({
    required this.datum,
    required this.entryId,
    required this.kommenCtrl,
    required this.gehenCtrl,
    required this.tkfCtrl,
    required this.notizCtrl,
    required this.onSave,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  TimeOfDay? _parse(String t) {
    if (t.isEmpty || t == '--:--') return null;
    try {
      final p = t.split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    } catch (_) {
      return null;
    }
  }

  TimeOfDay _addMinutes(TimeOfDay time, int minutes) {
    final totalMinutes = time.hour * 60 + time.minute + minutes;
    final newHour = (totalMinutes ~/ 60) % 24;
    final newMinute = totalMinutes % 60;
    return TimeOfDay(hour: newHour, minute: newMinute);
  }

  TimeOfDay _getDefaultGehenTime(TimeOfDay kommenTime) {
    return _addMinutes(kommenTime, 8 * 60 + 12);
  }

  void _adjustTime(TextEditingController controller, int minutesDelta, bool isGehenField) {
    TimeOfDay current;
    
    if (isGehenField && widget.gehenCtrl.text.isEmpty) {
      final kommenTime = _parse(widget.kommenCtrl.text);
      if (kommenTime != null) {
        current = _getDefaultGehenTime(kommenTime);
        setState(() {
          widget.gehenCtrl.text = 
              '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}';
        });
      } else {
        current = TimeOfDay.now();
      }
    } else {
      current = _parse(controller.text) ?? TimeOfDay.now();
    }
    
    final total = (current.hour * 60 + current.minute + minutesDelta).clamp(0, 23 * 60 + 59);
    setState(() {
      controller.text =
          '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pickTime(TextEditingController ctrl, bool isGehenField) async {
    final skin = AppTheme.of(context);
    TimeOfDay initialTime;
    
    if (isGehenField && widget.gehenCtrl.text.isEmpty) {
      final kommenTime = _parse(widget.kommenCtrl.text);
      if (kommenTime != null) {
        initialTime = _getDefaultGehenTime(kommenTime);
      } else {
        initialTime = TimeOfDay.now();
      }
    } else {
      initialTime = _parse(ctrl.text) ?? TimeOfDay.now();
    }
    
    int selH = initialTime.hour;
    int selM = initialTime.minute;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: skin.bgSheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Uhrzeit',
                style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: selH + 1000),
                      itemExtent: 40,
                      looping: true,
                      backgroundColor: Colors.transparent,
                      onSelectedItemChanged: (i) => selH = i % 24,
                      children: List.generate(
                        24,
                        (h) => Center(
                          child: Text(h.toString().padLeft(2, '0'),
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                        ),
                      ),
                    ),
                  ),
                  Text(':',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: skin.primary)),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: selM + 1000),
                      itemExtent: 40,
                      looping: true,
                      backgroundColor: Colors.transparent,
                      onSelectedItemChanged: (i) => selM = i % 60,
                      children: List.generate(
                        60,
                        (m) => Center(
                          child: Text(m.toString().padLeft(2, '0'),
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: skin.textPrimary)),
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
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: skin.surface(0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text('Abbrechen',
                            style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        ctrl.text =
                            '${selH.toString().padLeft(2, '0')}:${selM.toString().padLeft(2, '0')}';
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        gradient: skin.gradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'Übernehmen',
                          style: TextStyle(
                            color: skin.onGradient,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        decoration: BoxDecoration(
          color: skin.bgSheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: skin.borderMedium),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: skin.surface(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Bearbeiten – ${DateFormat('EEEE, dd.MM.yyyy', 'de').format(widget.datum)}',
              style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                    child: _SwipeEditTimeField(
                        label: 'KOMMEN',
                        ctrl: widget.kommenCtrl,
                        color: skin.kommenColor,
                        onTap: () => _pickTime(widget.kommenCtrl, false),
                        onSwipeUp: () => _adjustTime(widget.kommenCtrl, 1, false),
                        onSwipeDown: () => _adjustTime(widget.kommenCtrl, -1, false))),
                const SizedBox(width: 12),
                Expanded(
                    child: _SwipeEditTimeField(
                        label: 'GEHEN',
                        ctrl: widget.gehenCtrl,
                        color: skin.gehenColor,
                        onTap: () => _pickTime(widget.gehenCtrl, true),
                        onSwipeUp: () => _adjustTime(widget.gehenCtrl, 1, true),
                        onSwipeDown: () => _adjustTime(widget.gehenCtrl, -1, true))),
              ],
            ),
            const SizedBox(height: 12),
            _TextFieldInput(label: 'TKF', ctrl: widget.tkfCtrl),
            const SizedBox(height: 12),
            _TextFieldInput(label: 'NOTIZ', ctrl: widget.notizCtrl, maxLines: 2),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: widget.onSave,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: isChromeSkin
                      ? const LinearGradient(
                          colors: [Color(0xFF333333), Color(0xFF555555)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : skin.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    'Speichern',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
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
// Helper Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SwipeEditTimeField extends StatefulWidget {
  final String label;
  final TextEditingController ctrl;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  const _SwipeEditTimeField({
    required this.label,
    required this.ctrl,
    required this.color,
    required this.onTap,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  @override
  State<_SwipeEditTimeField> createState() => _SwipeEditTimeFieldState();
}

class _SwipeEditTimeFieldState extends State<_SwipeEditTimeField> {
  double _dragStart = 0;
  double _accumulated = 0;
  static const double _pxPerMin = 12;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onVerticalDragStart: (d) {
        _dragStart = d.localPosition.dy;
        _accumulated = 0;
      },
      onVerticalDragUpdate: (d) {
        _accumulated += _dragStart - d.localPosition.dy;
        _dragStart = d.localPosition.dy;
        while (_accumulated >= _pxPerMin) {
          _accumulated -= _pxPerMin;
          widget.onSwipeUp();
        }
        while (_accumulated <= -_pxPerMin) {
          _accumulated += _pxPerMin;
          widget.onSwipeDown();
        }
      },
      child: AnimatedBuilder(
        animation: widget.ctrl,
        builder: (_, __) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: widget.color, letterSpacing: 1)),
                  Icon(Icons.unfold_more, color: widget.color.withValues(alpha: 0.5), size: 14),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.ctrl.text.isEmpty ? '--:--' : widget.ctrl.text,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -1),
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextFieldInput extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final int maxLines;

  const _TextFieldInput({required this.label, required this.ctrl, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: skin.surface(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: skin.primary, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            style: TextStyle(color: skin.textPrimary, fontSize: 15),
            decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }
}

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
          border: Border.all(color: skin.borderSubtle),
        ),
        child: Icon(icon, color: skin.primary),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: skin.textMuted)),
          ],
        ),
      ),
    );
  }
}