import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/night_shift_helper.dart';

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
  final GlobalKey _tkfCardKey = GlobalKey();
  final GlobalKey _notizCardKey = GlobalKey();

  late AnimationController _flyController;
  late Animation<double> _flyScale;
  late Animation<double> _flyOpacity;

  late AnimationController _glideController;
  late Animation<Offset> _glideOffset;

  double _verticalDragStart = 0;
  bool _isDismissingKeyboard = false;

  String? _lastAlertMessage;
  DateTime? _lastAlertTime;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    // NEU:
_flyController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 220),
);
_flyOpacity = CurvedAnimation(
  parent: _flyController,
  curve: Curves.easeOut,
  reverseCurve: Curves.easeIn,
);
_flyScale = CurvedAnimation(
  parent: _flyController,
  curve: Curves.easeOutBack,
  reverseCurve: Curves.easeInBack,
);
_glideController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 1),
);
_glideOffset = Tween<Offset>(
  begin: Offset.zero,
  end: Offset.zero,
).animate(_glideController);
    _loadEntry();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate &&
        widget.selectedDate != _selectedDate) {
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
    _glideController.dispose();
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

  void _loadEntry() {
    setState(() => _resetTimeFieldsOnly());
  }

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
      _glideController.reverse();
      setState(() => _activeOverlay = _OverlayField.none);
    }
  }

  void closeOverlays() => _dismissKeyboardAndOverlay();

  Future<void> _closeOverlay() async {
    _tkfFocusNode.unfocus();
    _notizFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    await Future.wait([
      _flyController.reverse(),
      _glideController.reverse(),
    ]);
    if (mounted) setState(() => _activeOverlay = _OverlayField.none);
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
    final total = (current.hour * 60 + current.minute + minutesDelta)
        .clamp(0, 23 * 60 + 59);
    final newHour = total ~/ 60;
    final newMinute = total % 60;

    final nightShiftEnabled = NightShiftHelper.isNightShiftEnabled();
    if (!nightShiftEnabled && isKommen && _gehenController.text.isNotEmpty) {
      final gehenTime = _parseTime(_gehenController.text);
      if (gehenTime != null &&
          total > gehenTime.hour * 60 + gehenTime.minute) return;
    }
    if (!nightShiftEnabled && isGehen && _kommenController.text.isNotEmpty) {
      final kommenTime = _parseTime(_kommenController.text);
      if (kommenTime != null &&
          total < kommenTime.hour * 60 + kommenTime.minute) return;
    }

    setState(() {
      controller.text =
          '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  void _onTimeCardDoubleTap(TextEditingController controller) {
    setState(() => controller.clear());
    HapticFeedback.selectionClick();
  }

  Offset _computeGlideOffset(GlobalKey cardKey) {
    final screenSize = MediaQuery.of(context).size;
    final targetTop = screenSize.height * 0.22;
    final targetCenterX = screenSize.width / 2;
    final targetCenterY = targetTop + 80;

    final box = cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    final cardPos = box.localToGlobal(Offset.zero);
    final cardSize = box.size;
    final cardCenterX = cardPos.dx + cardSize.width / 2;
    final cardCenterY = cardPos.dy + cardSize.height / 2;

    return Offset(targetCenterX - cardCenterX, targetCenterY - cardCenterY);
  }

  void _openOverlay(_OverlayField field) {
  if (_activeOverlay != _OverlayField.none) return;
  HapticFeedback.lightImpact();
  setState(() => _activeOverlay = field);
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

  Future<bool> _checkDuplicateKommenTime(
      DateTime datum, String kommenTime) async {
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
      final isDuplicate =
          await _checkDuplicateKommenTime(_selectedDate, kommen);
      if (isDuplicate) {
        final skin = AppTheme.of(context);
        _showDebouncedSnackBar(
            context, '✗ Ein Eintrag mit dieser Kommen-Zeit existiert bereits', skin);
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

      final isToday =
          _dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now());
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

  void _showDebouncedSnackBar(
      BuildContext context, String message, AppSkin skin) {
    final now = DateTime.now();
    if (_lastAlertMessage == message &&
        _lastAlertTime != null &&
        now.difference(_lastAlertTime!) < const Duration(seconds: 2)) return;
    _lastAlertMessage = message;
    _lastAlertTime = now;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: skin.primary == Colors.white
          ? const Color(0xFF3DD6C8)
          : skin.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      duration: const Duration(milliseconds: 1500),
    ));
  }

  Future<void> _selectDateWithPicker() async {
    _dismissKeyboardAndOverlay();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    final skin = AppTheme.of(context);
    DateTime tempDate = _selectedDate;
    UniqueKey pickerKey = UniqueKey();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
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
              Text('Datum auswählen',
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  key: pickerKey,
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: tempDate,
                  minimumDate: DateTime(2020),
                  maximumDate: DateTime(2030),
                  backgroundColor: Colors.transparent,
                  onDateTimeChanged: (d) => tempDate = d,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        tempDate = DateTime.now();
                        pickerKey = UniqueKey();
                        setDialogState(() {});
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: skin.borderSubtle),
                        ),
                        child: Center(
                            child: Text('Heute',
                                style: TextStyle(
                                    color: skin.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _setDate(tempDate);
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(4, 0, 16, 0),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: skin.gradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                            child: Text('Übernehmen',
                                style: TextStyle(
                                    color: skin.onGradient,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
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
    builder: (_) => _IOSTimePicker(
  initialTime: _parseTime(controller.text) ?? TimeOfDay.now(),
  skin: skin,
  label: isKommen ? 'Uhrzeit Kommen' : 'Uhrzeit Gehen',   // ← NEU
  onTimeSelected: (t) {
    selectedTime = t;
  },
),
  );

  // Wird nach Schließen (egal ob per Button oder Tipp daneben) ausgeführt:
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
    controller.text =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  });
}

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isToday =
        DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey;
    final isChromeSkin = skin.key == 'chrome';
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
                  physics: overlayOpen
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 80),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(_greeting,
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: skin.surface(0.7))),
                            const SizedBox(width: 8),
                            const Text('👋',
                                style: TextStyle(fontSize: 20)),
                          ]),
                          if (_firstName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(_firstName,
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: skin.primary)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(children: [
                        _NavBtn(
                            icon: Icons.chevron_left,
                            onTap: () => _changeDate(-1)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: _selectDateWithPicker,
                            onDoubleTap: () {
                              HapticFeedback.selectionClick();
                              _setDate(DateTime.now());
                            },
                            // Horizontales Wischen auf der Datumskarte
                            // → nur Datum ändern, NICHT Seite wechseln
                            onHorizontalDragEnd: (d) {
                              final v = d.primaryVelocity ?? 0;
                              if (v < -300) _changeDate(1);
                              if (v > 300) _changeDate(-1);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: skin.bgCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isToday
                                      ? skin.primaryWithAlpha(0.5)
                                      : skin.surface(0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('📅',
                                      style: TextStyle(fontSize: 14)),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isToday ? 'HEUTE' : 'DATUM',
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: isToday
                                                  ? skin.primary
                                                  : skin.surface(0.38),
                                              letterSpacing: 1.0),
                                        ),
                                        Text(
                                          DateFormat(
                                                  'EEEE, d. MMMM yyyy',
                                                  'de')
                                              .format(_selectedDate),
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: skin.textPrimary,
                                              fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _NavBtn(
                            icon: Icons.chevron_right,
                            onTap: () => _changeDate(1)),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(children: [
                        Expanded(
                          child: _SwipeTimeCard(
                            label: 'KOMMEN',
                            color: skin.kommenColor,
                            controller: _kommenController,
                            onTap: () =>
                                _selectTimeWithPicker(_kommenController),
                            onDoubleTap: () =>
                                _onTimeCardDoubleTap(_kommenController),
                            onSwipeUp: () =>
                                _adjustTime(_kommenController, 1),
                            onSwipeDown: () =>
                                _adjustTime(_kommenController, -1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SwipeTimeCard(
                            label: 'GEHEN',
                            color: skin.gehenColor,
                            controller: _gehenController,
                            onTap: () =>
                                _selectTimeWithPicker(_gehenController),
                            onDoubleTap: () =>
                                _onTimeCardDoubleTap(_gehenController),
                            onSwipeUp: () =>
                                _adjustTime(_gehenController, 1),
                            onSwipeDown: () =>
                                _adjustTime(_gehenController, -1),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text('Wischen - Tippen - Doppeltippen',
                          style: TextStyle(
                              fontSize: 11, color: skin.surface(0.3))),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GestureDetector(
  key: _tkfCardKey,
  onTap: () => _openOverlay(_OverlayField.tkf),
  onDoubleTap: () {
    setState(() => _teamchefController.clear());
    HapticFeedback.selectionClick();
  },
                        child: AnimatedOpacity(
                          opacity: _activeOverlay == _OverlayField.tkf
                              ? 0.0
                              : (_activeOverlay == _OverlayField.notiz
                                  ? 0.3
                                  : 1.0),
                          duration: const Duration(milliseconds: 200),
                          child: _StaticInputCard(
                            label: 'TAGESKOMMANDOFÜHRER',
                            emoji: '👤',
                            controller: _teamchefController,
                            hint: 'Name des TKF',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GestureDetector(
  key: _notizCardKey,
  onTap: () => _openOverlay(_OverlayField.notiz),
  onDoubleTap: () {
    setState(() => _notizController.clear());
    HapticFeedback.selectionClick();
  },
                        child: AnimatedOpacity(
                          opacity: _activeOverlay == _OverlayField.notiz
                              ? 0.0
                              : (_activeOverlay == _OverlayField.tkf
                                  ? 0.3
                                  : 1.0),
                          duration: const Duration(milliseconds: 200),
                          child: _StaticInputCard(
                            label: 'NOTIZ',
                            emoji: '📝',
                            controller: _notizController,
                            hint: 'Optionale Notiz...',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 24),
  child: ScaleTransition(
    scale: Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
          parent: _saveAnimController,
          curve: Curves.easeInOut),
    ),
    child: GestureDetector(
      onTap: () => _saveEntry(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: skin.gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: skin.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.save_rounded, color: skin.onGradient, size: 20),
            const SizedBox(width: 8),
            Text(
              'Eintrag speichern',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: skin.onGradient,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
),
const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            if (_activeOverlay != _OverlayField.none)
              _FlyingCardOverlay(
                field: _activeOverlay,
                flyAnimation: _flyController,
                glideController: _glideController,
                glideOffset: _glideOffset,
                scaleAnim: _flyScale,
                opacityAnim: _flyOpacity,
                controller: _activeOverlay == _OverlayField.tkf
                    ? _teamchefController
                    : _notizController,
                focusNode: _activeOverlay == _OverlayField.tkf
                    ? _tkfFocusNode
                    : _notizFocusNode,
                onClose: _closeOverlay,
                onClear: () {
                  setState(() {
                    if (_activeOverlay == _OverlayField.tkf) {
                      _teamchefController.clear();
                    } else {
                      _notizController.clear();
                    }
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

// ─── Flying Card, StaticInputCard, NavBtn, IOSTimePicker, SwipeTimeCard ──────
// (identisch zu deiner letzten Version – komplett unverändert)

class _FlyingCardOverlay extends StatelessWidget {
  final _OverlayField field;
  final AnimationController flyAnimation;
  final AnimationController glideController;
  final Animation<Offset> glideOffset;
  final Animation<double> scaleAnim;
  final Animation<double> opacityAnim;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final VoidCallback onClear;

  const _FlyingCardOverlay({
    required this.field,
    required this.flyAnimation,
    required this.glideController,
    required this.glideOffset,
    required this.scaleAnim,
    required this.opacityAnim,
    required this.controller,
    required this.focusNode,
    required this.onClose,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isTkf = field == _OverlayField.tkf;
    final label = isTkf ? 'TAGESKOMMANDOFÜHRER' : 'NOTIZ';
    final emoji = isTkf ? '👤' : '📝';
    final hint = isTkf ? 'Name des TKF' : 'Optionale Notiz...';
    final screenH = MediaQuery.of(context).size.height;
    final cardTop = screenH * 0.22;

    return AnimatedBuilder(
  animation: flyAnimation,
  builder: (context, child) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onClose,
          child: Opacity(
            opacity: opacityAnim.value * 0.55,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
        Positioned(
  top: cardTop,
  left: 24.0,
  right: 24.0,
  child: Transform.scale(
    scale: 0.85 + scaleAnim.value * 0.15,
    child: Opacity(
      opacity: opacityAnim.value.clamp(0.0, 1.0),
      child: child!,
    ),
  ),
),
      ],
    );
  },

      child: Container(
        decoration: BoxDecoration(
          color: skin.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: skin.primaryWithAlpha(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: skin.primary.withValues(alpha: 0.18),
                blurRadius: 32,
                spreadRadius: 2,
                offset: const Offset(0, 8)),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: skin.primaryWithAlpha(0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 15))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: skin.primary,
                          letterSpacing: 1.0),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ),
                GestureDetector(
                  onTap: onClear,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: skin.surface(0.06),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.backspace_outlined,
                        size: 16, color: skin.surface(0.4)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        gradient: skin.gradient,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('Fertig',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: skin.onGradient)),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child:
                  Divider(color: skin.primaryWithAlpha(0.12), height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: field == _OverlayField.notiz ? 3 : 1,
                style: TextStyle(
                    color: skin.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      TextStyle(color: skin.surface(0.25), fontSize: 17),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onClose(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticInputCard extends StatelessWidget {
  final String label;
  final String emoji;
  final TextEditingController controller;
  final String hint;

  const _StaticInputCard({
    required this.label,
    required this.emoji,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: skin.surface(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: skin.surface(0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: skin.primaryWithAlpha(0.15),
                  borderRadius: BorderRadius.circular(9)),
              child: Center(
                  child:
                      Text(emoji, style: const TextStyle(fontSize: 14))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 9,
                          color: skin.primary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  const SizedBox(height: 2),
                  Text(
                    controller.text.isEmpty ? hint : controller.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: controller.text.isEmpty
    ? skin.surface(0.35)
    : skin.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 15, color: skin.surface(0.25)),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});

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
          border: Border.all(color: skin.surface(0.1)),
        ),
        child: Icon(icon, color: skin.surface(0.54), size: 22),
      ),
    );
  }
}

class _IOSTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final AppSkin skin;
  final Function(TimeOfDay) onTimeSelected;
  final String label;          // ← NEU

  const _IOSTimePicker({
    required this.initialTime,
    required this.skin,
    required this.onTimeSelected,
    this.label = 'Uhrzeit auswählen',   // ← NEU
  });

  @override
  State<_IOSTimePicker> createState() => _IOSTimePickerState();
}

class _IOSTimePickerState extends State<_IOSTimePicker> {
  late int _selectedHour;
  late int _selectedMinute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  static const int _hourLoopOffset = 500;
  static const int _minuteLoopOffset = 500;

  @override
  void initState() {
    super.initState();
    _selectedHour = widget.initialTime.hour;
    _selectedMinute = widget.initialTime.minute;
    _hourController = FixedExtentScrollController(
        initialItem: _hourLoopOffset * 24 + _selectedHour);
    _minuteController = FixedExtentScrollController(
        initialItem: _minuteLoopOffset * 60 + _selectedMinute);
  }

  // NEU – dispose() ruft onTimeSelected NICHT mehr auf:
@override
void dispose() {
  _hourController.dispose();
  _minuteController.dispose();
  super.dispose();
}

  void _setCurrentTime() {
    final now = DateTime.now();
    final nowHour = now.hour;
    final nowMinute = now.minute;

    final currentHourIdx = _hourController.selectedItem;
    final currentHourBase = (currentHourIdx ~/ 24) * 24;
    int targetHourIdx = currentHourBase + nowHour;
    if (targetHourIdx < currentHourIdx) targetHourIdx += 24;

    final currentMinuteIdx = _minuteController.selectedItem;
    final currentMinuteBase = (currentMinuteIdx ~/ 60) * 60;
    int targetMinuteIdx = currentMinuteBase + nowMinute;
    if (targetMinuteIdx < currentMinuteIdx) targetMinuteIdx += 60;

    _hourController.animateToItem(targetHourIdx,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    _minuteController.animateToItem(targetMinuteIdx,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);

    setState(() {
      _selectedHour = nowHour;
      _selectedMinute = nowMinute;
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Container(
      decoration: BoxDecoration(
        color: skin.bgSheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: skin.surface(0.08)),
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
          Text(
  widget.label,
  style: TextStyle(
      color: skin.textPrimary,
      fontSize: 17,
      fontWeight: FontWeight.w600),
),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Row(children: [
              Expanded(
                child: CupertinoPicker(
                  scrollController: _hourController,
                  magnification: 1.2,
                  backgroundColor: Colors.transparent,
                  itemExtent: 40,
                  looping: true,
                  onSelectedItemChanged: (index) =>
                      setState(() => _selectedHour = index % 24),
                  children: List.generate(
                      24,
                      (h) => Center(
                            child: Text(h.toString().padLeft(2, '0'),
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedHour == h
                                        ? skin.primary
                                        : skin.surface(0.6))),
                          )),
                ),
              ),
              Text(':',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: skin.primary)),
              Expanded(
                child: CupertinoPicker(
                  scrollController: _minuteController,
                  magnification: 1.2,
                  backgroundColor: Colors.transparent,
                  itemExtent: 40,
                  looping: true,
                  onSelectedItemChanged: (index) =>
                      setState(() => _selectedMinute = index % 60),
                  children: List.generate(
                      60,
                      (m) => Center(
                            child: Text(m.toString().padLeft(2, '0'),
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedMinute == m
                                        ? skin.primary
                                        : skin.surface(0.6))),
                          )),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _setCurrentTime,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: skin.surface(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: skin.primary.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.access_time,
                              color: skin.primary, size: 18),
                          const SizedBox(width: 6),
                          Text('Jetzt',
                              style: TextStyle(
                                  color: skin.primary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  widget.onTimeSelected(TimeOfDay(
                      hour: _selectedHour, minute: _selectedMinute));
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                      gradient: skin.gradient,
                      borderRadius: BorderRadius.circular(14)),
                  child: Center(
                      child: Text('Übernehmen',
                          style: TextStyle(
                              color: skin.onGradient,
                              fontSize: 16,
                              fontWeight: FontWeight.w700))),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _SwipeTimeCard extends StatefulWidget {
  final String label;
  final Color color;
  final TextEditingController controller;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  const _SwipeTimeCard({
    required this.label,
    required this.color,
    required this.controller,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  @override
  State<_SwipeTimeCard> createState() => _SwipeTimeCardState();
}

class _SwipeTimeCardState extends State<_SwipeTimeCard> {
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
  animation: widget.controller,
  builder: (context, __) {
    final skin = AppTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
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
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: widget.color,
                      letterSpacing: 1.2)),
              Icon(Icons.unfold_more,
                  color: widget.color.withValues(alpha: 0.5), size: 16),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              widget.controller.text.isEmpty
                  ? '--:--'
                  : widget.controller.text,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: skin.textPrimary,
                  letterSpacing: -1),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  },
),
    );
  }
}