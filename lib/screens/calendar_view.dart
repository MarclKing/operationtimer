// lib/screens/calendar_view.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/entry_sheet.dart';
import '../models/calendar_event.dart';
import '../screens/tasks_screen.dart' show TaskStore, Task;
import '../services/notification_service.dart';
import '../services/reminder_manager.dart';
import '../services/event_group_store.dart';
import '../services/sync_service.dart';
import '../services/sync_token_service.dart';

// ─────────────────────────────────────────────────────────────────────────
// DIENSTPLAN-LOOKUP — unverändert
// ─────────────────────────────────────────────────────────────────────────

// NEU: EINE Quelle für die Task-Akzentfarbe, damit der Punkt im
// Monatsgrid und der Banner in der Tagesliste garantiert dieselbe Farbe
// zeigen (vorher: Punkt kam aus der Gruppe 'sonstiges', Banner war
// hart-codiert lila — das lief auseinander).
const kTaskAccentColor = Color(0xFF8B5CF6);

class ShiftLookup {
  static final Map<String, Map<String, String?>> _monthCache = {};

  static String? codeForDay(DateTime day) {
    final monthKey = DateFormat('yyyy-MM').format(day);
    final dayKey = DateFormat('yyyy-MM-dd').format(day);

    final cachedMonth = _monthCache[monthKey];
    if (cachedMonth != null) {
      final cachedShift = cachedMonth[dayKey];
      if (cachedShift != null) return cachedShift;
      return null;
    }

    final box = Hive.box('einstellungen');
    final raw = box.get('schedule_$monthKey');
    if (raw is Map) {
      final monthValues = <String, String?>{};
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is String) {
          final value = entry.value.toString().trim();
          monthValues[entry.key.toString()] = value.isEmpty ? null : value.toUpperCase();
        }
      }
      _monthCache[monthKey] = monthValues;
      return monthValues[dayKey];
    }
    _monthCache[monthKey] = const {};
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// CALENDAR VIEW — Einstiegspunkt.
//
// NEU:
// - Monats-Ansicht ist jetzt zweigeteilt: oben ein fest-höhiger PageView
//   (Wochentage + Grid + Dienst-Badge + Dringend-ohne-Datum), unten eine
//   EIGENE, unabhängige ListView für die Tageseinträge. Dadurch bleibt
//   Wischen in der Liste ohne Effekt auf den Monat — nur Wischen im
//   oberen Kalenderbereich wechselt den Monat.
// - Jahresansicht ist jetzt ein unendlich scrollbarer PageView über Jahre
//   (analog zum Monats-Trick mit Anker-Index), nicht mehr fix auf ein Jahr.
// - Beim Wechsel in den AKTUELLEN Monat (egal ob per Swipe, Jahres-Tap
//   oder "Heute") wird automatisch der heutige Tag ausgewählt, nicht der 1.
// ─────────────────────────────────────────────────────────────────────────

class CalendarView extends StatefulWidget {
  final AppSkin skin;
  final void Function(DateTime focusedMonth)? onFocusedMonthChanged;
  final void Function(bool showingYear)? onShowingYearChanged;

  const CalendarView({
    super.key,
    required this.skin,
    this.onFocusedMonthChanged,
    this.onShowingYearChanged,
  });

  @override
  State<CalendarView> createState() => CalendarViewState();
}

class CalendarViewState extends State<CalendarView> with TickerProviderStateMixin {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();
  bool _showingYear = false;
  Rect? _zoomOriginRect;

  /// Anteil der Bildschirmhöhe für den oberen (swipebaren) Kalenderbereich.
  /// Alles darunter ist unabhängig scrollbare Tagesliste.
  static const double _monthTopFraction = 0.46;

  // ── Monats-Paging ──
  static const int _pageMiddleIndex = 6000;
  late final DateTime _anchorMonth = DateTime(_focusedMonth.year, _focusedMonth.month);
  late final PageController _monthPageController =
      PageController(initialPage: _pageMiddleIndex);

  int _indexForMonth(DateTime m) =>
      _pageMiddleIndex + (m.year - _anchorMonth.year) * 12 + (m.month - _anchorMonth.month);

  DateTime _monthForIndex(int idx) =>
      DateTime(_anchorMonth.year, _anchorMonth.month + (idx - _pageMiddleIndex));

  // ── Jahres-Scroll — freies ListView statt PageView, kein Einrasten mehr.
  static const int _yearPageMiddleIndex = 6000;
  late final int _yearAnchor = _focusedMonth.year;
  final ScrollController _yearScrollController = ScrollController();
  double? _yearItemExtent;
  bool _yearScrollInitialized = false;

  int _yearIndexForYear(int y) => _yearPageMiddleIndex + (y - _yearAnchor);
  int _yearForIndex(int idx) => _yearAnchor + (idx - _yearPageMiddleIndex);

  void _onYearScroll() {
    final extent = _yearItemExtent;
    if (extent == null || extent == 0) return;
    final idx = (_yearScrollController.offset / extent).round();
    final y = _yearForIndex(idx);
    if (y != _focusedMonth.year) {
      setState(() => _focusedMonth = DateTime(y, _focusedMonth.month));
      widget.onFocusedMonthChanged?.call(_focusedMonth);
    }
  }

