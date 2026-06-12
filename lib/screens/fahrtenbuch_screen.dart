import 'dart:ui';
import 'dart:io' as dartio;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIQUID GLASS EXTENSION
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

// ─────────────────────────────────────────────────────────────────────────────
// FAHRT MODEL — ERWEITERT
// ─────────────────────────────────────────────────────────────────────────────

class Fahrt {
  final String id;
  final DateTime datum;
  final int kmStart;
  final int kmEnd;
  final String kennzeichen;
  final double? getanktLiter;
  final String? fotoStartPath;
  final String? fotoEndPath;
  final bool uebertragen;

  // Neue Felder
  final DateTime? abfahrtZeit;
  final DateTime? ankunftDatum;
  final DateTime? ankunftZeit;
  final String fahrtTyp;
  final bool sonderWegerecht;
  final bool autoGewaschen;
  final double? stromKwh;
  final double? adblueKwh;
  final String fahrtZiel;

  Fahrt({
    required this.id,
    required this.datum,
    required this.kmStart,
    required this.kmEnd,
    required this.kennzeichen,
    this.getanktLiter,
    this.fotoStartPath,
    this.fotoEndPath,
    this.uebertragen = false,
    this.abfahrtZeit,
    this.ankunftDatum,
    this.ankunftZeit,
    this.fahrtTyp = '',
    this.sonderWegerecht = false,
    this.autoGewaschen = false,
    this.stromKwh,
    this.adblueKwh,
    this.fahrtZiel = '',
  });

  int get kmGefahren => kmEnd - kmStart;

  Map<String, dynamic> toMap() => {
        'id': id,
        'datum': datum.toIso8601String(),
        'kmStart': kmStart,
        'kmEnd': kmEnd,
        'kennzeichen': kennzeichen,
        'getanktLiter': getanktLiter,
        'fotoStartPath': fotoStartPath,
        'fotoEndPath': fotoEndPath,
        'uebertragen': uebertragen,
        'abfahrtZeit': abfahrtZeit?.toIso8601String(),
        'ankunftDatum': ankunftDatum?.toIso8601String(),
        'ankunftZeit': ankunftZeit?.toIso8601String(),
        'fahrtTyp': fahrtTyp,
        'sonderWegerecht': sonderWegerecht,
        'autoGewaschen': autoGewaschen,
        'stromKwh': stromKwh,
        'adblueKwh': adblueKwh,
        'fahrtZiel': fahrtZiel,
      };

