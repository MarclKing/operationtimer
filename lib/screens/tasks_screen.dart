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
import '../widgets/glass_pickers.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/swipe_animation_mixin.dart';
import '../services/notification_service.dart';
import '../services/spoken_task_parser.dart';
import '../services/reminder_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';


// ─────────────────────────────────────────────────────────────────────────────
// TASK MODEL
//
// reminderTimes: bis zu 3 konkrete Zeitpunkte (DateTime), zu denen erinnert
// werden soll. Werden aus ReminderOption (Duration) + Bezugspunkt berechnet:
//   - ohne Deadline: Bezugspunkt = "jetzt" (Erstellungszeitpunkt)
//   - mit Deadline:  Bezugspunkt = dueDate, Reminder = dueDate - duration
// reminderOptionIds: die IDs der gewählten ReminderOption — werden separat
// gespeichert, damit beim Bearbeiten die ursprüngliche Auswahl (z. B. "1 Tag
// vorher") wieder vorbelegt werden kann, statt nur den rohen DateTime zu
// haben (aus dem sich die Auswahl nicht mehr eindeutig rekonstruieren lässt).
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
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        dueDate: j['dueDate'] != null ? DateTime.tryParse(j['dueDate'] as String) : null,
        hasTime: j['hasTime'] as bool? ?? false,
        done: j['done'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        completedAt: j['completedAt'] != null ? DateTime.tryParse(j['completedAt'] as String) : null,
        reminderTimes: (j['reminderTimes'] as List?)
                ?.map((e) => DateTime.tryParse(e.toString()))
                .whereType<DateTime>()
                .toList() ??
            [],
        reminderOptionIds:
            (j['reminderOptionIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
        notes: j['notes'] as String? ?? '',
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

  /// Für schedule_screen.dart: liefert alle offenen Aufgaben mit Deadline am
  /// angegebenen Kalendertag, damit dort ein kleines Hinweis-Icon angezeigt
  /// werden kann (nur an Tagen mit hinterlegtem Dienstplan-Eintrag relevant —
  /// das Filtern danach übernimmt schedule_screen.dart selbst).
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _load() => setState(() => _tasks = TaskStore.loadAll());

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  /// Wird von main.dart bei Tab-Wechsel aufgerufen, damit offene Swipes und
  /// ein laufendes Inline-Edit (samt Speichern) korrekt geschlossen werden.
  void closeOverlays() {
    if (_inlineEditId != null) {
      final id = _inlineEditId!;
      final cardKey = _taskCardKeys[id];
      cardKey?.currentState?.commitInlineEditNow();
      setState(() => _inlineEditId = null);
    }
    if (_openSwipedId != null) setState(() => _openSwipedId = null);
  }

  List<Task> get _deadlineTasks {
    final list = _tasks.where((t) => t.hasDeadline && !t.done).toList();
    list.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return list;
  }

  List<Task> get _generalTasks {
    final list = _tasks.where((t) => !t.hasDeadline && !t.done).toList();
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

  // Swipe-Löschen löscht jetzt SOFORT, ohne Bestätigungsdialog.
  void _deleteTaskImmediate(Task task) {
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
      if (_openSwipedId == task.id) _openSwipedId = null;
      if (_inlineEditId == task.id) _inlineEditId = null;
    });
    TaskStore.delete(task.id);
    NotificationService.instance.cancelTaskReminders(task.id);
  }

  void _onCardSwiped(String? id) => setState(() => _openSwipedId = id);

  void _startInlineEdit(String id) {
    if (_inlineEditId == id) return;
    HapticFeedback.selectionClick();
    // Falls eine andere Karte noch im Inline-Edit war, deren Eingabe zuerst
    // sauber übernehmen, bevor die neue startet.
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
    setState(() {
      _inlineEditId = null;
      if (trimmed.isNotEmpty && trimmed != task.title) {
        task.title = trimmed;
      }
    });
    if (trimmed.isNotEmpty) {
      TaskStore.update(task);
    }
  }

  void openQuickAdd({String? initialTitle, DateTime? initialDate}) {
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
        child: _TaskEditSheet(
          skin: skin,
          initialTitle: initialTitle,
          initialDate: initialDate,
          onSaved: (task) {
            TaskStore.add(task);
            _load();
            _scheduleReminders(task);
          },
        ),
      ),
    );
  }

  void _editTaskFull(Task task) {
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
        child: _TaskEditSheet(
          skin: skin,
          existingTask: task,
          onSaved: (updated) {
            TaskStore.update(updated);
            _load();
            NotificationService.instance.cancelTaskReminders(updated.id);
            _scheduleReminders(updated);
          },
        ),
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

  /// Wird vom Diktier-Flow aufgerufen, nachdem der Text transkribiert und
  /// geparst wurde. Legt die Aufgabe DIREKT an, ohne Rückfrage — die
  /// Bearbeitung danach läuft über das normale Inline-/Double-Tap-Edit.
  void _createTaskFromSpeech(ParsedSpokenTask parsed) {
    final combined = parsed.combinedDateTime;
    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: parsed.title,
      dueDate: combined,
      hasTime: parsed.hasTime,
      createdAt: DateTime.now(),
    );
    TaskStore.add(task);
    _load();
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;
    final hasAnyOpen = _deadlineTasks.isNotEmpty || _generalTasks.isNotEmpty;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: GestureDetector(
        onTap: () {
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

            // ── Floating Action Buttons: Mikrofon (Diktieren) + Plus ──
            // Design 1:1 aus fahrtenbuch_screen.dart übernommen (56×56,
            // BorderRadius.circular(20), Glass-Blur, primary-Icon).
            Positioned(
              right: 20,
              bottom: bottomNavHeight + 16,
              child: Row(
                children: [
                  _DictationFab(
                    skin: skin,
                    onResult: _createTaskFromSpeech,
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

// ─────────────────────────────────────────────────────────────────────────────
// TASKS FAB — identisches Design zum FAB in fahrtenbuch_screen.dart
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
// DICTATION FAB + Sprechblase
//
// Verhalten:
//   - Press-and-hold (onLongPressStart) → startet stt.listen(), Icon wechselt
//     in "aktiviert"-Optik, eine Sprechblase erscheint dynamisch darüber.
//   - Während des Haltens: KEINE Transkription sichtbar, nur ein
//     Pegel-Spektrum aus echten Amplitudenwerten (onSoundLevelChange).
//   - Loslassen → stt.stop(), die Blase wächst animiert und enthüllt den
//     erkannten Text Wort-für-Wort, danach SpokenTaskParser.parse() →
//     Aufgabe wird direkt angelegt.
//
// FIX gegenüber der Vorversion: onSoundLevelChange liefert auf manchen
// Android-/iOS-Versionen für die ersten ~200-400ms keine Werte oder bleibt
// bei 0.0, bis die Engine "warmgelaufen" ist. Das führte dazu, dass die
// Balken die ganze Zeit über flach blieben. Fix: ein leichter Idle-Pulse
// läuft immer mit (sehr kleine Amplitude), echte Pegelwerte werden additiv
// draufgerechnet — die Blase wirkt dadurch von der ersten Millisekunde an
// "lebendig", auch bevor echte Werte ankommen, und reagiert danach sauber
// auf die tatsächliche Lautstärke.
// ─────────────────────────────────────────────────────────────────────────────

enum _DictationPhase { idle, listening, processing, revealing, done }

class _DictationFab extends StatefulWidget {
  final AppSkin skin;
  final void Function(ParsedSpokenTask parsed) onResult;
  const _DictationFab({required this.skin, required this.onResult});

  @override
  State<_DictationFab> createState() => _DictationFabState();
}

class _DictationFabState extends State<_DictationFab> with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  _DictationPhase _phase = _DictationPhase.idle;
String _liveTranscript = '';
String _finalTranscript = '';
List<String> _revealedWords = [];
int _revealIndex = 0;
Timer? _revealTimer;

double _rawLevel = 0.0;
double _smoothedLevel = 0.0;
static const double _levelSmoothing = 0.35;
DateTime? _listenStartedAt;

// ── Abbruch-Geste ──
bool _cancelDragActive = false;   // Finger bewegt sich während LongPress
double _cancelDragX = 0.0;        // akkumulierter horizontaler Versatz
bool _isCancelling = false;       // Abbruch-Animation läuft
static const double _cancelThreshold = 48.0; // px nach links → Abbruch
bool _showCancelHint = false;     // roter Hinweis sichtbar
Timer? _cancelHintTimer;          // zeigt Hint nach kurzem Delay

// Amplitude-Tracking: gleitende Max-Normalisierung damit auch leise
// Geräte ein sichtbares Spektrum bekommen.
double _levelMax = 0.12;          // dynamisch angepasst, startet niedrig

  late AnimationController _fabPulseCtrl;
  late AnimationController _idlePulseCtrl; // Sockel-Puls solange echte Werte fehlen
  late AnimationController _bubbleCtrl;
  late Animation<double> _bubbleScale;
  late Animation<double> _bubbleOpacity;

  late AnimationController _cancelCtrl;
late Animation<double> _cancelSlide;   // 0→1: Blase wischt nach links
late Animation<double> _cancelFade;
late AnimationController _cancelHintCtrl;
late Animation<double> _cancelHintOpacity;

@override
void initState() {
  super.initState();
  _fabPulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  _idlePulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);
  _bubbleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  _bubbleScale = CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
  _bubbleOpacity = CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);

  // Cancel-Animation: Blase fliegt nach links + verblasst (220ms)
  _cancelCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  _cancelSlide = Tween<double>(begin: 0.0, end: -180.0).animate(
      CurvedAnimation(parent: _cancelCtrl, curve: Curves.easeInCubic));
  _cancelFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _cancelCtrl, curve: const Interval(0.0, 0.7)));

  // Hint-Einblende-Animation (Pfeil links + roter Badge)
  _cancelHintCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  _cancelHintOpacity = CurvedAnimation(parent: _cancelHintCtrl, curve: Curves.easeOut);

  _initSpeech();
}

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (err) {
        if (mounted) {
          setState(() => _phase = _DictationPhase.idle);
          _bubbleCtrl.reverse();
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      if (_phase == _DictationPhase.listening) {
        _finishListeningAndReveal();
      }
    }
  }

  @override
void dispose() {
  _revealTimer?.cancel();
  _cancelHintTimer?.cancel();
  _fabPulseCtrl.dispose();
  _idlePulseCtrl.dispose();
  _bubbleCtrl.dispose();
  _cancelCtrl.dispose();
  _cancelHintCtrl.dispose();
  super.dispose();
}

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('🎙 Spracherkennung nicht verfügbar — Berechtigung in den Einstellungen prüfen.'),
          backgroundColor: widget.skin.bgCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ));
      }
      return;
    }
    HapticFeedback.mediumImpact();
    _listenStartedAt = DateTime.now();
    setState(() {
      _phase = _DictationPhase.listening;
      _liveTranscript = '';
      _finalTranscript = '';
      _rawLevel = 0.0;
      _smoothedLevel = 0.0;
      _revealedWords = [];
      _revealIndex = 0;
    });
    _bubbleCtrl.forward();

