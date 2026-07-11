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
import '../widgets/glass_kit.dart';
import '../widgets/glass_pickers.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/glass_dialogs.dart';
import '../services/night_shift_helper.dart';
import '../services/pdf_service.dart';
import '../services/sync_service.dart';
import '../services/travel_mode_service.dart';
import '../utils/time_rounding.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MonthScreen
// Enthält oben den HomeScreen-Inhalt (Zeiterfassung), dann eine Spring-Barriere
// und darunter die vollständige Monatsübersicht.
// home_screen.dart bleibt unverändert für spätere Nutzung.
// ─────────────────────────────────────────────────────────────────────────────

enum _OverlayField { none, tkf, notiz }
enum _MonthTab { zeit, monat }

class _GlassSegmentSwitcher extends StatelessWidget {
  final AppSkin skin;
  final _MonthTab active;
  final ValueChanged<_MonthTab> onChanged;

  const _GlassSegmentSwitcher({
    required this.skin,
    required this.active,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: BorderRadius.circular(18),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                _segment(
                  label: 'Zeiterfassung',
                  icon: Icons.access_time_rounded,
                  tab: _MonthTab.zeit,
                ),
                _segment(
                  label: 'Monatsübersicht',
                  icon: Icons.calendar_month_rounded,
                  tab: _MonthTab.monat,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required _MonthTab tab,
  }) {
    final isActive = active == tab;
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          HapticFeedback.selectionClick();
          onChanged(tab);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? skin.primary.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? skin.primary.withValues(alpha: 0.45) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive ? skin.primary : skin.surface(0.4),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? skin.primary : skin.surface(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class MonthScreenState extends State<MonthScreen> with TickerProviderStateMixin {

  // ── Tab-Switcher ───────────────────────────────────────────────────────────
  _MonthTab _activeTab = _MonthTab.zeit;
  final ScrollController _scrollController = ScrollController();

  // ── HomeScreen State ──────────────────────────────────────────────────────
  late DateTime _selectedDate;
  final _kommenController = TextEditingController();
  final _gehenController = TextEditingController();
  final _teamchefController = TextEditingController();
  final _notizController = TextEditingController();
  late AnimationController _saveAnimController;

  // ── Reisemodus: gewählte Zonen für Kommen/Gehen im Zeiterfassungs-Tab ──
  String? _kommenTzSelected;
  String? _gehenTzSelected;

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

  /// Aktuelle Rundungsstufe aus den Einstellungen (in Minuten pro Swipe-Schritt).
  int get _roundStep {
    final rule = Hive.box('einstellungen')
        .get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;
    return TimeRounding.stepMinutes(rule);
  }

  // ── MonthScreen State ─────────────────────────────────────────────────────
  late DateTime _selectedMonth;
  final Map<String, GlobalKey<GlassSwipeCardState>> _rowKeys = {};
  String? _openSwipedEntryId;

  final Map<String, DateTime> _lastSnackbarTime = {};
  static const Duration _snackbarCooldown = Duration(seconds: 5);

  // ─────────────────────────────────────────────────────────────────────────
  // Init / Dispose
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedMonth = widget.selectedMonth;

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTravelModeTz());

    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _flyOpacity = CurvedAnimation(
      parent: _flyController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _flyScale = CurvedAnimation(
      parent: _flyController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );
    _loadHomeEntry();
  }

  @override
  void didUpdateWidget(MonthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMonth != widget.selectedMonth &&
        widget.selectedMonth != _selectedMonth) {
      setState(() => _selectedMonth = widget.selectedMonth);
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

  // ─────────────────────────────────────────────────────────────────────────
  // Public API (für MainScreen)
  // ─────────────────────────────────────────────────────────────────────────

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _activeTab = _MonthTab.zeit);
  }

  void closeAllRows() {
    for (final key in _rowKeys.values) {
      key.currentState?.close();
    }
  }

  void closeOverlays() => _dismissKeyboardAndOverlay();

  bool get isOverlayOpen => _activeOverlay != _OverlayField.none;

  // ─────────────────────────────────────────────────────────────────────────
  // HomeScreen Logik
  // ─────────────────────────────────────────────────────────────────────────

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  String _getCurrentTimeFormatted() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _resetAllFieldsForToday() {
    _kommenController.text = _getCurrentTimeFormatted();
    _gehenController.clear();
    _teamchefController.clear();
    _notizController.clear();
    _kommenTzSelected = TravelModeService.isEnabled ? TravelModeService.activeTzId : null;
    _gehenTzSelected = _kommenTzSelected;
  }

  void _resetTimeFieldsOnly() {
    _kommenController.text = _getCurrentTimeFormatted();
    _gehenController.clear();
    _kommenTzSelected = TravelModeService.isEnabled ? TravelModeService.activeTzId : null;
    _gehenTzSelected = _kommenTzSelected;
  }

  void _loadHomeEntry() => setState(() => _resetTimeFieldsOnly());

  void _setDate(DateTime date) {
    setState(() => _selectedDate = date);
    _loadHomeEntry();
  }

  Future<void> _pickZoneForField({required bool isKommen}) async {
    _dismissKeyboardAndOverlay();
    final skin = AppTheme.of(context);
    final current = isKommen ? _kommenTzSelected : _gehenTzSelected;
    final result = await _showZonePickerSheet(
      context: context,
      skin: skin,
      currentTzId: current,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isKommen) {
        _kommenTzSelected = result;
      } else {
        _gehenTzSelected = result;
      }
    });
    await TravelModeService.setActiveTz(result);
  }