  /// Liefert den Standard-Auswahltag für einen Monat: im AKTUELLEN Monat
  /// (echtes "heute") den heutigen Tag, sonst den 1. des Monats.
  DateTime _defaultSelectedDayFor(DateTime month) {
    final now = DateTime.now();
    if (month.year == now.year && month.month == now.month) {
      return DateTime(now.year, now.month, now.day);
    }
    return DateTime(month.year, month.month, 1);
  }

  @override
  void initState() {
    super.initState();
    _yearScrollController.addListener(_onYearScroll); // siehe Punkt 6
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onFocusedMonthChanged?.call(_focusedMonth);
      // Sync-Fix: tatsächlichen Startzustand immer melden, auch beim Neu-Mounten.
      widget.onShowingYearChanged?.call(_showingYear);
    });
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    _yearScrollController.dispose();
    super.dispose();
  }

  void jumpToToday() {
    final now = DateTime(DateTime.now().year, DateTime.now().month);
    setState(() {
      _focusedMonth = now;
      _selectedDay = DateTime.now();
      _showingYear = false;
    });
    widget.onShowingYearChanged?.call(false);
    final targetIndex = _indexForMonth(now);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_monthPageController.hasClients) {
        _monthPageController.jumpToPage(targetIndex);
      }
    });
    widget.onFocusedMonthChanged?.call(now);
  }

  void openYearView() {
    setState(() => _showingYear = true);
    widget.onShowingYearChanged?.call(true);
    final targetIndex = _yearIndexForYear(_focusedMonth.year);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_yearScrollController.hasClients && _yearItemExtent != null) {
        _yearScrollController.jumpTo(targetIndex * _yearItemExtent!);
      }
    });
  }

  int get currentYear => _focusedMonth.year;

  /// Ausgewählter Tag — wird von TasksScreen für den "+"-Button gebraucht.
  DateTime get selectedDay => _selectedDay;

  void _onMonthTileTapped(int month, Rect originRectGlobal, int year) {
    Rect localOriginRect = originRectGlobal;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final topLeftLocal = box.globalToLocal(originRectGlobal.topLeft);
      localOriginRect = topLeftLocal & originRectGlobal.size;
    }

    final targetMonth = DateTime(year, month);
    setState(() {
      _zoomOriginRect = localOriginRect;
      _focusedMonth = targetMonth;
      _selectedDay = _defaultSelectedDayFor(targetMonth);
      _showingYear = false;
    });
    widget.onShowingYearChanged?.call(false);
    final targetIndex = _indexForMonth(targetMonth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_monthPageController.hasClients) {
        _monthPageController.jumpToPage(targetIndex);
      }
    });
    widget.onFocusedMonthChanged?.call(targetMonth);
  }

  void _openDetail(BuildContext context, CalendarEvent e) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
            child: EventDetailScreen(skin: widget.skin, eventId: e.id),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calendarAreaHeight = MediaQuery.of(context).size.height * _monthTopFraction;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        if (!_showingYear && _zoomOriginRect != null && child.key == const ValueKey('month')) {
          return _ZoomFromRectTransition(anim: anim, originRect: _zoomOriginRect!, child: child);
        }
        if (_showingYear && child.key == const ValueKey('year')) {
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
              child: child,
            ),
          );
        }
        return FadeTransition(opacity: anim, child: child);
      },
      child: _showingYear
          ? Builder(builder: (context) {
              // NEU (Punkt 7, 2. Anlauf): statt einer geratenen Bildschirm-
              // Anteil-Höhe wird die TATSÄCHLICH benötigte Höhe berechnet
              // (Titel + 4 Grid-Zeilen inkl. Abstände + Bottom-Padding) —
              // dadurch kein Abschneiden mehr, aber kompakter als 100%.
              final screenWidth = MediaQuery.of(context).size.width;
              const horizontalPadding = 40.0; // 20 links + 20 rechts
              const crossSpacing = 8.0;
              const mainSpacing = 10.0;
              const childAspectRatio = 0.95;
              const titleAreaHeight = 8.0 + 8.0 + 40.0; // Padding oben/unten + Jahreszahl
              const bottomPadding = 90.0;
              const safetyMargin = 12.0;

              final cellWidth = (screenWidth - horizontalPadding - 2 * crossSpacing) / 3;
              final cellHeight = cellWidth / childAspectRatio;
              final gridHeight = 4 * cellHeight + 3 * mainSpacing;
              final extent = titleAreaHeight + gridHeight + bottomPadding + safetyMargin;

              if (_yearItemExtent != extent) {
                _yearItemExtent = extent;
                if (!_yearScrollInitialized) {
                  _yearScrollInitialized = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_yearScrollController.hasClients) {
                      _yearScrollController.jumpTo(_yearIndexForYear(_focusedMonth.year) * extent);
                    }
                  });
                }
              }
              return ListView.builder(
                key: const ValueKey('year'),
                controller: _yearScrollController,
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                itemExtent: extent,
                itemBuilder: (context, idx) {
                  final y = _yearForIndex(idx);
                  return YearGrid(
                    key: ValueKey('year_$y'),
                    skin: widget.skin,
                    year: y,
                    onMonthTap: (month, rect) => _onMonthTileTapped(month, rect, y),
                  );
                },
              );
            })
          : Column(
              key: const ValueKey('month'),
              children: [
                // ── Oberer Bereich: NUR hier wechselt Wischen den Monat ──
                SizedBox(
                  height: calendarAreaHeight,
                  child: PageView.builder(
                    controller: _monthPageController,
                    scrollDirection: Axis.vertical,
                    reverse: false,
                    onPageChanged: (idx) {
                      final m = _monthForIndex(idx);
                      setState(() {
                        _focusedMonth = m;
                        if (_selectedDay.year != m.year || _selectedDay.month != m.month) {
                          _selectedDay = _defaultSelectedDayFor(m);
                        }
                      });
                      widget.onFocusedMonthChanged?.call(m);
                    },
                    itemBuilder: (context, idx) {
                      final m = _monthForIndex(idx);
                      final selectedForThisMonth =
                          (_selectedDay.year == m.year && _selectedDay.month == m.month)
                              ? _selectedDay
                              : _defaultSelectedDayFor(m);
                      return _MonthTopSection(
                        skin: widget.skin,
                        month: m,
                        selectedDay: selectedForThisMonth,
                        onDaySelected: (d) => setState(() => _selectedDay = d),
                      );
                    },
                  ),
                ),
                // ── Unterer Bereich: eigene, unabhängige Liste ──
                Expanded(
                  child: _DayEntriesSection(
                    skin: widget.skin,
                    selectedDay: _selectedDay,
                    onOpenDetail: _openDetail,
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ZOOM-FROM-RECT TRANSITION — unverändert
// ─────────────────────────────────────────────────────────────────────────

class _ZoomFromRectTransition extends StatelessWidget {
  final Animation<double> anim;
  final Rect originRect;
  final Widget child;

  const _ZoomFromRectTransition({required this.anim, required this.originRect, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullSize = constraints.biggest;
        final targetRect = Offset.zero & fullSize;

        final rectAnim = RectTween(begin: originRect, end: targetRect).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        );

        return AnimatedBuilder(
          animation: rectAnim,
          builder: (context, _) {
            final r = rectAnim.value ?? targetRect;
            final scaleX = r.width / fullSize.width;
            final scaleY = r.height / fullSize.height;
            return Opacity(
              opacity: anim.value.clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.topLeft,
                transform: Matrix4.identity()
                  ..translate(r.left, r.top)
                  ..scale(scaleX, scaleY),
                child: SizedBox(width: fullSize.width, height: fullSize.height, child: child),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// MONTH TOP SECTION — NEU: nur Wochentage + Grid + Dienst-Badge +
// Dringend-ohne-Datum. Die Tagesliste ist NICHT mehr Teil hiervon.
// ─────────────────────────────────────────────────────────────────────────

class _MonthTopSection extends StatefulWidget {
  final AppSkin skin;
  final DateTime month;
  final DateTime selectedDay;
  final void Function(DateTime day) onDaySelected;

  const _MonthTopSection({
    required this.skin,
    required this.month,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  State<_MonthTopSection> createState() => _MonthTopSectionState();
}

class _MonthTopSectionState extends State<_MonthTopSection> {
  Map<int, List<CalendarEvent>> _cachedEntriesByDay = const {};
  List<Task> _cachedUrgentTasks = const [];
  String? _cachedShiftCode;

  @override
  void initState() {
    super.initState();
    CalendarEventStore.changesSignal.addListener(_onExternalChange);
    _refreshCache();
  }

  @override
  void didUpdateWidget(covariant _MonthTopSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) {
      _refreshCache();
    } else if (oldWidget.selectedDay != widget.selectedDay) {
      _cachedShiftCode = ShiftLookup.codeForDay(widget.selectedDay);
    }
  }

  @override
  void dispose() {
    CalendarEventStore.changesSignal.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) {
      _refreshCache();
      setState(() {});
    }
  }

  void _refreshCache() {
    final month = widget.month;
    final all = CalendarEventStore.loadAll();
    final rangeStart = DateTime(month.year, month.month - 1, 1);
    final rangeEnd = DateTime(month.year, month.month + 2, 1);
    final visibleEvents = CalendarEventStore.occurrencesInRange(all, rangeStart, rangeEnd).toList(growable: false);

    final tasks = TaskStore.loadAll();
    final pseudoEvents = <CalendarEvent>[];
    for (final task in tasks) {
      if (task.dueDate == null || task.done) continue;
      pseudoEvents.add(CalendarEvent(
        id: 'task_${task.id}',
        title: task.title,
        start: task.dueDate!,
        end: task.dueDate!.add(const Duration(minutes: 30)),
        allDay: !task.hasTime,
        groupKeys: const ['sonstiges'],
        createdAt: task.createdAt,
      ));
    }

    final events = [...visibleEvents, ...pseudoEvents];
    final monthEntriesByDay = <int, List<CalendarEvent>>{};
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 1);
    for (final event in events) {
      var cursor = event.start.isBefore(monthStart)
          ? monthStart
          : DateTime(event.start.year, event.start.month, event.start.day);
      final coverEnd = event.end.isAfter(monthEnd) ? monthEnd : event.end;
      while (cursor.isBefore(coverEnd) && cursor.isBefore(monthEnd)) {
        if (cursor.year == month.year && cursor.month == month.month) {
          monthEntriesByDay.putIfAbsent(cursor.day, () => []).add(event);
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    _cachedEntriesByDay = monthEntriesByDay;
    _cachedUrgentTasks = tasks.where((task) => task.isUrgent && !task.done && task.dueDate == null).toList(growable: false);
    _cachedShiftCode = ShiftLookup.codeForDay(widget.selectedDay);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    // NEU: Mehrtägige Termine (ganztägig ODER mit Uhrzeit über
    // Tagesgrenzen hinweg) bekamen bisher nur am START-Tag einen Punkt,
    // weil ausschließlich e.start.day als Schlüssel genutzt wurde. Jetzt
    // wird jeder Tag im sichtbaren Monat erfasst, den der Termin überdeckt.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: const ['M', 'D', 'M', 'D', 'F', 'S', 'S']
                .map((d) => Expanded(child: Center(child: _WeekdayLabel(d))))
                .toList(),
          ),
        ),
        const SizedBox(height: 6),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _MonthGrid(
              skin: skin,
              focusedMonth: widget.month,
              selectedDay: widget.selectedDay,
              entriesByDay: _cachedEntriesByDay,
              onDayTap: widget.onDaySelected,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 0.6, margin: const EdgeInsets.symmetric(horizontal: 24), color: skin.surface(0.10)),
        const SizedBox(height: 8),

        Builder(builder: (context) {
          final code = _cachedShiftCode;
          if (code == null || code.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ShiftBadge(skin: skin, code: code),
            ),
          );
        }),

        if (_cachedUrgentTasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final task in _cachedUrgentTasks) _UrgentInlineCard(skin: skin, task: task),
              ],
            ),
          ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;
  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.surface(0.35)));
  }
}

// ─────────────────────────────────────────────────────────────────────────
// MONTH GRID — unverändert
// ─────────────────────────────────────────────────────────────────────────

// NEU: Task-Pseudo-Events (id beginnt mit 'task_') bekommen IMMER die
// einheitliche Task-Akzentfarbe statt der Gruppenfarbe von 'sonstiges' —
// muss exakt mit der Farbe im Tagesbanner (_TaskBannerStrip) übereinstimmen.
Iterable<Color> _colorsForEvent(CalendarEvent e) {
  if (e.id.startsWith('task_')) return [kTaskAccentColor];
  return e.groupKeys.map((k) => EventGroupStore.byKey(k).color);
}

class _MonthGrid extends StatelessWidget {
  final AppSkin skin;
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Map<int, List<CalendarEvent>> entriesByDay;
  final void Function(DateTime) onDayTap;

  const _MonthGrid({
    required this.skin,
    required this.focusedMonth,
    required this.selectedDay,
    required this.entriesByDay,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(focusedMonth.year, focusedMonth.month, 1).weekday;
    final leadingBlanks = firstWeekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final totalRows = (totalCells / 7).ceil();
    final now = DateTime.now();

    int dayCounter = 1 - leadingBlanks;
    final rows = <Widget>[];

    for (int row = 0; row < totalRows; row++) {
      final cells = <Widget>[];
      for (int col = 0; col < 7; col++) {
        final dayNum = dayCounter;
        if (dayNum < 1 || dayNum > daysInMonth) {
          cells.add(const Expanded(child: SizedBox()));
        } else {
          final date = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
          final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
          final isSelected = date.year == selectedDay.year &&
              date.month == selectedDay.month &&
              date.day == selectedDay.day;
          final dayEvents = entriesByDay[dayNum] ?? [];

          cells.add(Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onDayTap(date);
              },
              child: _DayCell(
                skin: skin,
                day: dayNum,
                isToday: isToday,
                isSelected: isSelected,
                eventColors: dayEvents.expand(_colorsForEvent).toList(),
              ),
            ),
          ));
        }
        dayCounter++;
      }
      rows.add(Expanded(child: Row(children: cells)));
      if (row != totalRows - 1) {
        rows.add(Container(height: 0.6, margin: const EdgeInsets.symmetric(vertical: 3), color: skin.surface(0.08)));
      }
    }

    return Column(children: rows);
  }
}

class _DayCell extends StatelessWidget {
  final AppSkin skin;
  final int day;
  final bool isToday;
  final bool isSelected;
  final List<Color> eventColors;

  const _DayCell({
    required this.skin,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.eventColors,
  });

  @override
  Widget build(BuildContext context) {
    Color numberColor;
    if (isSelected) {
      numberColor = skin.isLight ? Colors.white : Colors.black;
    } else if (isToday) {
      numberColor = const Color(0xFFEF5B5B);
    } else {
      numberColor = skin.textPrimary;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? skin.textPrimary : Colors.transparent,
          ),
          child: Text('$day', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: numberColor)),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 4,
          child: eventColors.isEmpty
              ? null
              : eventColors.length == 1
                  ? Container(width: 4, height: 4, decoration: BoxDecoration(color: eventColors.first, shape: BoxShape.circle))
                  : _EventBar(colors: eventColors),
        ),
      ],
    );
  }
}

