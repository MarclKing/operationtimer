import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_pickers.dart';
import '../services/night_shift_helper.dart';
import 'week_shift_strip.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entfernt: extension AppSkinGlass  → jetzt in glass_kit.dart (AppSkinGlass)
// Entfernt: GlassSurface            → jetzt in glass_kit.dart
// Entfernt: _GlassPrimaryButton     → jetzt GlassPrimaryButton in glass_kit.dart
// Entfernt: _GlassButton            → jetzt GlassSecondaryButton in glass_kit.dart
// Entfernt: _GlassSheet             → jetzt GlassSheet in glass_kit.dart
// Entfernt: _SheetHandle            → jetzt SheetHandle in glass_kit.dart
// Entfernt: _GlassIconBadge         → jetzt GlassIconBadge in glass_kit.dart
// Entfernt: _IOSTimePicker          → jetzt IOSTimePicker(confirmOnDismiss: false)
//                                      in glass_pickers.dart
// Entfernt: _selectDateWithPicker   → nutzt jetzt showSingleDatePicker aus
//                                      glass_pickers.dart
// ─────────────────────────────────────────────────────────────────────────────

enum _OverlayField { none, tkf, notiz }

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  const HomeScreen({
    super.key,
    required this.onNavigateToMonth,
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late DateTime _selectedDate;
  final _kommenController = TextEditingController();
  final _gehenController = TextEditingController();
  final _teamchefController = TextEditingController();
  final _notizController = TextEditingController();
  late AnimationController _saveAnimController;
  final _scrollController = ScrollController();

  _OverlayField _activeOverlay = _OverlayField.none;
  final FocusNode _tkfFocusNode = FocusNode();
  final FocusNode _notizFocusNode = FocusNode();

  late AnimationController _flyController;
  late Animation<double> _flyScale;
  late Animation<double> _flyOpacity;

  double _verticalDragStart = 0;
  bool _isDismissingKeyboard = false;

  String? _lastAlertMessage;
  DateTime? _lastAlertTime;

  VoidCallback? onOverlayStateChanged;
  bool get isOverlayOpen => _activeOverlay != _OverlayField.none;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _saveAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _flyController = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _flyOpacity = CurvedAnimation(parent: _flyController, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    _flyScale = CurvedAnimation(parent: _flyController, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
    _loadEntry();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate && widget.selectedDate != _selectedDate) {
      setState(() => _selectedDate = widget.selectedDate);
      _loadEntry();
    }
  }

  @override
  void deactivate() {
    _tkfFocusNode.unfocus();
    _notizFocusNode.unfocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _saveAnimController.dispose();
    _flyController.dispose();
    _kommenController.dispose();
    _gehenController.dispose();
    _teamchefController.dispose();
    _notizController.dispose();
    _scrollController.dispose();
    _tkfFocusNode.dispose();
    _notizFocusNode.dispose();
    super.dispose();
  }

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Guten Morgen';
    if (hour < 18) return 'Guten Tag';
    return 'Guten Abend';
  }

  String get _firstName {
    final box = Hive.box('einstellungen');
    final fullName = box.get('name', defaultValue: '') as String;
    if (fullName.trim().isEmpty) return '';
    return fullName.trim().split(' ').first;
  }

  String _getCurrentTimeFormatted() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _resetAllFieldsForToday() {
    _kommenController.text = _getCurrentTimeFormatted();
    _gehenController.clear();
    _teamchefController.clear();
    _notizController.clear();
  }

  void _resetTimeFieldsOnly() {
    _kommenController.text = _getCurrentTimeFormatted();
    _gehenController.clear();
  }

  void _loadEntry() => setState(() => _resetTimeFieldsOnly());

  void _setDate(DateTime date) {
    setState(() => _selectedDate = date);
    widget.onDateChanged(date);
    _loadEntry();
  }

  void _dismissKeyboardAndOverlay() {
    _tkfFocusNode.unfocus();
    _notizFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    if (_activeOverlay != _OverlayField.none) {
      _flyController.reverse();
      setState(() => _activeOverlay = _OverlayField.none);
      onOverlayStateChanged?.call();
    }
  }

  void closeOverlays() => _dismissKeyboardAndOverlay();

  Future<void> _closeOverlay() async {
    _tkfFocusNode.unfocus();
    _notizFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    await _flyController.reverse();
    if (mounted) {
      setState(() => _activeOverlay = _OverlayField.none);
      onOverlayStateChanged?.call();
    }
  }

  void _changeDate(int days) {
    _dismissKeyboardAndOverlay();
    _setDate(_selectedDate.add(Duration(days: days)));
  }

  TimeOfDay? _parseTime(String text) {
    if (text.isEmpty || text == '--:--') return null;
    try {
      final parts = text.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null;
    }
  }

  void _adjustTime(TextEditingController controller, int minutesDelta) {
    final isKommen = controller == _kommenController;
    final isGehen = controller == _gehenController;
    final current = _parseTime(controller.text) ?? TimeOfDay.now();
    final total = (current.hour * 60 + current.minute + minutesDelta).clamp(0, 23 * 60 + 59);
    final newHour = total ~/ 60;
    final newMinute = total % 60;

    final nightShiftEnabled = NightShiftHelper.isNightShiftEnabled();
    if (!nightShiftEnabled && isKommen && _gehenController.text.isNotEmpty) {
      final gehenTime = _parseTime(_gehenController.text);
      if (gehenTime != null && total > gehenTime.hour * 60 + gehenTime.minute) return;
    }
    if (!nightShiftEnabled && isGehen && _kommenController.text.isNotEmpty) {
      final kommenTime = _parseTime(_kommenController.text);
      if (kommenTime != null && total < kommenTime.hour * 60 + kommenTime.minute) return;
    }

    setState(() {
      controller.text = '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  void _onTimeCardDoubleTap(TextEditingController controller) {
    setState(() => controller.clear());
    HapticFeedback.selectionClick();
  }

  void _openOverlay(_OverlayField field) {
    if (_activeOverlay != _OverlayField.none) return;
    HapticFeedback.lightImpact();
    setState(() => _activeOverlay = field);
    onOverlayStateChanged?.call();
    _flyController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (field == _OverlayField.tkf) {
        FocusScope.of(context).requestFocus(_tkfFocusNode);
      } else {
        FocusScope.of(context).requestFocus(_notizFocusNode);
      }
    });
  }

  Future<bool> _checkDuplicateKommenTime(DateTime datum, String kommenTime) async {
    if (kommenTime.isEmpty) return false;
    final box = Hive.box('arbeitszeiten');
    final dateKey = DateFormat('yyyy-MM-dd').format(datum);
    final existingData = box.get(dateKey);
    if (existingData == null) return false;
    List<Map<String, dynamic>> entries = [];
    if (existingData is List) {
      entries = List<Map<String, dynamic>>.from(existingData);
    } else {
      entries = [Map<String, dynamic>.from(existingData)];
    }
    for (final entry in entries) {
      if ((entry['kommen'] ?? '') == kommenTime) return true;
    }
    return false;
  }

  void _saveEntry(BuildContext context) async {
    HapticFeedback.mediumImpact();
    if (_activeOverlay != _OverlayField.none) await _closeOverlay();

    final kommen = _kommenController.text.trim();
    final gehen = _gehenController.text.trim();
    final tkf = _teamchefController.text.trim();
    final notiz = _notizController.text.trim();

    if (kommen.isNotEmpty) {
      final isDuplicate = await _checkDuplicateKommenTime(_selectedDate, kommen);
      if (isDuplicate) {
        final skin = AppTheme.of(context);
        _showDebouncedSnackBar(context, '✗ Ein Eintrag mit dieser Kommen-Zeit existiert bereits', skin);
        return;
      }
    }

    final result = await NightShiftHelper.save(
      context: context,
      datum: _selectedDate,
      kommen: kommen,
      gehen: gehen,
      tkf: tkf,
      notiz: notiz,
    );

    if (result == SaveResult.saved || result == SaveResult.splitSaved) {
      await _saveAnimController.forward();
      await _saveAnimController.reverse();

      final isToday = _dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (isToday) _resetAllFieldsForToday();

      if (mounted) {
        final skin = AppTheme.of(context);
        final message = result == SaveResult.splitSaved
            ? '✓ Nachtschicht gespeichert (2 Einträge)'
            : '✓ Eintrag gespeichert';
        _showDebouncedSnackBar(context, message, skin);
      }
    }
  }

  void _showDebouncedSnackBar(BuildContext context, String message, AppSkin skin) {
    final now = DateTime.now();
    if (_lastAlertMessage == message && _lastAlertTime != null && now.difference(_lastAlertTime!) < const Duration(seconds: 2)) return;
    _lastAlertMessage = message;
    _lastAlertTime = now;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: skin.primary == Colors.white ? const Color(0xFF3DD6C8) : skin.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      duration: const Duration(milliseconds: 1500),
    ));
  }

  Future<void> _selectDateWithPicker() async {
    _dismissKeyboardAndOverlay();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final skin = AppTheme.of(context);

    // ── showSingleDatePicker aus glass_pickers.dart ──
    final result = await showSingleDatePicker(
      context: context,
      skin: skin,
      initialDate: _selectedDate,
      minimumDate: DateTime(2020),
      maximumDate: DateTime(2030),
    );
    if (result != null) _setDate(result);
  }

  Future<void> _selectTimeWithPicker(TextEditingController controller) async {
    _dismissKeyboardAndOverlay();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    final isKommen = controller == _kommenController;
    final isGehen = controller == _gehenController;
    final nightShiftEnabled = NightShiftHelper.isNightShiftEnabled();
    final skin = AppTheme.of(context);

    TimeOfDay? selectedTime;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // ── IOSTimePicker aus glass_pickers.dart
      // confirmOnDismiss: false = home_screen-Verhalten
      // (Zeit nur bei explizitem "Übernehmen"-Tap übernehmen) ──
      builder: (_) => IOSTimePicker(
        initialTime: _parseTime(controller.text) ?? TimeOfDay.now(),
        skin: skin,
        label: isKommen ? 'Uhrzeit Kommen' : 'Uhrzeit Gehen',
        confirmOnDismiss: false,
        onTimeSelected: (t) => selectedTime = t,
      ),
    );

    if (!mounted) return;
    if (selectedTime == null) return;
    final t = selectedTime!;
    final newMinutes = t.hour * 60 + t.minute;
    if (!nightShiftEnabled && isKommen && _gehenController.text.isNotEmpty) {
      final g = _parseTime(_gehenController.text);
      if (g != null && newMinutes > g.hour * 60 + g.minute) return;
    }
    if (!nightShiftEnabled && isGehen && _kommenController.text.isNotEmpty) {
      final k = _parseTime(_kommenController.text);
      if (k != null && newMinutes < k.hour * 60 + k.minute) return;
    }
    setState(() {
      controller.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey;
    final overlayOpen = _activeOverlay != _OverlayField.none;

    return Scaffold(
      backgroundColor: skin.bgBase,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onVerticalDragStart: (d) {
          _verticalDragStart = d.globalPosition.dy;
          _isDismissingKeyboard = false;
        },
        onVerticalDragUpdate: (d) {
          final delta = d.globalPosition.dy - _verticalDragStart;
          if (delta > 40 && !_isDismissingKeyboard) {
            _isDismissingKeyboard = true;
            _dismissKeyboardAndOverlay();
          }
        },
        onVerticalDragEnd: (_) => _isDismissingKeyboard = false,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            GestureDetector(
              onTap: overlayOpen ? _closeOverlay : null,
              behavior: HitTestBehavior.translucent,
              child: SafeArea(
                child: ListView(
                  controller: _scrollController,
                  physics: overlayOpen ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 40),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(_greeting, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: skin.surface(0.55))),
                            const SizedBox(width: 8),
                            const Text('👋', style: TextStyle(fontSize: 20)),
                          ]),
                          if (_firstName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(_firstName, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: -0.5)),
                          ],
                          const SizedBox(height: 6),
                          WeekShiftStrip(skin: skin),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // ── DATUMSKARTE ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GestureDetector(
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v < -300) _changeDate(1);
                          if (v > 300) _changeDate(-1);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isToday ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder,
                                width: isToday ? 1.5 : 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                                BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                              ],
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _changeDate(-1),
                                  child: const SizedBox(width: 44, height: 52,
                                      child: Center(child: Icon(Icons.chevron_left, size: 22))),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _selectDateWithPicker,
                                    onDoubleTap: () {
                                      HapticFeedback.selectionClick();
                                      _setDate(DateTime.now());
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            isToday ? 'HEUTE' : 'DATUM',
                                            style: TextStyle(
                                                fontSize: 9, fontWeight: FontWeight.w700,
                                                color: isToday ? skin.primary : skin.surface(0.35),
                                                letterSpacing: 1.2),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateFormat('EEEE, d. MMMM yyyy', 'de').format(_selectedDate),
                                            style: TextStyle(fontSize: 13, color: skin.textPrimary, fontWeight: FontWeight.w600),
                                            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _changeDate(1),
                                  child: SizedBox(width: 44, height: 52,
                                      child: Center(child: Icon(Icons.chevron_right, size: 22, color: skin.surface(0.5)))),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Zeit-Karten
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(children: [
                        Expanded(
                          child: _GlassTimeCard(
                            label: 'KOMMEN', color: skin.kommenColor, controller: _kommenController, skin: skin,
                            onTap: () => _selectTimeWithPicker(_kommenController),
                            onDoubleTap: () => _onTimeCardDoubleTap(_kommenController),
                            onSwipeUp: () => _adjustTime(_kommenController, 1),
                            onSwipeDown: () => _adjustTime(_kommenController, -1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _GlassTimeCard(
                            label: 'GEHEN', color: skin.gehenColor, controller: _gehenController, skin: skin,
                            onTap: () => _selectTimeWithPicker(_gehenController),
                            onDoubleTap: () => _onTimeCardDoubleTap(_gehenController),
                            onSwipeUp: () => _adjustTime(_gehenController, 1),
                            onSwipeDown: () => _adjustTime(_gehenController, -1),
                          ),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                      child: Text('Wischen · Tippen · Doppeltippen', style: TextStyle(fontSize: 11, color: skin.surface(0.28))),
                    ),
                    const SizedBox(height: 16),

                    // TKF-Karte
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GestureDetector(
                        onTap: () => _openOverlay(_OverlayField.tkf),
                        onDoubleTap: () {
                          setState(() => _teamchefController.clear());
                          HapticFeedback.selectionClick();
                        },
                        child: _GlassInputCard(
                          skin: skin, label: 'TAGESKOMMANDOFÜHRER', icon: Icons.person_outline_rounded,
                          controller: _teamchefController, hint: 'Name des TKF',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Notiz-Karte
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GestureDetector(
                        onTap: () => _openOverlay(_OverlayField.notiz),
                        onDoubleTap: () {
                          setState(() => _notizController.clear());
                          HapticFeedback.selectionClick();
                        },
                        child: _GlassInputCard(
                          skin: skin, label: 'NOTIZ', icon: Icons.edit_note_rounded,
                          controller: _notizController, hint: 'Optionale Notiz...',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Speichern-Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 1.0, end: 0.96).animate(
                            CurvedAnimation(parent: _saveAnimController, curve: Curves.easeInOut)),
                        // ── GlassPrimaryButton aus glass_kit.dart ──
                        child: GlassPrimaryButton(
                          skin: skin,
                          label: 'Eintrag speichern',
                          icon: Icons.save_rounded,
                          onTap: () => _saveEntry(context),
                          large: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),

            // Overlay-Dimmer
            if (overlayOpen)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _flyController,
                  builder: (_, __) => GestureDetector(
                    onTap: _closeOverlay,
                    child: Container(color: Colors.black.withValues(alpha: _flyOpacity.value * 0.55)),
                  ),
                ),
              ),

            // Flying Card Overlay
            if (overlayOpen)
              _FlyingCardOverlay(
                field: _activeOverlay,
                flyAnimation: _flyController,
                scaleAnim: _flyScale,
                opacityAnim: _flyOpacity,
                controller: _activeOverlay == _OverlayField.tkf ? _teamchefController : _notizController,
                focusNode: _activeOverlay == _OverlayField.tkf ? _tkfFocusNode : _notizFocusNode,
                onClose: _closeOverlay,
                onClear: () {
                  setState(() {
                    if (_activeOverlay == _OverlayField.tkf) _teamchefController.clear();
                    else _notizController.clear();
                  });
                  HapticFeedback.selectionClick();
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS ZEIT-KARTE (Kommen / Gehen)
// ─────────────────────────────────────────────────────────────────────────────

class _GlassTimeCard extends StatefulWidget {
  final String label;
  final Color color;
  final TextEditingController controller;
  final AppSkin skin;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  const _GlassTimeCard({
    required this.label, required this.color, required this.controller, required this.skin,
    required this.onTap, required this.onDoubleTap, required this.onSwipeUp, required this.onSwipeDown,
  });

  @override
  State<_GlassTimeCard> createState() => _GlassTimeCardState();
}

class _GlassTimeCardState extends State<_GlassTimeCard> {
  double _dragStart = 0;
  double _accumulated = 0;
  static const double _pxPerMin = 12;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onVerticalDragStart: (d) { _dragStart = d.localPosition.dy; _accumulated = 0; },
      onVerticalDragUpdate: (d) {
        _accumulated += _dragStart - d.localPosition.dy;
        _dragStart = d.localPosition.dy;
        while (_accumulated >= _pxPerMin) { _accumulated -= _pxPerMin; widget.onSwipeUp(); }
        while (_accumulated <= -_pxPerMin) { _accumulated += _pxPerMin; widget.onSwipeDown(); }
      },
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, __) {
          final skin = widget.skin;
          final isEmpty = widget.controller.text.isEmpty;
          final br = BorderRadius.circular(20);
          final baseColor = skin.isLight
              ? Colors.white.withValues(alpha: skin.glassOpacity)
              : skin.bgCard.withValues(alpha: skin.glassOpacity);

          return ClipRRect(
            borderRadius: br,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: br,
                border: Border.all(
                  color: isEmpty ? skin.glassBorder : widget.color.withValues(alpha: 0.38),
                  width: isEmpty ? 1.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                  BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.label,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: widget.color, letterSpacing: 1.2)),
                      // ── GlassIconBadge aus glass_kit.dart ──
                      GlassIconBadge(skin: skin, icon: Icons.unfold_more_rounded),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isEmpty ? '--:--' : widget.controller.text,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700,
                          color: isEmpty ? skin.surface(0.2) : skin.textPrimary, letterSpacing: -1),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS INPUT CARD (TKF / Notiz)
// ─────────────────────────────────────────────────────────────────────────────

class _GlassInputCard extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;

  const _GlassInputCard({required this.skin, required this.label, required this.icon, required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      // ── GlassSurface aus glass_kit.dart ──
      builder: (_, __) => GlassSurface(
        borderRadius: 20, useBlur: false,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 36, height: 36,
                child: Icon(icon, size: 20, color: skin.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: TextStyle(fontSize: 9, color: skin.primary, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                  const SizedBox(height: 3),
                  Text(controller.text.isEmpty ? hint : controller.text,
                      style: TextStyle(fontSize: 14,
                          fontWeight: controller.text.isEmpty ? FontWeight.w400 : FontWeight.w600,
                          color: controller.text.isEmpty ? skin.surface(0.3) : skin.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // ── GlassIconBadge aus glass_kit.dart ──
            GlassIconBadge(skin: skin, icon: Icons.edit_outlined),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLYING CARD OVERLAY (TKF / Notiz Eingabe)
// ─────────────────────────────────────────────────────────────────────────────

class _FlyingCardOverlay extends StatelessWidget {
  final _OverlayField field;
  final AnimationController flyAnimation;
  final Animation<double> scaleAnim;
  final Animation<double> opacityAnim;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final VoidCallback onClear;

  const _FlyingCardOverlay({
    required this.field, required this.flyAnimation, required this.scaleAnim, required this.opacityAnim,
    required this.controller, required this.focusNode, required this.onClose, required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isTkf = field == _OverlayField.tkf;
    final label = isTkf ? 'TAGESKOMMANDOFÜHRER' : 'NOTIZ';
    final icon = isTkf ? Icons.person_outline_rounded : Icons.edit_note_rounded;
    final hint = isTkf ? 'Name des TKF' : 'Optionale Notiz...';
    final screenH = MediaQuery.of(context).size.height;
    final cardTop = screenH * 0.22;

    return AnimatedBuilder(
      animation: flyAnimation,
      builder: (context, child) => Positioned(
        top: cardTop, left: 24.0, right: 24.0,
        child: Transform.scale(
          scale: 0.86 + scaleAnim.value * 0.14,
          child: Opacity(opacity: opacityAnim.value.clamp(0.0, 1.0), child: child!),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Container(
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: skin.glassBorder, width: 1.0),
              boxShadow: [
                BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                  child: Row(children: [
                    Icon(icon, size: 18, color: skin.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(label,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 1.0),
                          overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                    GestureDetector(
                      onTap: onClear,
                      // ── GlassIconBadge aus glass_kit.dart ──
                      child: GlassIconBadge(skin: skin, icon: Icons.backspace_outlined),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Divider(color: skin.glassBorder, height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: field == _OverlayField.notiz ? 3 : 1,
                    style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(color: skin.surface(0.22), fontSize: 17),
                      border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onClose(),
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