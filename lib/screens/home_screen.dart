import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/dictation_fab.dart';
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

  const HomeScreen({
    super.key,
    required this.onNavigateToMonth,
    required this.selectedDate,
    required this.onDateChanged,
    this.onNavigateToFahrtenbuch,
    this.onNavigateToFahrtenbuchNeueFahrt,
    this.onNavigateToTasks,
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

  // DictationFab Key
  final GlobalKey<DictationFabState> _dictationFabKey = GlobalKey<DictationFabState>();
  bool _dictationOverlayActive = false;

  // Review-Callback von main.dart
  void Function(ParsedSpokenTask, String)? onReviewFromHomescreen;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _now = DateTime.now();

    _greetingCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _greetingFade = CurvedAnimation(parent: _greetingCtrl, curve: Curves.easeOut);
    _greetingCtrl.forward();

    // Uhr jede Minute aktualisieren
    _scheduleNextMinuteTick();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ „${task.title}" gespeichert'),
      backgroundColor: AppTheme.of(context).statComplete,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      duration: const Duration(seconds: 2),
    ));
  }

  void _createTaskFromSpeech(ParsedSpokenTask parsed, String logRef) {
    _saveTaskFromSpeech(parsed, logRef);
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

    // Modus aus Settings lesen
    final box = Hive.box('einstellungen');
    final taskAddMode = box.get('homescreen_task_add_mode', defaultValue: 'dictate') as String;
    final useDictate = taskAddMode == 'dictate';

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: FadingListView(
              fadeFromBottom: bottomNavHeight + 20,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 56), // Platz für Top-Bar

                  // ── Zeit + Begrüßung ──────────────────────────────────────────
                  FadeTransition(
                    opacity: _greetingFade,
                    child: _buildHeroHeader(skin),
                  ),

                  const SizedBox(height: 16),

                  // ── Wetter ──────────────────────────────────────────────────────
                  _buildWeatherRow(skin),

                  const SizedBox(height: 14),

                  // ── Heutiger Dienst ───────────────────────────────────────────
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
                  ],

                  // ── Quick-Access Kacheln ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickAccessKachel(
                            skin: skin,
                            icon: '🎙',
                            label: 'Aufgabe',
                            sublabel: useDictate ? 'Halten & sprechen' : 'Tippen zum Öffnen',
                            accentColor: const Color(0xFF3DD68C),
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              if (useDictate) {
                                // Diktat direkt starten
                                _dictationFabKey.currentState?.startListening();
                              } else {
                                widget.onNavigateToTasks?.call();
                              }
                            },
                            onLongPress: useDictate ? () {
                              // Direkt Diktat starten
                              _dictationFabKey.currentState?.startListening();
                            } : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Aufgaben-Vorschau ─────────────────────────────────────────
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

          // ── DictationFab — nur im Diktat-Modus ──────────────────────────────
          if (useDictate)
            Positioned(
              right: 20,
              bottom: bottomNavHeight + 16,
              child: DictationFab(
                key: _dictationFabKey,
                skin: skin,
                hideButton: true,
                onResult: _createTaskFromSpeech,
                onNeedsReview: _reviewTaskFromSpeech,
                onListeningStart: () => setState(() => _dictationOverlayActive = true),
                onListeningEnd: () => setState(() => _dictationOverlayActive = false),
              ),
            ),
        ],
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
  final weatherEnabled =
      box.get('homescreen_weather_big', defaultValue: false) as bool;
  final cityName = _getWeatherCity() ?? '';

  return FutureBuilder<WeatherData?>(
    future: WeatherService.instance.fetchIfNeeded(cityName),
    builder: (context, snapshot) {
      final data = snapshot.data ?? WeatherService.instance.cached;
      final weatherIcon = data?.icon ?? '⛅';
      final tempStr = data?.tempStr ?? '—°';
      final cityLabel = data == null
          ? (cityName.isNotEmpty ? cityName : 'Wird geladen…')
          : (data.isGps ? 'Aktueller Standort' : data.city);
      final detail = data != null
          ? 'Aktualisiert ${_formatWeatherAge(data.fetchedAt)}'
          : 'Standort oder Stadt…';

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
    },
  );
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
  for (final w in work) { if (u == w || u.startsWith('$w/')) return skin.primary; }
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
      'P': 'Frühdienst', 'P1': 'Frühdienst 1', 'P2': 'Frühdienst 2',
      'F': 'Spätdienst', 'F1': 'Spätdienst 1', 'F2': 'Spätdienst 2',
      'U': 'Urlaub', 'DA': 'Dienstfrei', 'X': 'Frei',
      'VK': 'Vertretungskraft', 'T': 'Tagdienst',
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
// QUICK ACCESS KACHEL — Neue Fahrt / Neue Aufgabe
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
    _pressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
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
        builder: (context, child) => Transform.scale(scale: _pressScale.value, child: child),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
            child: Container(
              height: 130,
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                    : skin.bgCard.withValues(alpha: skin.glassOpacity),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.accentColor.withValues(alpha: 0.30),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 4)),
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon Badge
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(widget.icon, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  const Spacer(),
                  // Label
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: skin.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Sub-Label
                  Text(
                    widget.sublabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: widget.accentColor.withValues(alpha: skin.isLight ? 0.8 : 0.7),
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

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.glassBorder, width: 1.0),
            boxShadow: [BoxShadow(
                color: skin.glassShadow, blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hauptzeile: Icon + Temp + Stadt ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 40)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(temp,
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                  color: skin.textPrimary,
                                  letterSpacing: -1,
                                )),
                            if (data != null) ...[
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
                        Row(children: [
                          if (data?.isGps == true)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.location_on,
                                  size: 11, color: skin.primary),
                            ),
                          Text(city,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: skin.surface(0.5),
                              )),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Detail-Zeile: Niederschlag + Wind ──
              if (data != null) ...[
                const SizedBox(height: 12),
                Container(
                  height: 0.5,
                  color: skin.surface(0.10),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _WeatherDetail(
                      skin: skin,
                      icon: Icons.water_drop_outlined,
                      label: 'Niederschlag',
                      value: data!.precipStr,
                    ),
                    const SizedBox(width: 16),
                    _WeatherDetail(
                      skin: skin,
                      icon: Icons.air_outlined,
                      label: 'Wind',
                      value: data!.windStr,
                    ),
                    const Spacer(),
                    Text(detail,
                        style: TextStyle(
                          fontSize: 10,
                          color: skin.surface(0.30),
                        )),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 6),
                Text(detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: skin.surface(0.38),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherDetail extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final String value;

  const _WeatherDetail({
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
        Icon(icon, size: 13, color: skin.surface(0.45)),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: 9,
                  color: skin.surface(0.35),
                  fontWeight: FontWeight.w500,
                )),
            Text(value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: skin.textPrimary,
                )),
          ],
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