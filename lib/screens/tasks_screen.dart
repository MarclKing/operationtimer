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

  static List<Task> loadAll() {
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

  static void saveAll(List<Task> tasks) {
    final box = Hive.box('einstellungen');
    box.put(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  static void add(Task task) {
    final all = loadAll();
    all.add(task);
    saveAll(all);
  }

  static void update(Task task) {
    final all = loadAll();
    final idx = all.indexWhere((t) => t.id == task.id);
    if (idx != -1) {
      all[idx] = task;
      saveAll(all);
    }
  }

  static void delete(String id) {
    final all = loadAll();
    all.removeWhere((t) => t.id == id);
    saveAll(all);
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
  const TasksScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _load();
    // Damit nach dem stündlichen App-weiten Cleanup auch dieser Screen
    // (falls gerade offen) die aktualisierte Liste zeigt.
    _periodicReloadTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
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
    if (task.done && task.hasReminder) {
      NotificationService.instance.cancelTaskReminders(task.id);
    }
    _syncUrgentReminder(task); // NEU
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
    // Löschung kurz nach Diktat = starkes Signal, dass die Erkennung
    // komplett danebenlag (Nutzer wollte den Task gar nicht so).
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

  void openQuickAdd({String? initialTitle, DateTime? initialDate}) {
    closeOverlays();
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (_) => _TaskEditSheet(
        skin: skin,
        initialTitle: initialTitle,
        initialDate: initialDate,
                onSaved: (task) {
          TaskStore.add(task);
          _load();
          _scheduleReminders(task);
          _syncUrgentReminder(task); // NEU
        },
      ),
    );
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
      builder: (_) => _TaskEditSheet(
        skin: skin,
        existingTask: task,
                onSaved: (updated) {
          TaskStore.update(updated);
          if (updated.title != titleBefore || updated.dueDate != dueBefore) {
            SpeechLog.markEdited(updated.id, updated.createdAt);
          }
          _load();
          NotificationService.instance.cancelTaskReminders(updated.id);
          _scheduleReminders(updated);
          _syncUrgentReminder(updated); // NEU
        },
      ),
    );
  }

  void _scheduleReminders(Task task) {
    if (!task.hasReminder) return;
    for (var i = 0; i < task.reminderTimes.length; i++) {
      NotificationService.instance.scheduleTaskReminder(
        taskId: task.id,
        reminderIndex: i,
        title: task.title,
        reminderAt: task.reminderTimes[i],
      );
    }
  }

    // NEU ─────────────────────────────────────────────────────────────────────
  /// Zentrale Stelle, die nach JEDER Änderung an einer Aufgabe aufgerufen
  /// wird (Anlegen, Bearbeiten, Erledigt-Toggle, Diktat) und dafür sorgt,
  /// dass die einmalige 24h-Dringend-Erinnerung konsistent mit dem
  /// tatsächlichen Zustand bleibt: läuft nur, wenn die Aufgabe aktuell als
  /// dringend markiert UND nicht erledigt ist.
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
    _syncUrgentReminder(task); // NEU
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
      builder: (_) => _TaskEditSheet(
        skin: skin,
        existingTask: draft,
        isReviewMode: true,
                onSaved: (finalTask) {
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
          _syncUrgentReminder(finalTask); // NEU
        },
      ),
    );
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
    // Greift zuverlässig auch wenn die ListView selbst scrollt — anders als
    // ein reiner GestureDetector, der gegen das Scrollable die Gesture-Arena
    // meist verliert.
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aufgaben',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: !hasAnyOpen && _doneTasks.isEmpty
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
                        : FadingListView(
                            fadeFromBottom: bottomNavHeight + 20,
                            child: ListView(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                              children: [
                                if (_urgentTasks.isNotEmpty) ...[
                                  _UrgentSectionHeader(skin: skin),
                                  const SizedBox(height: 10),
                                  ..._urgentTasks.map((t) {
                                    _taskCardKeys.putIfAbsent(t.id, () => GlobalKey<_TaskCardState>());
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _TaskCard(
                                        key: _taskCardKeys[t.id],
                                        task: t,
                                        skin: skin,
                                        externallyOpenKey: _openSwipedId,
                                        onCardSwiped: _onCardSwiped,
                                        onToggleDone: () => _toggleDone(t),
                                        isInlineEditing: _inlineEditId == t.id,
                                        onStartInlineEdit: () => _startInlineEdit(t.id),
                                        onCommitInlineEdit: (v) => _commitInlineEdit(t, v),
                                        onFullEdit: () => _editTaskFull(t),
                                        onDelete: () => _deleteTaskWithAnimation(t),
                                        isUrgent: true,
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 18),
                                ],
                                if (_deadlineTasks.isNotEmpty) ...[
                                  _SectionHeader(icon: Icons.event_outlined, label: 'MIT FRIST', skin: skin),
                                  const SizedBox(height: 10),
                                  ..._deadlineTasks.map((t) {
                                    _taskCardKeys.putIfAbsent(t.id, () => GlobalKey<_TaskCardState>());
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _TaskCard(
                                        key: _taskCardKeys[t.id],
                                        task: t,
                                        skin: skin,
                                        externallyOpenKey: _openSwipedId,
                                        onCardSwiped: _onCardSwiped,
                                        onToggleDone: () => _toggleDone(t),
                                        isInlineEditing: _inlineEditId == t.id,
                                        onStartInlineEdit: () => _startInlineEdit(t.id),
                                        onCommitInlineEdit: (v) => _commitInlineEdit(t, v),
                                        onFullEdit: () => _editTaskFull(t),
                                        onDelete: () => _deleteTaskWithAnimation(t),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 18),
                                ],
                                if (_generalTasks.isNotEmpty) ...[
                                  _SectionHeader(icon: Icons.notes_outlined, label: 'ALLGEMEIN', skin: skin),
                                  const SizedBox(height: 10),
                                  ..._generalTasks.map((t) {
                                    _taskCardKeys.putIfAbsent(t.id, () => GlobalKey<_TaskCardState>());
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _TaskCard(
                                        key: _taskCardKeys[t.id],
                                        task: t,
                                        skin: skin,
                                        externallyOpenKey: _openSwipedId,
                                        onCardSwiped: _onCardSwiped,
                                        onToggleDone: () => _toggleDone(t),
                                        isInlineEditing: _inlineEditId == t.id,
                                        onStartInlineEdit: () => _startInlineEdit(t.id),
                                        onCommitInlineEdit: (v) => _commitInlineEdit(t, v),
                                        onFullEdit: () => _editTaskFull(t),
                                        onDelete: () => _deleteTaskWithAnimation(t),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 18),
                                ],
                                if (_doneTasks.isNotEmpty) ...[
                                  _SectionHeader(icon: Icons.check_circle_outline, label: 'ERLEDIGT', skin: skin, muted: true),
                                  const SizedBox(height: 10),
                                  ..._doneTasks.map((t) {
                                    _taskCardKeys.putIfAbsent(t.id, () => GlobalKey<_TaskCardState>());
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _TaskCard(
                                        key: _taskCardKeys[t.id],
                                        task: t,
                                        skin: skin,
                                        externallyOpenKey: _openSwipedId,
                                        onCardSwiped: _onCardSwiped,
                                        onToggleDone: () => _toggleDone(t),
                                        isInlineEditing: _inlineEditId == t.id,
                                        onStartInlineEdit: () => _startInlineEdit(t.id),
                                        onCommitInlineEdit: (v) => _commitInlineEdit(t, v),
                                        onFullEdit: () => _editTaskFull(t),
                                        onDelete: () => _deleteTaskWithAnimation(t),
                                      ),
                                    );
                                  }),
                                ],
                                SizedBox(height: bottomNavHeight + 100),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // ── Floating Action Buttons ──
            Positioned(
              right: 20,
              bottom: bottomNavHeight + 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DictationFab(
  skin: skin,
  onResult: _createTaskFromSpeech,
  onNeedsReview: _reviewTaskFromSpeech,
),
                  const SizedBox(width: 12),
                  _TasksFab(
                    skin: skin,
                    icon: Icons.add,
                    onTap: () => openQuickAdd(),
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
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: skin.isLight ? Colors.white.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
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
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.done ? skin.statComplete : Colors.transparent,
                border: Border.all(color: task.done ? skin.statComplete : skin.surface(0.28), width: 1.8),
              ),
              child: task.done ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
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
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: widget.isUrgent
                ? const Color(0xFFEF5B5B).withValues(alpha: skin.isLight ? 0.04 : 0.07)
                : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity)),
            borderRadius: BorderRadius.circular(14),
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
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
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
// TASK EDIT SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _TaskDateTile extends StatefulWidget {
  final AppSkin skin;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<int> onSwipeDay;

  const _TaskDateTile({
    required this.skin,
    required this.date,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSwipeDay,
  });

  @override
  State<_TaskDateTile> createState() => _TaskDateTileState();
}

class _TaskDateTileState extends State<_TaskDateTile> {
  double _hAccum = 0;
  static const double _pxPerDay = 120;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final hasDate = widget.date != null;
    final dateLabel = hasDate ? DateFormat('EEE, dd.MM.yyyy', 'de').format(widget.date!) : 'Datum wählen';

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onHorizontalDragStart: hasDate ? (_) => _hAccum = 0 : null,
      onHorizontalDragUpdate: hasDate
          ? (d) {
              _hAccum += d.delta.dx;
              while (_hAccum >= _pxPerDay) {
                _hAccum -= _pxPerDay;
                widget.onSwipeDay(1);
                HapticFeedback.selectionClick();
              }
              while (_hAccum <= -_pxPerDay) {
                _hAccum += _pxPerDay;
                widget.onSwipeDay(-1);
                HapticFeedback.selectionClick();
              }
            }
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: hasDate ? skin.primary.withValues(alpha: skin.isLight ? 0.08 : 0.14) : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasDate ? skin.primary.withValues(alpha: 0.32) : skin.glassBorder,
                width: hasDate ? 1.3 : 1.0,
              ),
              boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined, size: 15, color: hasDate ? skin.primary : skin.surface(0.4)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('DATUM', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: hasDate ? skin.primary : skin.surface(0.35), letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: hasDate ? skin.textPrimary : skin.surface(0.32)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hasDate) Icon(Icons.unfold_more_rounded, size: 13, color: skin.surface(0.3)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TaskTimeTile extends StatefulWidget {
  final AppSkin skin;
  final bool enabled;
  final TimeOfDay? time;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<int> onSwipeMinute;

  const _TaskTimeTile({
    required this.skin,
    required this.enabled,
    required this.time,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSwipeMinute,
  });

  @override
  State<_TaskTimeTile> createState() => _TaskTimeTileState();
}

class _TaskTimeTileState extends State<_TaskTimeTile> {
  double _vAccum = 0;
  static const double _pxPerMin = 10;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final hasTime = widget.time != null;
    final timeLabel = hasTime ? widget.time!.format(context) : 'Uhrzeit';

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onDoubleTap: widget.onDoubleTap,
        onVerticalDragStart: widget.enabled && hasTime ? (_) => _vAccum = 0 : null,
        onVerticalDragUpdate: widget.enabled && hasTime
            ? (d) {
                _vAccum += -d.delta.dy;
                while (_vAccum >= _pxPerMin) {
                  _vAccum -= _pxPerMin;
                  widget.onSwipeMinute(1);
                  HapticFeedback.selectionClick();
                }
                while (_vAccum <= -_pxPerMin) {
                  _vAccum += _pxPerMin;
                  widget.onSwipeMinute(-1);
                  HapticFeedback.selectionClick();
                }
              }
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: hasTime ? skin.primary.withValues(alpha: skin.isLight ? 0.08 : 0.14) : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasTime ? skin.primary.withValues(alpha: 0.32) : skin.glassBorder,
                  width: hasTime ? 1.3 : 1.0,
                ),
                boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: Row(children: [
                Icon(Icons.schedule_outlined, size: 15, color: hasTime ? skin.primary : skin.surface(0.4)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('UHRZEIT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: hasTime ? skin.primary : skin.surface(0.35), letterSpacing: 1.0)),
                      const SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: hasTime ? skin.textPrimary : skin.surface(0.32)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (hasTime) Icon(Icons.unfold_more_rounded, size: 13, color: skin.surface(0.3)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandleBar extends StatelessWidget {
  final AppSkin skin;
  const _SheetHandleBar({required this.skin});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 100) Navigator.pop(context);
      },
      child: Container(
        width: double.infinity,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: SheetHandle(skin: skin),
      ),
    );
  }
}

class _TaskEditSheet extends StatefulWidget {
  final AppSkin skin;
  final String? initialTitle;
  final DateTime? initialDate;
  final Task? existingTask;
  final bool isReviewMode;
  final void Function(Task task) onSaved;

  const _TaskEditSheet({
    required this.skin,
    this.initialTitle,
    this.initialDate,
    this.existingTask,
    this.isReviewMode = false,
    required this.onSaved,
  });

  @override
  State<_TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<_TaskEditSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _notesCtrl;
  final _titleFocus = FocusNode();
  DateTime? _dueDate;
  bool _hasTime = false;
  bool _fristEnabled = true;
  bool _isUrgent = false;

  List<String> _selectedReminderIds = [];
  List<ReminderOption> _quickOptions = [];

  bool get _isEditing => widget.existingTask != null;

  ReminderMode get _mode => _dueDate != null ? ReminderMode.beforeDeadline : ReminderMode.relative;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existingTask?.title ?? widget.initialTitle ?? '');
    _notesCtrl = TextEditingController(text: widget.existingTask?.notes ?? '');
    if (widget.existingTask != null) {
      _dueDate = widget.existingTask!.dueDate;
      _hasTime = widget.existingTask!.hasTime;
      _isUrgent = widget.existingTask!.isUrgent;
    } else if (widget.initialDate != null) {
      _dueDate = widget.initialDate;
      _hasTime = false;
      _isUrgent = false;
    } else {
      _dueDate = null;
      _hasTime = false;
      _isUrgent = false;
    }
    _fristEnabled = _dueDate != null;
    _selectedReminderIds = List<String>.from(widget.existingTask?.reminderOptionIds ?? []);
    _refreshQuickOptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isEditing) FocusScope.of(context).requestFocus(_titleFocus);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _refreshQuickOptions() {
    _quickOptions = ReminderManager.getSorted(_mode);
  }

  Future<void> _pickDate() async {
    final skin = widget.skin;
    final result = await showSingleDatePicker(
      context: context,
      skin: skin,
      initialDate: _dueDate ?? DateTime.now(),
      minimumDate: DateTime.now().subtract(const Duration(days: 1)),
      maximumDate: DateTime(DateTime.now().year + 3),
    );
    if (result != null) {
      final hadDeadlineBefore = _dueDate != null;
      setState(() {
        _dueDate = DateTime(result.year, result.month, result.day, _dueDate?.hour ?? 0, _dueDate?.minute ?? 0);
        _fristEnabled = true;
      });
      if (!hadDeadlineBefore) await _onDeadlineModeChanged();
    }
  }

  void _swipeDate(int deltaDays) {
    if (_dueDate == null) return;
    setState(() {
      _dueDate = _dueDate!.add(Duration(days: deltaDays));
    });
  }

  void _doubleTapDate() {
    HapticFeedback.mediumImpact();
    if (_dueDate != null) {
      _clearDate();
    } else {
      final now = DateTime.now();
      setState(() {
        _dueDate = DateTime(now.year, now.month, now.day, 0, 0);
        _hasTime = false;
        _fristEnabled = true;
      });
    }
  }

  void _doubleTapTime() {
    HapticFeedback.mediumImpact();
    if (_hasTime && _dueDate != null) {
      setState(() => _hasTime = false);
    } else if (!_hasTime && _dueDate != null) {
      final now = DateTime.now();
      setState(() {
        _dueDate = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day, now.hour + 1, 0);
        _hasTime = true;
        _fristEnabled = true;
      });
    } else {
      final now = DateTime.now();
      setState(() {
        _dueDate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
        _hasTime = true;
        _fristEnabled = true;
      });
    }
  }

  Future<void> _pickTime() async {
    if (_dueDate == null) return;
    final skin = widget.skin;
    final base = _dueDate!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
        skin: skin,
        label: 'Uhrzeit auswählen',
        onTimeSelected: (t) {
          setState(() {
            final d = _dueDate!;
            _dueDate = DateTime(d.year, d.month, d.day, t.hour, t.minute);
            _hasTime = true;
          });
        },
      ),
    );
  }

  void _swipeTime(int deltaMinutes) {
    if (_dueDate == null || !_hasTime) return;
    setState(() {
      _dueDate = _dueDate!.add(Duration(minutes: deltaMinutes));
    });
  }

  Future<void> _clearDate() async {
    final hadDeadlineBefore = _dueDate != null;
    setState(() {
      _dueDate = null;
      _hasTime = false;
      _fristEnabled = false;
    });
    if (hadDeadlineBefore) await _onDeadlineModeChanged();
  }

  Future<void> _setFristEnabled(bool enabled) async {
    if (enabled == _fristEnabled) return;
    if (!enabled) {
      final hadDeadlineBefore = _dueDate != null;
      setState(() {
        _fristEnabled = false;
        _dueDate = null;
        _hasTime = false;
      });
      if (hadDeadlineBefore) await _onDeadlineModeChanged();
    } else {
      final hadDeadlineBefore = _dueDate != null;
      final now = DateTime.now();
      setState(() {
        _fristEnabled = true;
        _dueDate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
        _hasTime = true;
      });
      if (!hadDeadlineBefore) await _onDeadlineModeChanged();
    }
  }

  Future<void> _onDeadlineModeChanged() async {
    final hadReminders = _selectedReminderIds.isNotEmpty;
    setState(() {
      _selectedReminderIds = [];
      _refreshQuickOptions();
    });
    if (hadReminders && mounted) {
      await _showReminderResetInfoDialog();
    }
  }

  Future<void> _showReminderResetInfoDialog() async {
  await confirmActionDialog(
    context: context,
    skin: widget.skin,
    icon: Icons.notifications_off_outlined,
    title: 'Erinnerungen zurückgesetzt',
    message: 'Da sich der Fristen-Status geändert hat, wurden alle bisher gewählten Erinnerungen entfernt. Du kannst unten neue auswählen.',
    cancelLabel: 'Verstanden',
    confirmLabel: 'Verstanden',
  );
}

  void _toggleReminderOption(String id) {
  if (_selectedReminderIds.contains(id)) {
    setState(() => _selectedReminderIds.remove(id));
  } else {
    if (_selectedReminderIds.length >= ReminderManager.maxSelectable) {
      HapticFeedback.heavyImpact();
      showGlassSnackBar(
        context,
        'Maximal 3 Erinnerungen pro Aufgabe.',
        type: GlassSnackBarType.warning,
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _selectedReminderIds.add(id));
  }
}

  List<DateTime> _computeReminderTimes() {
    final options = ReminderManager.optionsFor(_mode);
    final base = _mode == ReminderMode.beforeDeadline ? _dueDate! : DateTime.now();
    final times = <DateTime>[];
    for (final id in _selectedReminderIds) {
      final opt = options.firstWhere((o) => o.id == id, orElse: () => options.first);
      final time = _mode == ReminderMode.beforeDeadline ? base.subtract(opt.duration) : base.add(opt.duration);
      times.add(time);
    }
    times.sort();
    return times;
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    for (final id in _selectedReminderIds) {
      ReminderManager.recordUsage(_mode, id);
    }

    final task = widget.existingTask ??
        Task(id: DateTime.now().millisecondsSinceEpoch.toString(), title: title, createdAt: DateTime.now());
    task.title = title;
    task.dueDate = _dueDate;
    task.hasTime = _dueDate != null && _hasTime;
    task.notes = _notesCtrl.text.trim();
    task.isUrgent = _isUrgent;
    task.reminderOptionIds = List<String>.from(_selectedReminderIds);
    task.reminderTimes = _computeReminderTimes();
    widget.onSaved(task);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: MediaQuery.of(context).padding.top + 12,
      ),
      child: GlassSheet(
        skin: skin,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              if (notification.scrollDelta != null && notification.scrollDelta! < -5) {
                FocusScope.of(context).unfocus();
              }
            }
            return false;
          },
          child: GestureDetector(
            onVerticalDragUpdate: (d) {
              if (d.delta.dy > 12) FocusScope.of(context).unfocus();
            },
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SheetHandleBar(skin: skin),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(
                        widget.isReviewMode ? Icons.mic_outlined : Icons.task_alt_outlined,
                        size: 18,
                        color: skin.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.isReviewMode
                            ? 'Erkannt — bitte prüfen'
                            : (_isEditing ? 'Aufgabe bearbeiten' : 'Neue Aufgabe'),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary),
                      ),
                    ]),
                    if (widget.isReviewMode) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Diktat wurde automatisch erkannt — Titel und Datum ggf. anpassen.',
                        style: TextStyle(fontSize: 11.5, color: skin.textMuted),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleCtrl,
                      focusNode: _titleFocus,
                      autofocus: !_isEditing,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Titel',
                        hintStyle: TextStyle(color: skin.surface(0.22), fontSize: 17),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _save(),
                    ),

                    const SizedBox(height: 14),
                    Container(height: 0.6, color: skin.surface(0.10)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: skin.textPrimary, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'Notiz hinzufügen…',
                        hintStyle: TextStyle(color: skin.surface(0.26), fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                'DRINGEND',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _isUrgent ? const Color(0xFFEF5B5B).withValues(alpha: 0.85) : skin.surface(0.38),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 0.5,
                                  color: _isUrgent ? const Color(0xFFEF5B5B).withValues(alpha: 0.25) : skin.surface(0.12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: _isUrgent,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => _isUrgent = v);
                            },
                            activeThumbColor: const Color(0xFFEF5B5B),
                            activeTrackColor: const Color(0xFFEF5B5B).withValues(alpha: 0.28),
                            inactiveThumbColor: skin.surface(0.4),
                            inactiveTrackColor: skin.surface(0.08),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: _SectionLabel(label: 'FRIST', skin: skin)),
                        Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: _fristEnabled,
                            onChanged: (v) => _setFristEnabled(v),
                            activeThumbColor: skin.primary,
                            activeTrackColor: skin.primary.withValues(alpha: 0.28),
                            inactiveThumbColor: skin.surface(0.4),
                            inactiveTrackColor: skin.surface(0.08),
                          ),
                        ),
                      ],
                    ),
                    if (_fristEnabled) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: _TaskDateTile(
                            skin: skin,
                            date: _dueDate,
                            onTap: _pickDate,
                            onDoubleTap: _doubleTapDate,
                            onSwipeDay: _swipeDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TaskTimeTile(
                            skin: skin,
                            enabled: _dueDate != null,
                            time: (_dueDate != null && _hasTime) ? TimeOfDay(hour: _dueDate!.hour, minute: _dueDate!.minute) : null,
                            onTap: _pickTime,
                            onDoubleTap: _doubleTapTime,
                            onSwipeMinute: _swipeTime,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text('Wischen · Tippen · Doppeltippen', style: TextStyle(fontSize: 10, color: skin.surface(0.28))),
                    ],
                    const SizedBox(height: 16),
                    _SectionLabel(label: 'HINWEISEN', skin: skin),
                    const SizedBox(height: 8),
                    Text(
                      _dueDate == null
                          ? 'Wann möchtest du erinnert werden?'
                          : 'Wie weit vor der Frist möchtest du erinnert werden?',
                      style: TextStyle(fontSize: 12, color: skin.surface(0.4)),
                    ),
                    const SizedBox(height: 10),
                    _ReminderQuickChips(
  options: _quickOptions,
  selectedIds: _selectedReminderIds,
  onToggle: _toggleReminderOption,
),
                    if (_selectedReminderIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_selectedReminderIds.length} von ${ReminderManager.maxSelectable} Erinnerungen gewählt',
                        style: TextStyle(fontSize: 10.5, color: skin.surface(0.32)),
                      ),
                    ],

                    const SizedBox(height: 22),
                    GlassPrimaryButton(
                      skin: skin,
                      label: widget.isReviewMode
                          ? 'Übernehmen'
                          : (_isEditing ? 'Speichern' : 'Hinzufügen'),
                      icon: Icons.check_circle_outline,
                      large: true,
                      onTap: _save,
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
// REMINDER QUICK CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderQuickChips extends StatelessWidget {
  final List<ReminderOption> options;
  final List<String> selectedIds;
  final void Function(String id) onToggle;

  const _ReminderQuickChips({
    required this.options,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final opt = options[i];
          final selected = selectedIds.contains(opt.id);
          return GlassChip(
            label: opt.label,
            active: selected,
            icon: Icons.check_rounded,
            onTap: () => onToggle(opt.id),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _SectionLabel({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: skin.surface(0.38), letterSpacing: 1.2)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 0.5, color: skin.surface(0.12))),
    ]);
  }
}