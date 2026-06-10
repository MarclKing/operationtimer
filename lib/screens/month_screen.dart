import 'dart:ui';
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

// ─────────────────────────────────────────────────────────────────────────────
// LIQUID GLASS HELPERS — lokal importiert aus home_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

extension _AppSkinGlass on AppSkin {
  double get glassBlur => isLight ? 18.0 : 22.0;
  double get glassOpacity => isLight ? 0.62 : 0.55;
  Color get glassHighlight =>
      isLight ? Colors.white.withValues(alpha: 0.70) : Colors.white.withValues(alpha: 0.12);
  Color get glassBorder =>
      isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.16);
  Color get glassShadow =>
      Colors.black.withValues(alpha: isLight ? 0.08 : 0.35);
}

class _GlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool useBlur;
  final bool highlighted;
  final Color? overrideColor;

  const _GlassSurface({
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.useBlur = true,
    this.highlighted = false,
    this.overrideColor,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final br = BorderRadius.circular(borderRadius);
    final baseColor = overrideColor ??
        (skin.isLight
            ? Colors.white.withValues(alpha: skin.glassOpacity)
            : skin.bgCard.withValues(alpha: skin.glassOpacity));

    final decoration = BoxDecoration(
      color: baseColor,
      borderRadius: br,
      border: Border.all(
        color: highlighted
            ? skin.primary.withValues(alpha: 0.45)
            : skin.glassBorder,
        width: highlighted ? 1.5 : 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: skin.glassShadow,
          blurRadius: 24,
          spreadRadius: 0,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: skin.glassHighlight,
          blurRadius: 0,
          spreadRadius: -1,
          offset: const Offset(0, 1),
        ),
      ],
    );

    final inner = Container(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: decoration,
      child: child,
    );

    if (!useBlur) return ClipRRect(borderRadius: br, child: inner);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: inner,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS PRIMARY BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _GlassPrimaryButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool large;

  const _GlassPrimaryButton({
    required this.skin,
    required this.label,
    required this.onTap,
    this.icon,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = skin.isLight
        ? skin.primary.withValues(alpha: 0.13)
        : skin.primary.withValues(alpha: 0.22);
    final borderColor = skin.isLight
        ? skin.primary.withValues(alpha: 0.28)
        : skin.primary.withValues(alpha: 0.45);
    final textColor = skin.isLight
        ? skin.primary.withValues(alpha: 0.90)
        : skin.primary.withValues(alpha: 0.85);
    final iconColor = skin.isLight
        ? skin.primary.withValues(alpha: 0.65)
        : skin.primary.withValues(alpha: 0.70);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
            vertical: large ? 17 : 14, horizontal: 20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(large ? 20 : 14),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: skin.glassShadow,
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 6)),
            BoxShadow(
                color: skin.glassHighlight,
                blurRadius: 0,
                spreadRadius: -1,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor, size: large ? 20 : 17),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: large ? 16 : 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SECONDARY BUTTON (angepasst)
// ─────────────────────────────────────────────────────────────────────────────

class _GlassSecondaryButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final VoidCallback onTap;

  const _GlassSecondaryButton({required this.skin, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: skin.isLight
              ? Colors.white.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.glassBorder, width: 1.0),
          boxShadow: [
            BoxShadow(
                color: skin.glassShadow,
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: skin.textPrimary)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MonthScreen
// ─────────────────────────────────────────────────────────────────────────────

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
      final start = Duration(hours: int.parse(k[0]), minutes: int.parse(k[1]));
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
    closeAllRows();
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
    closeAllRows();
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
                    borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('KOMMEN',
                      style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.teal)),
                  pw.SizedBox(height: 4),
                  pw.Text(kommen, style: pw.TextStyle(font: fontBold, fontSize: 26)),
                ]),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFEEEEFF),
                    borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('GEHEN',
                      style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.red)),
                  pw.SizedBox(height: 4),
                  pw.Text(gehen, style: pw.TextStyle(font: fontBold, fontSize: 26)),
                ]),
              ),
            ),
          ]),
          if (tkf.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('TKF: $tkf',
                style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700)),
          ],
          if (notiz.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Notiz: $notiz',
                style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700)),
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

  void _showMonthPicker() {
    closeAllRows();
    final skin = AppTheme.of(context);
    int pickedYear = _selectedMonth.year;
    int pickedMonth = _selectedMonth.month - 1;
    final yearCount = DateTime.now().year - 2020 + 2;
    final monthCtrl =
        FixedExtentScrollController(initialItem: 1000 * 12 + pickedMonth);
    final yearCtrl = FixedExtentScrollController(initialItem: pickedYear - 2020);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => _GlassBottomSheet(
          skin: skin,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHandle(skin: skin),
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
                      onSelectedItemChanged: (i) =>
                          setSheet(() => pickedYear = 2020 + i.clamp(0, yearCount - 1)),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: _GlassSecondaryButton(
                      skin: skin,
                      label: 'Aktuell',
                      onTap: () {
                        final now = DateTime.now();
                        _setMonth(DateTime(now.year, now.month));
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GlassPrimaryButton(
                      skin: skin,
                      label: 'Auswählen',
                      onTap: () {
                        _setMonth(DateTime(pickedYear, pickedMonth + 1));
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ]),
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

                        // ── Monats-Navigation (wie HomeScreen) ─────────────────
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                                sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                            child: Container(
                              decoration: BoxDecoration(
                                color: skin.isLight
                                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                                    : skin.bgCard.withValues(alpha: skin.glassOpacity),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: skin.glassBorder, width: 1.0),
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
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _changeMonth(-1),
                                    child: const SizedBox(
                                      width: 44, height: 52,
                                      child: Center(
                                        child: Icon(Icons.chevron_left, size: 22),
                                      ),
                                    ),
                                  ),
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
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(monthName,
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: skin.textPrimary)),
                                            const SizedBox(width: 6),
                                            Icon(Icons.expand_more,
                                                color: skin.surface(0.4), size: 18),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _changeMonth(1),
                                    child: SizedBox(
                                      width: 44, height: 52,
                                      child: Center(
                                        child: Icon(Icons.chevron_right,
                                            size: 22, color: skin.surface(0.5)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Stat Cards ────────────────────────────────────────
                        Row(children: [
                          _GlassStatCard(label: 'Arbeit', value: '${entries.length}', color: skin.statEntries),
                          const SizedBox(width: 10),
                          _GlassStatCard(label: 'Tage', value: '$daysInMonth', color: skin.statComplete),
                          const SizedBox(width: 10),
                          _GlassStatCard(label: 'Offen', value: '$offeneEntries', color: skin.statOpen),
                        ]),

                        const SizedBox(height: 8),
                        Text(
                          '← Löschen  ·  → Bearbeiten / Teilen',
                          style: TextStyle(fontSize: 11, color: skin.surface(0.3)),
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
                                const Text('📭', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text('Keine Einträge für diesen Monat',
                                    style: TextStyle(color: skin.surface(0.3), fontSize: 15)),
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
                                padding: EdgeInsets.fromLTRB(24, 4, 24, bottomNavHeight + 88),
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
                                      duration: _calcDuration(
                                          entry['kommen'] ?? '', entry['gehen'] ?? ''),
                                      isComplete: _isEntryComplete(entry),
                                      onEdit: () => _editEntry(entry),
                                      onDelete: () => _deleteEntry(datum, entryId),
                                      onShare: () => _shareEntry(entry),
                                      onCloseOthers: () => _closeOtherRows(entryId),
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

          // ── Export-Button ──────────────────────────────────────────────────
          Positioned(
            left: 24,
            right: 24,
            bottom: bottomNavHeight + 32,
            child: GestureDetector(
              onTap: () {
                closeAllRows();
                if (entries.isEmpty) {
                  final mn = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
                  _showSnackbar('Keine Einträge für $mn vorhanden', skin.deleteColor);
                  return;
                }
                PdfService.exportMonth(context, _selectedMonth);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: skin.isLight
                      ? skin.primary.withValues(alpha: 0.13)
                      : skin.primary.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: skin.isLight
                        ? skin.primary.withValues(alpha: 0.28)
                        : skin.primary.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: skin.glassShadow,
                        blurRadius: 24,
                        spreadRadius: 0,
                        offset: const Offset(0, 6)),
                    BoxShadow(
                        color: skin.glassHighlight,
                        blurRadius: 0,
                        spreadRadius: -1,
                        offset: const Offset(0, 1)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.picture_as_pdf_outlined,
                        color: skin.isLight
                            ? skin.primary.withValues(alpha: 0.65)
                            : skin.primary.withValues(alpha: 0.70),
                        size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Diesen Monat exportieren',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: skin.isLight
                              ? skin.primary.withValues(alpha: 0.90)
                              : skin.primary.withValues(alpha: 0.85),
                          letterSpacing: 0.2),
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

// ─────────────────────────────────────────────────────────────────────────────
// GLASS STAT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _GlassStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _GlassStatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: skin.isLight ? 0.10 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(fontSize: 11, color: skin.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _GlassBottomSheet extends StatelessWidget {
  final AppSkin skin;
  final Widget child;

  const _GlassBottomSheet({required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: 0.88)
                : skin.bgSheet.withValues(alpha: 0.90),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: skin.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  final AppSkin skin;
  const _SheetHandle({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
          color: skin.surface(0.18), borderRadius: BorderRadius.circular(2)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDABLE ROW — Glass-Card + Action-Kacheln (mit Scale-Animation)
// ─────────────────────────────────────────────────────────────────────────────

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

class _SlidableRowState extends State<_SlidableRow> with TickerProviderStateMixin {
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

  double get _revealProgress => _offset < 0 
      ? (_offset.abs() / _deleteReveal).clamp(0.0, 1.0) 
      : 0.0;
  double get _editRevealProgress => (_offset / _editReveal).clamp(0.0, 1.0);

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
    final hasNotiz = (entry['notiz'] ?? '').isNotEmpty;
    final isComplete = widget.isComplete;

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
                // ── LINKS: Bearbeiten + Teilen (mit Scale-Animation) ─────────────
                Positioned(
                  left: 0,
                  top: 4,
                  bottom: 4,
                  width: _editReveal,
                  child: Row(children: [
                    Expanded(
                      child: Transform.scale(
                        scale: _editRevealProgress,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () {
                            _animateTo(0);
                            Future.delayed(
                                const Duration(milliseconds: 200), widget.onEdit);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  color: skin.editColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: skin.editColor.withValues(alpha: 0.22)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_outlined, color: skin.editColor, size: 22),
                                    const SizedBox(height: 4),
                                    Text('Bearbeiten',
                                        style: TextStyle(
                                            color: skin.editColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Transform.scale(
                        scale: _editRevealProgress,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () {
                            _animateTo(0);
                            Future.delayed(
                                const Duration(milliseconds: 200), widget.onShare);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  color: skin.statComplete.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: skin.statComplete.withValues(alpha: 0.22)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.ios_share_outlined,
                                        color: skin.statComplete, size: 22),
                                    const SizedBox(height: 4),
                                    Text('Teilen',
                                        style: TextStyle(
                                            color: skin.statComplete,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),

                // ── RECHTS: Löschen (mit Scale-Animation) ────────────────────────
                Positioned(
                  right: 0,
                  top: 4,
                  bottom: 4,
                  width: _deleteReveal,
                  child: GestureDetector(
                    onTap: () => widget.onDelete(),
                    child: Opacity(
                      opacity: _deleteFadeAnim.value,
                      child: Transform.scale(
                        scale: _revealProgress,
                        alignment: Alignment.center,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              margin: const EdgeInsets.only(left: 5),
                              decoration: BoxDecoration(
                                color: skin.deleteColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: skin.deleteColor.withValues(alpha: 0.22)),
                                boxShadow: _deleteAnimController.value > 0
                                    ? [
                                        BoxShadow(
                                          color: skin.deleteColor.withValues(
                                              alpha: 0.5 * _deleteAnimController.value),
                                          blurRadius: 16 * _deleteAnimController.value,
                                          spreadRadius: 2 * _deleteAnimController.value,
                                        )
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.delete_outline,
                                      color: skin.deleteColor, size: 22),
                                  const SizedBox(height: 4),
                                  Text('Löschen',
                                      style: TextStyle(
                                          color: skin.deleteColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── HAUPTKARTE (Glass) — mit optimierten Größen und vertikaler Zentrierung ─────────────────────
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(_offset + _slideAnim.value, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                            sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                        child: Container(
                          decoration: BoxDecoration(
                            color: skin.isLight
                                ? Colors.white.withValues(alpha: skin.glassOpacity)
                                : skin.bgCard.withValues(alpha: skin.glassOpacity),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: skin.glassBorder, width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: skin.glassShadow,
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: skin.glassHighlight,
                                blurRadius: 0,
                                spreadRadius: -1,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // ── Tag-Badge (vertikal zentriert) ──
                              SizedBox(
                                width: 52,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(dayName.toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                            color: skin.surface(0.38))),
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
                                        Text(DateFormat('MMM', 'de').format(datum),
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                                color: skin.surface(0.3))),
                                      ],
                                    ),
                                    if (showNumber)
                                      Text('$entryNumber.',
                                          style: TextStyle(
                                              fontSize: 7,
                                              fontWeight: FontWeight.w600,
                                              color: skin.primary.withValues(alpha: 0.6))),
                                  ],
                                ),
                              ),
                              // ── Trennstrich ──
                              Container(
                                width: 1,
                                height: 44,
                                margin: const EdgeInsets.symmetric(horizontal: 12),
                                color: skin.surface(0.07),
                              ),
                              // ── Zeiten + TKF/Notiz (vertikal zentriert) ──
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          kommen.isEmpty ? '--:--' : kommen,
                                          style: TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w700,
                                              color: kommen.isEmpty
                                                  ? skin.surface(0.2)
                                                  : skin.kommenColor),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Icon(Icons.arrow_forward,
                                              size: 16, color: skin.surface(0.2)),
                                        ),
                                        Text(
                                          gehen.isEmpty ? '--:--' : gehen,
                                          style: TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w700,
                                              color: gehen.isEmpty
                                                  ? skin.surface(0.2)
                                                  : skin.gehenColor),
                                        ),
                                      ],
                                    ),
                                    if (tkf.isNotEmpty || hasNotiz) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          if (tkf.isNotEmpty) ...[
                                            Icon(Icons.person_outline,
                                                size: 14, color: skin.surface(0.35)),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(tkf,
                                                  style: TextStyle(
                                                      fontSize: 12, color: skin.surface(0.42)),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis),
                                            ),
                                          ],
                                          if (hasNotiz) ...[
                                            if (tkf.isNotEmpty) const SizedBox(width: 8),
                                            Icon(Icons.note_outlined,
                                                size: 14,
                                                color: skin.primary.withValues(alpha: 0.45)),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // ── Dauer + Status (vertikal zentriert) ──
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (kommen.isNotEmpty && gehen.isNotEmpty)
                                    Text(widget.duration,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: skin.textPrimary)),
                                  const SizedBox(height: 4),
                                  Text(
                                    isComplete ? '✓ Ok' : '⏳ Offen',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isComplete ? skin.statComplete : skin.statOpen),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// EDIT SHEET — Glass
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
    return TimeOfDay(hour: (totalMinutes ~/ 60) % 24, minute: totalMinutes % 60);
  }

  TimeOfDay _getDefaultGehenTime(TimeOfDay kommenTime) =>
      _addMinutes(kommenTime, 8 * 60 + 12);

  void _adjustTime(TextEditingController controller, int minutesDelta, bool isGehenField) {
    TimeOfDay current;
    if (controller.text.isEmpty || controller.text == '--:--') {
      if (isGehenField) {
        final kommenTime = _parse(widget.kommenCtrl.text);
        current = kommenTime != null ? _getDefaultGehenTime(kommenTime) : TimeOfDay.now();
      } else {
        current = TimeOfDay.now();
      }
    } else {
      current = _parse(controller.text) ?? TimeOfDay.now();
    }
    final total =
        (current.hour * 60 + current.minute + minutesDelta).clamp(0, 23 * 60 + 59);
    setState(() {
      controller.text =
          '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pickTime(TextEditingController ctrl, bool isGehenField) async {
    final skin = AppTheme.of(context);
    TimeOfDay initialTime;
    if (ctrl.text.isNotEmpty && ctrl.text != '--:--') {
      initialTime = _parse(ctrl.text) ?? TimeOfDay.now();
    } else if (isGehenField) {
      final kommenTime = _parse(widget.kommenCtrl.text);
      initialTime = kommenTime != null ? _getDefaultGehenTime(kommenTime) : TimeOfDay.now();
    } else {
      initialTime = TimeOfDay.now();
    }
    int selH = initialTime.hour;
    int selM = initialTime.minute;
    final hourCtrl = FixedExtentScrollController(initialItem: selH + 1008);
    final minCtrl = FixedExtentScrollController(initialItem: selM + 1020);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => _GlassBottomSheet(
          skin: skin,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHandle(skin: skin),
              const SizedBox(height: 20),
              Text(isGehenField ? 'Uhrzeit Gehen' : 'Uhrzeit Kommen',
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
                      scrollController: hourCtrl,
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
                      scrollController: minCtrl,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: _GlassSecondaryButton(
                      skin: skin,
                      label: 'Jetzt',
                      onTap: () {
                        final now = DateTime.now();
                        selH = now.hour;
                        selM = now.minute;
                        hourCtrl.jumpToItem(selH + 1008);
                        minCtrl.jumpToItem(selM + 1020);
                        ctrl.text =
                            '${selH.toString().padLeft(2, '0')}:${selM.toString().padLeft(2, '0')}';
                        setSheet(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GlassPrimaryButton(
                      skin: skin,
                      label: 'Übernehmen',
                      onTap: () {
                        ctrl.text =
                            '${selH.toString().padLeft(2, '0')}:${selM.toString().padLeft(2, '0')}';
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 8) FocusScope.of(context).unfocus();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.90)
                    : skin.bgSheet.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: skin.glassBorder),
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
                        onSwipeDown: () => _adjustTime(widget.kommenCtrl, -1, false),
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
                        onSwipeDown: () => _adjustTime(widget.gehenCtrl, -1, true),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onDoubleTap: () {
                      setState(() => widget.tkfCtrl.clear());
                      HapticFeedback.selectionClick();
                    },
                    child: _GlassTextFieldInput(
                        label: 'TKF', ctrl: widget.tkfCtrl, capitalize: true),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onDoubleTap: () {
                      setState(() => widget.notizCtrl.clear());
                      HapticFeedback.selectionClick();
                    },
                    child: _GlassTextFieldInput(
                        label: 'NOTIZ', ctrl: widget.notizCtrl, maxLines: 2, capitalize: true),
                  ),
                  const SizedBox(height: 20),
                  _GlassPrimaryButton(
                    skin: skin,
                    label: 'Speichern',
                    onTap: widget.onSave,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SWIPE EDIT TIME FIELD — Glass
// ─────────────────────────────────────────────────────────────────────────────

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
        builder: (context, __) {
          final skin = AppTheme.of(context);
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: skin.isLight
                      ? widget.color.withValues(alpha: 0.08)
                      : widget.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.color.withValues(alpha: 0.28)),
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
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: skin.textPrimary,
                            letterSpacing: -1),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS TEXT FIELD INPUT
// ─────────────────────────────────────────────────────────────────────────────

class _GlassTextFieldInput extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final int maxLines;
  final bool capitalize;

  const _GlassTextFieldInput({
    required this.label,
    required this.ctrl,
    this.maxLines = 1,
    this.capitalize = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: 0.70)
                : skin.bgCard.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.glassBorder),
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
                textCapitalization:
                    capitalize ? TextCapitalization.sentences : TextCapitalization.none,
                style: TextStyle(color: skin.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FADING LIST VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _FadingListView extends StatelessWidget {
  final Widget child;
  final double fadeFromBottom;
  const _FadingListView({required this.child, required this.fadeFromBottom});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        final h = bounds.height;
        final fadeStartPx = fadeFromBottom + 60;
        final fadeEndPx = fadeFromBottom - 20;
        final startStop = ((h - fadeStartPx) / h).clamp(0.0, 1.0);
        final endStop = ((h - fadeEndPx) / h).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.white, Colors.white, Colors.transparent, Colors.transparent, Colors.transparent],
stops: [0.0, startStop, endStop, endStop + 0.01, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}