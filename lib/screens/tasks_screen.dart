import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/dictation_fab.dart';
import '../widgets/glass_pickers.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/swipe_animation_mixin.dart';
import '../services/notification_service.dart';
import '../services/spoken_task_parser.dart';
import '../services/reminder_manager.dart';
import '../services/speech_normalizer.dart';
import '../services/speech_log.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import '../services/rule_engine.dart';
import '../services/sync_service.dart';
import '../widgets/entry_sheet.dart';
import '../screens/calendar_view.dart';
import '../models/calendar_event.dart';
import '../widgets/entry_sheet.dart';
import '../services/sync_service.dart';

const _kCardRadius = BorderRadius.all(Radius.circular(14));
final _kBlur10 = ImageFilter.blur(sigmaX: 10, sigmaY: 10);
const _kFabRadius = BorderRadius.all(Radius.circular(20));
final _kBlur20 = ImageFilter.blur(sigmaX: 20, sigmaY: 20);

// ─────────────────────────────────────────────────────────────────────────────
// TASK MODEL
// ─────────────────────────────────────────────────────────────────────────────

class Task {
  final String id;
  String title;
  DateTime? dueDate;
  bool hasTime;
  bool done;
  final DateTime createdAt;
  DateTime? completedAt;
  List<DateTime> reminderTimes;
  List<String> reminderOptionIds;
  String notes;
  bool isUrgent;

  Task({
    required this.id,
    required this.title,
    this.dueDate,
    this.hasTime = false,
    this.done = false,
    required this.createdAt,
    this.completedAt,
    List<DateTime>? reminderTimes,
    List<String>? reminderOptionIds,
    this.notes = '',
    this.isUrgent = false,
  })  : reminderTimes = reminderTimes ?? [],
        reminderOptionIds = reminderOptionIds ?? [];

  bool get hasDeadline => dueDate != null;
  bool get hasNotes => notes.trim().isNotEmpty;
  bool get hasReminder => reminderTimes.isNotEmpty;

  ReminderMode get reminderMode =>
      hasDeadline ? ReminderMode.beforeDeadline : ReminderMode.relative;

