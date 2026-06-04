import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class MonthScreen extends StatefulWidget {
  final VoidCallback onNavigateToHome;
  const MonthScreen({super.key, required this.onNavigateToHome});

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  DateTime _selectedMonth = DateTime.now();
  final Map<String, GlobalKey<_SlidableRowState>> _rowKeys = {};

  // Verhindert Screen-Wisch wenn Drag auf interaktivem Element startet
  bool _dragOnInteractive = false;

  List<Map<String, dynamic>> _getEntriesForMonth() {
    final box = Hive.box('arbeitszeiten');
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final List<Map<String, dynamic>> entries = [];
    for (final key in box.keys) {
      if (key.toString().startsWith(monthKey)) {
        final entry = box.get(key);
        if (entry != null) entries.add(Map<String, dynamic>.from(entry));
      }
    }
    entries.sort((a, b) => a['datum'].compareTo(b['datum']));
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
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  void _deleteEntry(String datum) {
    Hive.box('arbeitszeiten').delete(datum);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Eintrag gelöscht'),
      backgroundColor: const Color(0xFFFF6B6B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    ));
  }

  void _editEntry(Map<String, dynamic> entry) {
    final kommenCtrl = TextEditingController(text: entry['kommen'] ?? '');
    final gehenCtrl = TextEditingController(text: entry['gehen'] ?? '');
    final tkfCtrl = TextEditingController(text: entry['TKF'] ?? '');
    final notizCtrl = TextEditingController(text: entry['notiz'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditSheet(
        datum: DateTime.parse(entry['datum']),
        kommenCtrl: kommenCtrl,
        gehenCtrl: gehenCtrl,
        tkfCtrl: tkfCtrl,
        notizCtrl: notizCtrl,
        onSave: () {
          Hive.box('arbeitszeiten').put(entry['datum'], {
            'kommen': kommenCtrl.text,
            'gehen': gehenCtrl.text,
            'TKF': tkfCtrl.text,
            'notiz': notizCtrl.text,
            'datum': entry['datum'],
          });
          setState(() {});
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Aktualisiert ✓'),
            backgroundColor: const Color(0xFF6C63FF),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          ));
        },
      ),
    );
  }

  Future<void> _shareEntry(Map<String, dynamic> entry) async {
    final settingsBox = Hive.box('einstellungen');
    final fullName =
        settingsBox.get('name', defaultValue: 'Unbekannt') as String;
    final datum = DateTime.parse(entry['datum']);
    final datumStr = DateFormat('EEEE, dd.MM.yyyy', 'de').format(datum);
    final dateKey = DateFormat('yyyy-MM-dd').format(datum);
    final kommen =
        (entry['kommen'] ?? '').isEmpty ? '--:--' : entry['kommen'];
    final gehen = (entry['gehen'] ?? '').isEmpty ? '--:--' : entry['gehen'];
    final tkf = entry['TKF'] ?? '';
    final notiz = entry['notiz'] ?? '';

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.Page(
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
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 18,
                          color: PdfColors.white)),
                  pw.Text(fullName,
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 13,
                          color: PdfColors.grey400)),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text(datumStr,
                style: pw.TextStyle(font: fontBold, fontSize: 16)),
            pw.SizedBox(height: 16),
            pw.Row(
              children: [
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
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 10,
                                color: PdfColors.teal)),
                        pw.SizedBox(height: 4),
                        pw.Text(kommen,
                            style:
                                pw.TextStyle(font: fontBold, fontSize: 26)),
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
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 10,
                                color: PdfColors.red)),
                        pw.SizedBox(height: 4),
                        pw.Text(gehen,
                            style:
                                pw.TextStyle(font: fontBold, fontSize: 26)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (tkf.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text('TKF: $tkf',
                  style: pw.TextStyle(
                      font: font,
                      fontSize: 12,
                      color: PdfColors.grey700)),
            ],
            if (notiz.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Notiz: $notiz',
                  style: pw.TextStyle(
                      font: font,
                      fontSize: 12,
                      color: PdfColors.grey700)),
            ],
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 6),
            pw.Text(
              'Erstellt am ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
              style: pw.TextStyle(
                  font: font, fontSize: 9, color: PdfColors.grey400),
            ),
          ],
        ),
      ),
    );

    final safeName = fullName.replaceAll(' ', '_');
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'OperationTimer_${safeName}_$dateKey.pdf',
    );
  }

  void _showMonthPicker() {
    int pickedYear = _selectedMonth.year;
    int pickedMonth = _selectedMonth.month - 1;
    final yearCount = DateTime.now().year - 2020 + 2;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141420),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Monat & Jahr',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                            initialItem: pickedMonth + 1000),
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
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white),
                                  ),
                                )),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                            initialItem: pickedYear - 2020),
                        itemExtent: 44,
                        looping: false,
                        backgroundColor: Colors.transparent,
                        onSelectedItemChanged: (i) => setSheet(
                            () => pickedYear =
                                2020 + i.clamp(0, yearCount - 1)),
                        children: List.generate(
                            yearCount,
                            (i) => Center(
                                  child: Text(
                                    '${2020 + i}',
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white),
                                  ),
                                )),
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
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text('Abbrechen',
                              style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedMonth =
                            DateTime(pickedYear, pickedMonth + 1));
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            Color(0xFF6C63FF),
                            Color(0xFF4ECDC4)
                          ]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text('Auswählen',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
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
    final entries = _getEntriesForMonth();
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    final complete =
        entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length;
    final open = entries.length - complete;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: GestureDetector(
        onTap: _closeAllRows,
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _dragOnInteractive = false;
        },
        onHorizontalDragEnd: (d) {
          if (_dragOnInteractive) return;
          final v = d.primaryVelocity ?? 0;
          // Nach rechts wischen → zurück zum HomeScreen
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
                    // ── Titel ──────────────────────────────────────────────
                    const Text(
                      'Monatsübersicht',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 16),

                    // ── Monat Navigation ───────────────────────────────────
                    Listener(
                      onPointerDown: (_) => _dragOnInteractive = true,
                      child: Row(
                        children: [
                          _MonthNavBtn(
                              icon: Icons.chevron_left,
                              onTap: () => _changeMonth(-1)),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141420),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFF6C63FF)
                                          .withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(monthName,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white)),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.expand_more,
                                        color: Color(0xFF6C63FF), size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _MonthNavBtn(
                              icon: Icons.chevron_right,
                              onTap: () => _changeMonth(1)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard(
                            label: 'Einträge',
                            value: '${entries.length}',
                            color: const Color(0xFF6C63FF)),
                        const SizedBox(width: 10),
                        _StatCard(
                            label: 'Vollständig',
                            value: '$complete',
                            color: const Color(0xFF4ECDC4)),
                        const SizedBox(width: 10),
                        _StatCard(
                            label: 'Offen',
                            value: '$open',
                            color: const Color(0xFFFF6B6B)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '← Löschen  ·  → Bearbeiten / Teilen',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.3)),
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
                            const Text('📭',
                                style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('Keine Einträge für diesen Monat',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.3),
                                    fontSize: 15)),
                          ],
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (_) {
                          _closeAllRows();
                          return false;
                        },
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(24, 4, 24, 100),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final datum = entry['datum'] as String;
                            _rowKeys[datum] ??=
                                GlobalKey<_SlidableRowState>();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SlidableRow(
                                key: _rowKeys[datum],
                                entry: entry,
                                duration: _calcDuration(
                                    entry['kommen'] ?? '',
                                    entry['gehen'] ?? ''),
                                onEdit: () => _editEntry(entry),
                                onDelete: () => _deleteEntry(datum),
                                onShare: () => _shareEntry(entry),
                                onCloseOthers: () {
                                  for (final k in _rowKeys.entries) {
                                    if (k.key != datum) {
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
  final String duration;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onCloseOthers;

  const _SlidableRow({
    super.key,
    required this.entry,
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

  // _offset NEGATIV  → Kachel nach links  → Delete rechts sichtbar
  // _offset POSITIV  → Kachel nach rechts → Edit + Share links sichtbar
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

  @override
  Widget build(BuildContext context) {
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
        ? const Color(0xFF4ECDC4).withValues(alpha: 0.3)
        : const Color(0xFFFF6B6B).withValues(alpha: 0.3);
    final rowHeight = notiz.isNotEmpty ? 132.0 : 94.0;

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
            // ── LINKS: Edit + Share ────────────────────────────────────────
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
                        Future.delayed(
                            const Duration(milliseconds: 200), widget.onEdit);
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF6C63FF),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_outlined,
                                color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Bearbeiten',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _animateTo(0);
                        Future.delayed(
                            const Duration(milliseconds: 200),
                            widget.onShare);
                      },
                      child: Container(
                        color: const Color(0xFF4ECDC4),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.ios_share_outlined,
                                color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Tag teilen',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── RECHTS: Löschen ────────────────────────────────────────────
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _deleteReveal,
              child: GestureDetector(
                onTap: () {
                  _animateTo(0);
                  Future.delayed(
                      const Duration(milliseconds: 150), widget.onDelete);
                },
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B6B),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline,
                          color: Colors.white, size: 22),
                      SizedBox(height: 4),
                      Text('Löschen',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

            // ── Vordergrund Kachel ─────────────────────────────────────────
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(_offset, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141420),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 50,
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(dayName.toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF6C63FF),
                                        fontWeight: FontWeight.w700)),
                                Text(dayNum,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _TimeChip(
                                        time: kommen.isEmpty
                                            ? '--:--'
                                            : kommen,
                                        color: const Color(0xFF4ECDC4)),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6),
                                      child: Icon(Icons.arrow_forward,
                                          size: 12,
                                          color: Color(0xFF555570)),
                                    ),
                                    _TimeChip(
                                        time:
                                            gehen.isEmpty ? '--:--' : gehen,
                                        color: const Color(0xFFFF6B6B)),
                                  ],
                                ),
                                if (tkf.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('👤 $tkf',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF555570))),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(widget.duration,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isComplete
                                      ? const Color(0xFF4ECDC4)
                                          .withValues(alpha: 0.12)
                                      : const Color(0xFFFF6B6B)
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isComplete ? '✓ Ok' : '⏳ Offen',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isComplete
                                        ? const Color(0xFF4ECDC4)
                                        : const Color(0xFFFF6B6B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (notiz.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Text('📝',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(notiz,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.6))),
                              ),
                            ],
                          ),
                        ),
                      ],
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
// EDIT SHEET MIT SWIPE-FUNKTIONALITÄT
// ─────────────────────────────────────────────────────────────────────────────

