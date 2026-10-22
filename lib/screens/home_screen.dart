import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/dictation_fab.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/glass_snackbar.dart';
import '../models/relationship_style.dart';
import '../services/weather_service.dart';
import '../services/sync_service.dart';
import 'tasks_screen.dart' show TaskStore, Task;
import '../services/spoken_task_parser.dart';
import '../utils/time_rounding.dart';
import '../widgets/day_plan.dart';
import '../widgets/location_actions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN — News-App-Style Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToMonth;
  final VoidCallback? onNavigateToFahrtenbuch;
  final VoidCallback? onNavigateToFahrtenbuchNeueFahrt;
  final VoidCallback? onNavigateToTasks;
  final VoidCallback? onNavigateToTasksQuickAdd;
  final VoidCallback? onNavigateToTasksQuickAddEvent;
  final VoidCallback? onNavigateToSchedule;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback? onNavigateToScheduleAndImport;

  const HomeScreen({
    super.key,
    required this.onNavigateToMonth,
    required this.selectedDate,
    required this.onDateChanged,
    this.onNavigateToFahrtenbuch,
    this.onNavigateToFahrtenbuchNeueFahrt,
    this.onNavigateToTasks,
    this.onNavigateToTasksQuickAdd,
    this.onNavigateToTasksQuickAddEvent,
    this.onNavigateToSchedule,
    this.onNavigateToScheduleAndImport,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late DateTime _selectedDate;
  late AnimationController _greetingCtrl;
  late Animation<double> _greetingFade;

  // Für Uhr-Ticker
  late DateTime _now;

  // ── NEU: Wetter-State, wird verzögert nach erstem Frame befüllt ──────────
WeatherData? _weatherData;
bool _isRefreshingWeather = false;

  // Review-Callback von main.dart
  void Function(ParsedSpokenTask, String)? onReviewFromHomescreen;

  // NEU
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    TaskStore.changesSignal.addListener(_onTasksChangedExternally);
    SyncService.instance.scheduleDataChanged.addListener(_onPlanSync);
    _selectedDate = widget.selectedDate;
    _now = DateTime.now();

    // Sofort verfügbaren Cache zeigen (kein Warten, kein Netzwerk-Call)
_weatherData = WeatherService.instance.cached;

WeatherService.instance.refreshSignal.addListener(_onWeatherInvalidated);

    _greetingCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _greetingFade = CurvedAnimation(parent: _greetingCtrl, curve: Curves.easeOut);
    _greetingCtrl.forward();

    // Uhr jede Minute aktualisieren
    _scheduleNextMinuteTick();

    // ── NEU: Wetter-Fetch erst NACH dem ersten Frame anstoßen ──────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshWeather();
      // Falls der erste Versuch scheitert (z.B. GPS-Permission-Dialog war
      // noch nicht beantwortet, langsamer Fix), nach 8s automatisch erneut
      // versuchen, statt für immer "Wird geladen…" anzuzeigen.
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted && _weatherData == null) _refreshWeather();
      });
    });
  }

  Future<void> _refreshWeather() async {
    final box = Hive.box('einstellungen');
    final useGps = box.get('weather_use_gps', defaultValue: true) as bool;
    final cityName = useGps ? '' : (_getWeatherCity() ?? '');

    final data = await WeatherService.instance.fetchIfNeeded(cityName, useGps: useGps);
    if (!mounted) return;
    setState(() => _weatherData = data);
  }

  void _onWeatherInvalidated() {
  if (mounted) _refreshWeather();
}

  // NEU
Future<void> _refreshWeatherManual() async {
  if (_isRefreshingWeather) return;
  HapticFeedback.mediumImpact();
  setState(() => _isRefreshingWeather = true);

  WeatherService.instance.invalidateCache();
  final box = Hive.box('einstellungen');
  final useGps = box.get('weather_use_gps', defaultValue: true) as bool;
  final cityName = useGps ? '' : (_getWeatherCity() ?? '');

  final data = await WeatherService.instance.fetchIfNeeded(cityName, useGps: useGps);

  if (!mounted) return;
  setState(() {
    _weatherData = data;
    _isRefreshingWeather = false;
  });
}

  void _scheduleNextMinuteTick() {
    final now = DateTime.now();
    final msUntilNextMinute = (60 - now.second) * 1000 - now.millisecond;
    Future.delayed(Duration(milliseconds: msUntilNextMinute), () {
      if (mounted) {
        setState(() => _now = DateTime.now());
        _scheduleNextMinuteTick();
      }
    });
  }

  // NEU
  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  WeatherService.instance.refreshSignal.removeListener(_onWeatherInvalidated);
  TaskStore.changesSignal.removeListener(_onTasksChangedExternally);
  SyncService.instance.scheduleDataChanged.removeListener(_onPlanSync);
  _greetingCtrl.dispose();
  super.dispose();
}

// NEU: hört auf Task-Änderungen egal woher (z.B. TasksScreen), damit die
// Aufgaben-Vorschau-Kachel auf dem Homescreen immer aktuell ist
void _onTasksChangedExternally() {
  if (mounted) setState(() {});
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  if (state == AppLifecycleState.resumed) {
    _refreshWeather();
  }
}

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      setState(() => _selectedDate = widget.selectedDate);
    }
  }

  void _onPlanSync() {
    if (mounted) setState(() {});
  }

  /// Alle Ereignisse von heute (chronologisch). Welches vorne liegt, entscheidet der Stapel.
  List<DayPlanItem> _getTodayEvents() {
    final key = DateFormat('yyyy-MM-dd').format(_now);
    return DayPlanStore.load(key);
  }

  /// Wird von außen (MainScreen) gesetzt, um benachrichtigt zu werden,
  /// wenn sich der Overlay-Status dieses Screens ändert.
  VoidCallback? onOverlayStateChanged;

  void closeOverlays() {}
  bool get isOverlayOpen => false;

  // ── Task-Methoden für Diktat ─────────────────────────────────────────────

  void _saveTaskFromSpeech(ParsedSpokenTask parsed, String logRef) {
    final combined = parsed.combinedDateTime;
    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: parsed.title,
      dueDate: combined,
      hasTime: parsed.hasTime,
      createdAt: DateTime.now(),
      isUrgent: parsed.isUrgent,
    );
    TaskStore.add(task);
    setState(() {});
    HapticFeedback.mediumImpact();
    showGlassSnackBar(context, '„${task.title}" gespeichert',
    type: GlassSnackBarType.success);
  }

  void _createTaskFromSpeech(ParsedSpokenTask parsed, String logRef) {
  if (_isLikelyDuplicate(parsed)) {
    HapticFeedback.heavyImpact();
    _showDuplicateDialog(parsed, logRef);
    return;
  }
  _saveTaskFromSpeech(parsed, logRef);
}

bool _isLikelyDuplicate(ParsedSpokenTask parsed) {
  final all = TaskStore.loadAll();
  final newNorm = parsed.title.toLowerCase().trim();
  if (newNorm.isEmpty) return false;
  final newDate = parsed.combinedDateTime;
  return all.any((t) {
    if (t.done) return false;
    final sameTitle = t.title.toLowerCase().trim() == newNorm;
    if (!sameTitle) return false;
    if (newDate == null && t.dueDate == null) return true;
    if (newDate == null || t.dueDate == null) return false;
    return newDate.year == t.dueDate!.year &&
        newDate.month == t.dueDate!.month &&
        newDate.day == t.dueDate!.day;
  });
}

