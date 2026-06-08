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
import '../services/pdf_service.dart';

class MonthScreen extends StatefulWidget {
  final VoidCallback onNavigateToHome;
  final DateTime selectedMonth;
  final ValueChanged<DateTime> onMonthChanged;

  const MonthScreen({
    super.key,
    required this.onNavigateToHome,
    required this.selectedMonth,
    required this.onMonthChanged,
  });

  @override
  State<MonthScreen> createState() => MonthScreenState();
}

class MonthScreenState extends State<MonthScreen> {
  late DateTime _selectedMonth;
  final Map<String, GlobalKey<_SlidableRowState>> _rowKeys = {};

  final Map<String, DateTime> _lastSnackbarTime = {};
  static const Duration _snackbarCooldown = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.selectedMonth;
  }

  @override
  void didUpdateWidget(MonthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMonth != widget.selectedMonth &&
        widget.selectedMonth != _selectedMonth) {
      setState(() => _selectedMonth = widget.selectedMonth);
    }
  }

  void _showSnackbar(String message, Color color) {
    final now = DateTime.now();
    final last = _lastSnackbarTime[message];
    if (last != null && now.difference(last) < _snackbarCooldown) return;
    _lastSnackbarTime[message] = now;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    ));
  }

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
              final e = Map<String, dynamic>.from(entry);
              if (!e.containsKey('datum')) e['datum'] = key.toString();
              entries.add(e);
            }
          } else {
            final e = Map<String, dynamic>.from(data);
            if (!e.containsKey('datum')) e['datum'] = key.toString();
            entries.add(e);
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

  static bool _isEntryComplete(Map<String, dynamic> entry) {
    final kommen = (entry['kommen'] ?? '').toString().trim();
    final gehen = (entry['gehen'] ?? '').toString().trim();
    final tkf = (entry['TKF'] ?? '').toString().trim();
    if (kommen.isNotEmpty && gehen.isNotEmpty) return true;
    if (tkf.isNotEmpty) return true;
    return false;
  }

  String _calcDuration(String kommen, String gehen) {
    if (kommen.isEmpty || gehen.isEmpty) return '--';
    try {
      final k = kommen.split(':');
      final g = gehen.split(':');
      final start =
          Duration(hours: int.parse(k[0]), minutes: int.parse(k[1]));
      final end = Duration(hours: int.parse(g[0]), minutes: int.parse(g[1]));
      final diff = end - start;
      if (diff.isNegative) return '--';
      return '${diff.inHours}h ${(diff.inMinutes % 60).toString().padLeft(2, '0')}m';
    } catch (_) {
      return '--';
    }
  }

  void closeAllRows() {
    for (final key in _rowKeys.values) {
      key.currentState?.close();
    }
  }

  void _closeOtherRows(String currentEntryId) {
    for (final entry in _rowKeys.entries) {
      if (entry.key != currentEntryId) {
        entry.value.currentState?.close();
      }
    }
  }

  void _setMonth(DateTime month) {
    setState(() => _selectedMonth = month);
    widget.onMonthChanged(month);
    closeAllRows();
  }

  void _changeMonth(int delta) {
    _setMonth(DateTime(_selectedMonth.year, _selectedMonth.month + delta));
  }

  void _deleteEntry(String datum, String entryId) {
    HapticFeedback.mediumImpact();
    final key = _rowKeys[entryId];
    key?.currentState?.animateOutAndDelete(() {
      final date = DateTime.parse(datum);
      NightShiftHelper.deleteEntry(date, entryId);
      setState(() => _rowKeys.remove(entryId));
      final skin = AppTheme.of(context);
      _showSnackbar('Eintrag gelöscht', skin.deleteColor);
    });
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
          _showSnackbar(
              'Aktualisiert ✓',
              skin.primary == Colors.white
                  ? const Color(0xFF3DD6C8)
                  : skin.primary);
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
    final gehen =
        (entry['gehen'] ?? '').isEmpty ? '--:--' : entry['gehen'];
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
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.teal)),
                    pw.SizedBox(height: 4),
                    pw.Text(kommen,
                        style: pw.TextStyle(font: fontBold, fontSize: 26)),
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
                        style: pw.TextStyle(font: fontBold, fontSize: 26)),
                  ],
                ),
              ),
            ),
          ]),
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
    ));

    final safeName = fullName.replaceAll(' ', '_');
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'OperationTimer_${safeName}_$dateKey.pdf',
    );
  }

  void _showMonthPicker() {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';
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
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: Text('Auswählen',
                              style: const TextStyle(
                                  color: Colors.white,
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
    final entries = _getEntriesForMonth();
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    final isChromeSkin = skin.key == 'chrome';
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;

    final daysInMonth =
        DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);
    final offeneEntries = entries.where((e) => !_isEntryComplete(e)).length;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: Stack(
        children: [
          GestureDetector(
            onTap: closeAllRows,
            behavior: HitTestBehavior.translucent,
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
                        Text('Monatsübersicht',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: skin.textPrimary)),
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
                                padding: const EdgeInsets.symmetric(
                                    vertical: 13),
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
                                  ],
                                ),
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
                              value: '${entries.length}',
                              color: skin.statEntries),
                          const SizedBox(width: 10),
                          _StatCard(
                              label: 'Tage',
                              value: '$daysInMonth',
                              color: skin.statComplete),
                          const SizedBox(width: 10),
                          _StatCard(
                              label: 'Offen',
                              value: '$offeneEntries',
                              color: skin.statOpen),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          '← Löschen  ·  → Bearbeiten / Teilen',
                          style: TextStyle(
                              fontSize: 11, color: skin.white(0.3)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
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
                                        color: skin.white(0.3),
                                        fontSize: 15)),
                              ],
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              closeAllRows();
                              return false;
                            },
                            child: _FadingListView(
                              fadeFromBottom: bottomNavHeight + 88,
                              child: ListView.builder(
                                padding: EdgeInsets.fromLTRB(
                                    24, 4, 24, bottomNavHeight + 88),
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  final datum = entry['datum'] as String;
                                  final entryId = entry['id'] as String;
                                  _rowKeys[entryId] ??=
                                      GlobalKey<_SlidableRowState>();
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _SlidableRow(
                                      key: _rowKeys[entryId],
                                      entry: entry,
                                      entryId: entryId,
                                      duration: _calcDuration(
                                          entry['kommen'] ?? '',
                                          entry['gehen'] ?? ''),
                                      isComplete: _isEntryComplete(entry),
                                      onEdit: () => _editEntry(entry),
                                      onDelete: () =>
                                          _deleteEntry(datum, entryId),
                                      onShare: () => _shareEntry(entry),
                                      onCloseOthers: () =>
                                          _closeOtherRows(entryId),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: bottomNavHeight + 20,
            child: GestureDetector(
              onTap: () => PdfService.exportMonth(context, _selectedMonth),
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
                      : const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: isChromeSkin
                          ? Colors.black.withValues(alpha: 0.3)
                          : const Color(0xFF6C63FF).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.picture_as_pdf_outlined,
                        color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Diesen Monat exportieren',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SlidableRow ──────────────────────────────────────────────────────────────

class _SlidableRow extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String entryId;
  final String duration;
  final bool isComplete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onCloseOthers;

  const _SlidableRow({
    super.key,
    required this.entry,
    required this.entryId,
    required this.duration,
    required this.isComplete,
    required this.onEdit,
    required this.onDelete,
    required this.onShare,
    required this.onCloseOthers,
  });

  @override
  State<_SlidableRow> createState() => _SlidableRowState();
}

class _SlidableRowState extends State<_SlidableRow>
    with TickerProviderStateMixin {
  double _offset = 0;
  static const double _deleteReveal = 80.0;
  static const double _editReveal = 160.0;
  static const double _snap = 40.0;

  late AnimationController _deleteAnimController;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _heightAnim;
  late Animation<double> _deleteScaleAnim;
  late Animation<double> _deleteFadeAnim;

  bool get _isOpen => _offset != 0;

  @override
  void initState() {
    super.initState();
    _deleteAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _slideAnim = Tween<double>(begin: 0, end: -440).animate(
      CurvedAnimation(
        parent: _deleteAnimController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeInBack),
      ),
    );
    _fadeAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _deleteAnimController,
        curve: const Interval(0.3, 0.75, curve: Curves.easeOut),
      ),
    );
    _heightAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _deleteAnimController,
        curve: const Interval(0.65, 1.0, curve: Curves.easeInOut),
      ),
    );
    _deleteScaleAnim = Tween<double>(begin: 1, end: 1.18).animate(
      CurvedAnimation(
        parent: _deleteAnimController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _deleteFadeAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _deleteAnimController,
        curve: const Interval(0.5, 0.85, curve: Curves.easeIn),
      ),
    );
    _deleteAnimController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _deleteAnimController.dispose();
    super.dispose();
  }

  void close() => _animateTo(0);

  void animateOutAndDelete(VoidCallback onDone) {
    _deleteAnimController.forward().then((_) => onDone());
  }

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
      _offset =
          (_offset + d.delta.dx).clamp(-_deleteReveal, _editReveal);
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
      final index =
          entries.indexWhere((e) => e['id'] == widget.entryId);
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
    final hasNotiz = (entry['notiz'] ?? '').isNotEmpty;
    final isComplete = widget.isComplete;
    final borderColor = isComplete
        ? skin.statComplete.withValues(alpha: 0.3)
        : skin.statOpen.withValues(alpha: 0.3);

    final entryNumber = _getEntryNumber();
    final entriesForDay = NightShiftHelper.getEntriesForDay(datum);
    final showNumber = entriesForDay.length > 1;

    const double rowHeight = 90.0;

    return AnimatedBuilder(
      animation: _deleteAnimController,
      builder: (context, child) {
        return SizeTransition(
          sizeFactor: _heightAnim,
          axisAlignment: -1,
          child: Opacity(opacity: _fadeAnim.value, child: child!),
        );
      },
      child: GestureDetector(
        onHorizontalDragStart: (_) => widget.onCloseOthers(),
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onTap: () {
          if (_isOpen) _animateTo(0);
          widget.onCloseOthers();
        },
        child: SizedBox(
          height: rowHeight,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _editReveal,
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          _animateTo(0);
                          Future.delayed(
                              const Duration(milliseconds: 200),
                              widget.onEdit);
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
                                  color: skin.primary == Colors.white
                                      ? Colors.black
                                      : Colors.white,
                                  size: 22),
                              const SizedBox(height: 4),
                              Text('Bearbeiten',
                                  style: TextStyle(
                                      color: skin.primary == Colors.white
                                          ? Colors.black
                                          : Colors.white,
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
                          decoration: BoxDecoration(
                            color: skin.statComplete,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(18),
                              bottomRight: Radius.circular(18),
                            ),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.ios_share_outlined,
                                  color: Colors.white, size: 22),
                              SizedBox(height: 4),
                              Text('Teilen',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _deleteReveal,
                  child: GestureDetector(
                    onTap: () => widget.onDelete(),
                    child: Opacity(
                      opacity: _deleteFadeAnim.value,
                      child: Transform.scale(
                        scale: _deleteScaleAnim.value,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            color: skin.deleteColor,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: _deleteAnimController.value > 0
                                ? [
                                    BoxShadow(
                                      color: skin.deleteColor.withValues(
                                          alpha: 0.5 *
                                              _deleteAnimController.value),
                                      blurRadius:
                                          16 * _deleteAnimController.value,
                                      spreadRadius:
                                          2 * _deleteAnimController.value,
                                    )
                                  ]
                                : null,
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
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(_offset + _slideAnim.value, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: skin.bgCard,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: skin.primaryWithAlpha(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(dayName.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: skin.primary,
                                        fontWeight: FontWeight.w700)),
                                Text(dayNum,
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: skin.textPrimary)),
                                if (showNumber)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: skin.primary
                                          .withValues(alpha: 0.2),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text('$entryNumber.',
                                        style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w600,
                                            color: skin.primary)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: skin.kommenColor
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      kommen.isEmpty ? '--:--' : kommen,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: skin.kommenColor),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(Icons.arrow_forward,
                                      size: 12, color: skin.white(0.3)),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: skin.gehenColor
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      gehen.isEmpty ? '--:--' : gehen,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: skin.gehenColor),
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 5),
                                Row(children: [
                                  if (tkf.isNotEmpty) ...[
                                    Icon(Icons.person_outline,
                                        size: 11,
                                        color: skin.white(0.35)),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(tkf,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: skin.white(0.4)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                  if (hasNotiz) ...[
                                    if (tkf.isNotEmpty)
                                      const SizedBox(width: 8),
                                    Icon(Icons.note_outlined,
                                        size: 11,
                                        color: skin.primary
                                            .withValues(alpha: 0.45)),
                                  ],
                                ]),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(widget.duration,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: skin.textPrimary)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isComplete
                                      ? skin.statComplete
                                          .withValues(alpha: 0.12)
                                      : skin.statOpen
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isComplete ? '✓ Ok' : '⏳ Offen',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isComplete
                                          ? skin.statComplete
                                          : skin.statOpen),
                                ),
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
        ),
      ),
    );
  }
}