  factory Fahrt.fromMap(Map<String, dynamic> map) => Fahrt(
        id: map['id'] as String,
        datum: DateTime.parse(map['datum'] as String),
        kmStart: map['kmStart'] as int,
        kmEnd: map['kmEnd'] as int,
        kennzeichen: map['kennzeichen'] as String? ?? '',
        getanktLiter: (map['getanktLiter'] as num?)?.toDouble(),
        fotoStartPath: map['fotoStartPath'] as String?,
        fotoEndPath: map['fotoEndPath'] as String?,
        uebertragen: map['uebertragen'] as bool? ?? false,
        abfahrtZeit: map['abfahrtZeit'] != null ? DateTime.tryParse(map['abfahrtZeit'] as String) : null,
        ankunftDatum: map['ankunftDatum'] != null ? DateTime.tryParse(map['ankunftDatum'] as String) : null,
        ankunftZeit: map['ankunftZeit'] != null ? DateTime.tryParse(map['ankunftZeit'] as String) : null,
        fahrtTyp: map['fahrtTyp'] as String? ?? '',
        sonderWegerecht: map['sonderWegerecht'] as bool? ?? false,
        autoGewaschen: map['autoGewaschen'] as bool? ?? false,
        stromKwh: (map['stromKwh'] as num?)?.toDouble(),
        adblueKwh: (map['adblueKwh'] as num?)?.toDouble(),
        fahrtZiel: map['fahrtZiel'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRTENBUCH SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class FahrtenbuchScreen extends StatefulWidget {
  const FahrtenbuchScreen({super.key});

  @override
  State<FahrtenbuchScreen> createState() => FahrtenbuchScreenState();
}

class FahrtenbuchScreenState extends State<FahrtenbuchScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  bool get _isDevMode {
    final box = Hive.box('einstellungen');
    return box.get('fahrtenbuch_dev_mode', defaultValue: false) as bool;
  }

  List<Fahrt> _getFahrtenForMonth() {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final raw = box.get('fahrten_$monthKey');
    if (raw == null) return [];
    if (raw is! List) return [];
    return raw
        .map((e) => Fahrt.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.datum.compareTo(b.datum));
  }

  void _saveFahrt(Fahrt fahrt) {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(fahrt.datum);
    final existing = _getFahrtenForMonth();
    final idx = existing.indexWhere((f) => f.id == fahrt.id);
    if (idx >= 0) {
      existing[idx] = fahrt;
    } else {
      existing.add(fahrt);
    }
    box.put('fahrten_$monthKey', existing.map((f) => f.toMap()).toList());
    setState(() {});
  }

  void _deleteFahrt(String id) {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final existing = _getFahrtenForMonth();
    existing.removeWhere((f) => f.id == id);
    box.put('fahrten_$monthKey', existing.map((f) => f.toMap()).toList());
    setState(() {});
  }

  void _setMonth(DateTime month) {
    setState(() => _selectedMonth = month);
  }

  void _changeMonth(int delta) {
    _setMonth(DateTime(_selectedMonth.year, _selectedMonth.month + delta));
  }

  void _showMonthPicker() {
    final skin = AppTheme.of(context);
    int pickedYear = _selectedMonth.year;
    int pickedMonth = _selectedMonth.month - 1;
    final yearCount = DateTime.now().year - 2020 + 2;
    final monthCtrl = FixedExtentScrollController(initialItem: 1000 * 12 + pickedMonth);
    final yearCtrl = FixedExtentScrollController(initialItem: pickedYear - 2020);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => _GlassSheet(
          skin: skin,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHandle(skin: skin),
              const SizedBox(height: 20),
              Text('Monat & Jahr',
                  style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
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
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: skin.textPrimary)),
                        ),
                      ),
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

  void showAddFahrtOverlay() {
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FahrtEintragenSheet(
        skin: skin,
        initialDate: DateTime.now(),
        onSave: _saveFahrt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final fahrten = _getFahrtenForMonth();
    final devMode = _isDevMode;
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;

    final totalFahrten = fahrten.length;
    final uebertragenCount = fahrten.where((f) => f.uebertragen).length;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 50),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Titel mit BETA Badge ──
                  Row(children: [
                    Text('Fahrtenbuch',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.4)),
                          ),
                          child: const Text('BETA',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFFB347),
                                  letterSpacing: 0.8)),
                        ),
                      ),
                    ),
                    if (devMode) ...[
                      const SizedBox(width: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF5B5B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFEF5B5B).withValues(alpha: 0.4)),
                            ),
                            child: const Text('DEV',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFEF5B5B),
                                    letterSpacing: 0.8)),
                          ),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),

                  // ── Monats-Navigation ──
                  GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -300) _changeMonth(1);
                      if (v > 300) _changeMonth(-1);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                        child: Container(
                          decoration: BoxDecoration(
                            color: skin.isLight
                                ? Colors.white.withValues(alpha: skin.glassOpacity)
                                : skin.bgCard.withValues(alpha: skin.glassOpacity),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: skin.glassBorder, width: 1.0),
                            boxShadow: [
                              BoxShadow(color: skin.glassShadow, blurRadius: 24, offset: const Offset(0, 6)),
                              BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                            ],
                          ),
                          child: Row(children: [
                            GestureDetector(
                              onTap: () => _changeMonth(-1),
                              child: const SizedBox(width: 44, height: 52,
                                  child: Center(child: Icon(Icons.chevron_left, size: 22))),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: _showMonthPicker,
                                onDoubleTap: () {
                                  HapticFeedback.selectionClick();
                                  final now = DateTime.now();
                                  _setMonth(DateTime(now.year, now.month));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(monthName,
                                          style: TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                                      const SizedBox(width: 6),
                                      Icon(Icons.expand_more, color: skin.primary, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _changeMonth(1),
                              child: SizedBox(width: 44, height: 52,
                                  child: Center(child: Icon(Icons.chevron_right, size: 22, color: skin.surface(0.5)))),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Stat Cards ──
                  Row(children: [
                    _StatCard(label: 'Fahrten', value: '$totalFahrten', color: skin.primary),
                    const SizedBox(width: 10),
                    _StatCard(label: 'Eingetragen', value: '$uebertragenCount', color: skin.statComplete),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Liste ──
            Expanded(
              child: (!devMode || fahrten.isEmpty)
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🚗', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text('Keine Fahrten eingetragen',
                              style: TextStyle(color: skin.surface(0.3), fontSize: 15)),
                          const SizedBox(height: 6),
                          Text(
                            devMode
                                ? 'Tippe auf + um eine Fahrt einzutragen'
                                : 'Fahrtenbuch ist noch nicht verfügbar',
                            style: TextStyle(color: skin.surface(0.2), fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : _FadingListView(
                      fadeFromBottom: bottomNavHeight + 20,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                        itemCount: fahrten.length + 1,
                        itemBuilder: (context, index) {
                          if (index == fahrten.length) {
                            return SizedBox(height: bottomNavHeight + 40);
                          }
                          final fahrt = fahrten[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _FahrtCard(
                              fahrt: fahrt,
                              skin: skin,
                              onDelete: () => _deleteFahrt(fahrt.id),
                              onToggleUebertragen: () {
                                _saveFahrt(Fahrt(
                                  id: fahrt.id,
                                  datum: fahrt.datum,
                                  kmStart: fahrt.kmStart,
                                  kmEnd: fahrt.kmEnd,
                                  kennzeichen: fahrt.kennzeichen,
                                  getanktLiter: fahrt.getanktLiter,
                                  fotoStartPath: fahrt.fotoStartPath,
                                  fotoEndPath: fahrt.fotoEndPath,
                                  uebertragen: !fahrt.uebertragen,
                                  abfahrtZeit: fahrt.abfahrtZeit,
                                  ankunftDatum: fahrt.ankunftDatum,
                                  ankunftZeit: fahrt.ankunftZeit,
                                  fahrtTyp: fahrt.fahrtTyp,
                                  sonderWegerecht: fahrt.sonderWegerecht,
                                  autoGewaschen: fahrt.autoGewaschen,
                                  stromKwh: fahrt.stromKwh,
                                  adblueKwh: fahrt.adblueKwh,
                                  fahrtZiel: fahrt.fahrtZiel,
                                ));
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _FahrtCard extends StatefulWidget {
  final Fahrt fahrt;
  final AppSkin skin;
  final VoidCallback onDelete;
  final VoidCallback onToggleUebertragen;

  const _FahrtCard({
    required this.fahrt,
    required this.skin,
    required this.onDelete,
    required this.onToggleUebertragen,
  });

  @override
  State<_FahrtCard> createState() => _FahrtCardState();
}

class _FahrtCardState extends State<_FahrtCard> {
  double _swipeOffset = 0;
  static const double _revealWidth = 160.0;
  static const double _snapThreshold = 60.0;
  bool _isOpen = false;
  bool _dragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;

  double get _revealProgress => (_swipeOffset.abs() / _revealWidth).clamp(0.0, 1.0);

  void _animateTo(double target) {
    if (!mounted) return;
    final start = _swipeOffset;
    final dist = target - start;
    int step = 0;
    const steps = 12;
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 12));
      if (!mounted) return false;
      step++;
      final t = step / steps;
      final eased = 1 - (1 - t) * (1 - t);
      setState(() => _swipeOffset = start + dist * eased);
      if (step >= steps) {
        if (mounted) setState(() => _swipeOffset = target);
        return false;
      }
      return true;
    });
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = false;
    _dragStartX = d.globalPosition.dx;
    _dragStartY = d.globalPosition.dy;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final totalDx = d.globalPosition.dx - _dragStartX;
    final totalDy = (d.globalPosition.dy - _dragStartY).abs();
    if (!_dragging) {
      if (totalDy > totalDx.abs()) return;
      if (totalDx > 0) return;
      if (totalDx.abs() < 8) return;
      _dragging = true;
    }
    final newOffset = (_swipeOffset + d.delta.dx).clamp(-_revealWidth, 0.0);
    setState(() => _swipeOffset = newOffset);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final v = d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx;
    if (_swipeOffset < -_snapThreshold || v < -400) {
      _animateTo(-_revealWidth);
      setState(() => _isOpen = true);
    } else {
      _animateTo(0);
      setState(() => _isOpen = false);
    }
  }

  void _close() {
    _animateTo(0);
    if (mounted) setState(() => _isOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final fahrt = widget.fahrt;
    final dayName = DateFormat('EEE', 'de').format(fahrt.datum);
    final dayNum = DateFormat('dd', 'de').format(fahrt.datum);
    final monthAbbr = DateFormat('MMM', 'de').format(fahrt.datum);
    final hatGetankt = fahrt.getanktLiter != null && fahrt.getanktLiter! > 0;

    return GestureDetector(
      onHorizontalDragStart: _onPanStart,
      onHorizontalDragUpdate: _onPanUpdate,
      onHorizontalDragEnd: _onPanEnd,
      onTap: _isOpen ? _close : null,
      child: SizedBox(
        height: 90,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // ── Actions rechts ──
              Positioned(
                right: 0,
                top: 4,
                bottom: 4,
                width: _revealWidth,
                child: Row(children: [
                  const SizedBox(width: 6),
                  Expanded(
                    child: Transform.scale(
                      scale: _revealProgress,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTap: () {
                          _close();
                          widget.onToggleUebertragen();
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
                                border: Border.all(color: skin.statComplete.withValues(alpha: 0.25)),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    fahrt.uebertragen
                                        ? Icons.check_circle_rounded
                                        : Icons.check_circle_outline,
                                    color: skin.statComplete,
                                    size: 22,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    fahrt.uebertragen ? 'Eingetr.' : 'Eintragen',
                                    style: TextStyle(
                                        color: skin.statComplete,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
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
                      scale: _revealProgress,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTap: () {
                          _close();
                          widget.onDelete();
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: skin.deleteColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25)),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.delete_outline, color: skin.deleteColor, size: 22),
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
                ]),
              ),

              // ── Hauptkarte ──
              Transform.translate(
                offset: Offset(_swipeOffset, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                    child: Container(
                      decoration: BoxDecoration(
                        color: skin.isLight
                            ? Colors.white.withValues(alpha: skin.glassOpacity)
                            : skin.bgCard.withValues(alpha: skin.glassOpacity),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: fahrt.uebertragen
                              ? skin.statComplete.withValues(alpha: 0.35)
                              : skin.glassBorder,
                          width: fahrt.uebertragen ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                          BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ── Datum ──
                          SizedBox(
                            width: 52,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
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
                                    Text(monthAbbr,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: skin.surface(0.3))),
                                  ],
                                ),
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

                          // ── KM Stände ──
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _KmDisplay(km: fahrt.kmStart, skin: skin, color: skin.kommenColor),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Icon(Icons.arrow_forward, size: 14, color: skin.surface(0.2)),
                                    ),
                                    _KmDisplay(km: fahrt.kmEnd, skin: skin, color: skin.gehenColor),
                                  ],
                                ),
                                if (fahrt.kennzeichen.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Row(children: [
                                    Icon(Icons.directions_car_outlined,
                                        size: 13, color: skin.surface(0.35)),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(fahrt.kennzeichen,
                                          style: TextStyle(
                                              fontSize: 12, color: skin.surface(0.42), fontWeight: FontWeight.w500),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (hatGetankt) ...[
                                      const SizedBox(width: 8),
                                      Icon(Icons.local_gas_station_outlined,
                                          size: 13, color: skin.primary.withValues(alpha: 0.55)),
                                    ],
                                    if (fahrt.sonderWegerecht) ...[
                                      const SizedBox(width: 6),
                                      Icon(Icons.emergency_outlined,
                                          size: 13, color: const Color(0xFFEF5B5B).withValues(alpha: 0.75)),
                                    ],
                                  ]),
                                ],
                              ],
                            ),
                          ),

                          // ── km gefahren ──
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${fahrt.kmGefahren} km',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: skin.textPrimary)),
                              const SizedBox(height: 4),
                              Text(
                                fahrt.uebertragen ? '✓ Eingetr.' : '· Offen',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: fahrt.uebertragen ? skin.statComplete : skin.statOpen),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
// KM DISPLAY
// ─────────────────────────────────────────────────────────────────────────────

class _KmDisplay extends StatelessWidget {
  final int km;
  final AppSkin skin;
  final Color color;

  const _KmDisplay({required this.km, required this.skin, required this.color});

  @override
  Widget build(BuildContext context) {
    final hunderts = km % 1000;
    final tausends = km ~/ 1000;
    final hundertStr = hunderts.toString().padLeft(3, '0');
    final tausendStr = tausends > 0 ? '$tausends.' : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (tausendStr.isNotEmpty)
          Text(tausendStr,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: skin.textPrimary.withValues(alpha: 0.45),
                  letterSpacing: 0)),
        Text(hundertStr,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: skin.textPrimary,
                letterSpacing: -1)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOGGLE KACHEL (Sonder/Wegerecht, Auto gewaschen)
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleKachel extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final AppSkin skin;
  final VoidCallback onTap;

  const _ToggleKachel({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.skin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: skin.isLight ? 0.13 : 0.18)
              : (skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.45)
                : skin.glassBorder,
            width: active ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? Icons.check_circle_rounded : icon,
              size: 18,
              color: active ? activeColor : skin.surface(0.35),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? activeColor : skin.surface(0.45),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRT EINTRAGEN SHEET — VOLLSTÄNDIG NEU
// ─────────────────────────────────────────────────────────────────────────────

class _FahrtEintragenSheet extends StatefulWidget {
  final AppSkin skin;
  final DateTime initialDate;
  final void Function(Fahrt) onSave;

  const _FahrtEintragenSheet({
    required this.skin,
    required this.initialDate,
    required this.onSave,
  });

  @override
  State<_FahrtEintragenSheet> createState() => _FahrtEintragenSheetState();
}

class _FahrtEintragenSheetState extends State<_FahrtEintragenSheet> {
  // Fahrzeug
  final _kennzeichenCtrl = TextEditingController();

  // Zeiten
  late DateTime _abfahrtDatum;
  TimeOfDay? _abfahrtZeit;
  DateTime? _ankunftDatum;
  TimeOfDay? _ankunftZeit;

  // KM
  final _kmStartCtrl = TextEditingController();
  final _kmEndCtrl = TextEditingController();
  final _picker = ImagePicker();
  String? _fotoStartPath;
  String? _fotoEndPath;

  // Fahrttyp
  String _fahrtTyp = '';
  final _fahrtTypCtrl = TextEditingController();
  static const List<String> _fahrtTypVorschlaege = [
    'Einsatz', 'Tanken', 'Versorgung', 'Dienstfahrt',
    'Materialtransport', 'Fortbildung', 'Bereitschaft',
    'Werkstatt', 'Sonstiges',
  ];

  // Toggle-Felder
  bool _sonderWegerecht = false;
  bool _autoGewaschen = false;

  // Betriebsstoffe
  final _kraftstoffCtrl = TextEditingController();
  final _stromCtrl = TextEditingController();
  final _adblueCtrl = TextEditingController();

  // Freitext
  final _fahrtZielCtrl = TextEditingController();

  AppSkin get skin => widget.skin;

  @override
  void initState() {
    super.initState();
    _abfahrtDatum = widget.initialDate;
    _ankunftDatum = widget.initialDate;
    _fahrtTypCtrl.addListener(() {
      if (_fahrtTypCtrl.text != _fahrtTyp) {
        setState(() => _fahrtTyp = _fahrtTypCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _kennzeichenCtrl.dispose();
    _kmStartCtrl.dispose();
    _kmEndCtrl.dispose();
    _fahrtTypCtrl.dispose();
    _kraftstoffCtrl.dispose();
    _stromCtrl.dispose();
    _adblueCtrl.dispose();
    _fahrtZielCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(bool isStart) async {
    final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) setState(() => isStart ? _fotoStartPath = picked.path : _fotoEndPath = picked.path);
  }

  void _openKmInput(TextEditingController ctrl, String label) {
    FocusScope.of(context).unfocus();
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _GlassSheet(
          skin: skin,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetHandle(skin: skin),
                const SizedBox(height: 16),
                Text(label,
                    style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: skin.isLight ? Colors.white.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: skin.glassBorder),
                      ),
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(color: skin.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(color: skin.surface(0.2), fontSize: 28),
                          border: InputBorder.none,
                          isDense: true,
                          suffix: Text(' km', style: TextStyle(color: skin.surface(0.4), fontSize: 16, fontWeight: FontWeight.w500)),
                        ),
                        onSubmitted: (_) => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _GlassPrimaryButton(
                  skin: skin,
                  label: 'Übernehmen',
                  onTap: () { setState(() {}); Navigator.pop(context); },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isAbfahrt) async {
    FocusScope.of(context).unfocus();
    final initial = isAbfahrt ? _abfahrtDatum : (_ankunftDatum ?? _abfahrtDatum);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('de'),
    );
    if (picked != null) {
      setState(() {
        if (isAbfahrt) {
          _abfahrtDatum = picked;
          if (_ankunftDatum != null && _ankunftDatum!.isBefore(picked)) {
            _ankunftDatum = picked;
          }
        } else {
          _ankunftDatum = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isAbfahrt) async {
    FocusScope.of(context).unfocus();
    final initial = isAbfahrt
        ? (_abfahrtZeit ?? TimeOfDay.now())
        : (_ankunftZeit ?? TimeOfDay.now());
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isAbfahrt) _abfahrtZeit = picked;
        else _ankunftZeit = picked;
      });
    }
  }

  String _formatDate(DateTime d) => DateFormat('dd.MM.yy', 'de').format(d);
  String _formatTime(TimeOfDay? t) => t != null ? t.format(context) : '—';

  void _save() {
    final kmStart = int.tryParse(_kmStartCtrl.text) ?? 0;
    final kmEnd = int.tryParse(_kmEndCtrl.text) ?? 0;
    final kennzeichen = _kennzeichenCtrl.text.trim().toUpperCase();

    DateTime? abfahrtZeit;
    if (_abfahrtZeit != null) {
      abfahrtZeit = DateTime(_abfahrtDatum.year, _abfahrtDatum.month, _abfahrtDatum.day,
          _abfahrtZeit!.hour, _abfahrtZeit!.minute);
    }
    DateTime? ankunftZeit;
    if (_ankunftZeit != null && _ankunftDatum != null) {
      ankunftZeit = DateTime(_ankunftDatum!.year, _ankunftDatum!.month, _ankunftDatum!.day,
          _ankunftZeit!.hour, _ankunftZeit!.minute);
    }

    final fahrt = Fahrt(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      datum: _abfahrtDatum,
      kmStart: kmStart,
      kmEnd: kmEnd,
      kennzeichen: kennzeichen,
      getanktLiter: double.tryParse(_kraftstoffCtrl.text.replaceAll(',', '.')),
      fotoStartPath: _fotoStartPath,
      fotoEndPath: _fotoEndPath,
      abfahrtZeit: abfahrtZeit,
      ankunftDatum: _ankunftDatum,
      ankunftZeit: ankunftZeit,
      fahrtTyp: _fahrtTyp.trim(),
      sonderWegerecht: _sonderWegerecht,
      autoGewaschen: _autoGewaschen,
      stromKwh: double.tryParse(_stromCtrl.text.replaceAll(',', '.')),
      adblueKwh: double.tryParse(_adblueCtrl.text.replaceAll(',', '.')),
      fahrtZiel: _fahrtZielCtrl.text.trim(),
    );

    widget.onSave(fahrt);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kmStart = int.tryParse(_kmStartCtrl.text);
    final kmEnd = int.tryParse(_kmEndCtrl.text);
    final canSave = kmStart != null && kmEnd != null && kmEnd >= kmStart;

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
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.92)
                    : skin.bgSheet.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: skin.glassBorder),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Handle & Header ──
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: skin.surface(0.18),
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: skin.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.directions_car_outlined, size: 18, color: skin.primary),
                      ),
                      const SizedBox(width: 12),
                      Text('Fahrt eintragen',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                    ]),
                    const SizedBox(height: 20),

                    // ══════════════════════════════════════
                    // BLOCK 1: FAHRZEUG
                    // ══════════════════════════════════════
                    _SectionLabel(label: 'FAHRZEUG', skin: skin),
                    const SizedBox(height: 8),
                    _InputRow(
                      skin: skin,
                      icon: Icons.directions_car_outlined,
                      label: 'KENNZEICHEN',
                      ctrl: _kennzeichenCtrl,
                      hint: 'z.B. B-AB 1234',
                      capitalize: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 20),

                    // ══════════════════════════════════════
                    // BLOCK 2: ZEITRAUM — ABFAHRT / ANKUNFT
                    // ══════════════════════════════════════
                    _SectionLabel(label: 'ZEITRAUM', skin: skin),
                    const SizedBox(height: 8),
                    Row(children: [
                      // Abfahrt
                      Expanded(
                        child: _ZeitBlock(
                          skin: skin,
                          label: 'ABFAHRT',
                          color: skin.kommenColor,
                          datumText: _formatDate(_abfahrtDatum),
                          zeitText: _formatTime(_abfahrtZeit),
                          onDateTap: () => _pickDate(true),
                          onTimeTap: () => _pickTime(true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Ankunft
                      Expanded(
                        child: _ZeitBlock(
                          skin: skin,
                          label: 'ANKUNFT',
                          color: skin.gehenColor,
                          datumText: _ankunftDatum != null ? _formatDate(_ankunftDatum!) : '—',
                          zeitText: _formatTime(_ankunftZeit),
                          onDateTap: () => _pickDate(false),
                          onTimeTap: () => _pickTime(false),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ══════════════════════════════════════
                    // BLOCK 3: KILOMETERSTAND
                    // ══════════════════════════════════════
                    _SectionLabel(label: 'KILOMETERSTAND', skin: skin),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _KmInputCard(
                          label: 'ABFAHRT KM',
                          ctrl: _kmStartCtrl,
                          skin: skin,
                          color: skin.kommenColor,
                          fotoPath: _fotoStartPath,
                          onTap: () => _openKmInput(_kmStartCtrl, 'Abfahrtkilometer'),
                          onCameraPressed: () => _pickPhoto(true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _KmInputCard(
                          label: 'ANKUNFT KM',
                          ctrl: _kmEndCtrl,
                          skin: skin,
                          color: skin.gehenColor,
                          fotoPath: _fotoEndPath,
                          onTap: () => _openKmInput(_kmEndCtrl, 'Ankunftkilometer'),
                          onCameraPressed: () => _pickPhoto(false),
                        ),
                      ),
                    ]),

                    // km-Differenz anzeigen wenn befüllt
                    if (kmStart != null && kmEnd != null && kmEnd >= kmStart) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: skin.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: skin.primary.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            '${kmEnd - kmStart} km gefahren',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: skin.primary.withValues(alpha: 0.8)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ══════════════════════════════════════
                    // BLOCK 4: FAHRTTYP
                    // ══════════════════════════════════════
                    _SectionLabel(label: 'FAHRTTYP', skin: skin),
                    const SizedBox(height: 8),
                    // Vorschlags-Chips
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _fahrtTypVorschlaege.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final typ = _fahrtTypVorschlaege[i];
                          final selected = _fahrtTyp == typ;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _fahrtTyp = selected ? '' : typ;
                                _fahrtTypCtrl.text = _fahrtTyp;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? skin.primary.withValues(alpha: 0.15)
                                    : skin.surface(0.06),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? skin.primary.withValues(alpha: 0.45)
                                      : skin.glassBorder,
                                  width: selected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Text(
                                typ,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? skin.primary : skin.surface(0.45),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Freitext-Fahrttyp
                    _InputRow(
                      skin: skin,
                      icon: Icons.label_outline,
                      label: 'ODER EIGENER GRUND',
                      ctrl: _fahrtTypCtrl,
                      hint: 'z.B. Krankenfahrt',
                    ),
                    const SizedBox(height: 20),

                    // ══════════════════════════════════════
                    // BLOCK 5: STATUS-KACHELN
                    // ══════════════════════════════════════
                    _SectionLabel(label: 'STATUS', skin: skin),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _ToggleKachel(
                          label: 'Sonder-/Wegerecht',
                          icon: Icons.emergency_outlined,
                          active: _sonderWegerecht,
                          activeColor: const Color(0xFFEF5B5B),
                          skin: skin,
                          onTap: () => setState(() => _sonderWegerecht = !_sonderWegerecht),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ToggleKachel(
                          label: 'Auto gewaschen',
                          icon: Icons.local_car_wash_outlined,
                          active: _autoGewaschen,
                          activeColor: const Color(0xFF4FC3F7),
                          skin: skin,
                          onTap: () => setState(() => _autoGewaschen = !_autoGewaschen),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ══════════════════════════════════════
                    // BLOCK 6: BETRIEBSSTOFFE
                    // ══════════════════════════════════════
                    _SectionLabel(label: 'BETRIEBSSTOFFE', skin: skin),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _BetriebsstoffCard(
                          skin: skin,
                          icon: Icons.local_gas_station_outlined,
                          label: 'KRAFTSTOFF',
                          unit: 'Liter',
                          ctrl: _kraftstoffCtrl,
                          color: const Color(0xFFFFB347),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BetriebsstoffCard(
                          skin: skin,
                          icon: Icons.bolt_outlined,
                          label: 'STROM',
                          unit: 'kWh',
                          ctrl: _stromCtrl,
                          color: const Color(0xFF66BB6A),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BetriebsstoffCard(
                          skin: skin,
                          icon: Icons.water_drop_outlined,
                          label: 'ADBLUE',
                          unit: 'Liter',
                          ctrl: _adblueCtrl,
                          color: const Color(0xFF42A5F5),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ══════════════════════════════════════
                    // BLOCK 7: FAHRTBESCHREIBUNG
                    // ══════════════════════════════════════
                    _SectionLabel(label: 'ZIEL & STRECKE', skin: skin),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: skin.isLight
                                ? Colors.white.withValues(alpha: skin.glassOpacity)
                                : skin.bgCard.withValues(alpha: skin.glassOpacity),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: skin.glassBorder),
                            boxShadow: [
                              BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.map_outlined, size: 16, color: skin.primary),
                                const SizedBox(width: 8),
                                Text('FAHRTZIEL & WEG',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: skin.primary,
                                        letterSpacing: 1.0)),
                              ]),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _fahrtZielCtrl,
                                maxLines: 3,
                                minLines: 2,
                                style: TextStyle(
                                    color: skin.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.5),
                                decoration: InputDecoration(
                                  hintText: 'z.B. Hauptbahnhof → Krankenhaus Mitte, Umweg über A9...',
                                  hintStyle: TextStyle(
                                      color: skin.surface(0.3),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Speichern ──
                    AnimatedOpacity(
                      opacity: canSave ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 200),
                      child: _GlassPrimaryButton(
                        skin: skin,
                        label: 'Fahrt speichern',
                        icon: Icons.save_rounded,
                        onTap: canSave ? _save : () {},
                        large: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZEIT BLOCK (Datum + Uhrzeit nebeneinander in einer Kachel)
// ─────────────────────────────────────────────────────────────────────────────

class _ZeitBlock extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final Color color;
  final String datumText;
  final String zeitText;
  final VoidCallback onDateTap;
  final VoidCallback onTimeTap;

  const _ZeitBlock({
    required this.skin,
    required this.label,
    required this.color,
    required this.datumText,
    required this.zeitText,
    required this.onDateTap,
    required this.onTimeTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.30), width: 1.0),
            boxShadow: [
              BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              // Datum-Chip
              GestureDetector(
                onTap: onDateTap,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: color),
                    const SizedBox(width: 6),
                    Text(datumText,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: skin.textPrimary)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              // Zeit-Chip
              GestureDetector(
                onTap: onTimeTap,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.access_time_outlined, size: 12, color: color),
                    const SizedBox(width: 6),
                    Text(zeitText,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: zeitText == '—' ? skin.surface(0.3) : skin.textPrimary)),
                  ]),
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
// BETRIEBSSTOFF CARD (kompakt, dreispaltig)
// ─────────────────────────────────────────────────────────────────────────────

class _BetriebsstoffCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final String unit;
  final TextEditingController ctrl;
  final Color color;

  const _BetriebsstoffCard({
    required this.skin,
    required this.icon,
    required this.label,
    required this.unit,
    required this.ctrl,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.8)),
              const SizedBox(height: 4),
              AnimatedBuilder(
                animation: ctrl,
                builder: (_, __) => TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '—',
                    hintStyle: TextStyle(color: skin.surface(0.25), fontSize: 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    suffix: Text(unit,
                        style: TextStyle(
                            color: skin.surface(0.35),
                            fontSize: 9,
                            fontWeight: FontWeight.w500)),
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
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _SectionLabel({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: skin.surface(0.38),
              letterSpacing: 1.2)),
      const SizedBox(width: 8),
      Expanded(
        child: Container(height: 0.5, color: skin.surface(0.12)),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KM INPUT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _KmInputCard extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final AppSkin skin;
  final Color color;
  final String? fotoPath;
  final VoidCallback onTap;
  final VoidCallback onCameraPressed;

  const _KmInputCard({
    required this.label,
    required this.ctrl,
    required this.skin,
    required this.color,
    required this.onTap,
    required this.onCameraPressed,
    this.fotoPath,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final isEmpty = ctrl.text.isEmpty;
        final br = BorderRadius.circular(20);
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: br,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                    : skin.bgCard.withValues(alpha: skin.glassOpacity),
                borderRadius: br,
                border: Border.all(
                  color: isEmpty ? skin.glassBorder : color.withValues(alpha: 0.38),
                  width: isEmpty ? 1.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(color: skin.glassShadow, blurRadius: 24, offset: const Offset(0, 6)),
                  BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                              letterSpacing: 1.2)),
                      GestureDetector(
                        onTap: onCameraPressed,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: fotoPath != null ? color.withValues(alpha: 0.15) : skin.surface(0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            fotoPath != null ? Icons.check_circle_rounded : Icons.camera_alt_outlined,
                            size: 14,
                            color: fotoPath != null ? color : skin.surface(0.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isEmpty ? '—' : '${ctrl.text} km',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isEmpty ? skin.surface(0.2) : skin.textPrimary,
                        letterSpacing: -0.5),
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
// INPUT ROW
// ─────────────────────────────────────────────────────────────────────────────

class _InputRow extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final TextCapitalization capitalize;
  final TextInputType? keyboardType;

  const _InputRow({
    required this.skin,
    required this.icon,
    required this.label,
    required this.ctrl,
    required this.hint,
    this.capitalize = TextCapitalization.none,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: skin.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: skin.primary,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: ctrl,
                      keyboardType: keyboardType,
                      textCapitalization: capitalize,
                      style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(color: skin.surface(0.3), fontSize: 15),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
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
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

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
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 11, color: skin.textMuted)),
              ],
            ),
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
        final startStop = ((h - (fadeFromBottom - 30)) / h).clamp(0.0, 1.0);
        final endStop = ((h - (fadeFromBottom - 70)) / h).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.white, Colors.white, Colors.black26, Colors.transparent, Colors.transparent],
          stops: [0.0, startStop, (startStop + endStop) / 2, endStop, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _GlassSheet extends StatelessWidget {
  final AppSkin skin;
  final Widget child;
  const _GlassSheet({required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: 0.82) : skin.bgSheet.withValues(alpha: 0.88),
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
      decoration: BoxDecoration(color: skin.surface(0.18), borderRadius: BorderRadius.circular(2)),
    );
  }
}

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
    final bgColor = skin.isLight ? skin.primary.withValues(alpha: 0.13) : skin.primary.withValues(alpha: 0.22);
    final borderColor = skin.isLight ? skin.primary.withValues(alpha: 0.28) : skin.primary.withValues(alpha: 0.45);
    final textColor = skin.isLight ? skin.primary.withValues(alpha: 0.90) : skin.primary.withValues(alpha: 0.85);
    final iconColor = skin.isLight ? skin.primary.withValues(alpha: 0.65) : skin.primary.withValues(alpha: 0.70);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: large ? 17 : 14, horizontal: 20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(large ? 20 : 14),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
            BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
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
          color: skin.isLight ? Colors.white.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.glassBorder, width: 1.0),
          boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6))],
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary)),
        ),
      ),
    );
  }
}