Future<void> _showDuplicateDialog(ParsedSpokenTask parsed, String logRef) async {
  final skin = AppTheme.of(context);
  final confirmed = await confirmActionDialog(
    context: context,
    skin: skin,
    icon: Icons.content_copy_outlined,
    title: 'Ähnliche Aufgabe existiert',
    message: 'Es gibt bereits eine offene Aufgabe mit dem Titel „${parsed.title}". Möchtest du sie trotzdem als neue Aufgabe anlegen?',
    cancelLabel: 'Abbrechen',
    confirmLabel: 'Trotzdem anlegen',
  );
  if (confirmed == true) {
    _saveTaskFromSpeech(parsed, logRef);
  }
}

  void _reviewTaskFromSpeech(ParsedSpokenTask parsed, String logRef) {
    // Review: navigiere zu Tasks und öffne das Review-Sheet dort
    widget.onNavigateToTasks?.call();
    // Kleiner Delay damit der Tab-Wechsel fertig ist
    Future.delayed(const Duration(milliseconds: 400), () {
      onReviewFromHomescreen?.call(parsed, logRef);
    });
  }

  // ── Daten-Helfer ─────────────────────────────────────────────────────────

  String get _firstName {
    final box = Hive.box('einstellungen');
    final full = box.get('name', defaultValue: '') as String;
    if (full.trim().isEmpty) return '';
    return full.trim().split(' ').first;
  }

  String get _greeting {
    final h = _now.hour;
    final style = RelationshipStyleStore.load();
    final name = _firstName;

    String base;
    if (h < 5)       base = 'Gute Nacht';
    else if (h < 12) base = 'Guten Morgen';
    else if (h < 18) base = 'Guten Nachmittag';
    else             base = 'Guten Abend';

    if (name.isEmpty) return base;

    switch (style) {
      case RelationshipStyle.bro:
        return '$base, $name!';
      case RelationshipStyle.vorname:
        return '$base, $name!';
      case RelationshipStyle.familie:
        final box = Hive.box('einstellungen');
        final full = box.get('name', defaultValue: '') as String;
        final parts = full.trim().split(' ');
        final last = parts.length > 1 ? parts.last : name;
        return '$base, $last!';
    }
  }

  /// Heutiger Dienst aus dem Dienstplan
  String? _getTodayShift() {
    final box = Hive.box('einstellungen');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final monthKey = DateFormat('yyyy-MM').format(DateTime.now());
    final raw = box.get('schedule_$monthKey');
    if (raw is Map) {
      return raw[today] as String?;
    }
    return null;
  }

  /// Nächste 3 Dienste (ohne heute)
  List<_ShiftPreview> _getUpcomingShifts() {
    final box = Hive.box('einstellungen');
    final today = DateTime.now();
    final result = <_ShiftPreview>[];

    for (int i = 1; i <= 14 && result.length < 3; i++) {
      final day = today.add(Duration(days: i));
      final monthKey = DateFormat('yyyy-MM').format(day);
      final dateKey = DateFormat('yyyy-MM-dd').format(day);
      final raw = box.get('schedule_$monthKey');
      if (raw is Map) {
        final shift = raw[dateKey] as String?;
        if (shift != null && shift.isNotEmpty) {
          result.add(_ShiftPreview(day: day, shift: shift));
        }
      }
    }
    return result;
  }

  /// Offene Tasks (max. 3, die nächsten nach Deadline)
  List<Task> _getUpcomingTasks({int limit = 7}) {
    final all = TaskStore.loadAll();
    final open = all.where((t) => !t.done).toList();
    int byDue(Task a, Task b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    }
    int byCreated(Task a, Task b) => a.createdAt.compareTo(b.createdAt);
    final urgent = open.where((t) => t.isUrgent).toList()
      ..sort((a, b) => TaskStore.compareManual(a, b, byCreated));
    final dated = open.where((t) => !t.isUrgent && t.dueDate != null).toList()
      ..sort((a, b) => TaskStore.compareManual(a, b, byDue));
    final general = open.where((t) => !t.isUrgent && t.dueDate == null).toList()
      ..sort((a, b) => TaskStore.compareManual(a, b, byCreated));
    return [...urgent, ...dated, ...general].take(limit).toList();
  }

  bool get _hasScheduleThisMonth {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(DateTime.now());
    final raw = box.get('schedule_$monthKey');
    return raw is Map && (raw as Map).isNotEmpty;
  }

  // ── Wetter ────────────────────────────────────────────────────────────────

  String? _getWeatherCity() {
    final box = Hive.box('einstellungen');
    return box.get('weather_city', defaultValue: null) as String?;
  }

  String _formatWeatherAge(DateTime fetchedAt) {
    final diff = DateTime.now().difference(fetchedAt).inMinutes;
    if (diff < 2) return 'gerade eben';
    if (diff < 60) return 'vor $diff Min.';
    return 'vor ${diff ~/ 60} Std.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final todayShift = _getTodayShift();
    final upcomingShifts = _getUpcomingShifts();
    final todayEvents = _getTodayEvents();
    final screenH = MediaQuery.sizeOf(context).height;
    final stackDepth = screenH >= 900 ? 3 : (screenH >= 800 ? 2 : 1);
    final upcomingTasks = _getUpcomingTasks(limit: todayEvents.isEmpty ? 7 : 2);
    final bottomNavHeight = 70.0 + MediaQuery.paddingOf(context).bottom;

    
final box = Hive.box('einstellungen');
    final taskAddMode = box.get('homescreen_task_add_mode', defaultValue: 'dictate') as String;
    final useDictate = taskAddMode == 'dictate';
    final compactTiles = box.get('homescreen_compact_tiles', defaultValue: false) as bool;
    final readOnlyMode = box.get('read_only_mode', defaultValue: false) as bool;
    return Scaffold(
  backgroundColor: skin.bgBase,
  body: SafeArea(
    bottom: false,
    child: Column(
      children: [
        FadingListView(
  fadeFromBottom: 0,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 36),

              FadeTransition(
                opacity: _greetingFade,
                child: _buildHeroHeader(skin),
              ),

              const SizedBox(height: 16),
              _buildWeatherRow(skin),
              const SizedBox(height: 14),

              if (todayShift != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _DiensteKachel(
                    skin: skin,
                    todayShift: todayShift,
                    upcoming: upcomingShifts,
                  ),
                ),
                const SizedBox(height: 14),
              ] else if (!_hasScheduleThisMonth) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _DienstplanPlaceholderKachel(
                    skin: skin,
                    onTap: () => widget.onNavigateToScheduleAndImport?.call(),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20),
  child: LayoutBuilder(
    builder: (context, constraints) {
      const gap = 10.0;
      final kachelW = (constraints.maxWidth - gap * 2) / 3;
      // Höhe proportional zur Kachel-Breite, mit sinnvollen Grenzen
      // Kompakter Inhalt ist immer eine einzeilige Row (Icon 30px + Padding
      // 12 oben/unten) — 58px ist die exakt passende Höhe dafür, unabhängig
      // von der Kachel-Breite.
      final kachelH = compactTiles
        ? 58.0
        : (kachelW * 1.02).clamp(84.0, 128.0);

      // NEU: im Lesemodus andere Kachel-Belegung — Diktieren/Entry-Sheet
      // Aufgabe, Entry-Sheet neues Ereignis, Kurzverknüpfung Dienstplan.
      if (readOnlyMode) {
        return Row(
          children: [
            Expanded(
              child: _DictationTaskKachel(
                skin: skin,
                height: kachelH,
                compact: compactTiles,
                onResult: _createTaskFromSpeech,
                onNeedsReview: _reviewTaskFromSpeech,
                onNavigateToTasks: widget.onNavigateToTasks,
                onNavigateToTasksQuickAdd: widget.onNavigateToTasksQuickAdd,
                useDictate: useDictate,
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: _QuickAccessKachel(
                skin: skin,
                height: kachelH,
                compact: compactTiles,
                icon: '📅',
                label: 'Neuer Termin',
                compactLabel: 'Termin',
                sublabel: 'Kalender →',
                accentColor: const Color(0xFF2FD3C7),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onNavigateToTasksQuickAddEvent?.call();
                },
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: _QuickAccessKachel(
                skin: skin,
                height: kachelH,
                compact: compactTiles,
                icon: '📋',
                label: 'Dienstplan',
                compactLabel: 'Plan',
                sublabel: 'Ansehen →',
                accentColor: const Color(0xFFFFB347),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onNavigateToSchedule?.call();
                },
              ),
            ),
          ],
        );
      }

      return Row(
        children: [
          Expanded(
            child: _StempeluhrKachel(
              skin: skin,
              height: kachelH,
              compact: compactTiles,
              onNavigateToMonth: widget.onNavigateToMonth,
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: _QuickAccessKachel(
              skin: skin,
              height: kachelH,
              compact: compactTiles,
              icon: '🚗',
              label: 'Neue Fahrt',
              compactLabel: 'Fahrt',
              sublabel: 'KM + Foto →',
              accentColor: const Color(0xFF2D6CFF),
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onNavigateToFahrtenbuchNeueFahrt?.call();
              },
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: _DictationTaskKachel(
              skin: skin,
              height: kachelH,
              compact: compactTiles,
              onResult: _createTaskFromSpeech,
              onNeedsReview: _reviewTaskFromSpeech,
              onNavigateToTasks: widget.onNavigateToTasks,
              onNavigateToTasksQuickAdd: widget.onNavigateToTasksQuickAdd,
              useDictate: useDictate,
            ),
          ),
        ],
      );
    },
  ),
),

              const SizedBox(height: 14),
            ],
          ),
        ),

        // ── Ereignis-Stapel (nur heute, nur wenn vorhanden) ──
        if (todayEvents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: _EventStackKachel(
              skin: skin,
              items: todayEvents,
              now: _now,
              depth: stackDepth,
              onChanged: () { if (mounted) setState(() {}); },
            ),
          ),

        // ── Aufgaben-Kachel: wächst bis max. zur Navbar, scrollt intern ──
        if (upcomingTasks.isNotEmpty)
          Flexible(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomNavHeight + 16),
              child: _TaskPreviewKachel(
                skin: skin,
                tasks: upcomingTasks,
                onTapAll: widget.onNavigateToTasks,
              ),
            ),
          )
        else
          SizedBox(height: bottomNavHeight + 16),
      ],
    ),
  ),
);
  }

  // ── Hero: Zeit + Greeting ─────────────────────────────────────────────────

  Widget _buildHeroHeader(AppSkin skin) {
    final timeStr = DateFormat('HH:mm').format(_now);
    final hour = timeStr.split(':')[0];
    final minute = timeStr.split(':')[1];
    final dateStr = DateFormat('EEE, d. MMMM', 'de').format(_now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Große Uhrzeit
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Datum dezent
              Text(
                dateStr.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: skin.surface(0.38),
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              // Zeit
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$hour:',
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: skin.textPrimary,
                        height: 1.0,
                        letterSpacing: -2,
                      ),
                    ),
                    TextSpan(
                      text: minute,
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w300,
                        color: skin.textPrimary.withValues(alpha: 0.65),
                        height: 1.0,
                        letterSpacing: -2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Begrüßung
              Text(
                _greeting,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: skin.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Wetter ─────────────────────────────────────────────────────────────────

  Widget _buildWeatherRow(AppSkin skin) {
    final box = Hive.box('einstellungen');
    final weatherEnabled = box.get('homescreen_weather_big', defaultValue: false) as bool;
    final useGps = box.get('weather_use_gps', defaultValue: true) as bool;
    final cityName = useGps ? '' : (_getWeatherCity() ?? '');

    final data = _weatherData;
    final weatherIcon = data?.icon ?? '⛅';
    final tempStr = data?.tempStr ?? '—°';

    final cityLabel = useGps
        ? (data != null ? 'Aktueller Standort' : 'Wird geladen…')
        : (data == null
            ? (cityName.isNotEmpty ? cityName : 'Stadt nicht gesetzt')
            : data.city);

    final detail = data != null
        ? 'Aktualisiert ${_formatWeatherAge(data.fetchedAt)}'
        : 'Lädt…';

    if (weatherEnabled) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: _WeatherKachelGross(
      skin: skin,
      data: data,
      icon: weatherIcon,
      temp: tempStr,
      city: cityLabel,
      detail: detail,
      isRefreshing: _isRefreshingWeather,
      onRefresh: _refreshWeatherManual,
    ),
  );
} else {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
    child: Align(
      alignment: Alignment.centerRight,
      child: _WeatherChip(
        skin: skin,
        icon: weatherIcon,
        temp: tempStr,
        city: cityLabel,
        isRefreshing: _isRefreshingWeather,
        onRefresh: _refreshWeatherManual,
      ),
    ),
  );
}
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// DIENST KACHEL
// ─────────────────────────────────────────────────────────────────────────────

class _ShiftPreview {
  final DateTime day;
  final String shift;
  _ShiftPreview({required this.day, required this.shift});
}

Color _shiftColor(String s, AppSkin skin) {
  final u = s.trim().toUpperCase();
  if (u == 'U' || u == 'DA' || u == 'X') return skin.surface(0.35);
  if (u == 'VK' || u == 'IS') return const Color(0xFFEF5B5B);
  const work = ['P1', 'P2', 'P', 'F1', 'F2', 'F', 'T'];
  for (final w in work) {
    if (u == w || u.startsWith('$w/')) return skin.primary;
  }
  return skin.primary;
}

class _DiensteKachel extends StatelessWidget {
  final AppSkin skin;
  final String todayShift;
  final List<_ShiftPreview> upcoming;

  const _DiensteKachel({
    required this.skin,
    required this.todayShift,
    required this.upcoming,
  });

  String _shiftLabel(String s) {
    final u = s.trim().toUpperCase();
    final map = {
      'P': 'PS',
      'P1': 'PS früh',
      'P2': 'PS spät',
      'F': 'Fahrer',
      'F1': 'Fahrer früh',
      'F2': 'Fahrer spät',
      'U': 'Urlaub',
      'DA': 'Dienstausgleich',
      'X': 'Frei',
      'VK': 'Vorkommando',
      'T': 'Tagdienst',
    };
    return map[u] ?? u;
  }

  @override
  Widget build(BuildContext context) {
    final color = _shiftColor(todayShift, skin);
    final label = _shiftLabel(todayShift);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: PlatformBackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
            boxShadow: [
              BoxShadow(color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Dienst-Badge
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.30)),
                  ),
                  child: Center(
                    child: Text(
                      todayShift.toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Label + Subtext
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: skin.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Heute',
                        style: TextStyle(
                          fontSize: 11,
                          color: skin.surface(0.38),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Nächste Tage — kompakte Chips
                if (upcoming.isNotEmpty)
                  Row(
                    children: upcoming.map((p) {
                      final c = _shiftColor(p.shift, skin);
                      final dayAbbr = DateFormat('EEE', 'de').format(p.day).substring(0, 2).toUpperCase();
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Column(
                          children: [
                            Text(
                              dayAbbr,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: skin.surface(0.35),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: c.withValues(alpha: 0.28), width: 0.8),
                              ),
                              child: Text(
                                p.shift.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: c,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
// QUICK ACCESS KACHEL — Neue Fahrt
// ─────────────────────────────────────────────────────────────────────────────

class _QuickAccessKachel extends StatefulWidget {
  final AppSkin skin;
  final double height;
  final bool compact;
  final String icon;
  final String label;
  final String? compactLabel;
  final String sublabel;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _QuickAccessKachel({
    required this.skin,
    required this.height,
    required this.compact,
    required this.icon,
    required this.label,
    this.compactLabel,
    required this.sublabel,
    required this.accentColor,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_QuickAccessKachel> createState() => _QuickAccessKachelState();
}

class _QuickAccessKachelState extends State<_QuickAccessKachel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _pressScale = Tween(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _pressScale,
        builder: (context, child) =>
            Transform.scale(scale: _pressScale.value, child: child),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: PlatformBackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              height: widget.height,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                    : skin.bgCard.withValues(alpha: skin.glassOpacity),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.accentColor.withValues(alpha: 0.30),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                      color: skin.glassShadow,
                      blurRadius: 16,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: widget.compact
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(widget.icon, style: const TextStyle(fontSize: 15)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.compactLabel ?? widget.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: skin.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(widget.icon,
                                style: const TextStyle(fontSize: 17)),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: skin.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.sublabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: widget.accentColor
                                .withValues(alpha: skin.isLight ? 0.8 : 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
// STEMPELUHR KACHEL — Direkt Kommen-Zeit stempeln
// ─────────────────────────────────────────────────────────────────────────────

class _StempeluhrKachel extends StatefulWidget {
  final AppSkin skin;
  final double height;
  final bool compact;
  final VoidCallback onNavigateToMonth;

  const _StempeluhrKachel({
    required this.skin,
    required this.height,
    required this.compact,
    required this.onNavigateToMonth,
  });

  @override
  State<_StempeluhrKachel> createState() => _StempeluhrKachelState();
}

class _StempeluhrKachelState extends State<_StempeluhrKachel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;
  bool _justStamped = false;

  // NEU: manuell verschobene Kommen-Zeit (null = "jetzt")
  TimeOfDay? _customTime;
  double _dragStart = 0;
  double _accumulated = 0;
  static const double _pxPerStep = 22; // Sensibilität des Wischens

  // NEU: aktuell gültige Rundungs-Regel aus den Einstellungen
  String get _rundungRule => Hive.box('einstellungen')
      .get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;

  // NEU: Kommen-Zeit per Wischen anpassen – Schrittgröße kommt aus den Settings
  void _adjustTime(int direction) {
    final base = _customTime ??
        (() {
          final rounded = TimeRounding.round(DateTime.now(), _rundungRule);
          return TimeOfDay(hour: rounded.hour, minute: rounded.minute);
        })();
    final total = TimeRounding.steppedTotal(
        base.hour * 60 + base.minute, _rundungRule, direction);
    setState(() {
      _customTime = TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
    });
    HapticFeedback.selectionClick();
  }

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _pressScale = Tween(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _stempel() async {
    final now = DateTime.now();
    final TimeOfDay kommen = _customTime ??
        (() {
          final rounded = TimeRounding.round(now, _rundungRule);
          return TimeOfDay(hour: rounded.hour, minute: rounded.minute);
        })();
    final kommenTime =
        '${kommen.hour.toString().padLeft(2, '0')}:${kommen.minute.toString().padLeft(2, '0')}';
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final box = Hive.box('arbeitszeiten');
    final existing = box.get(dateKey);
    final entry = {
      'id': now.millisecondsSinceEpoch.toString(),
      'datum': dateKey,
      'kommen': kommenTime,
      'gehen': '',
      'TKF': '',
      'Bemerkung': '',
      'createdAt': now.toIso8601String(),
    };

    final entries = existing is List
        ? List<dynamic>.from(existing)
        : existing is Map
            ? <dynamic>[Map<String, dynamic>.from(existing)]
            : <dynamic>[];
    entries.add(entry);
    await box.put(dateKey, entries);
    await box.flush();
    unawaited(SyncService.instance.pushArbeitszeit(dateKey).catchError((error) {
      debugPrint('Arbeitszeit-Sync fehlgeschlagen: $error');
    }));

    if (!mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _justStamped = true);

    if (mounted) {
  showGlassSnackBar(
    context,
    '✓ Kommen $kommenTime gestempelt',
    type: GlassSnackBarType.success,
    duration: const Duration(seconds: 2),
    actionLabel: 'Öffnen',
    onAction: widget.onNavigateToMonth,
  );
}

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _justStamped = false;
          _customTime = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final displayTime = _customTime ??
        (() {
          final now = DateTime.now();
          return TimeOfDay(hour: now.hour, minute: now.minute);
        })();
    final timeStr =
        '${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')}';
    const accentColor = Color(0xFFFFB347);

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        unawaited(_stempel());
      },
      onTapCancel: () => _pressCtrl.reverse(),
      onVerticalDragStart: (d) {
        _dragStart = d.localPosition.dy;
        _accumulated = 0;
      },
      onVerticalDragUpdate: (d) {
        _accumulated += _dragStart - d.localPosition.dy;
        _dragStart = d.localPosition.dy;
        while (_accumulated >= _pxPerStep) {
          _accumulated -= _pxPerStep;
          _adjustTime(1);
        }
        while (_accumulated <= -_pxPerStep) {
          _accumulated += _pxPerStep;
          _adjustTime(-1);
        }
      },
      child: AnimatedBuilder(
        animation: _pressScale,
        builder: (context, child) =>
            Transform.scale(scale: _pressScale.value, child: child),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: PlatformBackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              height: widget.height,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: _justStamped
                    ? accentColor.withValues(alpha: skin.isLight ? 0.12 : 0.18)
                    : (skin.isLight
                        ? Colors.white.withValues(alpha: skin.glassOpacity)
                        : skin.bgCard.withValues(alpha: skin.glassOpacity)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accentColor
                      .withValues(alpha: _justStamped ? 0.55 : 0.30),
                  width: _justStamped ? 1.5 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                      color: skin.glassShadow,
                      blurRadius: 16,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: widget.compact
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: _justStamped ? 0.25 : 0.15),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _justStamped
                                  ? Icon(Icons.check_rounded, key: const ValueKey('check'), size: 16, color: accentColor)
                                  : Icon(Icons.login_rounded, key: const ValueKey('stamp'), size: 16, color: accentColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _justStamped ? '✓' : timeStr,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: _justStamped ? 0.25 : 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _justStamped
                                  ? Icon(Icons.check_rounded, key: const ValueKey('check'), size: 18, color: accentColor)
                                  : Icon(Icons.login_rounded, key: const ValueKey('stamp'), size: 18, color: accentColor),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _justStamped ? 'Gestempelt!' : 'Kommen',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary),
                          maxLines: 1,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _justStamped ? '✓ gespeichert' : timeStr,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: accentColor.withValues(alpha: skin.isLight ? 0.85 : 0.75),
                          ),
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
// TASK PREVIEW KACHEL
// ─────────────────────────────────────────────────────────────────────────────

class _TaskPreviewKachel extends StatelessWidget {
  final AppSkin skin;
  final List<Task> tasks;
  final VoidCallback? onTapAll;

  const _TaskPreviewKachel({
    required this.skin,
    required this.tasks,
    this.onTapAll,
  });

  String _formatDue(Task t) {
    if (t.dueDate == null) return '';
    final now = DateTime.now();
    final due = t.dueDate!;
    if (due.year == now.year && due.month == now.month && due.day == now.day) return 'Heute';
    final diff = due.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 1) return 'Mo';
    return DateFormat('EEE', 'de').format(due).substring(0, 2).capitalize();
  }

  Widget _buildTaskRow(Task t) {
    final isOverdue = t.isOverdue;
    final dueLabel = _formatDue(t);
    final dueColor = isOverdue
        ? const Color(0xFFEF5B5B)
        : (t.isToday ? const Color(0xFFFFB347) : skin.surface(0.45));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isOverdue ? const Color(0xFFEF5B5B) : skin.surface(0.25),
                width: 1.8,
              ),
              color: isOverdue
                  ? const Color(0xFFEF5B5B).withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: skin.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (t.isUrgent) ...[
const SizedBox(width: 6),
 Container(
  width: 6,
 height: 6,
 decoration: const BoxDecoration(
 shape: BoxShape.circle,
 color: Color(0xFFEF5B5B),
  ),
 ),
 ],
          if (dueLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              dueLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dueColor),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: PlatformBackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.glassBorder, width: 1.0),
            boxShadow: [
              BoxShadow(color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header — bleibt fix, scrollt nicht mit
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  children: [
                    Text(
                      'AUFGABEN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: skin.surface(0.38),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onTapAll,
                      child: Text(
                        'alle →',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: skin.primary),
                      ),
                    ),
                  ],
                ),
              ),
              // Task-Liste — wächst bis zum Rest-Platz, scrollt dann intern
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Divider(height: 0.5, color: skin.glassBorder),
                  ),
                  itemBuilder: (context, i) => _buildTaskRow(tasks[i]),
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
// WETTER — Kompakter Chip
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherChip extends StatelessWidget {
  final AppSkin skin;
  final String icon;
  final String temp;
  final String city;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  const _WeatherChip({
    required this.skin,
    required this.icon,
    required this.temp,
    required this.city,
    this.isRefreshing = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: PlatformBackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.glassBorder, width: 0.8),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(icon, style: const TextStyle(fontSize: 14)),
    const SizedBox(width: 6),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(temp, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 9, color: Color(0xFF5B8DEF)),
            const SizedBox(width: 2),
            Text(city, style: TextStyle(fontSize: 9, color: skin.surface(0.38), fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    ),
    if (onRefresh != null) ...[
      const SizedBox(width: 4),
      _RefreshButton(
        skin: skin,
        isRefreshing: isRefreshing,
        onTap: onRefresh!,
        size: 13,
      ),
    ],
  ],
),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WETTER — Große Kachel (Settings-Toggle: homescreen_weather_big = true)
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherKachelGross extends StatelessWidget {
  final AppSkin skin;
  final WeatherData? data;
  final String icon;
  final String temp;
  final String city;
  final String detail;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  const _WeatherKachelGross({
    required this.skin,
    required this.data,
    required this.icon,
    required this.temp,
    required this.city,
    required this.detail,
    this.isRefreshing = false,
    this.onRefresh,
  });

  List<({String time, String label, Color color})> _nextTwoSunEvents() {
  final now = DateTime.now();
  final rise = data?.sunrise;
  final set = data?.sunset;

  // Sammle alle bekannten Events mit Zeitstempel
  final events = <(DateTime dt, String label, Color color)>[];

  if (rise != null) events.add((rise, 'Aufgang', const Color(0xFFFFA040)));
  if (set != null) events.add((set, 'Untergang', const Color(0xFFFF6B35)));

  // Morgen-Aufgang schätzen (~24h nach heutigem Aufgang)
  if (rise != null) {
    final tomorrowRise = rise.add(const Duration(hours: 24));
    events.add((tomorrowRise, 'Aufgang', const Color(0xFFFFA040)));
  }

  // Sortieren und nur zukünftige nehmen
  events.sort((a, b) => a.$1.compareTo(b.$1));
  final upcoming = events.where((e) => e.$1.isAfter(now)).take(2).toList();

  return upcoming
      .map((e) => (time: _fmt(e.$1), label: e.$2, color: e.$3))
      .toList();
}

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final sunEvents = _nextTwoSunEvents();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: PlatformBackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.glassBorder, width: 1.0),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Oberer Bereich ──────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wetter-Icon
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(icon, style: const TextStyle(fontSize: 36)),
                  ),
                  const SizedBox(width: 12),
                  // Temp + Gefühlt + Stadt
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(temp,
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: skin.textPrimary,
                                  letterSpacing: -1.0,
                                  height: 1.0,
                                )),
                            if (data?.feelsLikeStr.isNotEmpty == true) ...[
                              const SizedBox(width: 8),
                              Text('Gefühlt ${data!.feelsLikeStr}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: skin.surface(0.45),
                                    fontWeight: FontWeight.w500,
                                  )),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Standort mit BLAUEM Pin
                        Row(children: [
                          Icon(
                            data?.isGps == true
                                ? Icons.location_on
                                : Icons.location_city_outlined,
                            size: 11,
                            color: const Color(0xFF5B8DEF),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(city,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: skin.surface(0.45),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ],
                    ),
                  ),

                  // ── Sonnen-Ereignis ─────────────────────────────────────
if (sunEvents.isNotEmpty)
  _SunEventBadge(
    skin: skin,
    events: sunEvents,
  ),
                ],
              ),

              // ── Trennlinie + Details ─────────────────────────────────
if (data != null) ...[
  const SizedBox(height: 2),
  Row(
    children: [
      Expanded(
        child: Container(height: 0.5, color: skin.surface(0.10)),
      ),
      const SizedBox(width: 8),
      Text(detail,
          style: TextStyle(fontSize: 9, color: skin.surface(0.28))),
      if (onRefresh != null) ...[
        const SizedBox(width: 4),
        _RefreshButton(
          skin: skin,
          isRefreshing: isRefreshing,
          onTap: onRefresh!,
          size: 12,
        ),
      ],
    ],
  ),
  const SizedBox(height: 2),
                Row(
                  children: [
                    _WeatherDetailRow(
                      skin: skin,
                      icon: Icons.water_drop_outlined,
                      label: 'Niederschlag',
                      value: data!.precipStr,
                    ),
                    const SizedBox(width: 30),
                    _WeatherDetailRow(
                      skin: skin,
                      icon: Icons.air_outlined,
                      label: 'Wind',
                      value: data!.windStr,
                    ),
                    // NEU: Luftfeuchtigkeit
                    if (data!.humidityPercent != null) ...[
                      const SizedBox(width: 30),
                      _WeatherDetailRow(
                        skin: skin,
                        icon: Icons.water_outlined,
                        label: 'Luftfeuchte',
                        value: data!.humidityStr,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// NEU: _SunEventBadge — eleganter Sonnenuntergang/Aufgang Badge
// ────────────────────────────────────────────────────────────────────────────

class _SunEventBadge extends StatelessWidget {
  final AppSkin skin;
  final List<({String time, String label, Color color})> events;

  const _SunEventBadge({
    required this.skin,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int i = 0; i < events.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                events[i].label == 'Aufgang'
                    ? Icons.wb_twilight_rounded
                    : Icons.wb_sunny_outlined,
                size: 12,
                color: events[i].color.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 4),
              Text(
                events[i].time,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: i == 0
                      ? skin.textPrimary
                      : skin.textPrimary.withValues(alpha: 0.45),
                  letterSpacing: -0.2,
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
// REFRESH BUTTON — Tap-to-Refresh mit Spin-Animation + kurzer "Fertig"-Bestätigung
// ─────────────────────────────────────────────────────────────────────────────

class _RefreshButton extends StatefulWidget {
  final AppSkin skin;
  final bool isRefreshing;
  final VoidCallback onTap;
  final double size;

  const _RefreshButton({
    required this.skin,
    required this.isRefreshing,
    required this.onTap,
    this.size = 14,
  });

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinCtrl;
  bool _showCheck = false;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isRefreshing) _spinCtrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _RefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isRefreshing && !oldWidget.isRefreshing) {
      // Refresh startet → Icon dreht sich
      _spinCtrl.repeat();
    } else if (!widget.isRefreshing && oldWidget.isRefreshing) {
      // Refresh fertig → Drehung stoppen, kurz Häkchen zeigen
      _spinCtrl.stop();
      _spinCtrl.value = 0;
      setState(() => _showCheck = true);
      Future.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _showCheck = false);
      });
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    return GestureDetector(
      onTap: widget.isRefreshing ? null : widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: _showCheck
              ? Icon(
                  Icons.check_rounded,
                  key: const ValueKey('check'),
                  size: widget.size,
                  color: const Color(0xFF3DD68C),
                )
              : RotationTransition(
                  key: const ValueKey('refresh'),
                  turns: _spinCtrl,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: widget.size,
                    color: widget.isRefreshing
                        ? skin.primary.withValues(alpha: 0.85)
                        : skin.surface(0.38),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEATHER Detail Row — Kompakte Anzeige für Wetter-Details
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherDetailRow extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final String value;

  const _WeatherDetailRow({
    required this.skin,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: skin.surface(0.40)),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  color: skin.surface(0.38),
                  fontWeight: FontWeight.w500,
                )),
            Text(value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: skin.textPrimary,
                )),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIENSTPLAN PLACEHOLDER
// ─────────────────────────────────────────────────────────────────────────────

class _DienstplanPlaceholderKachel extends StatelessWidget {
  final AppSkin skin;
  final VoidCallback? onTap;
  const _DienstplanPlaceholderKachel({required this.skin, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: PlatformBackdropFilter(
          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFFFB347).withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text('📋', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kein Dienstplan',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Tippen zum Importieren →',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                          color: const Color(0xFFFFB347).withValues(alpha: 0.8))),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DICTATION TASK KACHEL — Long-Press startet Diktat, exakt wie Tasks-Screen
// ─────────────────────────────────────────────────────────────────────────────

class _DictationTaskKachel extends StatefulWidget {
  final AppSkin skin;
  final double height;
  final bool compact;
  final void Function(ParsedSpokenTask, String) onResult;
  final void Function(ParsedSpokenTask, String) onNeedsReview;
  final VoidCallback? onNavigateToTasks;
  final VoidCallback? onNavigateToTasksQuickAdd;
  final bool useDictate;

  const _DictationTaskKachel({
    required this.skin,
    required this.height,
    required this.compact,
    required this.onResult,
    required this.onNeedsReview,
    this.onNavigateToTasks,
    this.onNavigateToTasksQuickAdd,
    required this.useDictate,
  });

  @override
  State<_DictationTaskKachel> createState() => _DictationTaskKachelState();
}

class _DictationTaskKachelState extends State<_DictationTaskKachel>
    with TickerProviderStateMixin {
  final GlobalKey _kachelKey = GlobalKey();
  final GlobalKey<DictationFabState> _fabKey = GlobalKey<DictationFabState>();

  bool _isListening = false;
  OverlayEntry? _overlayEntry;

  // Pulsier-Animation (nur während Listening)
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

   _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    }

  @override
  void dispose() {
    _removeOverlay();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Overlay ────────────────────────────────────────────────────────────────

  Offset _getAnchorTopRight() {
    final box = _kachelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    final pos = box.localToGlobal(Offset.zero);
    return Offset(pos.dx + box.size.width, pos.dy);
  }

  double _getKachelWidth() {
    final box = _kachelKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 100.0;
  }

  void _removeOverlay() {
  try {
    _overlayEntry?.remove();
  } catch (_) {}
  _overlayEntry = null;
}

  void _rebuildOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  void _showOverlay() {
  _removeOverlay();
  const accentColor = Color(0xFF3DD68C);

  _overlayEntry = OverlayEntry(builder: (_) {
    final fabState = _fabKey.currentState;
    if (fabState == null) return const SizedBox.shrink();

    final anchorTopRight = _getAnchorTopRight();
    final kachelWidth = _getKachelWidth();
    final kachelHeight = widget.height;

    final bubbles = fabState.buildExternalBubbles(
      skin: widget.skin,
      anchorTopRight: anchorTopRight,
      kachelWidth: kachelWidth,
      kachelHeight: kachelHeight,
    );

    if (bubbles.isEmpty) return const SizedBox.shrink();

    final showScrim = fabState.phase != DictationPhase.idle;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
        // ── Abdunklung: alles außer der Diktier-Funktion tritt zurück ──
        if (showScrim)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: 1.0,
                child: Container(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ),
          ),
        // ── Kachel-Klon bleibt hell über der Abdunklung sichtbar ──
        if (showScrim)
          Positioned(
            left: anchorTopRight.dx - kachelWidth,
            top: anchorTopRight.dy,
            width: kachelWidth,
            height: kachelHeight,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PlatformBackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: widget.skin.glassBlur, sigmaY: widget.skin.glassBlur),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: widget.skin.isLight ? 0.14 : 0.20),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentColor.withValues(alpha: 0.65), width: 1.6),
                    ),
                    child: widget.compact
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(Icons.mic_rounded, size: 16, color: accentColor),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Höre zu…',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.mic_rounded, size: 18, color: accentColor),
                              ),
                              const Spacer(),
                              const Text('Aufgabe',
                                  style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                              const SizedBox(height: 1),
                              const Text('Höre zu…',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: accentColor)),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ...bubbles,
        ],
      ),
    );
  });

  Overlay.of(context).insert(_overlayEntry!);
}

  void _hideOverlay() {
    _removeOverlay();
    _pulseCtrl.stop();
    if (mounted) setState(() => _isListening = false);
  }

  // ── Aktionen ───────────────────────────────────────────────────────────────

  void _handleLongPress() {
    if (!widget.useDictate) return;
    HapticFeedback.mediumImpact();
    _showOverlay();
    _fabKey.currentState?.startListening();
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final dx = details.offsetFromOrigin.dx;
    _fabKey.currentState?.onExternalDragUpdate(dx);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _fabKey.currentState?.onExternalDragEnd();
    _fabKey.currentState?.finishListening();
  }

  void _handleTap() {
    if (_isListening) return;
    if (widget.useDictate) {
      widget.onNavigateToTasks?.call();
    } else {
      // Diktieren deaktiviert → Tap soll direkt "Neue Aufgabe" öffnen
      widget.onNavigateToTasksQuickAdd?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    const accentColor = Color(0xFF3DD68C);

    return SizedBox(
      width: double.infinity,
      child: Stack(
      children: [
        // ── Unsichtbarer DictationFab für Logik ──────────────────────────
        if (widget.useDictate)
          Offstage(
            offstage: true,
            child: DictationFab(
              key: _fabKey,
              skin: skin,
              hideButton: true,
              useExternalBubbles: true,
              onBubbleStateChanged: () {
                final fabState = _fabKey.currentState;
                if (fabState == null) return;
                if (fabState.phase == DictationPhase.idle &&
                    !fabState.isCancelling &&
                    fabState.cancelAnimCtrl.value == 0) {
                  _removeOverlay();
                } else if (_overlayEntry == null) {
                  _showOverlay();
                } else {
                  _rebuildOverlay();
                }
              },
              onResult: (parsed, logRef) {
                widget.onResult(parsed, logRef);
                _hideOverlay();
              },
              onNeedsReview: (parsed, logRef) {
                widget.onNeedsReview(parsed, logRef);
                _hideOverlay();
              },
              onListeningStart: () {
                if (mounted) setState(() => _isListening = true);
                _pulseCtrl.repeat(reverse: true);
                _rebuildOverlay();
              },
              onListeningEnd: () {
                if (mounted) setState(() => _isListening = false);
                _pulseCtrl.stop();
                _rebuildOverlay();
              },
            ),
          ),

        // ── Sichtbare Kachel ─────────────────────────────────────────────
        GestureDetector(
          key: _kachelKey,
          onTap: _handleTap,
          onLongPress: _handleLongPress,
          onLongPressMoveUpdate: _handleLongPressMoveUpdate,
          onLongPressEnd: _handleLongPressEnd,
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PlatformBackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                  child: Container(
                    width: double.infinity,
                    height: widget.height,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: _isListening
                          ? accentColor.withValues(
                              alpha: skin.isLight ? 0.12 : 0.18)
                          : (skin.isLight
                              ? Colors.white
                                  .withValues(alpha: skin.glassOpacity)
                              : skin.bgCard
                                  .withValues(alpha: skin.glassOpacity)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isListening
                            ? accentColor.withValues(
                                alpha: 0.5 + 0.2 * _pulseAnim.value)
                            : accentColor.withValues(alpha: 0.30),
                        width: _isListening ? 1.6 : 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: skin.glassShadow,
                            blurRadius: 16,
                            offset: const Offset(0, 4)),
                        if (_isListening)
                          BoxShadow(
                            color: accentColor.withValues(
                                alpha: 0.12 * _pulseAnim.value),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: widget.compact
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(
                                      alpha: _isListening ? 0.22 + 0.08 * _pulseAnim.value : 0.15),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Center(
                                  child: Icon(
                                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                                    size: 16,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _isListening ? 'Höre zu…' : 'Task',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: skin.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(
                                alpha: _isListening ? 0.22 + 0.08 * _pulseAnim.value : 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isListening
                                  ? Icon(Icons.mic_rounded, key: const ValueKey('on'), size: 18, color: accentColor)
                                  : Icon(Icons.mic_none_rounded, key: const ValueKey('off'), size: 18, color: accentColor),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text('Aufgabe', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                        const SizedBox(height: 1),
                        Text(
                          _isListening ? 'Höre zu…' : 'Halten & sprechen',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: _isListening ? accentColor : accentColor.withValues(alpha: skin.isLight ? 0.8 : 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STRING EXTENSION
// ─────────────────────────────────────────────────────────────────────────────

extension _StringExt on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// EREIGNIS-STAPEL (heutige Ereignisse, ein Wisch = eine Karte weiter)
// ─────────────────────────────────────────────────────────────────────────────

class _EventStackKachel extends StatefulWidget {
  final AppSkin skin;
  final List<DayPlanItem> items;
  final DateTime now;
  final int depth;
  final VoidCallback? onChanged;
  const _EventStackKachel({
    required this.skin,
    required this.items,
    required this.now,
    required this.depth,
    this.onChanged,
  });

  @override
  State<_EventStackKachel> createState() => _EventStackKachelState();
}

class _EventStackKachelState extends State<_EventStackKachel> with SingleTickerProviderStateMixin {
  static const double _cardH = 82;
  static const double _peek = 8;
  static const double _inset = 8;

  late final AnimationController _ctrl;
  int _sel = 0;
  int _lastAuto = -1;
  String _lastSig = '';
  int _tok = 0;
  double _dir = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _syncSelection();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _sig(List<DayPlanItem> l) => l.map((e) => '${e.id}@${e.start.millisecondsSinceEpoch}').join('|');

  /// Das nächste anstehende Ereignis; sind alle vorbei, das letzte.
  int _autoIdx() {
    final n = widget.items.length;
    final w = widget.now;
    final nowMin = DateTime(w.year, w.month, w.day, w.hour, w.minute);
    for (int i = 0; i < n; i++) {
      if (!widget.items[i].start.isBefore(nowMin)) return i;
    }
    return n - 1;
  }

  /// Automatisch nach vorn holen, sobald sich das "nächste Ereignis" oder die Liste ändert.
  /// Dazwischen bleibt die per Wisch gewählte Karte vorn.
  void _syncSelection() {
    final n = widget.items.length;
    if (n == 0) {
      _sel = 0;
      return;
    }
    final sig = _sig(widget.items);
    final auto = _autoIdx();
    if (sig != _lastSig || auto != _lastAuto) {
      _lastSig = sig;
      _lastAuto = auto;
      _sel = auto;
      _tok++;
      if (_ctrl.value != 0) _ctrl.value = 0;
    }
    if (_sel > n - 1) _sel = n - 1;
  }

  @override
  void didUpdateWidget(covariant _EventStackKachel old) {
    super.didUpdateWidget(old);
    _syncSelection();
  }

  Future<void> _advance(int dir) async {
    final target = _sel + dir;
    if (target < 0 || target >= widget.items.length || _ctrl.isAnimating) return;
    HapticFeedback.selectionClick();
    _dir = dir.toDouble();
    final tok = ++_tok;
    await _ctrl.forward(from: 0);
    if (!mounted || tok != _tok) return;
    setState(() {
      _sel = target;
      _ctrl.value = 0;
    });
  }

  /// Vorderstes Ereignis löschen (gleicher DayPlanStore wie der Tagesplan im Schedule-Screen).
  Future<void> _confirmDelete() async {
    if (widget.items.isEmpty || _sel >= widget.items.length) return;
    final it = widget.items[_sel];
    HapticFeedback.mediumImpact();
    final ok = await confirmDeleteDialog(
      context: context,
      skin: widget.skin,
      title: 'Ereignis löschen',
      message: '„${it.title}“ wird aus dem Tagesplan gelöscht.',
    );
    if (ok != true || !mounted) return;
    final key = DateFormat('yyyy-MM-dd').format(widget.now);
    await DayPlanStore.delete(key, it.id);
    widget.onChanged?.call();
  }

  Widget _slot(DayPlanItem it, double p,
      {double opacity = 1, double dy = 0, double angle = 0, bool hl = false}) {
    return Positioned(
      left: _inset * p,
      right: _inset * p,
      top: _peek * p,
      height: _cardH,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: _EventCard(skin: widget.skin, item: it, highlight: hl),
          ),
        ),
      ),
    );
  }

  /// Punkt-Indikator (wie bei Apple): wo im Stapel bin ich, wie viele davor/danach.
  Widget _dots() {
    final skin = widget.skin;
    final n = widget.items.length;
    const maxDots = 7;
    var start = 0;
    var end = n;
    if (n > maxDots) {
      start = (_sel - maxDots ~/ 2).clamp(0, n - maxDots).toInt();
      end = start + maxDots;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = start; i < end; i++)
          Builder(builder: (_) {
            final active = i == _sel;
            final edge = n > maxDots && ((i == start && start > 0) || (i == end - 1 && end < n));
            final size = active ? 8.0 : (edge ? 4.0 : 6.0);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 3),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? skin.surface(0.70) : skin.surface(0.18),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final n = items.length;
    if (n == 0) return const SizedBox.shrink();
    final v = n < widget.depth ? n : widget.depth;
    DayPlanItem? at(int i) => (i >= 0 && i < n) ? items[i] : null;

    final stack = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _confirmDelete,
      onVerticalDragEnd: (d) {
        final vy = d.primaryVelocity ?? 0;
        if (vy < -120) {
          _advance(1);
        } else if (vy > 120) {
          _advance(-1);
        }
      },
      child: SizedBox(
        height: _cardH + _peek * (v - 1),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_ctrl.value);
            final animating = _ctrl.value > 0;
            final children = <Widget>[];

            if (!animating) {
              for (int k = v - 1; k >= 0; k--) {
                final it = at(_sel + k);
                if (it != null) children.add(_slot(it, k.toDouble(), hl: k == 0));
              }
            } else if (_dir > 0) {
              // vorwärts: vorderste Karte wischt nach links weg, der Rest rückt nach
              final enter = at(_sel + v);
              if (enter != null) children.add(_slot(enter, v - t, opacity: t));
              for (int k = v - 1; k >= 1; k--) {
                final it = at(_sel + k);
                if (it != null) children.add(_slot(it, k - t));
              }
              children.add(_slot(items[_sel], 0,
                  hl: true, opacity: 1 - t, dy: -_cardH * 1.3 * t));
            } else {
              // zurück: vorherige Karte kommt von links nach vorn, der Rest rutscht nach hinten
              for (int k = v - 1; k >= 0; k--) {
                final it = at(_sel + k);
                if (it != null) children.add(_slot(it, k + t, opacity: k == v - 1 ? 1 - t : 1));
              }
              children.add(_slot(items[_sel - 1], 0,
                  hl: true, opacity: t, dy: -_cardH * 1.3 * (1 - t)));
            }
            return Stack(clipBehavior: Clip.none, children: children);
          },
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: stack),
        if (n > 1) ...[
          const SizedBox(width: 10),
          _dots(),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final AppSkin skin;
  final DayPlanItem item;
  final bool highlight;
  const _EventCard({required this.skin, required this.item, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final it = item;
    final fmt = DateFormat('HH:mm');
    // Deckend, damit die Karten im Stapel nicht durcheinander scheinen
    final glass = skin.isLight
        ? Colors.white.withValues(alpha: skin.glassOpacity)
        : skin.bgCard.withValues(alpha: skin.glassOpacity);
    final solid = Color.alphaBlend(glass, skin.bgBase);

    final loc = it.loc;
    final name = (loc?.name ?? '').trim();
    var addr = loc?.singleLine ?? '';
    if (addr.isEmpty && loc != null && loc.hasCoords) {
      addr = '${loc.lat!.toStringAsFixed(5)}, ${loc.lng!.toStringAsFixed(5)}';
    }
    if (addr.isEmpty) addr = it.location.trim();
    // Zeile 2: Ortsname, wenn vorhanden, sonst die Adresse
    final placeLine = name.isNotEmpty ? name : addr;
    final canNav = placeLine.isNotEmpty && MapsNavigator.canNavigate(loc, it.location);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        color: solid,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder,
          width: highlight ? 1.4 : 1.0,
        ),
        boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Uhrzeit untereinander
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmt.format(it.start), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: skin.primary)),
          const SizedBox(height: 3),
          Text(fmt.format(it.end), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: skin.surface(0.42))),
        ]),
        const SizedBox(width: 14),
        // Titel groß, darunter Ort/Adresse in Weiß
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary, height: 1.2)),
              if (placeLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.place_outlined, size: 13, color: skin.textPrimary.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(placeLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: skin.textPrimary, height: 1.2)),
                  ),
                ]),
              ],
            ],
          ),
        ),
        // Navigieren
        if (canNav) ...[
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.mediumImpact();
              MapsNavigator.navigate(context, skin: skin, loc: it.loc, fallbackText: it.location);
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: skin.primary.withValues(alpha: skin.isLight ? 0.13 : 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: skin.primary.withValues(alpha: skin.isLight ? 0.28 : 0.45), width: 1.5),
              ),
              child: Icon(Icons.navigation_outlined, size: 18, color: skin.primary),
            ),
          ),
        ],
      ]),
    );
  }
}
