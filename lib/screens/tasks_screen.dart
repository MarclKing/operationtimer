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

// ─────────────────────────────────────────────────────────────────────────────
// TASK MODEL
//
// Erweitert um: Uhrzeit-Komponente war schon vorhanden (hasTime), NEU
// hinzugekommen sind reminderAt (Hinweis-Zeitpunkt, aktuell nur als
// Platzhalter-Datenfeld — siehe notification_service.dart) und notes
// (Freitext-Notiz, wird NICHT in der Kachel angezeigt, nur als kleines
// Icon markiert — analog zum Notiz-Verhalten in schedule_screen.dart).
// ─────────────────────────────────────────────────────────────────────────────

class Task {
  final String id;
  String title;
  DateTime? dueDate;
  bool hasTime;
  bool done;
  final DateTime createdAt;
  DateTime? completedAt;
  DateTime? reminderAt; // Platzhalter-Feld für künftige Push-Notification
  String notes;

  Task({
    required this.id,
    required this.title,
    this.dueDate,
    this.hasTime = false,
    this.done = false,
    required this.createdAt,
    this.completedAt,
    this.reminderAt,
    this.notes = '',
  });

  bool get hasDeadline => dueDate != null;
  bool get hasNotes => notes.trim().isNotEmpty;
  bool get hasReminder => reminderAt != null;

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
        'reminderAt': reminderAt?.toIso8601String(),
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
        reminderAt: j['reminderAt'] != null ? DateTime.tryParse(j['reminderAt'] as String) : null,
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

  /// Praktisch für schedule_screen.dart: liefert alle offenen Aufgaben mit
  /// Deadline am angegebenen Kalendertag (yyyy-MM-dd Vergleich), damit dort
  /// ein kleines Hinweis-Icon angezeigt werden kann.
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

