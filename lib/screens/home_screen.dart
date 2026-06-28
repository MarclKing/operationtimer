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
import 'tasks_screen.dart' show TaskStore, Task;
import '../services/spoken_task_parser.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN — News-App-Style Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToMonth;
  final VoidCallback? onNavigateToFahrtenbuch;
  final VoidCallback? onNavigateToFahrtenbuchNeueFahrt;
  final VoidCallback? onNavigateToTasks;
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
    this.onNavigateToScheduleAndImport,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late DateTime _selectedDate;
  late AnimationController _greetingCtrl;
  late Animation<double> _greetingFade;

  // Für Uhr-Ticker
  late DateTime _now;

  // ── NEU: Wetter-State, wird verzögert nach erstem Frame befüllt ──────────
  WeatherData? _weatherData;

  // Review-Callback von main.dart
  void Function(ParsedSpokenTask, String)? onReviewFromHomescreen;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _now = DateTime.now();

    // Sofort verfügbaren Cache zeigen (kein Warten, kein Netzwerk-Call)
    _weatherData = WeatherService.instance.cached;

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

  @override
  void dispose() {
    _greetingCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      setState(() => _selectedDate = widget.selectedDate);
    }
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
    setState(() {}); // Aufgaben-Preview aktualisieren
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
        return '$base, Bro!';
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
  List<Task> _getUpcomingTasks() {
    final all = TaskStore.loadAll();
    final open = all.where((t) => !t.done).toList();
    open.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    return open.take(3).toList();
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
    final upcomingTasks = _getUpcomingTasks();
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;

    final box = Hive.box('einstellungen');
    final taskAddMode = box.get('homescreen_task_add_mode', defaultValue: 'dictate') as String;
    final useDictate = taskAddMode == 'dictate';

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        bottom: false,
        child: FadingListView(
          fadeFromBottom: bottomNavHeight + 20,
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
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

              // ── Quick-Access Kacheln ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _StempeluhrKachel(
                        skin: skin,
                        onNavigateToMonth: widget.onNavigateToMonth,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickAccessKachel(
                        skin: skin,
                        icon: '🚗',
                        label: 'Neue Fahrt',
                        sublabel: 'KM + Foto →',
                        accentColor: const Color(0xFF2D6CFF),
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onNavigateToFahrtenbuchNeueFahrt?.call();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DictationTaskKachel(
                        skin: skin,
                        onResult: _createTaskFromSpeech,
                        onNeedsReview: _reviewTaskFromSpeech,
                        onNavigateToTasks: widget.onNavigateToTasks,
                        useDictate: useDictate,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              if (upcomingTasks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _TaskPreviewKachel(
                    skin: skin,
                    tasks: upcomingTasks,
                    onTapAll: widget.onNavigateToTasks,
                  ),
                ),
                const SizedBox(height: 14),
              ],

              SizedBox(height: bottomNavHeight + 16),
            ],
          ),
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
      'P': 'Frühdienst',
      'P1': 'Frühdienst 1',
      'P2': 'Frühdienst 2',
      'F': 'Spätdienst',
      'F1': 'Spätdienst 1',
      'F2': 'Spätdienst 2',
      'U': 'Urlaub',
      'DA': 'Dienstfrei',
      'X': 'Frei',
      'VK': 'Vertretungskraft',
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
      child: BackdropFilter(
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
  final String icon;
  final String label;
  final String sublabel;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _QuickAccessKachel({
    required this.skin,
    required this.icon,
    required this.label,
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
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              height: 100,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon Badge kompakt
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
  final VoidCallback onNavigateToMonth;

  const _StempeluhrKachel({
    required this.skin,
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

  void _stempel() {
    final now = DateTime.now();
    final kommenTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
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

    if (existing is List) {
      existing.add(entry);
      box.put(dateKey, existing);
    } else {
      box.put(dateKey, [entry]);
    }

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
      if (mounted) setState(() => _justStamped = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    const accentColor = Color(0xFFFFB347);

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        _stempel();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _pressScale,
        builder: (context, child) =>
            Transform.scale(scale: _pressScale.value, child: child),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              height: 100,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accentColor
                          .withValues(alpha: _justStamped ? 0.25 : 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _justStamped
                            ? Icon(Icons.check_rounded,
                                key: const ValueKey('check'),
                                size: 18,
                                color: accentColor)
                            : Icon(Icons.login_rounded,
                                key: const ValueKey('stamp'),
                                size: 18,
                                color: accentColor),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _justStamped ? 'Gestempelt!' : 'Kommen',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: skin.textPrimary,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _justStamped ? '✓ gespeichert' : timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: accentColor
                          .withValues(alpha: skin.isLight ? 0.85 : 0.75),
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

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
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
            children: [
              // Header
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
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: skin.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Task-Einträge
              ...tasks.asMap().entries.map((entry) {
                final i = entry.key;
                final t = entry.value;
                final isOverdue = t.isOverdue;
                final dueLabel = _formatDue(t);
                final dueColor = isOverdue
                    ? const Color(0xFFEF5B5B)
                    : (t.isToday ? const Color(0xFFFFB347) : skin.surface(0.45));

                return Column(
                  children: [
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Divider(height: 0.5, color: skin.glassBorder),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                      child: Row(
                        children: [
                          // Checkbox-Ring
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isOverdue
                                    ? const Color(0xFFEF5B5B)
                                    : skin.surface(0.25),
                                width: 1.8,
                              ),
                              color: isOverdue
                                  ? const Color(0xFFEF5B5B).withValues(alpha: 0.08)
                                  : Colors.transparent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Titel
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
                          // Due Label
                          if (dueLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              dueLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: dueColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 4),
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

  const _WeatherChip({
    required this.skin,
    required this.icon,
    required this.temp,
    required this.city,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
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
                  Text(
                    temp,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: skin.textPrimary,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, size: 9, color: Color(0xFF5B8DEF)),
                      const SizedBox(width: 2),
                      Text(
                        city,
                        style: TextStyle(
                          fontSize: 9,
                          color: skin.surface(0.38),
                          fontWeight: FontWeight.w500,
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

  const _WeatherKachelGross({
    required this.skin,
    required this.data,
    required this.icon,
    required this.temp,
    required this.city,
    required this.detail,
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
      child: BackdropFilter(
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
                            color: const Color(0xFF5B8DEF), // ← BLAU
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

                  // ── Sonnen-Ereignis: elegant neu designt ──────────────
                  if (sunEvents.isNotEmpty) ...[
  const SizedBox(width: 12),
  _SunEventBadge(
    skin: skin,
    events: sunEvents,
  ),
],
                ],
              ),

              // ── Trennlinie + Details ─────────────────────────────────
              if (data != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(height: 0.5, color: skin.surface(0.10)),
                    ),
                    const SizedBox(width: 8),
                    Text(detail,
                        style: TextStyle(fontSize: 9, color: skin.surface(0.28))),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _WeatherDetailRow(
                      skin: skin,
                      icon: Icons.water_drop_outlined,
                      label: 'Niederschlag',
                      value: data!.precipStr,
                    ),
                    const SizedBox(width: 20),
                    _WeatherDetailRow(
                      skin: skin,
                      icon: Icons.air_outlined,
                      label: 'Wind',
                      value: data!.windStr,
                    ),
                    // NEU: Luftfeuchtigkeit
                    if (data!.humidityPercent != null) ...[
                      const SizedBox(width: 20),
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
        child: BackdropFilter(
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
  final void Function(ParsedSpokenTask, String) onResult;
  final void Function(ParsedSpokenTask, String) onNeedsReview;
  final VoidCallback? onNavigateToTasks;
  final bool useDictate;

  const _DictationTaskKachel({
    required this.skin,
    required this.onResult,
    required this.onNeedsReview,
    this.onNavigateToTasks,
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

  // Press-Animation
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;

  // Pulsier-Animation (nur während Listening)
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _pressScale = Tween(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _removeOverlay();
    _pressCtrl.dispose();
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

    _overlayEntry = OverlayEntry(builder: (_) {
      final fabState = _fabKey.currentState;
      if (fabState == null) return const SizedBox.shrink();

      final anchorTopRight = _getAnchorTopRight();
      final kachelWidth = _getKachelWidth();

      final bubbles = fabState.buildExternalBubbles(
        skin: widget.skin,
        anchorTopRight: anchorTopRight,
        kachelWidth: kachelWidth,
      );

      if (bubbles.isEmpty) return const SizedBox.shrink();

      return Stack(
        children: bubbles,
      );
    });

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _removeOverlay();
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
    widget.onNavigateToTasks?.call();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    const accentColor = Color(0xFF3DD68C);

    return Stack(
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
                _rebuildOverlay();
              },
              onListeningEnd: () {
                if (mounted) setState(() => _isListening = false);
                _rebuildOverlay();
              },
            ),
          ),

        // ── Sichtbare Kachel ─────────────────────────────────────────────
        GestureDetector(
          key: _kachelKey,
          onTapDown: (_) => _pressCtrl.forward(),
          onTapUp: (_) {
            _pressCtrl.reverse();
            _handleTap();
          },
          onTapCancel: () => _pressCtrl.reverse(),
          onLongPress: _handleLongPress,
          onLongPressMoveUpdate: _handleLongPressMoveUpdate,
          onLongPressEnd: _handleLongPressEnd,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pressScale, _pulseAnim]),
            builder: (context, child) => Transform.scale(
              scale: _pressScale.value,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                  child: Container(
                    height: 100,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(
                                alpha: _isListening
                                    ? 0.22 + 0.08 * _pulseAnim.value
                                    : 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isListening
                                  ? Icon(Icons.mic_rounded,
                                      key: const ValueKey('on'),
                                      size: 18,
                                      color: accentColor)
                                  : Icon(Icons.mic_none_rounded,
                                      key: const ValueKey('off'),
                                      size: 18,
                                      color: accentColor),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Aufgabe',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: skin.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _isListening ? 'Höre zu…' : 'Halten & sprechen',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: _isListening
                                ? accentColor
                                : accentColor.withValues(
                                    alpha: skin.isLight ? 0.8 : 0.7),
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
          ),
        ),
      ],
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