// Hint nach 500ms einblenden
    _cancelHintTimer?.cancel();
    _cancelHintTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _phase == _DictationPhase.listening) {
        setState(() => _showCancelHint = true);
        _cancelHintCtrl.forward();
      }
    });

    await _speech.listen(
      localeId: 'de_DE',
      onResult: (result) {
        if (mounted) {
          setState(() {
            _liveTranscript = result.recognizedWords;
            if (result.finalResult) _finalTranscript = result.recognizedWords;
          });
        }
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        // Normalisiere auf 0..1, dann adaptiv skalieren:
        // _levelMax passt sich nach oben an, damit auch leise Geräte
        // ein sichtbares Spektrum bekommen. Langsames Decay verhindert
        // dauerhaft hohe Decks bei einmaliger Lautstärke.
        final normalized = (level.clamp(-2.0, 10.0) + 2.0) / 12.0;
        _levelMax = (_levelMax * 0.97).clamp(0.08, 1.0);
        if (normalized > _levelMax) _levelMax = normalized;
        final scaled = (normalized / _levelMax).clamp(0.0, 1.0);
        setState(() => _rawLevel = scaled);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );
  }

  Future<void> _finishListeningAndReveal() async {
    if (_phase != _DictationPhase.listening) return;
    _cancelHintTimer?.cancel();
    _cancelHintCtrl.reverse();
    setState(() { _showCancelHint = false; _cancelDragActive = false; _cancelDragX = 0; });
    await _speech.stop();
    final text = (_finalTranscript.isNotEmpty ? _finalTranscript : _liveTranscript).trim();

    if (text.isEmpty) {
      setState(() => _phase = _DictationPhase.idle);
      _bubbleCtrl.reverse();
      return;
    }

    setState(() => _phase = _DictationPhase.processing);

    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    setState(() {
      _phase = _DictationPhase.revealing;
      _revealedWords = words;
      _revealIndex = 0;
    });

    _revealTimer?.cancel();
    _revealTimer = Timer.periodic(const Duration(milliseconds: 90), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _revealIndex++);
      if (_revealIndex >= _revealedWords.length) {
        timer.cancel();
        _onRevealComplete(text);
      }
    });
  }

  /// Bricht die laufende Aufnahme ohne Verarbeitung ab.
  /// Animiert die Blase nach links weg, dann Reset.
  Future<void> _cancelListening() async {
    if (_isCancelling || _phase != _DictationPhase.listening) return;
    _isCancelling = true;
    HapticFeedback.heavyImpact();
    _cancelHintTimer?.cancel();
    await _speech.cancel();

    // Blase nach links wegwischen
    await _cancelCtrl.forward();

    if (!mounted) return;
    // Reset
    _cancelCtrl.reset();
    _bubbleCtrl.reverse();
    setState(() {
      _phase = _DictationPhase.idle;
      _liveTranscript = '';
      _finalTranscript = '';
      _revealedWords = [];
      _revealIndex = 0;
      _rawLevel = 0.0;
      _smoothedLevel = 0.0;
      _levelMax = 0.12;
      _cancelDragActive = false;
      _cancelDragX = 0.0;
      _isCancelling = false;
      _showCancelHint = false;
    });
    _cancelHintCtrl.reset();
  }

  void _onRevealComplete(String text) {
    setState(() => _phase = _DictationPhase.done);
    final parsed = SpokenTaskParser.parse(text);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      widget.onResult(parsed);
      _bubbleCtrl.reverse().then((_) {
        if (mounted) {
          setState(() {
            _phase = _DictationPhase.idle;
            _liveTranscript = '';
            _finalTranscript = '';
            _revealedWords = [];
            _revealIndex = 0;
          });
        }
      });
    });
  }

  bool get _isActive => _phase != _DictationPhase.idle;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // ── Sprechblase ──
        AnimatedBuilder(
          animation: Listenable.merge([_bubbleCtrl, _cancelCtrl]),
          builder: (context, child) {
            if (_bubbleCtrl.value == 0 && _phase == _DictationPhase.idle && !_isCancelling) {
              return const SizedBox.shrink();
            }
            // Cancel: Blase nach links schieben + ausblenden
            final cancelOffset = _cancelSlide.value;
            final cancelOpacity = _cancelFade.value;
            return Positioned(
              bottom: 70,
              right: -8,
              child: Transform.translate(
                offset: Offset(cancelOffset + _cancelDragX.clamp(-60.0, 0.0), 0),
                child: Transform.scale(
                  alignment: Alignment.bottomRight,
                  scale: (0.85 + _bubbleScale.value * 0.15) *
                      (1.0 - (_cancelDragX.clamp(-60.0, 0.0).abs() / 60.0) * 0.15),
                  child: Opacity(
                    opacity: (_bubbleOpacity.value * cancelOpacity *
                            (1.0 - (_cancelDragX.clamp(-60.0, 0.0).abs() / 60.0) * 0.5))
                        .clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: AnimatedBuilder(
            animation: _idlePulseCtrl,
            builder: (context, _) {
              // Sockel-Puls: in den ersten ~350ms sorgt er allein für
              // Bewegung; sobald echte Pegelwerte ankommen, dominieren sie
              // (das Maximum aus beiden Quellen wird verwendet, kein
              // einfaches Addieren, damit es bei lauten Tönen nicht "klippt").
              final warmingUp = _listenStartedAt != null &&
                  DateTime.now().difference(_listenStartedAt!) < const Duration(milliseconds: 450);
              final idleComponent = warmingUp ? 0.18 + _idlePulseCtrl.value * 0.10 : 0.05 + _idlePulseCtrl.value * 0.04;
              final effectiveRaw = math.max(_rawLevel, idleComponent);
              _smoothedLevel = _smoothedLevel + (effectiveRaw - _smoothedLevel) * _levelSmoothing;

              return _DictationBubble(
                skin: skin,
                phase: _phase,
                level: _smoothedLevel,
                revealedWords: _revealedWords,
                revealIndex: _revealIndex,
              );
            },
          ),
        ),

        // ── FAB ──
        GestureDetector(
          onLongPressStart: (_) => _startListening(),
          onLongPressEnd: (_) {
            if (!_isCancelling) _finishListeningAndReveal();
          },
          onLongPressCancel: () {
            if (!_isCancelling) _finishListeningAndReveal();
          },
          // Wischen nach links während Halten → Abbrechen
          onLongPressMoveUpdate: (details) {
            if (_phase != _DictationPhase.listening || _isCancelling) return;
            final dx = details.offsetFromOrigin.dx;
            setState(() {
              _cancelDragX = dx;
              _cancelDragActive = dx < -8;
            });
            if (dx < -_cancelThreshold) {
              _cancelListening();
            }
          },
          child: AnimatedBuilder(
            animation: _fabPulseCtrl,
            builder: (context, child) {
              final pulse = _phase == _DictationPhase.listening ? _fabPulseCtrl.value : 0.0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _isActive
                          ? skin.primary.withValues(alpha: 0.85 + pulse * 0.15)
                          : (skin.isLight ? Colors.white.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.55)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isActive
                            ? Colors.white.withValues(alpha: 0.35)
                            : (skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12)),
                        width: _isActive ? 1.2 : 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isActive
                              ? skin.primaryWithAlpha(0.45 + pulse * 0.2)
                              : Colors.black.withValues(alpha: skin.isLight ? 0.08 : 0.35),
                          blurRadius: _isActive ? 20 + pulse * 10 : 24,
                          spreadRadius: _isActive ? pulse * 2 : 0,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            _cancelDragActive
                                ? Icons.close_rounded
                                : (_isActive ? Icons.mic_rounded : Icons.mic_none_rounded),
                            key: ValueKey(_cancelDragActive ? 'x' : (_isActive ? 'on' : 'off')),
                            color: _cancelDragActive
                                ? const Color(0xFFEF5B5B)
                                : (_isActive ? skin.onGradient : skin.textPrimary),
                            size: 24,
                          ),
                        ),
                        // Roter Cancel-Hint: kleines Badge oben-links
                        if (_showCancelHint || _cancelHintCtrl.value > 0)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: FadeTransition(
                              opacity: _cancelHintOpacity,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF5B5B),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.arrow_back_rounded, size: 8, color: Colors.white),
                                    SizedBox(width: 1),
                                    Text('abbr.', style: TextStyle(color: Colors.white, fontSize: 6, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
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
    );
  }
}

/// Die dynamische Sprechblase über dem Mikro-FAB.
class _DictationBubble extends StatelessWidget {
  final AppSkin skin;
  final _DictationPhase phase;
  final double level;
  final List<String> revealedWords;
  final int revealIndex;

  const _DictationBubble({
    required this.skin,
    required this.phase,
    required this.level,
    required this.revealedWords,
    required this.revealIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isListening = phase == _DictationPhase.listening;
    final isProcessing = phase == _DictationPhase.processing;
    final isRevealing = phase == _DictationPhase.revealing || phase == _DictationPhase.done;

    final double minWidth = 64;
    final double maxWidth = 240;
    final double targetWidth = isRevealing
        ? math.min(maxWidth, minWidth + (revealedWords.take(revealIndex).join(' ').length * 6.2))
        : minWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      width: targetWidth.clamp(minWidth, maxWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: skin.isLight ? Colors.white.withValues(alpha: 0.85) : skin.bgCard.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: skin.primary.withValues(alpha: 0.30), width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: isListening
                ? _SpectrumIndicator(skin: skin, level: level)
                : isProcessing
                    ? _ProcessingIndicator(skin: skin)
                    : _RevealingText(skin: skin, words: revealedWords, revealIndex: revealIndex),
          ),
        ),
      ),
    );
  }
}

/// Reines Pegel-Spektrum (5 vertikale Balken), KEINE Transkription.
class _SpectrumIndicator extends StatefulWidget {
  final AppSkin skin;
  final double level;
  const _SpectrumIndicator({required this.skin, required this.level});

  @override
  State<_SpectrumIndicator> createState() => _SpectrumIndicatorState();
}

class _SpectrumIndicatorState extends State<_SpectrumIndicator>
    with SingleTickerProviderStateMixin {
  late final List<double> _barOffsets;
  // Pro-Balken geglätteter Level — damit jeder Balken unabhängig animiert
  // und nicht alle synchron springen.
  late final List<double> _smoothed;
  late final Ticker _ticker;
  static const double _smoothing = 0.28;

  // Jeder Balken bekommt eine leicht unterschiedliche Phasenlage für den
  // Idle-Puls, damit die Balken versetzt schwingen (organischer Effekt).
  final List<double> _idlePhase = List.generate(5, (i) => i * 0.42);
  double _idleTick = 0.0;

  @override
  void initState() {
    super.initState();
    _barOffsets = List.generate(5, (i) => (i - 2) * 0.10);
    _smoothed = List.generate(5, (_) => 0.08);
    _ticker = createTicker((_) => _tick())..start();
  }

  void _tick() {
    if (!mounted) return;
    _idleTick += 0.055; // ~60fps → ~3.3 Zyklen/s
    setState(() {
      for (var i = 0; i < 5; i++) {
        // Idle-Puls: sehr leichte Bewegung, phasenverschoben pro Balken
        final idleVal = 0.06 + math.sin(_idleTick + _idlePhase[i]) * 0.04;
        // Echter Pegel mit Balken-Offset, Minimum = idleVal
        // level wird verstärkt (×2.5), damit es bei typischen Mikrofon-
        // Pegelwerten (0.1–0.4) deutlich sichtbar wird.
        final boosted = (widget.level * 2.5 + _barOffsets[i]).clamp(0.0, 1.0);
        final target = math.max(boosted, idleVal).clamp(0.06, 1.0);
        // Asymmetrisches Smoothing: schnell hoch (Attack), langsam runter (Release)
        final s = target > _smoothed[i] ? 0.55 : _smoothing;
        _smoothed[i] = _smoothed[i] + (target - _smoothed[i]) * s;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return SizedBox(
      height: 28,
      width: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(5, (i) {
          final v = _smoothed[i].clamp(0.06, 1.0);
          final h = 6.0 + v * 22.0;
          return Container(
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: skin.primary.withValues(alpha: 0.50 + v * 0.50),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

class _ProcessingIndicator extends StatelessWidget {
  final AppSkin skin;
  const _ProcessingIndicator({required this.skin});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: 64,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(skin.primary)),
        ),
      ),
    );
  }
}

class _RevealingText extends StatelessWidget {
  final AppSkin skin;
  final List<String> words;
  final int revealIndex;
  const _RevealingText({required this.skin, required this.words, required this.revealIndex});

  @override
  Widget build(BuildContext context) {
    final visibleWords = words.take(revealIndex).toList();
    return Text(
      visibleWords.isEmpty ? '…' : visibleWords.join(' '),
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: skin.textPrimary, height: 1.35),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// TASK CARD
//
// Fixes gegenüber v2:
//   1) Swipe → Löschen passiert SOFORT (kein confirmDeleteDialog mehr).
//   2) Inline-Edit speichert garantiert: zusätzlich zum Fokus-Listener gibt
//      es jetzt commitInlineEditNow(), das von außen (Tab-Wechsel, Tippen
//      außerhalb, Wischen) zuverlässig aufgerufen werden kann — der reine
//      Fokus-Listener allein war nicht robust genug, wenn der Fokuswechsel
//      durch Navigator/Tab-Switch nicht synchron feuert.
//   3) Reminder-Icon (Glocke) in der Kachel, analog zum Notiz-Icon.
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
  bool _committing = false; // Schutz gegen doppeltes Commit (Fokus-Listener + expliziter Call)

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

  /// Öffentlich, damit der Parent (Tab-Wechsel, Tippen außerhalb, Wischen)
  /// das Übernehmen garantiert anstoßen kann — unabhängig davon, ob der
  /// FocusNode-Listener rechtzeitig feuert.
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

  // Sofortiges Löschen beim Tap auf den Lösch-Bereich — kein Dialog mehr.
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
                  // Reminder-Icon: nur Glocke, keine Zeitpunkte sichtbar —
                  // die konkreten Zeiten sieht man erst im Edit-Sheet.
                  if (task.hasReminder) ...[
                    if (task.hasDeadline) const SizedBox(width: 8),
                    Icon(Icons.notifications_active_outlined, size: 12, color: skin.primary.withValues(alpha: 0.55)),
                  ],
                  // Notiz-Icon: nur Symbol, kein Text — analog schedule_screen.dart
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
            color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isInlineEditing ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder,
              width: widget.isInlineEditing ? 1.5 : 1.0,
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
                // Wischen nach unten schließt + übernimmt den Inline-Edit.
                if (d.delta.dy > 6) commitInlineEditNow();
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
//
// Fixes/Erweiterungen gegenüber v2:
//   - Lösch-Kachel komplett entfernt (Löschen geht jetzt nur noch über den
//     Swipe in der Liste).
//   - Reminder-System: Quick-Chips (MRU-sortiert, analog zu den
//     FahrtTyp-Quick-Chips in fahrtenbuch_screen.dart) + "weitere…"-Chip,
//     der den Vollbild-Picker mit Suche und Mehrfachauswahl (max. 3) öffnet.
// ─────────────────────────────────────────────────────────────────────────────
// TASK ZEIT BLOCK — Datum- und Uhrzeit-Kachel für das Edit-Sheet.
//
// Angelehnt an _ZeitBlock aus fahrtenbuch_screen.dart, aber schlanker:
//   - kein "ABFAHRT/ANKUNFT"-Doppelblock, sondern zwei eigenständige Kacheln
//     (Datum, Uhrzeit) nebeneinander, da Tasks nur einen Zeitpunkt brauchen.
//   - Tap → öffnet den jeweiligen Picker (showSingleDatePicker / IOSTimePicker).
//   - Datums-Kachel: horizontales Wischen ändert den Tag direkt (±1 pro
//     Schwellwert), ohne Sheet — exakt wie bei _ZeitBlock.
//   - Uhrzeit-Kachel: vertikales Wischen ändert die Minute direkt (±1 pro
//     Schwellwert), ohne Sheet.
//   - Beide bleiben dauerhaft sichtbar (kein Ein-/Ausblenden je nach Status),
//     damit Datum und Uhrzeit jederzeit per Wischen einstellbar sind.
// ─────────────────────────────────────────────────────────────────────────────

class _TaskDateTile extends StatefulWidget {
  final AppSkin skin;
  final DateTime? date; // null = noch kein Datum gesetzt
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<int> onSwipeDay; // delta in Tagen

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
              color: hasDate
                  ? skin.primary.withValues(alpha: skin.isLight ? 0.08 : 0.14)
                  : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity)),
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
                _vAccum += -d.delta.dy; // hoch = mehr Minuten
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
                color: hasTime
                    ? skin.primary.withValues(alpha: skin.isLight ? 0.08 : 0.14)
                    : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity)),
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

// ─────────────────────────────────────────────────────────────────────────────
// SHEET HANDLE BAR — Tap ODER nach unten wischen schließt das Sheet.
// Statisch (kein Live-Tracking/Transform) — analog zur Handle-Bar in
// fahrtenbuch_screen.dart: onVerticalDragEnd prüft nur die Geschwindigkeit
// beim Loslassen. Großzügige Hitbox: volle Breite, viel vertikaler Puffer.
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// TASK EDIT SHEET — v3
//
// Änderungen gegenüber v2 (auf expliziten Wunsch):
//   1) Datum + Uhrzeit sind jetzt zwei dauerhaft sichtbare Kacheln
//      (_TaskDateTile / _TaskTimeTile) statt Chips. Tap öffnet den
//      jeweiligen Picker; zusätzlich: horizontales Wischen auf der
//      Datums-Kachel ändert den Tag direkt, vertikales Wischen auf der
//      Uhrzeit-Kachel ändert die Minute direkt — ohne Sheet zu öffnen.
//   2) Reminder-Auswahl ist jetzt NUR noch die durchslidbare Chip-Reihe mit
//      ALLEN Optionen des Modus (MRU-sortiert). Kein Vollbild-Picker-Sheet
//      mehr, kein "weitere…"-Chip mehr — _ReminderPickerSheet wird in
//      diesem Screen nicht mehr verwendet.
// ─────────────────────────────────────────────────────────────────────────────

class _TaskEditSheet extends StatefulWidget {
  final AppSkin skin;
  final String? initialTitle;
  final DateTime? initialDate;
  final Task? existingTask;
  final void Function(Task task) onSaved;

  const _TaskEditSheet({
    required this.skin,
    this.initialTitle,
    this.initialDate,
    this.existingTask,
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
  bool _fristEnabled = true; // Steuert den FRIST-Switch im Sheet

  // Reminder-Auswahl: Liste der gewählten ReminderOption-IDs (max 3).
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
} else if (widget.initialDate != null) {
  _dueDate = widget.initialDate;
  _hasTime = false;
} else {
  // Neue Aufgabe ohne Vorgabe: aktuelles Datum, Uhrzeit auf nächste volle Stunde
  final now = DateTime.now();
  _dueDate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
  _hasTime = true;
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

  // ── Datum ──

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

  // Horizontales Wischen auf der Datums-Kachel: Tag direkt verschieben.
  // Falls noch gar kein Datum gesetzt war, greift das nicht (Kachel ist in
  // diesem Fall noch nicht swipe-aktiv, siehe _TaskDateTile.enabled-Logik
  // über die hasDate-Prüfung).
  void _swipeDate(int deltaDays) {
    if (_dueDate == null) return;
    setState(() {
      _dueDate = _dueDate!.add(Duration(days: deltaDays));
    });
  }

// Doppeltipp Datum: intelligent löschen/wiederherstellen
  void _doubleTapDate() {
    HapticFeedback.mediumImpact();
    if (_dueDate != null) {
      // Datum vorhanden → beides löschen (Datum + Uhrzeit) → Frist aus
      _clearDate();
    } else {
      // Datum leer → aktuelles Datum setzen, KEINE Uhrzeit → Frist an
      final now = DateTime.now();
      setState(() {
        _dueDate = DateTime(now.year, now.month, now.day, 0, 0);
        _hasTime = false;
        _fristEnabled = true;
      });
    }
  }

  // Doppeltipp Uhrzeit: intelligent löschen/wiederherstellen
  void _doubleTapTime() {
    HapticFeedback.mediumImpact();
    if (_hasTime && _dueDate != null) {
      // Uhrzeit vorhanden → nur Uhrzeit löschen, Datum bleibt
      setState(() => _hasTime = false);
    } else if (!_hasTime && _dueDate != null) {
      // Nur Datum, keine Uhrzeit → Datum+Uhrzeit auf jetzt setzen
      final now = DateTime.now();
      setState(() {
        _dueDate = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day,
            now.hour + 1, 0);
        _hasTime = true;
        _fristEnabled = true;
      });
    } else {
      // Gar nichts gesetzt → aktuelles Datum + nächste volle Stunde
      final now = DateTime.now();
      setState(() {
        _dueDate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
        _hasTime = true;
        _fristEnabled = true;
      });
    }
  }

  // ── Uhrzeit ──
  Future<void> _pickTime() async {
    if (_dueDate == null) return; // Uhrzeit ergibt ohne Datum keinen Sinn
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

  // Vertikales Wischen auf der Uhrzeit-Kachel: Minute direkt verschieben.
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

  // ── Frist Switch ──

  /// Zentrale Methode zum Ein-/Ausschalten der Frist — wird vom Switch
  /// aufgerufen. Doppeltipp-Handler (Datum/Uhrzeit) pflegen _fristEnabled
  /// direkt mit, sodass Switch und Doppeltipp immer denselben Zustand
  /// erzeugen und nie auseinanderlaufen können.
  Future<void> _setFristEnabled(bool enabled) async {
    if (enabled == _fristEnabled) return;
    if (!enabled) {
      // Frist aus → Datum/Uhrzeit komplett entfernen (= "ohne Frist").
      final hadDeadlineBefore = _dueDate != null;
      setState(() {
        _fristEnabled = false;
        _dueDate = null;
        _hasTime = false;
      });
      if (hadDeadlineBefore) await _onDeadlineModeChanged();
    } else {
      // Frist an → Datum auf heute, Uhrzeit auf nächste volle Stunde.
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

  /// Wird aufgerufen, sobald sich der Deadline-Status (vorhanden ↔ keine)
  /// ändert — NICHT bei reiner Uhrzeit-Vergabe (die ändert den Modus nicht,
  /// da Reminder-Berechnung sich nur am Datum orientiert). Setzt alle
  /// Reminder zurück und zeigt einen reinen Hinweis-Dialog.
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

  Future<void> _showReminderResetInfoDialog() {
    final skin = widget.skin;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: skin.isLight ? Colors.white.withValues(alpha: 0.94) : skin.bgCard.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: skin.glassBorder),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 28, offset: const Offset(0, 8))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: skin.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.notifications_off_outlined, color: skin.primary, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Erinnerungen zurückgesetzt',
                          style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'Da sich der Fristen-Status geändert hat, wurden alle bisher gewählten Erinnerungen entfernt. Du kannst unten neue auswählen.',
                    style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: skin.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: skin.primary.withValues(alpha: 0.25)),
                      ),
                      child: Center(
                        child: Text('Verstanden',
                            style: TextStyle(color: skin.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Reminder ──

  void _toggleReminderOption(String id) {
    setState(() {
      if (_selectedReminderIds.contains(id)) {
        _selectedReminderIds.remove(id);
      } else {
        if (_selectedReminderIds.length >= ReminderManager.maxSelectable) {
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Maximal 3 Erinnerungen pro Aufgabe.'),
            backgroundColor: widget.skin.bgCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          ));
          return;
        }
        HapticFeedback.selectionClick();
        _selectedReminderIds.add(id);
      }
    });
  }

  /// Berechnet die konkreten Reminder-DateTimes aus den gewählten Optionen.
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
    task.reminderOptionIds = List<String>.from(_selectedReminderIds);
    task.reminderTimes = _computeReminderTimes();
    widget.onSaved(task);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  Icon(Icons.task_alt_outlined, size: 18, color: skin.primary),
                  const SizedBox(width: 8),
                  Text(_isEditing ? 'Aufgabe bearbeiten' : 'Neue Aufgabe',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                ]),
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
                    _SectionLabel(label: 'FRIST', skin: skin),
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
                  skin: skin,
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
                  label: _isEditing ? 'Speichern' : 'Hinzufügen',
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
// REMINDER QUICK CHIPS — v3
//
// Fixes gegenüber v2:
//   1) Horizontales Wischen funktionierte nicht zuverlässig, weil die Reihe
//      in einem vertikalen SingleChildScrollView (dem restlichen Sheet)
//      eingebettet ist. Flutters Gesture-Arena entscheidet bei sehr kurzen
//      Wischbewegungen manchmal zugunsten des äußeren (vertikalen) Scrollers,
//      bevor die innere horizontale ListView "gewinnt" — vor allem, wenn man
//      nah am oberen/unteren Rand der Chip-Reihe ansetzt. Fix: die Reihe
//      bekommt einen EIGENEN ScrollController (statt implizitem), und wir
//      umschließen sie mit RawGestureDetector + HorizontalDragGestureRecognizer
//      mit eigenem GestureArenaTeam, damit horizontale Bewegungen innerhalb
//      dieser Zeile IMMER zuerst an die Chip-Reihe gehen, nie an das äußere
//      Sheet-Scrolling.
//   2) Neuer Fortschrittsanzeiger darunter: ein schlanker Balken zeigt, wie
//      weit man in der Liste ist und wie viel noch kommt.
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderQuickChips extends StatefulWidget {
  final AppSkin skin;
  final List<ReminderOption> options; // bereits MRU-sortiert (ReminderManager.getSorted)
  final List<String> selectedIds;
  final void Function(String id) onToggle;

  const _ReminderQuickChips({
    required this.skin,
    required this.options,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  State<_ReminderQuickChips> createState() => _ReminderQuickChipsState();
}

class _ReminderQuickChipsState extends State<_ReminderQuickChips> {
  final ScrollController _scrollCtrl = ScrollController();
  double _progress = 0.0; // 0 = ganz links, 1 = ganz rechts
  double _visibleFraction = 1.0; // Anteil der Liste, der sichtbar ist

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_updateProgress);
    // Nach dem ersten Layout einmal berechnen, damit die Anzeige sofort
    // korrekt ist (auch wenn noch nicht gescrollt wurde).
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateProgress());
  }

  @override
  void didUpdateWidget(_ReminderQuickChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateProgress());
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_updateProgress);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _updateProgress() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final maxExtent = pos.maxScrollExtent;
    final viewport = pos.viewportDimension;
    final total = maxExtent + viewport;
    setState(() {
      _progress = maxExtent <= 0 ? 0.0 : (pos.pixels / maxExtent).clamp(0.0, 1.0);
      _visibleFraction = total <= 0 ? 1.0 : (viewport / total).clamp(0.08, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          // RawGestureDetector mit eigenem Team sorgt dafür, dass eine
          // horizontale Drag-Geste, die HIER beginnt, immer von dieser
          // Liste gewinnt — nicht vom äußeren vertikalen Sheet-Scroll.
          child: RawGestureDetector(
            gestures: {
              HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
                () => HorizontalDragGestureRecognizer(),
                (instance) {
                  instance.onUpdate = (details) {
                    if (!_scrollCtrl.hasClients) return;
                    final newOffset = (_scrollCtrl.offset - details.delta.dx)
                        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
                    _scrollCtrl.jumpTo(newOffset);
                  };
                },
              ),
            },
            child: ListView.separated(
              controller: _scrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.options.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final opt = widget.options[i];
                final selected = widget.selectedIds.contains(opt.id);
                return GestureDetector(
                  onTap: () => widget.onToggle(opt.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? skin.primary.withValues(alpha: 0.15) : skin.surface(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder,
                        width: selected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (selected) ...[
                        Icon(Icons.check_rounded, size: 13, color: skin.primary),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        opt.label,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? skin.primary : skin.surface(0.5)),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
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