class _EditSheet extends StatefulWidget {
  final DateTime datum;
  final TextEditingController kommenCtrl;
  final TextEditingController gehenCtrl;
  final TextEditingController tkfCtrl;
  final TextEditingController notizCtrl;
  final VoidCallback onSave;

  const _EditSheet({
    required this.datum,
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

  void _adjustTime(TextEditingController controller, int minutesDelta) {
    final current = _parse(controller.text) ?? TimeOfDay.now();
    final total = (current.hour * 60 + current.minute + minutesDelta).clamp(0, 23 * 60 + 59);
    setState(() {
      controller.text =
          '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    int selH = _parse(ctrl.text)?.hour ?? TimeOfDay.now().hour;
    int selM = _parse(ctrl.text)?.minute ?? TimeOfDay.now().minute;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Uhrzeit',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                          initialItem: selH + 1000),
                      itemExtent: 40,
                      looping: true,
                      backgroundColor: Colors.transparent,
                      onSelectedItemChanged: (i) => selH = i % 24,
                      children: List.generate(
                          24,
                          (h) => Center(
                                child: Text(h.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              )),
                    ),
                  ),
                  const Text(':',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6C63FF))),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                          initialItem: selM + 1000),
                      itemExtent: 40,
                      looping: true,
                      backgroundColor: Colors.transparent,
                      onSelectedItemChanged: (i) => selM = i % 60,
                      children: List.generate(
                          60,
                          (m) => Center(
                                child: Text(m.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              )),
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
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                          child: Text('Abbrechen',
                              style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600))),
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
                        gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                          child: Text('Übernehmen',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700))),
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Bearbeiten – ${DateFormat('EEEE, dd.MM.yyyy', 'de').format(widget.datum)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                    child: _SwipeEditTimeField(
                        label: 'KOMMEN',
                        ctrl: widget.kommenCtrl,
                        color: const Color(0xFF4ECDC4),
                        onTap: () => _pickTime(widget.kommenCtrl),
                        onSwipeUp: () => _adjustTime(widget.kommenCtrl, 1),
                        onSwipeDown: () => _adjustTime(widget.kommenCtrl, -1))),
                const SizedBox(width: 12),
                Expanded(
                    child: _SwipeEditTimeField(
                        label: 'GEHEN',
                        ctrl: widget.gehenCtrl,
                        color: const Color(0xFFFF6B6B),
                        onTap: () => _pickTime(widget.gehenCtrl),
                        onSwipeUp: () => _adjustTime(widget.gehenCtrl, 1),
                        onSwipeDown: () => _adjustTime(widget.gehenCtrl, -1))),
              ],
            ),
            const SizedBox(height: 12),
            _TextFieldInput(label: 'TKF', ctrl: widget.tkfCtrl),
            const SizedBox(height: 12),
            _TextFieldInput(
                label: 'NOTIZ', ctrl: widget.notizCtrl, maxLines: 2),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: widget.onSave,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                    child: Text('Speichern',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SWIPE-FÄHIGES TIMEFIELD FÜR EDITSHEET
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
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: widget.color,
                          letterSpacing: 1)),
                  Icon(Icons.unfold_more,
                      color: widget.color.withValues(alpha: 0.5), size: 14),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.ctrl.text.isEmpty ? '--:--' : widget.ctrl.text,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
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

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _TextFieldInput extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final int maxLines;
  const _TextFieldInput(
      {required this.label, required this.ctrl, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 15),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, color: const Color(0xFF6C63FF)),
      ),
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
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF555570))),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String time;
  final Color color;
  const _TimeChip({required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(time,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }
}