  void _dismissKeyboardAndOverlay() {
    _tkfFocusNode.unfocus();
    _notizFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    if (_activeOverlay != _OverlayField.none) {
      _flyController.reverse();
      setState(() => _activeOverlay = _OverlayField.none);
    }
  }

  Future<void> _closeOverlay() async {
    _tkfFocusNode.unfocus();
    _notizFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    await _flyController.reverse();
    if (mounted) setState(() => _activeOverlay = _OverlayField.none);
  }

  void _changeDate(int days) {
    _dismissKeyboardAndOverlay();
    _setDate(_selectedDate.add(Duration(days: days)));
  }

  TimeOfDay? _parseHomeTime(String text) {
    if (text.isEmpty || text == '--:--') return null;
    try {
      final parts = text.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null;
    }
  }

   void _adjustHomeTime(TextEditingController controller, int direction) {
    final isKommen = controller == _kommenController;
    final isGehen = controller == _gehenController;
    final current = _parseHomeTime(controller.text) ?? TimeOfDay.now();
    final rule = Hive.box('einstellungen')
        .get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;
    final total = TimeRounding.steppedTotal(
        current.hour * 60 + current.minute, rule, direction);
    final newHour = total ~/ 60;
    final newMinute = total % 60;

    final nightShiftEnabled = NightShiftHelper.isNightShiftEnabled();
    if (!nightShiftEnabled && isKommen && _gehenController.text.isNotEmpty) {
      final g = _parseHomeTime(_gehenController.text);
      if (g != null && total > g.hour * 60 + g.minute) return;
    }
    if (!nightShiftEnabled && isGehen && _kommenController.text.isNotEmpty) {
      final k = _parseHomeTime(_kommenController.text);
      if (k != null && total < k.hour * 60 + k.minute) return;
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
          context,
          '✗ Ein Eintrag mit dieser Kommen-Zeit existiert bereits',
          skin,
        );
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
      kommenTz: _kommenTzSelected,
      gehenTz: _gehenTzSelected,
    );