  bool get isOverdue {
    if (dueDate == null || done) return false;
    final now = DateTime.now();
    if (hasTime) return dueDate!.isBefore(now);
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  bool get isToday {
    if (dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year && dueDate!.month == now.month && dueDate!.day == now.day;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dueDate': dueDate?.toIso8601String(),
    'hasTime': hasTime,
    'done': done,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'reminderTimes': reminderTimes.map((d) => d.toIso8601String()).toList(),
    'reminderOptionIds': reminderOptionIds,
    'notes': notes,
    'isUrgent': isUrgent,
  };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String,
    title: j['title'] as String,
    dueDate: j['dueDate'] != null ? DateTime.tryParse(j['dueDate'] as String) : null,
    hasTime: j['hasTime'] as bool? ?? false,
    done: j['done'] as bool? ?? false,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    completedAt: j['completedAt'] != null ? DateTime.tryParse(j['completedAt'] as String) : null,
    reminderTimes: (j['reminderTimes'] as List?)?.map((e) => DateTime.tryParse(e.toString())).whereType<DateTime>().toList() ?? [],
    reminderOptionIds: (j['reminderOptionIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
    notes: j['notes'] as String? ?? '',
    isUrgent: j['isUrgent'] as bool? ?? false,
  );
}

class TaskStore {
  static const _key = 'tasks';

  /// Wird bei jeder Änderung (add/update/delete) gepingt, damit ALLE
  /// aktiven Listener (Homescreen-Kachel, TasksScreen, egal von wo die
  /// Änderung kam) ihre Ansicht neu laden. Robust unabhängig vom Ort
  /// des Diktats/Speicherns.
  static final ValueNotifier<int> changesSignal = ValueNotifier(0);
  static void _notifyChanged() => changesSignal.value++;

  /// Rohdaten — ALLE lokal gespeicherten Aufgaben, unabhängig davon, ob
  /// eine noch unbestätigte eigene Änderung (Kopiergerät) dabei ist. Nur
  /// intern für Lese-Änderungs-Schreib-Zyklen und den Sync verwenden — NIE
  /// direkt für die Anzeige, sonst würden zurückgehaltene Vorschläge
  /// sichtbar.
  static List<Task> loadAllRaw() {
    final box = Hive.box('einstellungen');
    final raw = box.get(_key);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        return decoded.map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  /// Für die Anzeige: blendet eigene, auf dem Kopiergerät eingebrachte
  /// Änderungen aus, solange das Original sie noch nicht im
  /// Konflikte-Screen bestätigt oder verworfen hat.
  static List<Task> loadAll() =>
      SyncService.instance.filterPendingTasks(loadAllRaw());

  static void saveAll(List<Task> tasks) {
    final box = Hive.box('einstellungen');
    box.put(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  static void add(Task task) {
    final all = loadAllRaw();
    all.add(task);
    saveAll(all);
    // WICHTIG: pushTask() markiert den Datensatz (auf dem Kopiergerät)
    // synchron als "ausstehend" — das MUSS passieren, bevor _notifyChanged()
    // den TasksScreen zum Neuladen anstößt. Sonst wird kurzzeitig der noch
    // unbestätigte Stand angezeigt, bevor die Pending-Markierung greift.
    SyncService.instance.pushTask(task.id);
    _notifyChanged();
  }

  static void update(Task task) {
    final all = loadAllRaw();
    final idx = all.indexWhere((t) => t.id == task.id);
    if (idx != -1) {
      all[idx] = task;
      saveAll(all);
      SyncService.instance.pushTask(task.id);
      _notifyChanged();
    }
  }

  static void delete(String id) {
    final all = loadAllRaw();
    all.removeWhere((t) => t.id == id);
    saveAll(all);
    SyncService.instance.pushTask(id);
    _notifyChanged();
  }

  static bool hasOpenTaskOnDay(DateTime day) {
    final all = loadAll();
    return all.any((t) =>
        !t.done &&
        t.dueDate != null &&
        t.dueDate!.year == day.year &&
        t.dueDate!.month == day.month &&
        t.dueDate!.day == day.day);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TASKS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class TasksScreen extends StatefulWidget {
  final void Function(bool showingYear)? onCalendarShowingYearChanged;

  const TasksScreen({super.key, this.onCalendarShowingYearChanged});

  @override
  State<TasksScreen> createState() => TasksScreenState();
}

class TasksScreenState extends State<TasksScreen> with TickerProviderStateMixin {
  List<Task> _tasks = [];
  final ScrollController _scrollController = ScrollController();
  String? _openSwipedId;
  String? _inlineEditId;

  final Map<String, GlobalKey<_TaskCardState>> _taskCardKeys = {};

  Timer? _periodicReloadTimer;

  // ── NEU: Kalender-Modus ──
  final _calendarViewKey = GlobalKey<CalendarViewState>();
  bool _calendarMode = false;
  DateTime? _calendarFocusedMonth;

  void setCalendarMode(bool v) => setState(() => _calendarMode = v);
  void openYearView() => _calendarViewKey.currentState?.openYearView();
  // NEU: für Deep-Link vom Kalender-Widget — springt direkt zu Heute,
  // unabhängig davon ob Liste oder Kalender gerade aktiv war.
  void jumpCalendarToToday() => _calendarViewKey.currentState?.jumpToToday();
  bool _calendarShowingYear = false;

  // ── Entwurf-Mechanismus (analog Fahrtenbuch) ──
  final EntryDraft _draft = EntryDraft();
  bool _draftVisible = false;
  bool _entrySheetOpen = false;
  late AnimationController _draftBannerCtrl;
  late Animation<double> _draftBannerAnim;

  bool get hasDraft => _draftVisible;

  void _onCalendarMonthChanged(DateTime m) {
    if (mounted) setState(() => _calendarFocusedMonth = m);
  }

  void _onCalendarShowingYearChanged(bool showing) {
    if (mounted) setState(() => _calendarShowingYear = showing);
    // NEU: nach außen melden, damit MainScreen die _GlassBottomNav
    // in der Jahresübersicht ausblenden kann.
    widget.onCalendarShowingYearChanged?.call(showing);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _draftBannerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _draftBannerAnim = CurvedAnimation(parent: _draftBannerCtrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    TaskStore.changesSignal.addListener(_onTasksChangedExternally);
    _periodicReloadTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _load();
    });
  }

  void _onTasksChangedExternally() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    TaskStore.changesSignal.removeListener(_onTasksChangedExternally);
    _draftBannerCtrl.dispose();
    _periodicReloadTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _load() => setState(() {
    _tasks = TaskStore.loadAll();
    final loadedIds = _tasks.map((t) => t.id).toSet();
    _taskCardKeys.removeWhere((id, _) => !loadedIds.contains(id));
  });

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  void closeOverlays() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_inlineEditId != null) {
      final id = _inlineEditId!;
      final cardKey = _taskCardKeys[id];
      cardKey?.currentState?.commitInlineEditNow();
      setState(() => _inlineEditId = null);
    }
    if (_openSwipedId != null) setState(() => _openSwipedId = null);
  }

  List<Task> get _urgentTasks {
    final list = _tasks.where((t) => t.isUrgent && !t.done).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  List<Task> get _deadlineTasks {
    final list = _tasks.where((t) => t.hasDeadline && !t.done && !t.isUrgent).toList();
    list.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return list;
  }

  List<Task> get _generalTasks {
    final list = _tasks.where((t) => !t.hasDeadline && !t.done && !t.isUrgent).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  List<Task> get _doneTasks {
    final list = _tasks.where((t) => t.done).toList();
    list.sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
    return list;
  }

  void _toggleDone(Task task) {
    HapticFeedback.lightImpact();
    setState(() {
      task.done = !task.done;
      task.completedAt = task.done ? DateTime.now() : null;
    });
    TaskStore.update(task);
    if (task.done) {
      NotificationService.instance.cancelTaskReminders(task.id);
    } else {
      _scheduleReminders(task);
    }
    _syncUrgentReminder(task);
  }

  void _deleteTaskWithAnimation(Task task) {
    final cardKey = _taskCardKeys[task.id];
    if (cardKey?.currentState != null) {
      cardKey!.currentState!.animateOutAndDelete(() {
        _deleteTaskImmediate(task);
        _taskCardKeys.remove(task.id);
      });
    } else {
      _deleteTaskImmediate(task);
    }
  }

  void _deleteTaskImmediate(Task task) {
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
      if (_openSwipedId == task.id) _openSwipedId = null;
      if (_inlineEditId == task.id) _inlineEditId = null;
    });
    TaskStore.delete(task.id);
    SpeechLog.markEdited(task.id, task.createdAt);
    NotificationService.instance.cancelTaskReminders(task.id);
  }

  void _onCardSwiped(String? id) => setState(() => _openSwipedId = id);

  void _startInlineEdit(String id) {
    if (_inlineEditId == id) return;
    HapticFeedback.selectionClick();
    if (_inlineEditId != null) {
      _taskCardKeys[_inlineEditId]?.currentState?.commitInlineEditNow();
    }
    setState(() {
      _openSwipedId = null;
      _inlineEditId = id;
    });
  }

  void _commitInlineEdit(Task task, String newTitle) {
    final trimmed = newTitle.trim();
    final titleActuallyChanged = trimmed.isNotEmpty && trimmed != task.title;
    setState(() {
      _inlineEditId = null;
      if (titleActuallyChanged) {
        task.title = trimmed;
      }
    });
    if (trimmed.isNotEmpty) {
      TaskStore.update(task);
      if (titleActuallyChanged) {
        SpeechLog.markEdited(task.id, task.createdAt);
      }
    }
  }

  // ── openQuickAddEvent für Kalender-Modus ──
  void reopenDraft() {
    if (_entrySheetOpen) return;
    _showEntrySheet(mode: _draft.mode, reopening: true);
  }

  void openQuickAddEvent() {
    closeOverlays();
    if (_draftVisible) { reopenDraft(); return; }
    _draft.mode = EntryMode.event;
    final selected = _calendarViewKey.currentState?.selectedDay;
    _showEntrySheet(mode: EntryMode.event, initialDate: selected);
  }

  void _scheduleEventReminders(CalendarEvent event) {
    NotificationService.instance.cancelEventReminders(event.id);
    final options = ReminderManager.optionsFor(ReminderMode.beforeDeadline);
    for (int i = 0; i < event.reminderOptionIds.length; i++) {
      final opt = options.firstWhere(
        (o) => o.id == event.reminderOptionIds[i],
        orElse: () => options.first,
      );
      NotificationService.instance.scheduleEventReminder(
        eventId: event.id,
        reminderIndex: i,
        eventTitle: event.title,
        eventStart: event.start,
        reminderAt: event.start.subtract(opt.duration),
      );
    }
    // NEU (Punkt 5): garantierte Erinnerung exakt zum Start.
    NotificationService.instance.scheduleGuaranteedEventReminder(
      eventId: event.id,
      eventTitle: event.title,
      eventStart: event.start,
    );
  }

  void openQuickAdd({String? initialTitle, DateTime? initialDate}) {
    closeOverlays();
    if (_draftVisible) { reopenDraft(); return; }
    _draft.mode = EntryMode.task;
    _showEntrySheet(mode: EntryMode.task, initialTitle: initialTitle, initialDate: initialDate);
  }

  void _showEntrySheet({
    required EntryMode mode,
    String? initialTitle,
    DateTime? initialDate,
    bool reopening = false,
  }) {
    final skin = AppTheme.of(context);
    setState(() { _entrySheetOpen = true; _draftVisible = false; });
    _draftBannerCtrl.reverse();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      builder: (_) => EntrySheet(
        skin: skin,
        initialMode: mode,
        draft: _draft,
        initialTitle: reopening ? null : initialTitle,
        initialDate: reopening ? null : initialDate,
        onTaskSaved: (task) {
          TaskStore.add(task);
          _draft.reset();
          setState(() { _entrySheetOpen = false; _draftVisible = false; });
          _draftBannerCtrl.reverse();
          _load();
          _scheduleReminders(task);
          _syncUrgentReminder(task);
        },
        onEventSaved: (events) {
          for (final event in events) {
            CalendarEventStore.add(event);
            _scheduleEventReminders(event);
          }
          _draft.reset();
          setState(() { _entrySheetOpen = false; _draftVisible = false; });
          _draftBannerCtrl.reverse();
        },
      ),
    ).then((_) {
      if (_entrySheetOpen) {
        if (_draft.hasAnyData) {
          setState(() { _entrySheetOpen = false; _draftVisible = true; });
          _draftBannerCtrl.forward();
        } else {
          _draft.reset();
          setState(() { _entrySheetOpen = false; _draftVisible = false; });
        }
      }
    });
  }

  void _deleteDraft() {
    HapticFeedback.mediumImpact();
    _draft.reset();
    setState(() { _draftVisible = false; _entrySheetOpen = false; });
    _draftBannerCtrl.reverse();
  }

  void _editTaskFull(Task task) {
    closeOverlays();
    final skin = AppTheme.of(context);
    final titleBefore = task.title;
    final dueBefore = task.dueDate;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (_) => EntrySheet(
        skin: skin,
        draft: EntryDraft(),
        initialMode: EntryMode.task,
        existingTask: task,
        onTaskSaved: (updated) {
          TaskStore.update(updated);
          if (updated.title != titleBefore || updated.dueDate != dueBefore) {
            SpeechLog.markEdited(updated.id, updated.createdAt);
          }
          _load();
          NotificationService.instance.cancelTaskReminders(updated.id);
          _scheduleReminders(updated);
          _syncUrgentReminder(updated);
        },
      ),
    );
  }

  void _scheduleReminders(Task task) {
    for (var i = 0; i < task.reminderTimes.length; i++) {
      NotificationService.instance.scheduleTaskReminder(
        taskId: task.id,
        reminderIndex: i,
        title: task.title,
        reminderAt: task.reminderTimes[i],
      );
    }
    if (task.hasDeadline && !task.done) {
      NotificationService.instance.scheduleGuaranteedDueReminder(
        taskId: task.id,
        taskTitle: task.title,
        dueDate: task.dueDate!,
        hasTime: task.hasTime,
      );
    } else {
      NotificationService.instance.cancelGuaranteedDueReminder(task.id);
    }
  }

  void _syncUrgentReminder(Task task) {
    if (task.isUrgent && !task.done) {
      NotificationService.instance.scheduleUrgentReminder(
        taskId: task.id,
        taskTitle: task.title,
      );
    } else {
      NotificationService.instance.cancelUrgentReminder(task.id);
    }
  }

  // ── Diktier-Flow ────────────────────────────────────────────────────────────

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
    SpeechLog.linkLastEntryToTask(logRef, task.id);
    _load();
    HapticFeedback.mediumImpact();
    _scheduleReminders(task);
    _syncUrgentReminder(task);
  }

  bool _isLikelyDuplicate(ParsedSpokenTask parsed) {
    final newNorm = RuleEngine.normalizeForCompare(parsed.title);
    if (newNorm.isEmpty) return false;
    final newDate = parsed.combinedDateTime;

    return _tasks.any((t) {
      if (t.done) return false;
      final sameTitle = RuleEngine.normalizeForCompare(t.title) == newNorm;
      if (!sameTitle) return false;
      if (newDate == null && t.dueDate == null) return true;
      if (newDate == null || t.dueDate == null) return false;
      return newDate.year == t.dueDate!.year &&
          newDate.month == t.dueDate!.month &&
          newDate.day == t.dueDate!.day;
    });
  }

  void _createTaskFromSpeech(ParsedSpokenTask parsed, String logRef) {
    if (_isLikelyDuplicate(parsed)) {
      HapticFeedback.heavyImpact();
      _showDuplicateDialog(parsed, logRef);
      return;
    }
    _saveTaskFromSpeech(parsed, logRef);
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
    closeOverlays();
    final skin = AppTheme.of(context);
    final draft = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: parsed.title,
      dueDate: parsed.combinedDateTime,
      hasTime: parsed.hasTime,
      createdAt: DateTime.now(),
      isUrgent: parsed.isUrgent,
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (_) => EntrySheet(
        skin: skin,
        draft: EntryDraft(),
        initialMode: EntryMode.task,
        existingTask: draft,
        isReviewMode: true,
        onTaskSaved: (finalTask) {
          if (_isLikelyDuplicate(parsed)) {
            HapticFeedback.lightImpact();
          }
          TaskStore.add(finalTask);
          SpeechLog.linkLastEntryToTask(logRef, finalTask.id);
          final titleChanged = finalTask.title.trim() != parsed.title.trim();
          final dateChanged = finalTask.dueDate != parsed.combinedDateTime;
          if (titleChanged || dateChanged) {
            SpeechLog.markEdited(finalTask.id, finalTask.createdAt);
          }
          _load();
          _scheduleReminders(finalTask);
          _syncUrgentReminder(finalTask);
        },
      ),
    );
  }

  List<Widget> _buildListItems() {
    final items = <Widget>[];

    void addTaskCard(Task t, {bool isUrgent = false}) {
      _taskCardKeys.putIfAbsent(t.id, () => GlobalKey<_TaskCardState>());
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _TaskCard(
          key: _taskCardKeys[t.id],
          task: t,
          skin: AppTheme.of(context),
          externallyOpenKey: _openSwipedId,
          onCardSwiped: _onCardSwiped,
          onToggleDone: () => _toggleDone(t),
          isInlineEditing: _inlineEditId == t.id,
          onStartInlineEdit: () => _startInlineEdit(t.id),
          onCommitInlineEdit: (v) => _commitInlineEdit(t, v),
          onFullEdit: () => _editTaskFull(t),
          onDelete: () => _deleteTaskWithAnimation(t),
          isUrgent: isUrgent,
        ),
      ));
    }