class _EventBar extends StatelessWidget {
  final List<Color> colors;
  const _EventBar({required this.colors});

  @override
  Widget build(BuildContext context) {
    final distinct = <Color, int>{};
    for (final c in colors) {
      distinct[c] = (distinct[c] ?? 0) + 1;
    }
    const maxWidth = 18.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: maxWidth,
        height: 4,
        child: Row(
          children: distinct.entries.map((entry) {
            final flex = entry.value;
            return Expanded(flex: flex, child: Container(color: entry.key));
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// URGENT INLINE CARD — unverändert
// ─────────────────────────────────────────────────────────────────────────

class _UrgentInlineCard extends StatelessWidget {
  final AppSkin skin;
  final Task task;
  const _UrgentInlineCard({required this.skin, required this.task});

  static const _urgentColor = Color(0xFFEF5B5B);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _urgentColor.withValues(alpha: skin.isLight ? 0.04 : 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _urgentColor.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.priority_high_rounded, size: 15, color: _urgentColor),
          const SizedBox(width: 10),
          Expanded(
              child: Text(task.title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: skin.textPrimary))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// DAY ENTRIES SECTION — NEU: eigene, unabhängige ListView unterhalb des
// Kalenders. Lädt Einträge NUR für den ausgewählten Tag (nicht mehr über
// den ganzen Monat aggregiert), sortiert dringend → ganztags → zeitlich.
// ─────────────────────────────────────────────────────────────────────────

class _DayEntriesSection extends StatelessWidget {
  final AppSkin skin;
  final DateTime selectedDay;
  final void Function(BuildContext context, CalendarEvent e) onOpenDetail;

  const _DayEntriesSection({
    required this.skin,
    required this.selectedDay,
    required this.onOpenDetail,
  });

  List<CalendarEvent> _eventsForDay() {
    final all = CalendarEventStore.loadAll();
    final rangeStart = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final rangeEnd = rangeStart.add(const Duration(days: 1));
    final occ = CalendarEventStore.occurrencesInRange(all, rangeStart, rangeEnd);

    final taskEvents = TaskStore.loadAll()
        .where((t) =>
            t.dueDate != null &&
            !t.done &&
            t.dueDate!.year == selectedDay.year &&
            t.dueDate!.month == selectedDay.month &&
            t.dueDate!.day == selectedDay.day)
        .map((t) => CalendarEvent(
              id: 'task_${t.id}',
              title: t.title,
              start: t.dueDate!,
              end: t.dueDate!.add(const Duration(minutes: 30)),
              allDay: !t.hasTime,
              groupKeys: const ['sonstiges'],
              createdAt: t.createdAt,
            ))
        .toList();

    return [...occ, ...taskEvents];
  }

  List<Task> _urgentTasksOnDay() => TaskStore.loadAll()
      .where((t) =>
          t.isUrgent &&
          !t.done &&
          t.dueDate != null &&
          t.dueDate!.year == selectedDay.year &&
          t.dueDate!.month == selectedDay.month &&
          t.dueDate!.day == selectedDay.day)
      .toList();

  @override
Widget build(BuildContext context) {
  return ValueListenableBuilder<bool>(
    valueListenable: SyncService.instance.initialSyncInProgress,
    builder: (context, syncing, __) {
      if (syncing) return _SyncLoadingFill(skin: skin);
      return ValueListenableBuilder<int>(
        valueListenable: CalendarEventStore.changesSignal,
        builder: (context, _, __) => _buildList(context),
      );
    },
  );
}

  Widget _buildList(BuildContext context) {
    final dayEntries = _eventsForDay()
      ..sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.start.compareTo(b.start);
      });
    final urgent = _urgentTasksOnDay();

    final taskEntries = dayEntries.where((e) => e.id.startsWith('task_')).toList();
    final calendarEntries = dayEntries.where((e) => !e.id.startsWith('task_')).toList();

    // NEU: Fade-out unten, analog zu schedule_screen.dart — bisher fehlte
    // hier der komplette FadingListView-Wrapper.
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: FadingListView(
          fadeFromBottom: bottomNavHeight + 20,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
            children: [
              for (final t in urgent) _UrgentInlineCard(skin: skin, task: t),
              if (taskEntries.isNotEmpty) ...[
                _TaskBannerStrip(skin: skin, taskEvents: taskEntries),
                const SizedBox(height: 10),
              ],
              ...calendarEntries.map((e) => _DayEntryCard(
                    skin: skin,
                    event: e,
                    onTap: () => onOpenDetail(context, e),
                  )),
              if (calendarEntries.isEmpty && urgent.isEmpty && taskEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('Keine Einträge', style: TextStyle(color: skin.surface(0.3), fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// NEU: Füllt den gesamten unteren Bereich, solange der initiale Sync
// läuft — bewusst KEINE Liste darunter, auch wenn schon (unvollständige)
// Events lokal vorhanden wären.
class _SyncLoadingFill extends StatelessWidget {
  final AppSkin skin;
  const _SyncLoadingFill({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: skin.primary),
          ),
          const SizedBox(height: 14),
          Text(
            'Kalender wird synchronisiert…',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TASK BANNER STRIP (NEU, Punkt 1) — Tasks, die in den Kalender übernommen
// werden, heben sich jetzt bewusst über einen eigenen, farblich klar
// abgesetzten Balken ab statt als normale Kalenderkarte zu erscheinen.
// ─────────────────────────────────────────────────────────────────────────

class _TaskBannerStrip extends StatelessWidget {
  final AppSkin skin;
  final List<CalendarEvent> taskEvents;
  const _TaskBannerStrip({required this.skin, required this.taskEvents});

  static const _taskColor = kTaskAccentColor; // NEU: geteilte Konstante statt eigenem Hex-Wert

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: taskEvents.map((e) {
        final timeLabel = e.allDay ? '' : DateFormat('HH:mm').format(e.start);
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _taskColor.withValues(alpha: skin.isLight ? 0.14 : 0.20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _taskColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.task_alt_rounded, size: 14, color: _taskColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _taskColor)),
                ),
                if (timeLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(timeLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _taskColor.withValues(alpha: 0.85))),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// GROUP COLOR BAR — zeigt bis zu 3 Gruppenfarben als gestapelte Segmente
// ─────────────────────────────────────────────────────────────────────────

class _GroupColorBar extends StatelessWidget {
  final List<String> groupKeys;
  const _GroupColorBar({required this.groupKeys});

  @override
  Widget build(BuildContext context) {
    final colors = groupKeys.map((k) => EventGroupStore.byKey(k).color).toList();
    if (colors.isEmpty) colors.add(Colors.grey);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: 3,
        height: 26,
        child: Column(
          children: colors.map((c) => Expanded(child: Container(color: c))).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// DAY ENTRY CARD — unverändert (bereits kompakt)
// ─────────────────────────────────────────────────────────────────────────

class _DayEntryCard extends StatelessWidget {
  final AppSkin skin;
  final CalendarEvent event;
  final VoidCallback? onTap;

  const _DayEntryCard({required this.skin, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeLabel = event.allDay
        ? 'Ganztägig'
        : '${DateFormat('HH:mm').format(event.start)} – ${DateFormat('HH:mm').format(event.end)}';

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
           _GroupColorBar(groupKeys: event.groupKeys),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(event.title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: skin.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Row(children: [
                    Text(timeLabel, style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
                    if (event.hasNotes) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.sticky_note_2_outlined, size: 11, color: skin.primary.withValues(alpha: 0.5)),
                    ],
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// YEAR GRID — unverändert (Jahres-Paging steuert jetzt CalendarViewState)
// ─────────────────────────────────────────────────────────────────────────

class YearGrid extends StatelessWidget {
  final AppSkin skin;
  final int year;
  final void Function(int month, Rect originRect) onMonthTap;

  const YearGrid({super.key, required this.skin, required this.year, required this.onMonthTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text('$year', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFFEF5B5B))),
          ),
          Expanded(
            child: GridView.builder(
              // NEU: Ohne diese Zeile fängt sich das Grid selbst die
              // vertikale Wisch-Geste (Touch) und lässt sie nie beim
              // äußeren Jahres-ListView ankommen — deshalb ging auf dem
              // iPhone kein Jahreswechsel per Swipe, am Desktop per
              // Mausrad aber schon.
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 8,
                childAspectRatio: 0.95,
              ),
              itemCount: 12,
              itemBuilder: (context, i) {
                final month = i + 1;
                final key = GlobalKey();
                return _MiniMonthTile(
                  key: key,
                  skin: skin,
                  year: year,
                  month: month,
                  onTap: () {
                    final box = key.currentContext?.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final origin = box.localToGlobal(Offset.zero) & box.size;
                    onMonthTap(month, origin);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMonthTile extends StatelessWidget {
  final AppSkin skin;
  final int year;
  final int month;
  final VoidCallback onTap;

  const _MiniMonthTile({super.key, required this.skin, required this.year, required this.month, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday;
    final leadingBlanks = firstWeekday - 1;
    final now = DateTime.now();

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('MMMM', 'de').format(DateTime(year, month)),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary)),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.count(
              crossAxisCount: 7,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
              children: [
                for (int i = 0; i < leadingBlanks; i++) const SizedBox(),
                for (int d = 1; d <= daysInMonth; d++)
                  Center(
                    child: Text(
                      '$d',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        color: (year == now.year && month == now.month && d == now.day)
                            ? const Color(0xFFEF5B5B)
                            : skin.surface(0.55),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// EVENT DETAIL SCREEN
// ─────────────────────────────────────────────────────────────────────────

class EventDetailScreen extends StatefulWidget {
  final AppSkin skin;
  final String eventId;

  const EventDetailScreen({super.key, required this.skin, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  CalendarEvent? _event;
  double _edgeDragDx = 0;

  @override
  void initState() {
    super.initState();
    _load();
    CalendarEventStore.changesSignal.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    CalendarEventStore.changesSignal.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) _load();
  }

  void _load() {
    final e = CalendarEventStore.byId(widget.eventId);
    setState(() => _event = e);
    if (e == null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

  List<CalendarEvent> _neighboringEventsOnSameDay() {
    if (_event == null) return [];
    final all = CalendarEventStore.loadAll();
    final day = _event!.start;
    final rangeStart = DateTime(day.year, day.month, day.day);
    final rangeEnd = rangeStart.add(const Duration(days: 1));
    final occ = CalendarEventStore.occurrencesInRange(all, rangeStart, rangeEnd);
    return occ.where((e) => e.id != _event!.id).toList();
  }

bool get _isForeignOwnedSync {
    final ev = _event;
    if (ev == null) return false;
    final owner = SyncService.instance.ownerOf('calendar_events', ev.id);
    final myRole = SyncTokenService.role;
    if (owner == null || myRole == null) return false;
    return owner != myRole;
  }

  Set<String> get _lockedGroupKeys {
    final ev = _event;
    if (ev == null || !_isForeignOwnedSync) return {};
    return ev.groupKeys.where((k) {
      try { return EventGroupStore.byKey(k).isSync; } catch (_) { return false; }
    }).toSet();
  }

  Future<void> _edit() async {
    final e = _event;
    if (e == null) return;
    final skin = widget.skin;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      builder: (_) => EntrySheet(
        skin: skin,
        draft: EntryDraft(),
        initialMode: EntryMode.event,
        existingEvent: e,
        onEventSaved: (events) {
          final updated = events.first;
          CalendarEventStore.update(updated);
          NotificationService.instance.cancelEventReminders(updated.id);
          final options = ReminderManager.optionsFor(ReminderMode.beforeDeadline);
          for (int i = 0; i < updated.reminderOptionIds.length; i++) {
            final opt = options.firstWhere(
              (o) => o.id == updated.reminderOptionIds[i],
              orElse: () => options.first,
            );
            NotificationService.instance.scheduleEventReminder(
              eventId: updated.id,
              reminderIndex: i,
              eventTitle: updated.title,
              eventStart: updated.start,
              reminderAt: updated.start.subtract(opt.duration),
            );
          }
        },
      ),
    );
  }

  Future<void> _delete() async {
    final e = _event;
    if (e == null) return;
    final skin = widget.skin;
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Ereignis löschen?',
      message: e.repeat == RepeatRule.none
          ? 'Dieser Termin wird unwiderruflich gelöscht.'
          : 'Dies löscht die GESAMTE Serie, nicht nur dieses Vorkommen.',
    );
    if (confirmed == true) {
      NotificationService.instance.cancelEventReminders(e.id);
      CalendarEventStore.delete(e.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final e = _event;

    if (e == null) {
      return Scaffold(backgroundColor: skin.bgBase, body: const SizedBox());
    }

    final shiftCode = ShiftLookup.codeForDay(e.start);
    final neighbors = _neighboringEventsOnSameDay();

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 26,
                          height: 40,
                          child: Align(alignment: Alignment.centerLeft, child: Icon(Icons.arrow_back_ios_new, size: 18)),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy', 'de').format(e.start),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: skin.textPrimary, letterSpacing: -0.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: _edit,
                        child: GlassSurface(
                          borderRadius: 14,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.edit_outlined, size: 15, color: skin.primary),
                            const SizedBox(width: 6),
                            Text('Bearbeiten', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: skin.primary)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(e.title,
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: skin.textPrimary)),
                          ),
                          if (shiftCode != null) ...[
                            const SizedBox(width: 10),
                            _ShiftBadge(skin: skin, code: shiftCode),
                          ],
                        ],
                      ),
                      if (e.location.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          e.location,
                          style: TextStyle(fontSize: 14, color: skin.primary, fontWeight: FontWeight.w500),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        DateFormat('EEEE, d. MMMM yyyy', 'de').format(e.start),
                        style: TextStyle(fontSize: 14, color: skin.textPrimary, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.allDay
                            ? 'Ganztägig'
                            : '${DateFormat('HH:mm').format(e.start)} – ${DateFormat('HH:mm').format(e.end)}',
                        style: TextStyle(fontSize: 13, color: skin.textMuted),
                      ),
                      const SizedBox(height: 20),

                      if (!e.allDay) _MiniDayTimeline(skin: skin, focus: e, neighbors: neighbors),

                      const SizedBox(height: 24),

                      GlassSurface(
                        padding: EdgeInsets.zero,
                        child: GlassMultiDropdownButton<String>(
                          label: 'Gruppen',
                          values: e.groupKeys,
                          items: EventGroupStore.loadAll()
                              .map((g) => GlassDropdownItem(value: g.key, label: g.name))
                              .toList(),
                          maxSelectable: 3,
                          lockedValues: _lockedGroupKeys,
                          displaySummary: (vals) =>
                              vals.isEmpty ? 'Ohne' : vals.map((k) => EventGroupStore.byKey(k).name).join(' · '),
                          isLast: true,
                          onChanged: (ids) {
                            e.groupKeys = ids;
                            CalendarEventStore.update(e);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      GlassSurface(
                        padding: EdgeInsets.zero,
                        child: GlassMultiDropdownButton<String>(
                          label: 'Hinweisen',
                          values: e.reminderOptionIds,
                          items: ReminderManager.optionsFor(ReminderMode.beforeDeadline)
                              .map((o) => GlassDropdownItem(value: o.id, label: o.label))
                              .toList(),
                          maxSelectable: ReminderManager.maxSelectable,
                          displaySummary: (vals) => vals.isEmpty ? 'Ohne' : '${vals.length} gewählt',
                          isLast: true,
                          maxPopupHeight: 280,
                          onChanged: (ids) {
                            e.reminderOptionIds = ids;
                            CalendarEventStore.update(e);
                            NotificationService.instance.cancelEventReminders(e.id);
                            final options = ReminderManager.optionsFor(ReminderMode.beforeDeadline);
                            for (int i = 0; i < e.reminderOptionIds.length; i++) {
                              final opt = options.firstWhere(
                                (o) => o.id == e.reminderOptionIds[i],
                                orElse: () => options.first,
                              );
                              NotificationService.instance.scheduleEventReminder(
                                eventId: e.id,
                                reminderIndex: i,
                                eventTitle: e.title,
                                eventStart: e.start,
                                reminderAt: e.start.subtract(opt.duration),
                              );
                            }
                          },
                        ),
                      ),

                      if (e.hasNotes) ...[
                        const SizedBox(height: 20),
                        Text('NOTIZEN',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: skin.surface(0.38), letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text(e.notes, style: TextStyle(fontSize: 14, color: skin.textPrimary, height: 1.4)),
                      ],

                      const SizedBox(height: 32),
                      GlassDangerButton(
                        skin: skin,
                        label: 'Ereignis löschen',
                        icon: Icons.delete_outline,
                        fullWidth: false,
                        onTap: _delete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Eigene, immer-treffende Wisch-Zone am linken Rand
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (d) => _edgeDragDx = 0,
                onHorizontalDragUpdate: (d) => _edgeDragDx += d.delta.dx,
                onHorizontalDragEnd: (d) {
                  if (_edgeDragDx > 40) {
                    Navigator.pop(context);
                  }
                  _edgeDragDx = 0;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftBadge extends StatelessWidget {
  final AppSkin skin;
  final String code;
  const _ShiftBadge({required this.skin, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: skin.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: skin.primary.withValues(alpha: 0.35)),
      ),
      child: Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: skin.primary)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// MINI DAY TIMELINE — ganztägige Nachbar-Termine werden ausgeblendet
// ─────────────────────────────────────────────────────────────────────────

class _MiniDayTimeline extends StatelessWidget {
  final AppSkin skin;
  final CalendarEvent focus;
  final List<CalendarEvent> neighbors;

  const _MiniDayTimeline({required this.skin, required this.focus, required this.neighbors});

  @override
  Widget build(BuildContext context) {
    final windowStart = focus.start.subtract(const Duration(hours: 1));
    final windowEnd = focus.end.add(const Duration(hours: 1));
    final totalMinutes = windowEnd.difference(windowStart).inMinutes.clamp(1, 100000);

    // Ganztägige Nachbarn ausfiltern
    final relevant = [focus, ...neighbors.where((e) => !e.allDay)]
        .where((e) => e.start.isBefore(windowEnd) && e.end.isAfter(windowStart))
        .toList();

    final others = relevant.where((e) => e.id != focus.id).take(1).toList();

    double topFor(DateTime t) {
      final mins = t.difference(windowStart).inMinutes.clamp(0, totalMinutes);
      return mins / totalMinutes;
    }

    const height = 130.0;
    final hourMarks = <DateTime>[];
    var cursor = DateTime(windowStart.year, windowStart.month, windowStart.day, windowStart.hour);
    while (cursor.isBefore(windowEnd)) {
      hourMarks.add(cursor);
      cursor = cursor.add(const Duration(hours: 1));
    }

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.glassBorder),
      ),
      child: Stack(
        children: [
          for (final h in hourMarks)
            Positioned(
              top: topFor(h) * (height - 12),
              left: 0,
              right: 0,
              child: Row(children: [
                SizedBox(
                  width: 38,
                  child: Text(DateFormat('HH:mm').format(h), style: TextStyle(fontSize: 9, color: skin.surface(0.32))),
                ),
                Expanded(child: Container(height: 0.5, color: skin.surface(0.08))),
              ]),
            ),

          Positioned(
            top: topFor(focus.start) * (height - 12) + 2,
            left: 44,
            right: others.isEmpty ? 12 : (12 + 60),
            height: ((topFor(focus.end) - topFor(focus.start)) * (height - 12)).clamp(20, height),
            child: _TimelineBlock(
              color: focus.primaryGroupKey == null ? Colors.grey : EventGroupStore.byKey(focus.primaryGroupKey!).color,
              title: focus.title,
              filled: true,
            ),
          ),

          for (final n in others)
            Positioned(
              top: topFor(n.start) * (height - 12) + 2,
              right: 12,
              width: 56,
              height: ((topFor(n.end) - topFor(n.start)) * (height - 12)).clamp(16, height),
              child: _TimelineBlock(
                color: n.primaryGroupKey == null ? Colors.grey : EventGroupStore.byKey(n.primaryGroupKey!).color,
                title: n.title,
                filled: false,
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  final Color color;
  final String title;
  final bool filled;

  const _TimelineBlock({required this.color, required this.title, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(8),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: filled ? 11 : 9,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : color,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}