  void closeOverlays() {
    if (_openSwipedId != null) setState(() => _openSwipedId = null);
    if (_inlineEditId != null) setState(() => _inlineEditId = null);
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
      NotificationService.instance.cancelTaskReminder(task.id);
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

  void _deleteTaskImmediate(Task task) {
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
      if (_openSwipedId == task.id) _openSwipedId = null;
      if (_inlineEditId == task.id) _inlineEditId = null;
    });
    TaskStore.delete(task.id);
    NotificationService.instance.cancelTaskReminder(task.id);
  }

  void _onCardSwiped(String? id) => setState(() => _openSwipedId = id);

  void _startInlineEdit(String id) {
    if (_inlineEditId == id) return;
    HapticFeedback.selectionClick();
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
      builder: (_) => _TaskEditSheet(
        skin: skin,
        initialTitle: initialTitle,
        initialDate: initialDate,
        onSaved: (task) {
          TaskStore.add(task);
          _load();
          if (task.hasReminder) {
            NotificationService.instance.scheduleTaskReminder(
              taskId: task.id,
              title: task.title,
              reminderAt: task.reminderAt!,
            );
          }
        },
      ),
    );
  }

  void _editTaskFull(Task task) {
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TaskEditSheet(
        skin: skin,
        existingTask: task,
        onSaved: (updated) {
          TaskStore.update(updated);
          _load();
          if (updated.hasReminder) {
            NotificationService.instance.scheduleTaskReminder(
              taskId: updated.id,
              title: updated.title,
              reminderAt: updated.reminderAt!,
            );
          } else {
            NotificationService.instance.cancelTaskReminder(updated.id);
          }
        },
        onDelete: () => _deleteTaskWithAnimation(task),
      ),
    );
  }

  Future<void> _confirmDelete(Task task) async {
    final skin = AppTheme.of(context);
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Aufgabe löschen',
      message: 'Diese Aufgabe wird unwiderruflich gelöscht.',
    );
    if (confirmed == true) _deleteTaskWithAnimation(task);
  }

  /// Wird vom Diktier-Flow aufgerufen, nachdem der Text transkribiert und
  /// geparst wurde. Legt die Aufgabe DIREKT an, ohne Rückfrage — die
  /// Bearbeitung danach läuft über das normale Inline-Edit (Single-Tap).
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
          if (_openSwipedId != null) setState(() => _openSwipedId = null);
          if (_inlineEditId != null) setState(() => _inlineEditId = null);
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
                                        onDelete: () => _confirmDelete(t),
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
                                        onDelete: () => _confirmDelete(t),
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
                                        onDelete: () => _confirmDelete(t),
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
// (56×56, BorderRadius.circular(20) statt Kreis, Glass-Blur, primary-Icon)
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
//     in "aktiviert"-Optik (gefüllter Primary-Hintergrund statt Glass), eine
//     Sprechblase erscheint dynamisch darüber.
//   - Während des Haltens: die Sprechblase zeigt KEINE Transkription, nur
//     ein Pegel-Spektrum (echte Amplitude via stt.SpeechToText.listen(
//     onSoundLevelChange: ...)).
//   - onLongPressEnd (Loslassen) → stt.stop(), die Blase wächst animiert
//     und enthüllt den erkannten Text Wort-für-Wort (nicht alles auf
//     einmal), danach wird SpokenTaskParser.parse() aufgerufen und über
//     [onResult] direkt eine neue Aufgabe angelegt.
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

  // Pegel-Glättung: Rohwerte von speech_to_text liegen ungefähr zwischen
  // -2 (sehr leise) und 10 (sehr laut) — Skala ist plattformabhängig nicht
  // exakt dokumentiert, daher clampen + normalisieren wir defensiv.
  double _smoothedLevel = 0.0;
  static const double _levelSmoothing = 0.35;

  late AnimationController _fabPulseCtrl;
  late AnimationController _bubbleCtrl; // Erscheinen/Verschwinden der Blase
  late Animation<double> _bubbleScale;
  late Animation<double> _bubbleOpacity;

  @override
  void initState() {
    super.initState();
    _fabPulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _bubbleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _bubbleScale = CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
    _bubbleOpacity = CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (err) {
        if (mounted) {
          setState(() {
            _phase = _DictationPhase.idle;
          });
          _bubbleCtrl.reverse();
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  void _onSpeechStatus(String status) {
    // 'done' / 'notListening' kommt vom Plugin, wenn die Engine selbst
    // (z. B. durch Stille-Timeout) beendet — wir behandeln das wie ein
    // reguläres Loslassen, falls der Nutzer den Finger noch hält.
    if (status == 'done' || status == 'notListening') {
      if (_phase == _DictationPhase.listening) {
        _finishListeningAndReveal();
      }
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _fabPulseCtrl.dispose();
    _bubbleCtrl.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      // Berechtigung fehlt oder Gerät unterstützt STT nicht — kurzes
      // visuelles Feedback statt stillem Fehlschlag.
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
    setState(() {
      _phase = _DictationPhase.listening;
      _liveTranscript = '';
      _finalTranscript = '';
      _smoothedLevel = 0.0;
      _revealedWords = [];
      _revealIndex = 0;
    });
    _bubbleCtrl.forward();

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
        // Tiefpassfilter, damit die Blase nicht nervös zuckt.
        final normalized = (level.clamp(-2.0, 10.0) + 2.0) / 12.0; // → 0..1
        setState(() {
          _smoothedLevel = _smoothedLevel + (normalized - _smoothedLevel) * _levelSmoothing;
        });
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
    await _speech.stop();
    final text = (_finalTranscript.isNotEmpty ? _finalTranscript : _liveTranscript).trim();

    if (text.isEmpty) {
      setState(() => _phase = _DictationPhase.idle);
      _bubbleCtrl.reverse();
      return;
    }

    setState(() {
      _phase = _DictationPhase.processing;
    });

    // Kurze, bewusste Verzögerung: gibt der UI Zeit, den Übergang von
    // "Pegel-Spektrum" zu "Verarbeitung" sauber zu zeigen (Ladeindikator),
    // bevor das Wort-für-Wort-Reveal startet — fühlt sich intentional an
    // statt abrupt.
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

  void _onRevealComplete(String text) {
    setState(() => _phase = _DictationPhase.done);
    final parsed = SpokenTaskParser.parse(text);
    // Kurze Pause, damit der Nutzer das fertig enthüllte Ergebnis noch
    // einen Moment lesen kann, bevor die Blase wieder verschwindet und
    // die neue Aufgabe in der Liste erscheint.
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
          animation: _bubbleCtrl,
          builder: (context, child) {
            if (_bubbleCtrl.value == 0 && _phase == _DictationPhase.idle) return const SizedBox.shrink();
            return Positioned(
              bottom: 70,
              right: -8,
              child: Transform.scale(
                alignment: Alignment.bottomRight,
                scale: 0.85 + _bubbleScale.value * 0.15,
                child: Opacity(
                  opacity: _bubbleOpacity.value.clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            );
          },
          child: _DictationBubble(
            skin: skin,
            phase: _phase,
            level: _smoothedLevel,
            revealedWords: _revealedWords,
            revealIndex: _revealIndex,
          ),
        ),

        // ── FAB ──
        GestureDetector(
          onLongPressStart: (_) => _startListening(),
          onLongPressEnd: (_) => _finishListeningAndReveal(),
          onLongPressCancel: () => _finishListeningAndReveal(),
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
                    child: Icon(
                      _isActive ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _isActive ? skin.onGradient : skin.textPrimary,
                      size: 24,
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
  final double level; // 0..1, nur relevant bei phase == listening
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

    // Breite/Höhe wachsen, sobald Text enthüllt wird — AnimatedContainer
    // sorgt für die "wird dynamisch größer"-Optik aus der Anforderung.
    final double minWidth = 64;
    final double maxWidth = 240;
    final double targetWidth = isRevealing
        ? math.min(maxWidth, minWidth + (revealedWords.take(revealIndex).join(' ').length * 6.2))
        : minWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(
        minWidth: minWidth,
        maxWidth: maxWidth,
      ),
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
              border: Border.all(
                color: skin.primary.withValues(alpha: 0.30),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: isListening
                ? _SpectrumIndicator(skin: skin, level: level)
                : isProcessing
                    ? _ProcessingIndicator(skin: skin)
                    : _RevealingText(
                        skin: skin,
                        words: revealedWords,
                        revealIndex: revealIndex,
                      ),
          ),
        ),
      ),
    );
  }
}

/// Reines Pegel-Spektrum (mehrere vertikale Balken), KEINE Transkription —
/// nur visuelles Feedback, dass aufgenommen wird, wie in der Anforderung
/// beschrieben.
class _SpectrumIndicator extends StatefulWidget {
  final AppSkin skin;
  final double level;
  const _SpectrumIndicator({required this.skin, required this.level});

  @override
  State<_SpectrumIndicator> createState() => _SpectrumIndicatorState();
}

class _SpectrumIndicatorState extends State<_SpectrumIndicator> with SingleTickerProviderStateMixin {
  late final List<double> _barOffsets;

  @override
  void initState() {
    super.initState();
    // Leicht unterschiedliche Phasen-Offsets pro Balken, damit das
    // Spektrum nicht wie ein einziger synchroner Block aussieht, sondern
    // organisch wirkt — reagiert aber trotzdem auf den echten Pegel.
    _barOffsets = List.generate(5, (i) => (i - 2) * 0.12);
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
          final adjusted = (widget.level + _barOffsets[i]).clamp(0.06, 1.0);
          final h = 6.0 + adjusted * 22.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: skin.primary.withValues(alpha: 0.55 + adjusted * 0.45),
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
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation(skin.primary),
          ),
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
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: skin.textPrimary,
        height: 1.35,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TASK CARD
//
// Verhalten gemäß Anforderung:
//   - Single-Tap (wenn nicht gewischt offen) → Inline-Edit: Titel wird zum
//     TextField, Tastatur öffnet automatisch. Schließt + speichert bei:
//       a) Tippen außerhalb der Kachel (siehe TasksScreenState GestureDetector)
//       b) Wisch-Geste nach unten auf der Kachel
//       c) Tab-Wechsel (TasksScreenState.closeOverlays() wird von außen
//          aufgerufen, siehe Integrationshinweis unten)
//   - Double-Tap → öffnet das volle Edit-Sheet (Titel, Datum, Zeit,
//     Reminder, Notizen).
//   - Swipe-Delete nutzt jetzt SwipeAnimationMixin (Drag) +
//     eigenen _deleteAnimController (Austritts-Animation), 1:1 nach dem
//     Vorbild von _FahrtCardState in fahrtenbuch_screen.dart.
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
        widget.onCommitInlineEdit(_inlineCtrl.text);
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
    // Inline-Edit wurde von außen beendet (Tap außerhalb / Tab-Wechsel) →
    // Fokus abgeben, falls noch gehalten.
    if (oldWidget.isInlineEditing && !widget.isInlineEditing && _inlineFocus.hasFocus) {
      _inlineFocus.unfocus();
    }
    // Inline-Edit wurde von außen gestartet → Text synchronisieren + Fokus
    // setzen + Cursor ans Ende.
    if (!oldWidget.isInlineEditing && widget.isInlineEditing) {
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

  void _handleTap() {
    if (_isOpen) {
      _close();
      return;
    }
    if (widget.isInlineEditing) return; // schon im Edit-Modus, nichts tun
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
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: skin.textPrimary,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (v) => widget.onCommitInlineEdit(v),
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
                border: Border.all(
                  color: task.done ? skin.statComplete : skin.surface(0.28),
                  width: 1.8,
                ),
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
              if (task.hasDeadline || task.hasNotes) ...[
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
                  // Notiz-Icon: NUR ein Symbol, kein Text-Inhalt sichtbar —
                  // analog zum Notiz-Verhalten in schedule_screen.dart
                  // (_DayCard zeigt auch nur Icons.sticky_note_2_outlined).
                  if (task.hasNotes) ...[
                    if (task.hasDeadline) const SizedBox(width: 8),
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
                if (d.delta.dy > 6) {
                  widget.onCommitInlineEdit(_inlineCtrl.text);
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
                onTap: () { _close(); widget.onDelete(); },
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
// TASK EDIT SHEET — erweitert um Datum, Uhrzeit, Hinweis-Zeitpunkt (Reminder)
// und Notizen. Wird sowohl für "Neue Aufgabe" als auch für Double-Tap-Edit
// genutzt (existingTask == null → Neuanlage).
// ─────────────────────────────────────────────────────────────────────────────

class _TaskEditSheet extends StatefulWidget {
  final AppSkin skin;
  final String? initialTitle;
  final DateTime? initialDate;
  final Task? existingTask;
  final void Function(Task task) onSaved;
  final VoidCallback? onDelete;

  const _TaskEditSheet({
    required this.skin,
    this.initialTitle,
    this.initialDate,
    this.existingTask,
    required this.onSaved,
    this.onDelete,
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
  DateTime? _reminderAt;

  bool get _isEditing => widget.existingTask != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existingTask?.title ?? widget.initialTitle ?? '');
    _notesCtrl = TextEditingController(text: widget.existingTask?.notes ?? '');
    _dueDate = widget.existingTask?.dueDate ?? widget.initialDate;
    _hasTime = widget.existingTask?.hasTime ?? false;
    _reminderAt = widget.existingTask?.reminderAt;
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
      setState(() {
        _dueDate = DateTime(result.year, result.month, result.day, _dueDate?.hour ?? 0, _dueDate?.minute ?? 0);
      });
    }
  }

  Future<void> _pickTime() async {
    final skin = widget.skin;
    final base = _dueDate ?? DateTime.now();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
        skin: skin,
        label: 'Uhrzeit auswählen',
        onTimeSelected: (t) {
          setState(() {
            final d = _dueDate ?? DateTime.now();
            _dueDate = DateTime(d.year, d.month, d.day, t.hour, t.minute);
            _hasTime = true;
          });
        },
      ),
    );
  }

  void _clearDate() => setState(() {
        _dueDate = null;
        _hasTime = false;
        _reminderAt = null; // Reminder ohne Deadline ergibt aktuell keinen Sinn
      });

  Future<void> _pickReminder() async {
    if (_dueDate == null) return;
    final skin = widget.skin;
    final base = _reminderAt ?? _dueDate!;

    final result = await showSingleDatePicker(
      context: context,
      skin: skin,
      initialDate: base,
      minimumDate: DateTime.now().subtract(const Duration(days: 1)),
      maximumDate: _dueDate!,
    );
    if (result == null || !mounted) return;

    DateTime combined = DateTime(result.year, result.month, result.day, base.hour, base.minute);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: combined.hour, minute: combined.minute),
        skin: skin,
        label: 'Wann hinweisen?',
        onTimeSelected: (t) {
          setState(() {
            _reminderAt = DateTime(combined.year, combined.month, combined.day, t.hour, t.minute);
          });
        },
      ),
    );
  }

  void _clearReminder() => setState(() => _reminderAt = null);

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final task = widget.existingTask ??
        Task(id: DateTime.now().millisecondsSinceEpoch.toString(), title: title, createdAt: DateTime.now());
    task.title = title;
    task.dueDate = _dueDate;
    task.hasTime = _dueDate != null && _hasTime;
    task.notes = _notesCtrl.text.trim();
    task.reminderAt = _dueDate != null ? _reminderAt : null;
    widget.onSaved(task);
    Navigator.pop(context);
  }

  Future<void> _confirmDeleteFromSheet() async {
    if (widget.onDelete == null) return;
    final skin = widget.skin;
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Aufgabe löschen',
      message: 'Diese Aufgabe wird unwiderruflich gelöscht.',
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context);
      widget.onDelete!.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSheet(
        skin: skin,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: SheetHandle(skin: skin)),
                const SizedBox(height: 16),
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
                    hintText: 'z. B. Auto in die Werkstatt bringen',
                    hintStyle: TextStyle(color: skin.surface(0.22), fontSize: 17),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _ChipButton(
                    skin: skin,
                    icon: Icons.calendar_today_outlined,
                    label: _dueDate == null ? 'Datum' : DateFormat('dd.MM.yyyy').format(_dueDate!),
                    active: _dueDate != null,
                    onTap: _pickDate,
                  ),
                  if (_dueDate != null)
                    _ChipButton(
                      skin: skin,
                      icon: Icons.schedule_outlined,
                      label: _hasTime ? DateFormat('HH:mm').format(_dueDate!) : 'Uhrzeit',
                      active: _hasTime,
                      onTap: _pickTime,
                    ),
                  if (_dueDate != null)
                    GestureDetector(
                      onTap: _clearDate,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25)),
                        ),
                        child: Icon(Icons.close, size: 16, color: skin.deleteColor),
                      ),
                    ),
                ]),

                if (_dueDate != null) ...[
                  const SizedBox(height: 18),
                  _SectionLabel(label: 'HINWEISEN', skin: skin),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _ChipButton(
                      skin: skin,
                      icon: Icons.notifications_outlined,
                      label: _reminderAt == null
                          ? 'Zeitpunkt wählen'
                          : DateFormat('dd.MM. · HH:mm').format(_reminderAt!),
                      active: _reminderAt != null,
                      onTap: _pickReminder,
                    ),
                    if (_reminderAt != null)
                      GestureDetector(
                        onTap: _clearReminder,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: skin.deleteColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25)),
                          ),
                          child: Icon(Icons.close, size: 16, color: skin.deleteColor),
                        ),
                      ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Benachrichtigungen folgen in Kürze — der Zeitpunkt wird schon jetzt gespeichert.',
                      style: TextStyle(fontSize: 10.5, color: skin.surface(0.32)),
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                _SectionLabel(label: 'NOTIZEN', skin: skin),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: skin.glassBorder),
                      ),
                      child: TextField(
                        controller: _notesCtrl,
                        maxLines: 4,
                        minLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(color: skin.textPrimary, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
                        decoration: InputDecoration(
                          hintText: 'Notiz eingeben…',
                          hintStyle: TextStyle(color: skin.surface(0.25), fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),
                GlassPrimaryButton(
                  skin: skin,
                  label: _isEditing ? 'Speichern' : 'Hinzufügen',
                  icon: Icons.check_circle_outline,
                  large: true,
                  onTap: _save,
                ),
                if (_isEditing && widget.onDelete != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: GestureDetector(
                      onTap: _confirmDeleteFromSheet,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 20),
                            decoration: BoxDecoration(
                              color: skin.deleteColor.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: skin.deleteColor.withValues(alpha: 0.22)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.delete_outline, color: skin.deleteColor, size: 15),
                              const SizedBox(width: 7),
                              Text('Aufgabe löschen', style: TextStyle(color: skin.deleteColor, fontSize: 13, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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

class _ChipButton extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ChipButton({required this.skin, required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: active ? skin.primaryWithAlpha(0.14) : skin.surface(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? skin.primaryWithAlpha(0.35) : skin.glassBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: active ? skin.primary : skin.surface(0.45)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? skin.primary : skin.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}