    final skin = AppTheme.of(context);

    if (_urgentTasks.isNotEmpty) {
      items.add(_UrgentSectionHeader(skin: skin));
      items.add(const SizedBox(height: 10));
      for (final t in _urgentTasks) {
        addTaskCard(t, isUrgent: true);
      }
      items.add(const SizedBox(height: 18));
    }
    if (_deadlineTasks.isNotEmpty) {
      items.add(_SectionHeader(icon: Icons.event_outlined, label: 'MIT FRIST', skin: skin));
      items.add(const SizedBox(height: 10));
      for (final t in _deadlineTasks) {
        addTaskCard(t);
      }
      items.add(const SizedBox(height: 18));
    }
    if (_generalTasks.isNotEmpty) {
      items.add(_SectionHeader(icon: Icons.notes_outlined, label: 'ALLGEMEIN', skin: skin));
      items.add(const SizedBox(height: 10));
      for (final t in _generalTasks) {
        addTaskCard(t);
      }
      items.add(const SizedBox(height: 18));
    }
    if (_doneTasks.isNotEmpty) {
      items.add(_SectionHeader(icon: Icons.check_circle_outline, label: 'ERLEDIGT', skin: skin, muted: true));
      items.add(const SizedBox(height: 10));
      for (final t in _doneTasks) {
        addTaskCard(t);
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;
    final hasAnyOpen = _deadlineTasks.isNotEmpty || _generalTasks.isNotEmpty;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (_inlineEditId != null &&
              notification is ScrollUpdateNotification &&
              notification.scrollDelta != null &&
              notification.scrollDelta! < -6) {
            FocusManager.instance.primaryFocus?.unfocus();
            _taskCardKeys[_inlineEditId]?.currentState?.commitInlineEditNow();
            setState(() => _inlineEditId = null);
          }
          return false;
        },
        child: GestureDetector(
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            if (_inlineEditId != null) {
              _taskCardKeys[_inlineEditId]?.currentState?.commitInlineEditNow();
              setState(() => _inlineEditId = null);
            }
            if (_openSwipedId != null) setState(() => _openSwipedId = null);
          },
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 50),
                    if (!(_calendarMode && _calendarShowingYear)) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _calendarMode
                                  ? (_calendarFocusedMonth != null
                                      ? DateFormat('MMMM', 'de').format(_calendarFocusedMonth!)
                                      : 'Kalender')
                                  : 'Aufgaben',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: skin.textPrimary),
                            ),
                            if (_calendarMode)
                              GestureDetector(
                                onTap: openYearView,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: skin.isLight
                                            ? Colors.white.withValues(alpha: skin.glassOpacity)
                                            : skin.bgCard.withValues(alpha: skin.glassOpacity),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: skin.glassBorder),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.chevron_left_rounded, size: 16, color: skin.primary),
                                          Text(
                                            '${_calendarFocusedMonth?.year ?? DateTime.now().year}',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: skin.primary),
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
                      const SizedBox(height: 12),
                    ] else
                      const SizedBox(height: 8),
                    Expanded(
                      child: _calendarMode
                          ? CalendarView(
                              key: _calendarViewKey,
                              skin: skin,
                              onFocusedMonthChanged: _onCalendarMonthChanged,
                              onShowingYearChanged: _onCalendarShowingYearChanged,
                            )
                          : !hasAnyOpen && _doneTasks.isEmpty
                              ? Center(
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(Icons.task_alt_outlined, size: 46, color: skin.surface(0.18)),
                                    const SizedBox(height: 12),
                                    Text('Keine Aufgaben', style: TextStyle(color: skin.surface(0.3), fontSize: 15)),
                                    const SizedBox(height: 8),
                                    Text('Tippe unten auf + um eine Aufgabe anzulegen',
                                        style: TextStyle(color: skin.surface(0.2), fontSize: 12), textAlign: TextAlign.center),
                                  ]),
                                )
                              : ClipRect(
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                                    child: FadingListView(
                                      fadeFromBottom: bottomNavHeight + 20,
                                      child: Builder(
                                        builder: (context) {
                                          final listItems = _buildListItems();
                                          return ListView.builder(
                                            controller: _scrollController,
                                            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                                            itemCount: listItems.length + 1,
                                            itemBuilder: (context, index) {
                                              if (index == listItems.length) {
                                                return SizedBox(height: bottomNavHeight + 100);
                                              }
                                              return listItems[index];
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
              // ── Bottom-Leiste: Heute (links) — Entwurf-Banner (Mitte) — FABs (rechts) ──
              // NEU (Punkt 4): Der Block wird jetzt IMMER angezeigt, wenn
              // Kalender-Modus aktiv ist — auch in der Jahresansicht. Nur
              // Entwurf-Banner + FABs (die in der Jahresansicht keinen
              // Sinn ergeben) werden dort ausgeblendet, "Heute" bleibt.
              if (_calendarMode)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: bottomNavHeight + 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _calendarViewKey.currentState?.jumpToToday();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: skin.isLight ? Colors.white.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
                                  width: 0.8,
                                ),
                              ),
                              child: Text('Heute', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: skin.primary)),
                            ),
                          ),
                        ),
                      ),
                      if (!_calendarShowingYear) ...[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: AnimatedBuilder(
                              animation: _draftBannerAnim,
                              builder: (context, child) {
                                if (!_draftVisible && _draftBannerAnim.value == 0) {
                                  return const SizedBox.shrink();
                                }
                                return Opacity(
                                  opacity: _draftBannerAnim.value.clamp(0.0, 1.0),
                                  child: child,
                                );
                              },
                              child: _EntryDraftBanner(
                                skin: skin,
                                draft: _draft,
                                onReopen: reopenDraft,
                                onDelete: _deleteDraft,
                                externallyOpen: _openSwipedId,
                                onCardSwiped: _onCardSwiped,
                              ),
                            ),
                          ),
                        ),
                        _TasksFab(
                          skin: skin,
                          icon: _draftVisible ? Icons.edit_note_rounded : Icons.add,
                          onTap: () {
                            if (_entrySheetOpen) return;
                            if (_draftVisible) {
                              reopenDraft();
                            } else {
                              openQuickAddEvent();
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                )
              else if (!_calendarShowingYear)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: bottomNavHeight + 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _draftBannerAnim,
                          builder: (context, child) {
                            if (!_draftVisible && _draftBannerAnim.value == 0) {
                              return const SizedBox.shrink();
                            }
                            return Opacity(
                              opacity: _draftBannerAnim.value.clamp(0.0, 1.0),
                              child: child,
                            );
                          },
                          child: _EntryDraftBanner(
                            skin: skin,
                            draft: _draft,
                            onReopen: reopenDraft,
                            onDelete: _deleteDraft,
                            externallyOpen: _openSwipedId,
                            onCardSwiped: _onCardSwiped,
                          ),
                        ),
                      ),
                      DictationFab(
                        skin: skin,
                        onResult: _createTaskFromSpeech,
                        onNeedsReview: _reviewTaskFromSpeech,
                      ),
                      const SizedBox(width: 12),
                      _TasksFab(
                        skin: skin,
                        icon: _draftVisible ? Icons.edit_note_rounded : Icons.add,
                        onTap: () {
                          if (_entrySheetOpen) return;
                          if (_draftVisible) {
                            reopenDraft();
                          } else {
                            openQuickAdd();
                          }
                        },
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
// SECTION HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppSkin skin;
  final bool muted;
  const _SectionHeader({required this.icon, required this.label, required this.skin, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final color = muted ? skin.surface(0.32) : skin.primary;
    return Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.9)),
    ]);
  }
}