    if (result == SaveResult.saved || result == SaveResult.splitSaved) {
      await _saveAnimController.forward();
      await _saveAnimController.reverse();

      await SyncService.instance.pushArbeitszeit(_dateKey);

      final isToday =
          _dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (isToday) _resetAllFieldsForToday();

      if (mounted) {
        final skin = AppTheme.of(context);
        final message = result == SaveResult.splitSaved
            ? '✓ Nachtschicht gespeichert (2 Einträge)'
            : '✓ Eintrag gespeichert';
        _showDebouncedSnackBar(context, message, skin);
        setState(() {});
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

    final isError = message.startsWith('✗');
    showGlassSnackBar(
      context,
      message,
      type: isError ? GlassSnackBarType.error : GlassSnackBarType.success,
      duration: const Duration(milliseconds: 1800),
    );
  }

  Future<void> _selectDateWithPicker() async {
    _dismissKeyboardAndOverlay();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final skin = AppTheme.of(context);
    final result = await showSingleDatePicker(
      context: context,
      skin: skin,
      initialDate: _selectedDate,
      minimumDate: DateTime(2020),
      maximumDate: DateTime(2030),
    );
    if (result != null) _setDate(result);
  }

Future<void> _checkTravelModeTz() async {
    // Aktualisiert nur die erkannte Geräte-Zone (für die Vorschläge im
    // Zonen-Picker) — kein Dialog, keine Bestätigung nötig. Die
    // erkannte Zone taucht im Picker einfach oben in der Liste auf.
    await TravelModeService.checkForTimeZoneChange();
    if (mounted) setState(() {});
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
      builder: (_) => IOSTimePicker(
        initialTime: _parseHomeTime(controller.text) ?? TimeOfDay.now(),
        skin: skin,
        label: isKommen ? 'Uhrzeit Kommen' : 'Uhrzeit Gehen',
        confirmOnDismiss: false,
        minuteInterval: _roundStep,
        onTimeSelected: (t) => selectedTime = t,
      ),
    );

    if (!mounted) return;
    if (selectedTime == null) return;
    final rundungRule = Hive.box('einstellungen')
        .get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;
    final t = TimeRounding.roundTimeOfDay(selectedTime!, rundungRule);
    final newMinutes = t.hour * 60 + t.minute;
    if (!nightShiftEnabled && isKommen && _gehenController.text.isNotEmpty) {
      final g = _parseHomeTime(_gehenController.text);
      if (g != null && newMinutes > g.hour * 60 + g.minute) return;
    }
    if (!nightShiftEnabled && isGehen && _kommenController.text.isNotEmpty) {
      final k = _parseHomeTime(_kommenController.text);
      if (k != null && newMinutes < k.hour * 60 + k.minute) return;
    }
    setState(() {
      controller.text =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MonthScreen Logik
  // ─────────────────────────────────────────────────────────────────────────

  void _showSnackbar(String message, Color color) {
    final now = DateTime.now();
    final last = _lastSnackbarTime[message];
    if (last != null && now.difference(last) < _snackbarCooldown) return;
    _lastSnackbarTime[message] = now;

    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final isDelete = color == AppTheme.of(context).deleteColor;
    final isError = message.startsWith('✗');
    final type = isDelete
        ? GlassSnackBarType.error
        : isError
            ? GlassSnackBarType.error
            : GlassSnackBarType.success;

    showGlassSnackBar(context, message, type: type);
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
    key?.currentState?.animateOutAndDelete(() {});  // nur Animation, kein Delete mehr hier
  }

void _editEntry(Map<String, dynamic> entry) {
  closeAllRows();
  final datum = DateTime.parse(entry['datum']);
  final kommenCtrl = TextEditingController(text: entry['kommen'] ?? '');

  // Bei Zonen-Überquerung die ROHE Gehen-Zeit anzeigen (passend zur
  // Gehen-Zone), sonst die normal gespeicherte Zeit.
  final gehenRaw = entry['gehenRaw'] as String?;
  final gehenCtrl = TextEditingController(text: gehenRaw ?? entry['gehen'] ?? '');

  final tkfCtrl = TextEditingController(text: entry['TKF'] ?? '');
  final notizCtrl = TextEditingController(text: entry['Bemerkung'] ?? entry['notiz'] ?? '');
  final entryId = entry['id'] as String;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditSheet(
      datum: datum,
      entryId: entryId,
      entry: entry,
      kommenCtrl: kommenCtrl,
      gehenCtrl: gehenCtrl,
      tkfCtrl: tkfCtrl,
      notizCtrl: notizCtrl,
      onSave: (kommenTz, gehenTz) async {
        await NightShiftHelper.save(
          context: context,
          datum: datum,
          kommen: kommenCtrl.text,
          gehen: gehenCtrl.text,
          tkf: tkfCtrl.text,
          notiz: notizCtrl.text,
          existingId: entryId,
          kommenTz: kommenTz,
          gehenTz: gehenTz,
        );
        if (!mounted) return;
        setState(() {});
        Navigator.pop(context);
        final skin = AppTheme.of(context);
        _showSnackbar('Aktualisiert ✓', skin.primary);
      },
    ),
  );
}

  Future<void> _shareEntry(Map<String, dynamic> entry) async {
    closeAllRows();
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
    final notiz = entry['Bemerkung'] ?? entry['notiz'] ?? '';

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
                    borderRadius: pw.BorderRadius.circular(8)),
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
                          style: pw.TextStyle(
                              font: fontBold, fontSize: 26)),
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
                          style: pw.TextStyle(
                              font: fontBold, fontSize: 26)),
                    ]),
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
            pw.Text('Bemerkung: $notiz',
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

  Future<void> _showMonthPicker() async {
    closeAllRows();
    final skin = AppTheme.of(context);
    final result = await showMonthYearPicker(
      context: context,
      skin: skin,
      initialMonth: _selectedMonth,
    );
    if (result != null) _setMonth(result);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final overlayOpen = _activeOverlay != _OverlayField.none;
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;

    final entries = _getEntriesForMonth();
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    final daysInMonth =
        DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);
    final offeneEntries = entries.where((e) => !_isEntryComplete(e)).length;

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
              child: Column(
                children: [
                  // ── Titel + Segment-Switcher (fix, scrollt nicht) ──
                  SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 50),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Text('Arbeitszeit',
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: skin.textPrimary)),
                              if (TravelModeService.isEnabled) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.public_rounded, size: 20, color: skin.primary),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _GlassSegmentSwitcher(
                            skin: skin,
                            active: _activeTab,
                            onChanged: (tab) {
                              FocusScope.of(context).unfocus();
                              setState(() => _activeTab = tab);
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),

                  // ── Inhalt je aktivem Tab ──
                  Expanded(
                    child: IndexedStack(
                      index: _activeTab == _MonthTab.zeit ? 0 : 1,
                      children: [
                        _buildZeiterfassungTab(skin),
                        _buildMonatsuebersichtTab(skin, entries, monthName,
                            daysInMonth, offeneEntries, bottomNavHeight),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (overlayOpen)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _flyController,
                  builder: (_, __) => GestureDetector(
                    onTap: _closeOverlay,
                    child: Container(
                        color: Colors.black
                            .withValues(alpha: _flyOpacity.value * 0.55)),
                  ),
                ),
              ),

            if (overlayOpen)
              _FlyingCardOverlay(
                field: _activeOverlay,
                flyAnimation: _flyController,
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

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: Zeiterfassung
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildZeiterfassungTab(AppSkin skin) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Datumskarte
GlassNavCard(
  onPrevious: () => _changeDate(-1),
  onNext: () => _changeDate(1),
  onTap: _selectDateWithPicker,
  onDoubleTap: () {
    HapticFeedback.selectionClick();
    _setDate(DateTime.now());
  },
  onSwipe: (v) {
    if (v < -300) _changeDate(1);
    if (v > 300) _changeDate(-1);
  },
  highlighted: DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey,
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey
            ? 'HEUTE' : 'DATUM',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey
              ? skin.primary : skin.surface(0.35),
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        DateFormat('EEEE, d. MMMM yyyy', 'de').format(_selectedDate),
        style: TextStyle(fontSize: 13, color: skin.textPrimary, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    ],
  ),
),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(
                child: _GlassTimeCard(
                  label: 'KOMMEN',
                  color: skin.kommenColor,
                  controller: _kommenController,
                  skin: skin,
                  onTap: () => _selectTimeWithPicker(_kommenController),
                  onDoubleTap: () => _onTimeCardDoubleTap(_kommenController),
                  onSwipeUp: () => _adjustHomeTime(_kommenController, 1),
                  onSwipeDown: () => _adjustHomeTime(_kommenController, -1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GlassTimeCard(
                  label: 'GEHEN',
                  color: skin.gehenColor,
                  controller: _gehenController,
                  skin: skin,
                  onTap: () => _selectTimeWithPicker(_gehenController),
                  onDoubleTap: () => _onTimeCardDoubleTap(_gehenController),
                  onSwipeUp: () => _adjustHomeTime(_gehenController, 1),
                  onSwipeDown: () => _adjustHomeTime(_gehenController, -1),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
              child: Text('Wischen · Tippen · Doppeltippen',
                  style: TextStyle(fontSize: 11, color: skin.surface(0.28))),
            ),
            const SizedBox(height: 16),

            if (TravelModeService.isEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ZoneChip(
                      skin: skin,
                      tzId: _kommenTzSelected,
                      onTap: () => _pickZoneForField(isKommen: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ZoneChip(
                      skin: skin,
                      tzId: _gehenTzSelected,
                      onTap: () => _pickZoneForField(isKommen: false),
                    ),
                  ),
                ],
              ),
            ],

            GestureDetector(
              onTap: () => _openOverlay(_OverlayField.tkf),
              onDoubleTap: () {
                setState(() => _teamchefController.clear());
                HapticFeedback.selectionClick();
              },
              child: _GlassInputCard(
                skin: skin,
                label: 'TAGESKOMMANDOFÜHRER',
                icon: Icons.person_outline_rounded,
                controller: _teamchefController,
                hint: 'Name des TKF',
              ),
            ),
            const SizedBox(height: 10),

            GestureDetector(
              onTap: () => _openOverlay(_OverlayField.notiz),
              onDoubleTap: () {
                setState(() => _notizController.clear());
                HapticFeedback.selectionClick();
              },
              child: _GlassInputCard(
                skin: skin,
                label: 'Bemerkung',
                icon: Icons.edit_note_rounded,
                controller: _notizController,
                hint: 'Optionale Bemerkung...',
              ),
            ),
            const SizedBox(height: 24),

            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 0.96).animate(
                  CurvedAnimation(
                      parent: _saveAnimController, curve: Curves.easeInOut)),
              child: GlassPrimaryButton(
                skin: skin,
                label: 'Eintrag speichern',
                icon: Icons.save_rounded,
                onTap: () => _saveEntry(context),
                large: true,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: Monatsübersicht
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMonatsuebersichtTab(
    AppSkin skin,
    List<Map<String, dynamic>> entries,
    String monthName,
    int daysInMonth,
    int offeneEntries,
    double bottomNavHeight,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: FadingListView(
          fadeFromBottom: bottomNavHeight + 20,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Monats-Navigation
GlassNavCard(
  onPrevious: () => _changeMonth(-1),
  onNext: () => _changeMonth(1),
  onTap: _showMonthPicker,
  onDoubleTap: () {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    _setMonth(DateTime(now.year, now.month));
  },
  onSwipe: (v) {
    if (v < -300) _changeMonth(1);
    if (v > 300) _changeMonth(-1);
  },
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(monthName,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: skin.textPrimary)),
      const SizedBox(width: 6),
      Icon(Icons.expand_more, color: skin.surface(0.4), size: 18),
    ],
  ),
),

                  const SizedBox(height: 12),
                  Row(children: [
                    GlassStatCard(
                        label: 'Arbeit',
                        value: '${entries.length}',
                        color: skin.statEntries),
                    const SizedBox(width: 10),
                    GlassStatCard(
                        label: 'Tage',
                        value: '$daysInMonth',
                        color: skin.statComplete),
                    const SizedBox(width: 10),
                    GlassStatCard(
                        label: 'Offen',
                        value: '$offeneEntries',
                        color: skin.statOpen),
                  ]),
                  const SizedBox(height: 8),
                  Text('Wischen  ·  Doppeltippen',
                      style: TextStyle(fontSize: 11, color: skin.surface(0.3))),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          entries.isEmpty
              ? SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('📭', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text('Keine Einträge für diesen Monat',
                              style: TextStyle(
                                  color: skin.surface(0.3), fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == entries.length) {
                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                                0, 8, 0, bottomNavHeight + 32),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    closeAllRows();
                                    showGlassSnackBar(
                                      context,
                                      'PDF wird erstellt…',
                                      type: GlassSnackBarType.loading,
                                    );
                                    await PdfService.exportMonth(
                                        context, _selectedMonth);
                                    hideGlassSnackBar(context);
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 10, sigmaY: 10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 11, horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: skin.primary
                                              .withValues(alpha: 0.07),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: skin.primary
                                                  .withValues(alpha: 0.22)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                Icons.picture_as_pdf_outlined,
                                                color: skin.primary,
                                                size: 16),
                                            const SizedBox(width: 7),
                                            Text('Diesen Monat exportieren',
                                                style: TextStyle(
                                                    color: skin.primary,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final entry = entries[index];
                        final datum = entry['datum'] as String;
                        final entryId = entry['id'] as String;
                        _rowKeys[entryId] ??= GlobalKey<GlassSwipeCardState>();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassSwipeCard(
                            key: _rowKeys[entryId],
                            height: 90,
                            cardKey: entryId,
                            externallyOpen: _openSwipedEntryId,
                            onCardSwiped: (key) =>
                                setState(() => _openSwipedEntryId = key),
                            leftActions: [
                              GlassSwipeAction(
                                icon: Icons.edit_outlined,
                                label: 'Bearbeiten',
                                color: skin.editColor,
                                onTap: () => _editEntry(entry),
                              ),
                              GlassSwipeAction(
                                icon: Icons.ios_share_outlined,
                                label: 'Teilen',
                                color: skin.statComplete,
                                onTap: () => _shareEntry(entry),
                              ),
                            ],
                            onDelete: () => _deleteEntry(datum, entryId),
                            animateDelete: true,
                            onDeleteAnimationDone: () async {
                              final date = DateTime.parse(datum);
                              await NightShiftHelper.deleteEntry(date, entryId);
                              if (!mounted) return;
                              setState(() => _rowKeys.remove(entryId));
                              final skin = AppTheme.of(context);
                              _showSnackbar('Eintrag gelöscht', skin.deleteColor);
                            },
                            onDoubleTap: () => _editEntry(entry),
                            child: _MonthEntryCard(
  entry: entry,
  duration: entry['dauerMinuten'] != null
      ? '${(entry['dauerMinuten'] as int) ~/ 60}h ${((entry['dauerMinuten'] as int) % 60).toString().padLeft(2, '0')}m'
      : _calcDuration(entry['kommen'] ?? '', entry['gehen'] ?? ''),
  isComplete: _isEntryComplete(entry),
),
                          ),
                        );
                      },
                      childCount: entries.length + 1,
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
// MONTH ENTRY CARD (reiner Card-Inhalt ohne Swipe-Logik)
// ─────────────────────────────────────────────────────────────────────────────

class _MonthEntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String duration;
  final bool isComplete;

  const _MonthEntryCard({
    required this.entry,
    required this.duration,
    required this.isComplete,
  });

  int _getEntryNumber() {
    try {
      final datum = DateTime.parse(entry['datum']);
      final entries = NightShiftHelper.getEntriesForDay(datum);
      final index = entries.indexWhere((e) => e['id'] == entry['id']);
      return index + 1;
    } catch (_) {
      return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final datum = DateTime.parse(entry['datum']);
    final dayName = DateFormat('EEE', 'de').format(datum);
    final dayNum = DateFormat('dd').format(datum);
    final kommen = entry['kommen'] ?? '';
    final gehen = entry['gehen'] ?? '';
    final tkf = entry['TKF'] ?? '';
    final hasNotiz = ((entry['Bemerkung'] ?? entry['notiz']) ?? '').isNotEmpty;

    final entriesForDay = NightShiftHelper.getEntriesForDay(datum);
    final showNumber = entriesForDay.length > 1;
    final entryNumber = _getEntryNumber();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
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
                  offset: const Offset(0, 4)),
              BoxShadow(
                  color: skin.glassHighlight,
                  blurRadius: 0,
                  spreadRadius: -1,
                  offset: const Offset(0, 1)),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Datum-Spalte ──
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

              // ── Divider ──
              Container(
                  width: 1,
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: skin.surface(0.07)),

              // ── Zeiten + TKF ──
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
                        children: [
                          if (tkf.isNotEmpty) ...[
                            Icon(Icons.person_outline,
                                size: 14, color: skin.surface(0.35)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(tkf,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: skin.surface(0.42)),
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
                    if (TravelModeService.isEnabled && entry['tz'] != null) ...[
                      const SizedBox(height: 6),
                      _TzBreakdownRow(skin: skin, entry: entry),
                    ],
                  ],
                ),
              ),

              // ── Dauer + Status ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (kommen.isNotEmpty && gehen.isNotEmpty)
                    Text(duration,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS ZEIT-KARTE  (aus home_screen.dart übernommen)
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
    required this.label,
    required this.color,
    required this.controller,
    required this.skin,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSwipeUp,
    required this.onSwipeDown,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: br,
                border: Border.all(
                  color: isEmpty
                      ? skin.glassBorder
                      : widget.color.withValues(alpha: 0.38),
                  width: isEmpty ? 1.0 : 1.5,
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
                              letterSpacing: 1.2)),
                      GlassIconBadge(
                          skin: skin, icon: Icons.unfold_more_rounded),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isEmpty ? '--:--' : widget.controller.text,
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: isEmpty
                              ? skin.surface(0.2)
                              : skin.textPrimary,
                          letterSpacing: -1),
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
// GLASS INPUT CARD  (TKF / Notiz)
// ─────────────────────────────────────────────────────────────────────────────

class _GlassInputCard extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;

  const _GlassInputCard({
    required this.skin,
    required this.label,
    required this.icon,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => GlassSurface(
        borderRadius: 20,
        useBlur: false,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
                width: 36,
                height: 36,
                child: Icon(icon, size: 20, color: skin.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 9,
                          color: skin.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  const SizedBox(height: 3),
                  Text(
                      controller.text.isEmpty ? hint : controller.text,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: controller.text.isEmpty
                              ? FontWeight.w400
                              : FontWeight.w600,
                          color: controller.text.isEmpty
                              ? skin.surface(0.3)
                              : skin.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            GlassIconBadge(skin: skin, icon: Icons.edit_outlined),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLYING CARD OVERLAY
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
    required this.field,
    required this.flyAnimation,
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
    final label = isTkf ? 'TAGESKOMMANDOFÜHRER' : 'BEMERKUNG';
    final icon =
        isTkf ? Icons.person_outline_rounded : Icons.edit_note_rounded;
    final hint = isTkf ? 'Name des TKF' : 'Optionale Bemerkung...';
    final screenH = MediaQuery.of(context).size.height;
    final cardTop = screenH * 0.22;

    return AnimatedBuilder(
      animation: flyAnimation,
      builder: (context, child) => Positioned(
        top: cardTop,
        left: 24.0,
        right: 24.0,
        child: Transform.scale(
          scale: 0.86 + scaleAnim.value * 0.14,
          child: Opacity(
              opacity: opacityAnim.value.clamp(0.0, 1.0), child: child!),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Container(
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: skin.glassBorder, width: 1.0),
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
                      child: GlassIconBadge(
                          skin: skin, icon: Icons.backspace_outlined),
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
                    style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                          color: skin.surface(0.22), fontSize: 17),
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
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _EditSheet extends StatefulWidget {
  final DateTime datum;
  final String entryId;
  final Map<String, dynamic> entry; // NEU – für Zonen-Vorbefüllung
  final TextEditingController kommenCtrl;
  final TextEditingController gehenCtrl;
  final TextEditingController tkfCtrl;
  final TextEditingController notizCtrl;
  final Future<void> Function(String? kommenTz, String? gehenTz) onSave; // NEU: Zonen werden übergeben

  const _EditSheet({
    required this.datum,
    required this.entryId,
    required this.entry,
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
  // ── Zeitzonen für Bearbeitung ──
  String? _editKommenTz;
  String? _editGehenTz;

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

  int get _roundStep {
    final rule = Hive.box('einstellungen')
        .get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;
    return TimeRounding.stepMinutes(rule);
  }

  void _adjustTime(TextEditingController controller, int direction,
      bool isGehenField) {
    TimeOfDay current;
    if (controller.text.isEmpty || controller.text == '--:--') {
      if (isGehenField) {
        final kommenTime = _parse(widget.kommenCtrl.text);
        current = kommenTime != null
            ? _getDefaultGehenTime(kommenTime)
            : TimeOfDay.now();
      } else {
        current = TimeOfDay.now();
      }
    } else {
      current = _parse(controller.text) ?? TimeOfDay.now();
    }
    final rule = Hive.box('einstellungen')
        .get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;
    final total = TimeRounding.steppedTotal(
        current.hour * 60 + current.minute, rule, direction);
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
      initialTime = kommenTime != null
          ? _getDefaultGehenTime(kommenTime)
          : TimeOfDay.now();
    } else {
      initialTime = TimeOfDay.now();
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: initialTime,
        skin: skin,
        label: isGehenField ? 'Uhrzeit Gehen' : 'Uhrzeit Kommen',
        confirmOnDismiss: false,
        minuteInterval: _roundStep,
        onTimeSelected: (t) {
          final rule = Hive.box('einstellungen')
              .get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;
          final rounded = TimeRounding.roundTimeOfDay(t, rule);
          setState(() {
            ctrl.text =
                '${rounded.hour.toString().padLeft(2, '0')}:${rounded.minute.toString().padLeft(2, '0')}';
          });
        },
      ),
    );
  }

  Future<void> _pickZoneForField({required bool isKommen}) async {
    final skin = AppTheme.of(context);
    final current = isKommen ? _editKommenTz : _editGehenTz;
    final result = await _showZonePickerSheet(
      context: context,
      skin: skin,
      currentTzId: current,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isKommen) {
        _editKommenTz = result;
      } else {
        _editGehenTz = result;
      }
    });
    await TravelModeService.setActiveTz(result);
  }

@override
void initState() {
  super.initState();
  // Zonen aus dem Eintrag laden (nicht die aktuell aktive Zone!)
  _editKommenTz = widget.entry['tz'] as String? ??
      (TravelModeService.isEnabled ? TravelModeService.activeTzId : null);
  _editGehenTz = widget.entry['gehenTz'] as String? ?? _editKommenTz;
}

Widget? _buildZoneCrossingInfo(AppSkin skin) {
  if (!TravelModeService.isEnabled) return null;
  if (_editKommenTz == null || _editGehenTz == null) return null;
  if (_editKommenTz == _editGehenTz) return null;
  if (widget.kommenCtrl.text.isEmpty || widget.gehenCtrl.text.isEmpty) return null;

  final converted = TravelModeService.convertGehenToKommenTz(
    datum: widget.datum,
    kommenHhmm: widget.kommenCtrl.text,
    kommenTzId: _editKommenTz!,
    gehenHhmm: widget.gehenCtrl.text,
    gehenTzId: _editGehenTz!,
  );
  if (converted == null) return null;

  final dur = TravelModeService.actualDuration(
    datum: widget.datum,
    kommenHhmm: widget.kommenCtrl.text,
    kommenTzId: _editKommenTz!,
    gehenHhmm: widget.gehenCtrl.text,
    gehenTzId: _editGehenTz!,
  );
  final durText = dur != null
      ? '${dur.inHours}h ${(dur.inMinutes % 60).toString().padLeft(2, '0')}m'
      : '--';

  return Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: skin.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: skin.primary.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.public_rounded, size: 14, color: skin.primary),
            const SizedBox(width: 6),
            Text('Zonen-Umrechnung',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.primary)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Gehen roh: ${widget.gehenCtrl.text}  ($_editGehenTz, ${TravelModeService.offsetLabelFor(_editGehenTz!)})',
            style: TextStyle(fontSize: 12, color: skin.textPrimary)),
        const SizedBox(height: 2),
        Text('→ umgerechnet: $converted  ($_editKommenTz, ${TravelModeService.offsetLabelFor(_editKommenTz!)})',
            style: TextStyle(fontSize: 12, color: skin.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Tatsächliche Dauer: $durText',
            style: TextStyle(fontSize: 12, color: skin.surface(0.5))),
      ],
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
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.90)
                    : skin.bgSheet.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28)),
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
                            borderRadius:
                                BorderRadius.circular(2))),
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
                        onTap: () =>
                            _pickTime(widget.kommenCtrl, false),
                        onDoubleTap: () {
                          setState(
                              () => widget.kommenCtrl.clear());
                          HapticFeedback.selectionClick();
                        },
                         onSwipeUp: () =>
                            _adjustTime(widget.kommenCtrl, 1, false),
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
                        onTap: () =>
                            _pickTime(widget.gehenCtrl, true),
                        onDoubleTap: () {
                          setState(
                              () => widget.gehenCtrl.clear());
                          HapticFeedback.selectionClick();
                        },
                        onSwipeUp: () =>
                            _adjustTime(widget.gehenCtrl, 1, true),
                        onSwipeDown: () =>
                            _adjustTime(widget.gehenCtrl, -1, true),
                      ),
                    ),
                  ]),
                  if (TravelModeService.isEnabled) ...[
                    const SizedBox(height: 12),
  Row(
    children: [
      Expanded(
        child: _ZoneChip(
          skin: skin,
          tzId: _editKommenTz,
          onTap: () => _pickZoneForField(isKommen: true),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _ZoneChip(
          skin: skin,
          tzId: _editGehenTz,
          onTap: () => _pickZoneForField(isKommen: false),
        ),
      ),
    ],
  ),
  if (_buildZoneCrossingInfo(skin) != null) _buildZoneCrossingInfo(skin)!,
],
                  const SizedBox(height: 12),
                  GestureDetector(
                    onDoubleTap: () {
                      setState(() => widget.tkfCtrl.clear());
                      HapticFeedback.selectionClick();
                    },
                    child: _GlassTextFieldInput(
                        label: 'TKF',
                        ctrl: widget.tkfCtrl,
                        capitalize: true),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onDoubleTap: () {
                      setState(() => widget.notizCtrl.clear());
                      HapticFeedback.selectionClick();
                    },
                    child: _GlassTextFieldInput(
                        label: 'BEMERKUNG',
                        ctrl: widget.notizCtrl,
                        maxLines: 2,
                        capitalize: true),
                  ),
                  const SizedBox(height: 20),
                  GlassPrimaryButton(
    skin: skin,
    label: 'Speichern',
    onTap: () {
      widget.onSave(_editKommenTz, _editGehenTz);
    }),
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
// TzBreakdownRow
// ─────────────────────────────────────────────────────────────────────────────
class _TzBreakdownRow extends StatelessWidget {
  final AppSkin skin;
  final Map<String, dynamic> entry;

  const _TzBreakdownRow({required this.skin, required this.entry});

  @override
  Widget build(BuildContext context) {
    final tz = entry['tz'] as String? ?? '';
    final offsetLabel = entry['tzOffsetLabel'] as String? ?? '';
    final physTz = entry['physTzAtSave'] as String?;
    final travelled = physTz != null && physTz != tz;

    final gehenRaw = entry['gehenRaw'] as String?;
    final gehenRawTz = entry['gehenRawTz'] as String?;
    final zoneCrossing = gehenRaw != null && gehenRawTz != null;
    final dauerMinuten = entry['dauerMinuten'] as int?;
    final gehenDayShift = entry['gehenDayShift'] as int?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.public_rounded, size: 12, color: skin.surface(0.32)),
            const SizedBox(width: 4),
            Text(
              offsetLabel.isEmpty ? tz : '$tz ($offsetLabel)',
              style: TextStyle(fontSize: 10.5, color: skin.surface(0.4)),
            ),
            // "Gerät bereits woanders"-Hinweis nur zeigen, wenn es sich
            // NICHT um eine bewusste Zonen-Kreuzung innerhalb des Eintrags
            // handelt (sonst doppelt sich die Info mit der Zeile unten).
            if (travelled && !zoneCrossing) ...[
              const SizedBox(width: 6),
              Icon(Icons.flight_rounded, size: 11, color: skin.primary.withValues(alpha: 0.6)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  'Gerät bereits in $physTz',
                  style: TextStyle(
                      fontSize: 10, color: skin.primary.withValues(alpha: 0.6)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        if (zoneCrossing) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.flight_takeoff_rounded, size: 11, color: skin.primary.withValues(alpha: 0.65)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Gehen roh: $gehenRaw ($gehenRawTz)'
                  '${gehenDayShift != null && gehenDayShift != 0 ? (gehenDayShift > 0 ? ' · +1 Tag' : ' · -1 Tag') : ''}'
                  '${dauerMinuten != null ? ' · Dauer ${dauerMinuten ~/ 60}h ${(dauerMinuten % 60).toString().padLeft(2, '0')}m' : ''}',
                  style: TextStyle(fontSize: 10, color: skin.primary.withValues(alpha: 0.65)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SWIPE EDIT TIME FIELD
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
  State<_SwipeEditTimeField> createState() =>
      _SwipeEditTimeFieldState();
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
              filter:
                  ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: skin.isLight
                      ? widget.color.withValues(alpha: 0.08)
                      : widget.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color:
                          widget.color.withValues(alpha: 0.28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(widget.label,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: widget.color,
                                letterSpacing: 1)),
                        Icon(Icons.unfold_more,
                            color: widget.color
                                .withValues(alpha: 0.5),
                            size: 14),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.ctrl.text.isEmpty
                            ? '--:--'
                            : widget.ctrl.text,
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
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
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
                textCapitalization: capitalize
                    ? TextCapitalization.sentences
                    : TextCapitalization.none,
                style: TextStyle(
                    color: skin.textPrimary, fontSize: 15),
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
// ZONE PICKER SHEET
// ─────────────────────────────────────────────────────────────────────────────

Future<String?> _showZonePickerSheet({
  required BuildContext context,
  required AppSkin skin,
  required String? currentTzId,
}) async {
  final suggestions = TravelModeService.suggestedZoneIds();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: 0.92)
                : skin.bgSheet.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: skin.surface(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Zeitzone wählen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary)),
              const SizedBox(height: 14),
              ...suggestions.map((tzId) {
                final label = TravelModeService.offsetLabelFor(tzId);
                final isActive = tzId == currentTzId;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(sheetContext, tzId);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive ? skin.primary.withValues(alpha: 0.14) : skin.surface(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? skin.primary.withValues(alpha: 0.4) : skin.glassBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.public_rounded, size: 16,
                            color: isActive ? skin.primary : skin.surface(0.4)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(tzId,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                  color: skin.textPrimary)),
                        ),
                        Text(label, style: TextStyle(fontSize: 12, color: skin.surface(0.4))),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () async {
                  final query = await _promptFreetextZone(sheetContext, skin);
                  if (query == null || query.trim().isEmpty) return;
                  final found = await TravelModeService.verifyLocationTimeZone(query.trim());
                  if (found != null) {
                    Navigator.pop(sheetContext, found.tzId);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 16, color: skin.primary),
                      const SizedBox(width: 10),
                      Text('Ort/Stadt suchen…',
                          style: TextStyle(fontSize: 13.5, color: skin.primary, fontWeight: FontWeight.w600)),
                    ],
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

Future<String?> _promptFreetextZone(BuildContext context, AppSkin skin) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: skin.bgSheet,
      title: Text('Ort eingeben', style: TextStyle(color: skin.textPrimary)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: TextStyle(color: skin.textPrimary),
        decoration: const InputDecoration(hintText: 'z.B. Tokyo, New York'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, ctrl.text), child: const Text('Suchen')),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONE CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneChip extends StatelessWidget {
  final AppSkin skin;
  final String? tzId;
  final VoidCallback onTap;

  const _ZoneChip({required this.skin, required this.tzId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = tzId != null ? TravelModeService.offsetLabelFor(tzId!) : '';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: skin.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: skin.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 13, color: skin.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tzId ?? 'Zone wählen',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: skin.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10.5, color: skin.primary.withValues(alpha: 0.6))),
            ],
          ],
        ),
      ),
    );
  }
}