// ─── EditSheet ────────────────────────────────────────────────────────────────

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
    return TimeOfDay(
        hour: (totalMinutes ~/ 60) % 24, minute: totalMinutes % 60);
  }

  TimeOfDay _getDefaultGehenTime(TimeOfDay kommenTime) =>
      _addMinutes(kommenTime, 8 * 60 + 12);

  void _adjustTime(
      TextEditingController controller, int minutesDelta, bool isGehenField) {
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
    final total = (current.hour * 60 + current.minute + minutesDelta)
        .clamp(0, 23 * 60 + 59);
    setState(() {
      controller.text =
          '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pickTime(
      TextEditingController ctrl, bool isGehenField) async {
    final skin = AppTheme.of(context);
    TimeOfDay initialTime;
    if (isGehenField && widget.gehenCtrl.text.isEmpty) {
      final kommenTime = _parse(widget.kommenCtrl.text);
      initialTime = kommenTime != null
          ? _getDefaultGehenTime(kommenTime)
          : TimeOfDay.now();
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
            Text('Uhrzeit',
                style: TextStyle(
                    color: skin.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Row(children: [
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
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: skin.textPrimary)),
                            )),
                  ),
                ),
                Text(':',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: skin.primary)),
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
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
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
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                        color: skin.surface(0.06),
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(
                        child: Text('Abbrechen',
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
                        borderRadius: BorderRadius.circular(14)),
                    child: Center(
                        child: Text('Übernehmen',
                            style: TextStyle(
                                color: skin.onGradient,
                                fontSize: 15,
                                fontWeight: FontWeight.w700))),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
    setState(() {
      ctrl.text =
          '${selH.toString().padLeft(2, '0')}:${selM.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';

    // ── FIX: GestureDetector korrekt geschlossen ──────────────────────────
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 8) {
          FocusScope.of(context).unfocus();
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          decoration: BoxDecoration(
            color: skin.bgSheet,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
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
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Bearbeiten – ${DateFormat('EEEE, dd.MM.yyyy', 'de').format(widget.datum)}',
                style: TextStyle(
                    color: skin.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: _SwipeEditTimeField(
                    label: 'KOMMEN',
                    ctrl: widget.kommenCtrl,
                    color: skin.kommenColor,
                    onTap: () => _pickTime(widget.kommenCtrl, false),
                    onDoubleTap: () {
                      setState(() => widget.kommenCtrl.clear());
                      HapticFeedback.selectionClick();
                    },
                    onSwipeUp: () => _adjustTime(widget.kommenCtrl, 1, false),
                    onSwipeDown: () =>
                        _adjustTime(widget.kommenCtrl, -1, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SwipeEditTimeField(
                    label: 'GEHEN',
                    ctrl: widget.gehenCtrl,
                    color: skin.gehenColor,
                    onTap: () => _pickTime(widget.gehenCtrl, true),
                    onDoubleTap: () {
                      setState(() => widget.gehenCtrl.clear());
                      HapticFeedback.selectionClick();
                    },
                    onSwipeUp: () => _adjustTime(widget.gehenCtrl, 1, true),
                    onSwipeDown: () =>
                        _adjustTime(widget.gehenCtrl, -1, true),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              GestureDetector(
                onDoubleTap: () {
                  setState(() => widget.tkfCtrl.clear());
                  HapticFeedback.selectionClick();
                },
                child: _TextFieldInput(
                    label: 'TKF', ctrl: widget.tkfCtrl, capitalize: true),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onDoubleTap: () {
                  setState(() => widget.notizCtrl.clear());
                  HapticFeedback.selectionClick();
                },
                child: _TextFieldInput(
                    label: 'NOTIZ',
                    ctrl: widget.notizCtrl,
                    maxLines: 2,
                    capitalize: true),
              ),
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
      ),
    ); // ← GestureDetector
  }
}

// ─── SwipeEditTimeField ───────────────────────────────────────────────────────

class _SwipeEditTimeField extends StatefulWidget {
  final String label;
  final TextEditingController ctrl;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  const _SwipeEditTimeField({
    required this.label,
    required this.ctrl,
    required this.color,
    required this.onTap,
    this.onDoubleTap,
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
      onDoubleTap: widget.onDoubleTap,
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
            border:
                Border.all(color: widget.color.withValues(alpha: 0.25)),
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
                      color: widget.color.withValues(alpha: 0.5),
                      size: 14),
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
                      letterSpacing: -1),
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

// ─── TextFieldInput ───────────────────────────────────────────────────────────

class _TextFieldInput extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final int maxLines;
  final bool capitalize;

  const _TextFieldInput({
    required this.label,
    required this.ctrl,
    this.maxLines = 1,
    this.capitalize = false,
  });

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
              style: TextStyle(
                  fontSize: 10,
                  color: skin.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            textCapitalization: capitalize
                ? TextCapitalization.sentences
                : TextCapitalization.none,
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

// ─── MonthNavBtn ──────────────────────────────────────────────────────────────

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

// ─── StatCard ─────────────────────────────────────────────────────────────────

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
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(fontSize: 11, color: skin.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ─── FadingListView ───────────────────────────────────────────────────────────

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
        final fadeStartPx = fadeFromBottom - 30;
        final fadeEndPx = fadeFromBottom - 70;
        final startStop = ((h - fadeStartPx) / h).clamp(0.0, 1.0);
        final endStop = ((h - fadeEndPx) / h).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.white,
            Colors.white,
            Colors.black26,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: [
            0.0,
            startStop,
            (startStop + endStop) / 2,
            endStop,
            1.0,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}