class _UrgentSectionHeader extends StatelessWidget {
  final AppSkin skin;
  const _UrgentSectionHeader({required this.skin});

  static const _urgentColor = Color(0xFFEF5B5B);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _urgentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _urgentColor.withValues(alpha: 0.20)),
      ),
      child: Row(children: [
        Icon(Icons.priority_high_rounded, size: 13, color: _urgentColor),
        const SizedBox(width: 6),
        Text(
          'DRINGEND',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _urgentColor,
            letterSpacing: 0.9,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TASKS FAB
// ─────────────────────────────────────────────────────────────────────────────

class _TasksFab extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final VoidCallback onTap;
  const _TasksFab({required this.skin, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: _kFabRadius,
        child: BackdropFilter(
          filter: _kBlur20,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: skin.isLight ? Colors.white.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.55),
              borderRadius: _kFabRadius,
              border: Border.all(
                color: skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: skin.isLight ? 0.08 : 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: skin.primary, size: 24),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TASK CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TaskCard extends StatefulWidget {
  final Task task;
  final AppSkin skin;
  final String? externallyOpenKey;
  final void Function(String?) onCardSwiped;
  final VoidCallback onToggleDone;
  final bool isInlineEditing;
  final VoidCallback onStartInlineEdit;
  final void Function(String newTitle) onCommitInlineEdit;
  final VoidCallback onFullEdit;
  final VoidCallback onDelete;
  final bool isUrgent;

  const _TaskCard({
    super.key,
    required this.task,
    required this.skin,
    required this.externallyOpenKey,
    required this.onCardSwiped,
    required this.onToggleDone,
    required this.isInlineEditing,
    required this.onStartInlineEdit,
    required this.onCommitInlineEdit,
    required this.onFullEdit,
    required this.onDelete,
    this.isUrgent = false,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> with TickerProviderStateMixin, SwipeAnimationMixin {
  static const double _revealWidth = 80.0;
  static const double _snapThreshold = 40.0;
  bool _isOpen = false;
  bool _dragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;

  late TextEditingController _inlineCtrl;
  late FocusNode _inlineFocus;
  bool _committing = false;

  late AnimationController _deleteAnimController;
  late Animation<double> _slideOutAnim, _fadeOutAnim, _heightCollapseAnim;

  @override
  void initState() {
    super.initState();
    initSwipeAnimation(vsync: this);

    _inlineCtrl = TextEditingController(text: widget.task.title);
    _inlineFocus = FocusNode();
    _inlineFocus.addListener(() {
      if (!_inlineFocus.hasFocus && widget.isInlineEditing) {
        commitInlineEditNow();
      }
    });

    _deleteAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideOutAnim = Tween<double>(begin: 0, end: -420).animate(
        CurvedAnimation(parent: _deleteAnimController, curve: const Interval(0.0, 0.6, curve: Curves.easeInBack)));
    _fadeOutAnim = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _deleteAnimController, curve: const Interval(0.25, 0.7, curve: Curves.easeOut)));
    _heightCollapseAnim = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _deleteAnimController, curve: const Interval(0.6, 1.0, curve: Curves.easeInOut)));
    _deleteAnimController.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void didUpdateWidget(_TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externallyOpenKey != widget.task.id && _isOpen) {
      animateSwipeTo(0);
      setState(() => _isOpen = false);
    }
    if (oldWidget.isInlineEditing && !widget.isInlineEditing && _inlineFocus.hasFocus) {
      _inlineFocus.unfocus();
    }
    if (!oldWidget.isInlineEditing && widget.isInlineEditing) {
      _committing = false;
      _inlineCtrl.text = widget.task.title;
      _inlineCtrl.selection = TextSelection.collapsed(offset: _inlineCtrl.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_inlineFocus);
      });
    }
    if (oldWidget.task.title != widget.task.title && !widget.isInlineEditing) {
      _inlineCtrl.text = widget.task.title;
    }
  }

  @override
  void dispose() {
    disposeSwipeAnimation();
    _deleteAnimController.dispose();
    _inlineCtrl.dispose();
    _inlineFocus.dispose();
    super.dispose();
  }

  void animateOutAndDelete(VoidCallback onDone) {
    _deleteAnimController.forward().then((_) => onDone());
  }

  void commitInlineEditNow() {
    if (_committing) return;
    _committing = true;
    widget.onCommitInlineEdit(_inlineCtrl.text);
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
    final newOffset = (swipeOffset + d.delta.dx).clamp(-_revealWidth, 0.0);
    setSwipeOffsetImmediate(newOffset);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final v = d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx;
    if (swipeOffset < -_snapThreshold || v < -400) {
      animateSwipeTo(-_revealWidth);
      setState(() => _isOpen = true);
      widget.onCardSwiped(widget.task.id);
    } else {
      animateSwipeTo(0);
      if (_isOpen) {
        setState(() => _isOpen = false);
        widget.onCardSwiped(null);
      }
    }
  }

  void _close() {
    animateSwipeTo(0);
    if (mounted) setState(() => _isOpen = false);
    widget.onCardSwiped(null);
  }

  void _onDeleteAreaTap() {
    _close();
    HapticFeedback.mediumImpact();
    widget.onDelete();
  }

  void _handleTap() {
    if (_isOpen) {
      _close();
      return;
    }
    if (widget.isInlineEditing) return;
    widget.onStartInlineEdit();
  }

  void _handleDoubleTap() {
    if (_isOpen || widget.isInlineEditing) return;
    widget.onFullEdit();
  }

  String _formatDue(Task task) {
    final df = task.hasTime ? DateFormat('dd.MM. · HH:mm') : DateFormat('dd.MM.yyyy');
    return df.format(task.dueDate!);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final task = widget.task;
    final isOverdue = task.isOverdue;
    final isToday = task.isToday && !task.done;

    Color dueColor;
    if (task.done) {
      dueColor = skin.surface(0.3);
    } else if (isOverdue) {
      dueColor = const Color(0xFFEF5B5B);
    } else if (isToday) {
      dueColor = const Color(0xFFFFB347);
    } else {
      dueColor = skin.primary;
    }

    Widget titleArea = widget.isInlineEditing
        ? TextField(
            controller: _inlineCtrl,
            focusNode: _inlineFocus,
            autofocus: true,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
            onSubmitted: (v) => commitInlineEditNow(),
          )
        : Text(
            task.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: task.done ? skin.surface(0.32) : skin.textPrimary,
              decoration: task.done ? TextDecoration.lineThrough : null,
              decorationColor: skin.surface(0.32),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );

    Widget cardInner = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.isUrgent) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.priority_high_rounded,
              size: 14,
              color: const Color(0xFFEF5B5B).withValues(alpha: 0.85),
            ),
          ),
        ],
        GestureDetector(
          onTap: widget.onToggleDone,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: task.done ? skin.statComplete : Colors.transparent,
                  border: Border.all(color: task.done ? skin.statComplete : skin.surface(0.28), width: 1.6),
                ),
                child: task.done ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleArea,
              if (task.hasDeadline || task.hasNotes || task.hasReminder) ...[
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (task.hasDeadline) ...[
                    Icon(isOverdue ? Icons.error_outline : Icons.schedule_outlined, size: 11, color: dueColor),
                    const SizedBox(width: 4),
                    Text(
                      isOverdue ? 'Überfällig · ${_formatDue(task)}' : _formatDue(task),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: dueColor),
                    ),
                  ],
                  if (task.hasReminder) ...[
                    if (task.hasDeadline) const SizedBox(width: 8),
                    Icon(Icons.notifications_active_outlined, size: 12, color: skin.primary.withValues(alpha: 0.55)),
                  ],
                  if (task.hasNotes) ...[
                    if (task.hasDeadline || task.hasReminder) const SizedBox(width: 8),
                    Icon(Icons.sticky_note_2_outlined, size: 12, color: skin.primary.withValues(alpha: 0.55)),
                  ],
                ]),
              ],
            ],
          ),
        ),
        if (widget.isInlineEditing)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.keyboard_outlined, size: 16, color: skin.primary.withValues(alpha: 0.5)),
          ),
      ],
    );

    Widget cardWidget = ClipRRect(
      borderRadius: _kCardRadius,
     child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: widget.isUrgent
              ? const Color(0xFFEF5B5B).withValues(alpha: skin.isLight ? 0.04 : 0.07)
              : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity)),
          borderRadius: _kCardRadius,
          border: Border.all(
            color: widget.isUrgent
                ? const Color(0xFFEF5B5B).withValues(alpha: 0.45)
                : (widget.isInlineEditing ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder),
            width: (widget.isUrgent || widget.isInlineEditing) ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
            BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
          ],
        ),
        child: cardInner,
      ),
    );

    return AnimatedBuilder(
      animation: _deleteAnimController,
      builder: (context, child) => SizeTransition(
        sizeFactor: _heightCollapseAnim,
        axisAlignment: -1,
        child: Opacity(
          opacity: _fadeOutAnim.value,
          child: Transform.translate(offset: Offset(_slideOutAnim.value, 0), child: child!),
        ),
      ),
      child: GestureDetector(
        onHorizontalDragStart: widget.isInlineEditing ? null : _onPanStart,
        onHorizontalDragUpdate: widget.isInlineEditing ? null : _onPanUpdate,
        onHorizontalDragEnd: widget.isInlineEditing ? null : _onPanEnd,
        onVerticalDragUpdate: widget.isInlineEditing
            ? (d) {
                if (d.delta.dy > 6) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  commitInlineEditNow();
                }
              }
            : null,
        onTap: _handleTap,
        onDoubleTap: _handleDoubleTap,
        child: ClipRect(
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned(
              right: 0,
              top: 4,
              bottom: 4,
              width: _revealWidth,
              child: GestureDetector(
                onTap: _onDeleteAreaTap,
                child: Opacity(
                  opacity: (swipeOffset.abs() / _revealWidth).clamp(0.0, 1.0),
                  child: ClipRRect(
                    borderRadius: _kCardRadius,
                    child: BackdropFilter(
                      filter: _kBlur10,
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.10),
                          borderRadius: _kCardRadius,
                          border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25)),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.delete_outline, color: skin.deleteColor, size: 20),
                          const SizedBox(height: 3),
                          Text('Löschen', style: TextStyle(color: skin.deleteColor, fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(offset: Offset(swipeOffset, 0), child: cardWidget),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY DRAFT BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _EntryDraftBanner extends StatefulWidget {
  final AppSkin skin;
  final EntryDraft draft;
  final VoidCallback onReopen;
  final VoidCallback onDelete;
  final String? externallyOpen;
  final void Function(String?) onCardSwiped;
  const _EntryDraftBanner({
    required this.skin,
    required this.draft,
    required this.onReopen,
    required this.onDelete,
    required this.externallyOpen,
    required this.onCardSwiped,
  });

  @override
  State<_EntryDraftBanner> createState() => _EntryDraftBannerState();
}

class _EntryDraftBannerState extends State<_EntryDraftBanner>
    with TickerProviderStateMixin, SwipeAnimationMixin {
  static const String cardKey = '__entry_draft__';
  static const double _revealWidth = 76.0;
  static const double _snapThreshold = 38.0;
  bool _isOpen = false;
  bool _dragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;

  @override
  void initState() {
    super.initState();
    initSwipeAnimation(vsync: this);
  }

  @override
  void didUpdateWidget(_EntryDraftBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externallyOpen != cardKey && _isOpen) {
      animateSwipeTo(0);
      setState(() => _isOpen = false);
    }
  }

  @override
  void dispose() {
    disposeSwipeAnimation();
    super.dispose();
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
    final newOffset = (swipeOffset + d.delta.dx).clamp(-_revealWidth, 0.0);
    setSwipeOffsetImmediate(newOffset);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final v = d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx;
    if (swipeOffset < -_snapThreshold || v < -400) {
      animateSwipeTo(-_revealWidth);
      setState(() => _isOpen = true);
      widget.onCardSwiped(cardKey);
    } else {
      animateSwipeTo(0);
      if (_isOpen) {
        setState(() => _isOpen = false);
        widget.onCardSwiped(null);
      }
    }
  }

  void _close() {
    animateSwipeTo(0);
    if (mounted) setState(() => _isOpen = false);
    widget.onCardSwiped(null);
  }

  void _onDeleteTap() {
    _close();
    widget.onDelete();
  }

  void _handleTap() {
    if (_isOpen) {
      _close();
      return;
    }
    widget.onReopen();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final isEvent = widget.draft.mode == EntryMode.event;
    final label = widget.draft.title.trim().isNotEmpty
        ? widget.draft.title.trim()
        : (isEvent ? 'Neues Ereignis – Entwurf' : 'Neue Aufgabe – Entwurf');

    return GestureDetector(
      onHorizontalDragStart: _onPanStart,
      onHorizontalDragUpdate: _onPanUpdate,
      onHorizontalDragEnd: _onPanEnd,
      onTap: _handleTap,
      child: SizedBox(
        height: 52,
        child: ClipRect(
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned(
              right: 0, top: 0, bottom: 0, width: _revealWidth,
              child: GestureDetector(
                onTap: _onDeleteTap,
                child: Opacity(
                  opacity: (swipeOffset.abs() / _revealWidth).clamp(0.0, 1.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: skin.deleteColor.withValues(alpha: 0.30)),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.delete_outline, color: skin.deleteColor, size: 18),
                          const SizedBox(height: 2),
                          Text('Löschen', style: TextStyle(color: skin.deleteColor, fontSize: 9, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(swipeOffset, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: skin.isLight ? Colors.white.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
                        width: 0.8,
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: skin.isLight ? 0.08 : 0.35), blurRadius: 24, offset: const Offset(0, 6))],
                    ),
                    child: Stack(children: [
                      Center(child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(isEvent ? Icons.event_note_rounded : Icons.edit_note_rounded, size: 16, color: skin.primary),
                          const SizedBox(width: 6),
                          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.textPrimary))),
                        ]),
                      )),
                      Positioned(top: 6, left: 0, right: 0,
                        child: Center(child: Container(width: 40, height: 4,
                            decoration: BoxDecoration(color: skin.surface(0.18), borderRadius: BorderRadius.circular(2))))),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}