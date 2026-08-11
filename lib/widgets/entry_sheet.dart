// lib/widgets/entry_sheet.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/calendar_event.dart';
import '../screens/tasks_screen.dart' show Task;
import '../services/reminder_manager.dart';
import '../services/event_group_store.dart';
import 'glass_kit.dart';
import 'glass_pickers.dart';
import 'glass_dialogs.dart';
import 'glass_snackbar.dart';
import '../services/sync_service.dart';
import '../services/sync_token_service.dart';

// ─────────────────────────────────────────────────────────────────────────
// ENTRY MODE
// ─────────────────────────────────────────────────────────────────────────

enum EntryMode { task, event }

/// Rundet die aktuelle Uhrzeit auf die nächste volle Stunde und kombiniert
/// sie mit [day] (nur das Datum wird aus [day] übernommen). Verhindert, dass
/// neue Einträge auf Mitternacht (→ "12:00" im 12h-Format) landen.
DateTime _roundedTimeOnDay(DateTime day) {
  final now = DateTime.now();
  final roundedHour = now.minute == 0 ? now.hour : now.hour + 1;
  final wrapsDay = roundedHour >= 24;
  final base = wrapsDay
      ? DateTime(day.year, day.month, day.day).add(const Duration(days: 1))
      : DateTime(day.year, day.month, day.day);
  return DateTime(base.year, base.month, base.day, wrapsDay ? 0 : roundedHour, 0);
}

// ─────────────────────────────────────────────────────────────────────────
// ENTRY DRAFT — analog zu FahrtDraft in fahrtenbuch_screen.dart
// ─────────────────────────────────────────────────────────────────────────

class EntryDraft {
  EntryMode mode = EntryMode.task;
  String title = '';

  // Aufgabe
  String notes = '';
  DateTime? dueDate;
  bool hasTime = false;
  bool fristEnabled = false;
  bool isUrgent = false;
  List<String> taskReminderIds = [];

  // Ereignis
  String location = '';
  bool allDay = false;
  DateTime? start;
  DateTime? end;
  RepeatRule repeat = RepeatRule.none;
  List<String> groupKeys = [EventGroupStore.defaultGroup().key];
  String eventNotes = '';
  List<String> eventReminderIds = [];

  void reset() {
    mode = EntryMode.task;
    title = '';
    notes = '';
    dueDate = null;
    hasTime = false;
    fristEnabled = false;
    isUrgent = false;
    taskReminderIds = [];
    location = '';
    allDay = false;
    start = null;
    end = null;
    repeat = RepeatRule.none;
    groupKeys = [EventGroupStore.defaultGroup().key];
    eventNotes = '';
    eventReminderIds = [];
  }

  bool get hasAnyData {
    if (title.trim().isNotEmpty) return true;
    if (mode == EntryMode.task) {
      return notes.trim().isNotEmpty || dueDate != null || isUrgent || taskReminderIds.isNotEmpty;
    }
    return location.trim().isNotEmpty ||
        eventNotes.trim().isNotEmpty ||
        repeat != RepeatRule.none ||
        eventReminderIds.isNotEmpty;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// PUBLIC ENTRY POINT
//
// Ersetzt das alte, private _TaskEditSheet 1:1 für Aufgaben und deckt
// zusätzlich Kalender-Ereignisse ab. Aufrufe aus tasks_screen.dart:
//
//   showModalBottomSheet(
//     ...
//     builder: (_) => EntrySheet(
//       skin: skin,
//       initialMode: EntryMode.task,
//       existingTask: task,          // ODER existingEvent — nie beides
//       onTaskSaved: (t) => ...,
//       onEventSaved: (e) => ...,
//     ),
//   );
//
// [lockMode] = true beim Bearbeiten (existingTask/existingEvent gesetzt):
// Segmented Control ist dann sichtbar, aber deaktiviert/ausgegraut.
// ─────────────────────────────────────────────────────────────────────────

class EntrySheet extends StatefulWidget {
  final AppSkin skin;
  final EntryMode initialMode;
  final EntryDraft draft; // NEU
  final Task? existingTask;
  final CalendarEvent? existingEvent;
  final String? initialTitle;
  final DateTime? initialDate;
  final bool isReviewMode;
  final void Function(Task task)? onTaskSaved;
  final void Function(List<CalendarEvent> events)? onEventSaved;

  const EntrySheet({
    super.key,
    required this.skin,
    required this.draft, // NEU
    this.initialMode = EntryMode.task,
    this.existingTask,
    this.existingEvent,
    this.initialTitle,
    this.initialDate,
    this.isReviewMode = false,
    this.onTaskSaved,
    this.onEventSaved,
  }) : assert(existingTask == null || existingEvent == null,
            'Nie beides gleichzeitig setzen');

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  late EntryMode _mode;
  bool get _isEditing => widget.existingTask != null || widget.existingEvent != null;
  bool get _modeLocked => _isEditing;

  final _titleFocus = FocusNode();
  late TextEditingController _titleCtrl;

  @override
  void initState() {
    super.initState();
    _mode = widget.existingEvent != null
        ? EntryMode.event
        : (widget.existingTask != null ? EntryMode.task : widget.draft.mode);
    _titleCtrl = TextEditingController(
      text: widget.existingTask?.title ??
          widget.existingEvent?.title ??
          (widget.draft.title.isNotEmpty ? widget.draft.title : (widget.initialTitle ?? '')),
    );
    _titleCtrl.addListener(() {
      if (!_isEditing) widget.draft.title = _titleCtrl.text;
    });
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _closeSheet() {
    FocusScope.of(context).unfocus();
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
          onNotification: (n) {
            if (n is ScrollUpdateNotification &&
                n.scrollDelta != null &&
                n.scrollDelta! < -5) {
              FocusScope.of(context).unfocus();
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
                padding: EdgeInsets.fromLTRB(
                    20, 4, 20, 20 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DragHandle(skin: skin, onClose: _closeSheet),
                    const SizedBox(height: 10),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Opacity(
                        opacity: _modeLocked ? 0.45 : 1.0,
                        child: IgnorePointer(
                          ignoring: _modeLocked,
                          child: GlassSegmentedControl<EntryMode>(
                            compact: true,
                            value: _mode,
                            items: const [
                              GlassSegmentItem(value: EntryMode.task, label: 'Aufgabe'),
                              GlassSegmentItem(value: EntryMode.event, label: 'Ereignis'),
                            ],
                            onChanged: (m) {
                              if (_modeLocked) return;
                              setState(() => _mode = m);
                              widget.draft.mode = m;
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _titleCtrl,
                      focusNode: _titleFocus,
                      autofocus: !_isEditing,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                          color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Titel',
                        hintStyle: TextStyle(color: skin.surface(0.22), fontSize: 17),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(height: 0.6, color: skin.surface(0.10)),
                    const SizedBox(height: 12),

                    if (_mode == EntryMode.task)
                      _TaskFields(
                        skin: skin,
                        draft: widget.draft,
                        existingTask: widget.existingTask,
                        initialDate: widget.initialDate,
                        isReviewMode: widget.isReviewMode,
                        titleCtrl: _titleCtrl,
                        onSave: (task) {
                          widget.onTaskSaved?.call(task);
                          Navigator.pop(context);
                        },
                      )
                    else
                      _EventFields(
                        skin: skin,
                        draft: widget.draft,
                        existingEvent: widget.existingEvent,
                        initialDate: widget.initialDate,
                        titleCtrl: _titleCtrl,
                        onSave: (events) {
                          widget.onEventSaved?.call(events);
                          Navigator.pop(context);
                        },
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

// ─────────────────────────────────────────────────────────────────────────
// DRAG HANDLE (Tap zum Schließen, außer wenn Entwurf-Logik das
// übersteuert — Entwurf-Banner wird vom aufrufenden Screen verwaltet,
// analog zu FahrtenbuchScreen._DraftBanner. Hier nur das Handle selbst.)
// ─────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  final AppSkin skin;
  final VoidCallback onClose;
  const _DragHandle({required this.skin, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 100) onClose();
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

// ─────────────────────────────────────────────────────────────────────────
// SECTION LABEL (wiederverwendet aus tasks_screen-Optik)
// ─────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _SectionLabel({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: skin.surface(0.38), letterSpacing: 1.2)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 0.5, color: skin.surface(0.12))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// INLINE PILL BUTTON (NEU) — kompakte Datum/Zeit-Chips
// ─────────────────────────────────────────────────────────────────────────

class _InlinePillButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final VoidCallback? onTap;
  const _InlinePillButton({required this.skin, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: skin.surface(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: skin.textPrimary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TASK FIELDS — inhaltlich 1:1 identisch zum bisherigen _TaskEditSheet,
// nur ohne Titelfeld (das liegt jetzt eine Ebene höher, gemeinsam) und
// mit komplett neuem Layout (GlassListItem + InlinePillButton).
// ─────────────────────────────────────────────────────────────────────────

class _TaskFields extends StatefulWidget {
  final AppSkin skin;
  final EntryDraft draft;
  final Task? existingTask;
  final DateTime? initialDate;
  final bool isReviewMode;
  final TextEditingController titleCtrl;
  final void Function(Task task) onSave;

  const _TaskFields({
    required this.skin,
    required this.draft,
    required this.existingTask,
    required this.initialDate,
    required this.isReviewMode,
    required this.titleCtrl,
    required this.onSave,
  });

  @override
  State<_TaskFields> createState() => _TaskFieldsState();
}

class _TaskFieldsState extends State<_TaskFields> {
  late TextEditingController _notesCtrl;
  DateTime? _dueDate;
  bool _hasTime = false;
  bool _fristEnabled = true;
  bool _isUrgent = false;
  List<String> _selectedReminderIds = [];
  // NEU: Reihenfolge der Hinweisen-Optionen wird nur bei Moduswechsel neu
  // berechnet (Ohne Frist ⇄ Mit Frist ändert das Options-Set), nicht bei
  // jeder Auswahl — sonst "springen" die Einträge beim Markieren.
  ReminderMode? _quickOptionsMode;
  List<ReminderOption> _quickOptions = [];

  bool get _isEditing => widget.existingTask != null;
  ReminderMode get _mode => _dueDate != null ? ReminderMode.beforeDeadline : ReminderMode.relative;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.existingTask?.notes ?? widget.draft.notes);

    if (widget.existingTask != null) {
      _dueDate = widget.existingTask!.dueDate;
      _hasTime = widget.existingTask!.hasTime;
      _isUrgent = widget.existingTask!.isUrgent;
      _selectedReminderIds = List<String>.from(widget.existingTask!.reminderOptionIds);
      _fristEnabled = _dueDate != null;
    } else if (widget.draft.dueDate != null) {
      _dueDate = widget.draft.dueDate;
      _hasTime = widget.draft.hasTime;
      _isUrgent = widget.draft.isUrgent;
      _selectedReminderIds = List<String>.from(widget.draft.taskReminderIds);
      _fristEnabled = widget.draft.fristEnabled;
    } else if (widget.initialDate != null) {
      // NEU: Uhrzeit an aktuelle Zeit orientieren statt Mitternacht/12 Uhr.
      _dueDate = _roundedTimeOnDay(widget.initialDate!);
      _hasTime = true;
      _isUrgent = widget.draft.isUrgent;
      _selectedReminderIds = List<String>.from(widget.draft.taskReminderIds);
      _fristEnabled = true;
    } else {
      _dueDate = null;
      _hasTime = false;
      _isUrgent = widget.draft.isUrgent;
      _selectedReminderIds = List<String>.from(widget.draft.taskReminderIds);
      _fristEnabled = false;
    }

    _notesCtrl.addListener(_syncDraft);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _syncDraft() {
    if (_isEditing) return;
    widget.draft.notes = _notesCtrl.text;
    widget.draft.dueDate = _dueDate;
    widget.draft.hasTime = _hasTime;
    widget.draft.fristEnabled = _fristEnabled;
    widget.draft.isUrgent = _isUrgent;
    widget.draft.taskReminderIds = List<String>.from(_selectedReminderIds);
  }

  void _set(VoidCallback fn) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(fn);
    _syncDraft();
  }

  Future<void> _onDeadlineModeChanged() async {
    final hadReminders = _selectedReminderIds.isNotEmpty;
    _set(() => _selectedReminderIds = []);
    if (hadReminders && mounted) {
      await confirmActionDialog(
        context: context,
        skin: widget.skin,
        icon: Icons.notifications_off_outlined,
        title: 'Erinnerungen zurückgesetzt',
        message:
            'Da sich der Fristen-Status geändert hat, wurden alle bisher gewählten Erinnerungen entfernt.',
        cancelLabel: 'Verstanden',
        confirmLabel: 'Verstanden',
      );
    }
  }

  Future<void> _pickDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final result = await showSingleDatePicker(
      context: context,
      skin: widget.skin,
      initialDate: _dueDate ?? DateTime.now(),
      minimumDate: DateTime.now().subtract(const Duration(days: 1)),
      maximumDate: DateTime(DateTime.now().year + 3),
    );
    if (result == null) return;
    final hadBefore = _dueDate != null;
    _set(() {
      _dueDate = DateTime(result.year, result.month, result.day, _dueDate?.hour ?? 0, _dueDate?.minute ?? 0);
      _fristEnabled = true;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    if (!hadBefore) await _onDeadlineModeChanged();
  }

  Future<void> _pickTime() async {
    if (_dueDate == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final base = _dueDate!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
        skin: widget.skin,
        onTimeSelected: (t) {
          _set(() {
            _dueDate = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day, t.hour, t.minute);
            _hasTime = true;
          });
        },
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _setFristEnabled(bool enabled) async {
    if (enabled == _fristEnabled) return;
    if (!enabled) {
      final hadBefore = _dueDate != null;
      _set(() {
        _fristEnabled = false;
        _dueDate = null;
        _hasTime = false;
      });
      if (hadBefore) await _onDeadlineModeChanged();
    } else {
      final now = DateTime.now();
      _set(() {
        _fristEnabled = true;
        _dueDate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
        _hasTime = true;
      });
      await _onDeadlineModeChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    if (_quickOptionsMode != _mode) {
      _quickOptionsMode = _mode;
      _quickOptions = ReminderManager.getSorted(_mode);
    }
    final quickOptions = _quickOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _notesCtrl,
          maxLines: 8,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: skin.textPrimary, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Notiz hinzufügen…',
            hintStyle: TextStyle(color: skin.surface(0.26), fontSize: 14),
            filled: true,
            fillColor: skin.surface(0.04),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 16),

        // ── Karte: Dringend / Frist (+ Datum & Uhrzeit) ──
        GlassSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              GlassListItem(
                title: 'Dringend',
                switchValue: _isUrgent,
                switchActiveColor: const Color(0xFFEF5B5B),
                onSwitchChanged: (v) {
                  HapticFeedback.selectionClick();
                  _set(() => _isUrgent = v);
                },
                isLast: !_fristEnabled,
              ),
              GlassListItem(
                title: 'Frist',
                switchValue: _fristEnabled,
                onSwitchChanged: _setFristEnabled,
                isLast: !_fristEnabled,
              ),
              if (_fristEnabled)
                GlassListItem(
                  title: 'Datum & Uhrzeit',
                  isLast: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _InlinePillButton(
                        skin: skin,
                        label: _dueDate != null ? DateFormat('dd.MM.yyyy').format(_dueDate!) : 'Wählen',
                        onTap: _pickDate,
                      ),
                      const SizedBox(width: 8),
                      _InlinePillButton(
                        skin: skin,
                        label: (_dueDate != null && _hasTime)
                            ? TimeOfDay(hour: _dueDate!.hour, minute: _dueDate!.minute).format(context)
                            : '--:--',
                        onTap: _dueDate != null ? _pickTime : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Hinweisen — jetzt als Dropdown, eigene Kachel ──
        GlassSurface(
  padding: EdgeInsets.zero,
  child: GlassMultiDropdownButton<String>(
    // NEU: Ohne Frist bezieht sich der Hinweis auf den Erstellzeitpunkt
    // ("Hinweisen in X" = X nach jetzt), mit Frist ist es ein Vorlauf vor
    // dem Termin ("Hinweisen" = X vorher, siehe ReminderOption.label).
    label: _mode == ReminderMode.beforeDeadline ? 'Hinweisen' : 'Hinweisen in',
    values: _selectedReminderIds,
            items: quickOptions.map((o) => GlassDropdownItem(value: o.id, label: o.label)).toList(),
            maxSelectable: ReminderManager.maxSelectable,
            displaySummary: (vals) => vals.isEmpty ? 'Ohne' : '${vals.length} gewählt',
            isLast: true,
            maxPopupHeight: 280,
            onChanged: (ids) {
              for (final id in ids) {
                if (!_selectedReminderIds.contains(id)) ReminderManager.recordUsage(_mode, id);
              }
              _set(() => _selectedReminderIds = ids);
            },
          ),
        ),

        const SizedBox(height: 22),
        GlassPrimaryButton(
          skin: skin,
          label: widget.isReviewMode ? 'Übernehmen' : (_isEditing ? 'Speichern' : 'Hinzufügen'),
          icon: Icons.check_circle_outline,
          large: true,
          onTap: _save,
        ),
      ],
    );
  }

  void _save() {
    final title = widget.titleCtrl.text.trim();
    if (title.isEmpty) return;
    final task = widget.existingTask ??
        Task(id: DateTime.now().millisecondsSinceEpoch.toString(), title: title, createdAt: DateTime.now());
    task.title = title;
    task.dueDate = _dueDate;
    task.hasTime = _dueDate != null && _hasTime;
    task.notes = _notesCtrl.text.trim();
    task.isUrgent = _isUrgent;
    task.reminderOptionIds = List<String>.from(_selectedReminderIds);
    task.reminderTimes = _computeReminderTimes();
    widget.onSave(task);
  }

  List<DateTime> _computeReminderTimes() {
    final options = ReminderManager.optionsFor(_mode);
    final base = _mode == ReminderMode.beforeDeadline ? _dueDate! : DateTime.now();
    final times = <DateTime>[];
    for (final id in _selectedReminderIds) {
      final opt = options.firstWhere((o) => o.id == id, orElse: () => options.first);
      times.add(_mode == ReminderMode.beforeDeadline ? base.subtract(opt.duration) : base.add(opt.duration));
    }
    times.sort();
    return times;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// MINI INFO TILE — kompakte Datum/Zeit-Kachel, genutzt in Task- UND
// Event-Feldern (Start/Ende-Picker sehen optisch identisch aus).
// ─────────────────────────────────────────────────────────────────────────

class _MiniInfoTile extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;
  final String value;
  final bool active;

  const _MiniInfoTile({
    required this.skin,
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? skin.primary.withValues(alpha: skin.isLight ? 0.08 : 0.14)
                : (skin.isLight
                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                    : skin.bgCard.withValues(alpha: skin.glassOpacity)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? skin.primary.withValues(alpha: 0.32) : skin.glassBorder,
              width: active ? 1.3 : 1.0,
            ),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: active ? skin.primary : skin.surface(0.4)),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: active ? skin.primary : skin.surface(0.35),
                          letterSpacing: 1.0)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: active ? skin.textPrimary : skin.surface(0.32)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
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
// REMINDER MULTI-SELECT SHEET
//
// GlassDropdownButton ist Single-Select — für "bis zu 3 Hinweise" brauchen
// wir ein eigenes kleines Bottom-Sheet mit Checkbox-artigen Zeilen. Wird
// von Task- UND Event-Feldern gleich genutzt, damit sich beides identisch
// anfühlt (dein Wunsch: "exakt dieselbe Funktion/Aufbau übernehmen").
// ─────────────────────────────────────────────────────────────────────────

Future<void> showReminderMultiSelect({
  required BuildContext context,
  required AppSkin skin,
  required List<ReminderOption> options,
  required List<String> selectedIds,
  required int maxSelectable,
  required void Function(List<String>) onChanged,
}) async {
  var working = List<String>.from(selectedIds);
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSheet) => GlassSheet(
        skin: skin,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: SheetHandle(skin: skin)),
              const SizedBox(height: 16),
              Text('Hinweisen', style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Bis zu $maxSelectable auswählen',
                  style: TextStyle(color: skin.textMuted, fontSize: 12)),
              const SizedBox(height: 14),
              GlassSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    GlassListItem(
                      title: 'Ohne',
                      trailing: working.isEmpty
                          ? Icon(Icons.check_rounded, size: 18, color: skin.primary)
                          : null,
                      onTap: () => setSheet(() => working.clear()),
                    ),
                    ...options.asMap().entries.map((entry) {
                      final o = entry.value;
                      final isLast = entry.key == options.length - 1;
                      final selected = working.contains(o.id);
                      return GlassListItem(
                        title: o.label,
                        isLast: isLast,
                        trailing: selected ? Icon(Icons.check_rounded, size: 18, color: skin.primary) : null,
                        onTap: () {
                          setSheet(() {
                            if (selected) {
                              working.remove(o.id);
                            } else if (working.length < maxSelectable) {
                              working.add(o.id);
                            } else {
                              HapticFeedback.heavyImpact();
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassPrimaryButton(
                skin: skin,
                label: 'Übernehmen',
                onTap: () {
                  onChanged(working);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────
// EVENT FIELDS
// ─────────────────────────────────────────────────────────────────────────

class _EventFields extends StatefulWidget {
  final AppSkin skin;
  final EntryDraft draft;
  final CalendarEvent? existingEvent;
  final DateTime? initialDate;
  final TextEditingController titleCtrl;
  final void Function(List<CalendarEvent> events) onSave;

  const _EventFields({
    required this.skin,
    required this.draft,
    required this.existingEvent,
    required this.initialDate,
    required this.titleCtrl,
    required this.onSave,
  });

  @override
  State<_EventFields> createState() => _EventFieldsState();
}

class _EventFieldsState extends State<_EventFields> {
  late TextEditingController _locationCtrl;
  late TextEditingController _notesCtrl;
  bool _allDay = false;
  late DateTime _start;
  late DateTime _end;
  DateTime? _preAllDayStart;
  DateTime? _preAllDayEnd;
  // NEU: Reihenfolge einmalig fixiert — nicht bei jeder Auswahl neu sortiert.
  late final List<ReminderOption> _quickOptions;
  RepeatRule _repeat = RepeatRule.none;
  List<String> _groupKeys = [EventGroupStore.defaultGroup().key];
  List<String> _selectedReminderIds = [];

  bool get _isEditing => widget.existingEvent != null;

  bool get _isForeignOwnedSync {
    final ev = widget.existingEvent;
    if (ev == null) return false;
    final owner = SyncService.instance.ownerOf('calendar_events', ev.id);
    final myRole = SyncTokenService.role;
    if (owner == null || myRole == null) return false;
    return owner != myRole;
  }

  Set<String> get _lockedGroupKeys {
    if (!_isForeignOwnedSync) return {};
    return _groupKeys.where((k) {
      try { return EventGroupStore.byKey(k).isSync; } catch (_) { return false; }
    }).toSet();
  }

  @override
  void initState() {
    super.initState();
    _locationCtrl = TextEditingController(text: widget.existingEvent?.location ?? widget.draft.location);
    _notesCtrl = TextEditingController(text: widget.existingEvent?.notes ?? widget.draft.eventNotes);

    if (widget.existingEvent != null) {
      final e = widget.existingEvent!;
      _start = e.start;
      _end = e.end;
      _allDay = e.allDay;
      _repeat = e.repeat;
      _groupKeys = List<String>.from(e.groupKeys);
      _selectedReminderIds = List<String>.from(e.reminderOptionIds);
    } else if (widget.draft.start != null && widget.draft.end != null) {
      _start = widget.draft.start!;
      _end = widget.draft.end!;
      _allDay = widget.draft.allDay;
      _repeat = widget.draft.repeat;
      _groupKeys = List<String>.from(widget.draft.groupKeys);
      _selectedReminderIds = List<String>.from(widget.draft.eventReminderIds);
    } else {
      // NEU: Uhrzeit an aktuelle Zeit orientieren statt Mitternacht/12 Uhr.
      final selectedDate = widget.initialDate ?? DateTime.now();
      _start = _roundedTimeOnDay(selectedDate);
      _end = _start.add(const Duration(hours: 1));
    }

    _locationCtrl.addListener(_syncDraft);
    _notesCtrl.addListener(_syncDraft);
    _quickOptions = ReminderManager.getSorted(ReminderMode.beforeDeadline);
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _syncDraft() {
    if (_isEditing) return;
    widget.draft.location = _locationCtrl.text;
    widget.draft.allDay = _allDay;
    widget.draft.start = _start;
    widget.draft.end = _end;
    widget.draft.repeat = _repeat;
    widget.draft.groupKeys = List<String>.from(_groupKeys);
    widget.draft.eventNotes = _notesCtrl.text;
    widget.draft.eventReminderIds = List<String>.from(_selectedReminderIds);
  }

  void _set(VoidCallback fn) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(fn);
    _syncDraft();
  }

  /// NEU (Punkt 3): Verhindert, dass Ende vor/gleich Beginn liegt, wenn
  /// der Nutzer den START ändert. Statt (wie bisher) einfach auf den
  /// nächsten Tag zu springen und dabei die alte alte Uhrzeit stur
  /// beizubehalten, wird Ende jetzt intelligent auf Start + 1h gesetzt —
  /// UND bleibt dabei am selben Tag wie Start. Würde Start + 1h über
  /// Mitternacht hinausgehen, wird Ende stattdessen auf 23:59 desselben
  /// Tages gedeckelt (kein Tageswechsel mehr nötig).
  void _correctEndIfBeforeStart() {
    if (!_end.isAfter(_start)) {
      final sameDayCap = DateTime(_start.year, _start.month, _start.day, 23, 59);
      final proposedEnd = _start.add(const Duration(hours: 1));
      _end = proposedEnd.isAfter(sameDayCap) ? sameDayCap : proposedEnd;
    }
  }

  Future<void> _pickStartDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final result = await showSingleDatePicker(context: context, skin: widget.skin, initialDate: _start);
    FocusManager.instance.primaryFocus?.unfocus();
    if (result == null) return;
    _set(() {
      _start = DateTime(result.year, result.month, result.day, _start.hour, _start.minute);
      _correctEndIfBeforeStart();
    });
  }

  Future<void> _pickEndDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showSingleDatePicker(context: context, skin: widget.skin, initialDate: _end);
    FocusManager.instance.primaryFocus?.unfocus();
    if (result == null) return;
    _set(() => _end = DateTime(result.year, result.month, result.day, _end.hour, _end.minute));
  }

  Future<void> _pickStartTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute),
        skin: widget.skin,
        minuteInterval: 5,
        onTimeSelected: (t) => _set(() {
          _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
          _correctEndIfBeforeStart();
        }),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _pickEndTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: _end.hour, minute: _end.minute),
        skin: widget.skin,
        minuteInterval: 5,
        onTimeSelected: (t) => _set(() => _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute)),
      ),
    );
  }

  Future<void> _pickAllDayStartDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final result = await showSingleDatePicker(context: context, skin: widget.skin, initialDate: _start);
    if (result == null) return;
    _set(() {
      _start = DateTime(result.year, result.month, result.day);
      // NEU: Ende folgt automatisch auf denselben Tag wie der neue Start —
      // der Nutzer kann Ende danach eigenständig weiter nach hinten setzen,
      // um einen mehrtägigen Zeitraum aufzuspannen.
      _end = _start.add(const Duration(days: 1));
    });
  }

  Future<void> _pickAllDayEndDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final result = await showSingleDatePicker(
      context: context,
      skin: widget.skin,
      initialDate: _end.subtract(const Duration(days: 1)),
      minimumDate: _start,
    );
    if (result == null) return;
    _set(() {
      final endDay = DateTime(result.year, result.month, result.day);
      _end = endDay.add(const Duration(days: 1)); // exklusives Ende
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final quickOptions = _quickOptions;
    final groups = EventGroupStore.loadSelectable();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _locationCtrl,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: skin.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Standort',
            hintStyle: TextStyle(color: skin.surface(0.28), fontSize: 14.5),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 14),
        Container(height: 0.6, color: skin.surface(0.10)),
        const SizedBox(height: 16),

        // ── Karte: Ganztägig / Beginn / Ende ──
        GlassSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              GlassListItem(
                title: 'Ganztägig',
                switchValue: _allDay,
                onSwitchChanged: (v) {
                  HapticFeedback.selectionClick();
                  _set(() {
                    _allDay = v;
                    if (v) {
                      // Vor dem Umschalten die bisherige Uhrzeit merken, damit
                      // sie beim Zurückschalten exakt wiederhergestellt wird.
                      _preAllDayStart = _start;
                      _preAllDayEnd = _end;
                      final day = DateTime(_start.year, _start.month, _start.day);
                      _start = day;
                      _end = day.add(const Duration(days: 1));
                    } else if (_preAllDayStart != null && _preAllDayEnd != null) {
                      _start = _preAllDayStart!;
                      _end = _preAllDayEnd!;
                    } else if (_end.isAtSameMomentAs(_start)) {
                      _end = _start.add(const Duration(hours: 1));
                    }
                  });
                },
                isLast: _allDay,
              ),
              if (_allDay) ...[
                GlassListItem(
                  title: 'Beginn',
                  trailing: _InlinePillButton(
                    skin: skin,
                    label: DateFormat('dd.MM.yyyy').format(_start),
                    onTap: _pickAllDayStartDate,
                  ),
                ),
                GlassListItem(
                  title: 'Ende',
                  isLast: true,
                  trailing: _InlinePillButton(
                    skin: skin,
                    label: DateFormat('dd.MM.yyyy').format(_end.subtract(const Duration(days: 1))),
                    onTap: _pickAllDayEndDate,
                  ),
                ),
              ] else ...[
                GlassListItem(
                  title: 'Beginn',
                  isLast: false,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _InlinePillButton(skin: skin, label: DateFormat('dd.MM.yyyy').format(_start), onTap: _pickStartDate),
                      const SizedBox(width: 8),
                      _InlinePillButton(
                        skin: skin,
                        label: TimeOfDay(hour: _start.hour, minute: _start.minute).format(context),
                        onTap: _pickStartTime,
                      ),
                    ],
                  ),
                ),
                GlassListItem(
                  title: 'Ende',
                  isLast: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _InlinePillButton(skin: skin, label: DateFormat('dd.MM.yyyy').format(_end), onTap: _pickEndDate),
                      const SizedBox(width: 8),
                      _InlinePillButton(
                        skin: skin,
                        label: TimeOfDay(hour: _end.hour, minute: _end.minute).format(context),
                        onTap: _pickEndTime,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Wiederholen — eigene Kachel ──
        GlassSurface(
          padding: EdgeInsets.zero,
          child: GlassDropdownButton<RepeatRule>(
            value: _repeat,
            items: RepeatRule.values.map((r) => GlassDropdownItem(value: r, label: r.label)).toList(),
            onChanged: (v) => _set(() => _repeat = v),
            label: 'Wiederholen',
            displayBuilder: (v) => v.label,
            isLast: true,
          ),
        ),
        const SizedBox(height: 16),

        // ── Gruppen — bis zu 3 auswählbar ──
        GlassSurface(
          padding: EdgeInsets.zero,
          child: GlassMultiDropdownButton<String>(
            label: 'Gruppen',
            values: _groupKeys,
            items: groups.map((g) => GlassDropdownItem(value: g.key, label: g.name)).toList(),
            maxSelectable: 3,
            lockedValues: _lockedGroupKeys, // NEU siehe Punkt 11
            displaySummary: (vals) => vals.isEmpty ? 'Ohne' : vals.map((k) => EventGroupStore.byKey(k).name).join(' · '),
            isLast: true,
            onChanged: (ids) {
              // NEU: "Ohne" (leere Auswahl) ist jetzt erlaubt.
              _set(() => _groupKeys = ids);
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── Hinweisen — eigene Kachel, als Dropdown ──
        GlassSurface(
          padding: EdgeInsets.zero,
          child: GlassMultiDropdownButton<String>(
            label: 'Hinweisen',
            values: _selectedReminderIds,
            items: quickOptions.map((o) => GlassDropdownItem(value: o.id, label: o.label)).toList(),
            maxSelectable: ReminderManager.maxSelectable,
            displaySummary: (vals) => vals.isEmpty ? 'Ohne' : '${vals.length} gewählt',
            isLast: true,
            maxPopupHeight: 280,
            onChanged: (ids) {
              for (final id in ids) {
                if (!_selectedReminderIds.contains(id)) ReminderManager.recordUsage(ReminderMode.beforeDeadline, id);
              }
              _set(() => _selectedReminderIds = ids);
            },
          ),
        ),
        const SizedBox(height: 16),

        Text('Notizen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.textPrimary)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 8,
          minLines: 4,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: skin.textPrimary, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Notiz hinzufügen…',
            hintStyle: TextStyle(color: skin.surface(0.26), fontSize: 14),
            filled: true,
            fillColor: skin.surface(0.04),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(12),
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
      ],
    );
  }

  void _save() {
    final title = widget.titleCtrl.text.trim();
    if (title.isEmpty) return;

    if (_end.isBefore(_start)) {
      HapticFeedback.heavyImpact();
      showGlassSnackBar(context, 'Das Ende liegt vor dem Beginn.', type: GlassSnackBarType.warning);
      return;
    }

    // ─────────────────────────────────────────────────────────────────────
    // BUGFIX: Ganztägige Termine über mehrere Tage werden jetzt als EIN
    // einziges CalendarEvent mit start/end über den gesamten Zeitraum
    // gespeichert — nicht mehr als N separate Events mit je eigener id.
    //
    // Die frühere Aufsplittung war der Grund, warum Löschen oder
    // Bearbeiten nur den angeklickten Einzeltag traf: jeder Tag war
    // technisch ein komplett eigenständiges Ereignis ohne Verbindung zu
    // den anderen. occurrencesInRange() in calendar_event.dart berechnet
    // die sichtbaren Tage aus start/end ohnehin schon korrekt für ein
    // einzelnes mehrtägiges Event — die Aufsplittung war nie nötig.
    //
    // Jetzt verhalten sich ganztägige mehrtägige Termine exakt so wie
    // zeitbasierte mehrtägige Termine: Ein Event mit start/end über den
    // gesamten Zeitraum. Löschen/Bearbeiten wirkt automatisch auf den
    // gesamten Termin, weil es nur noch eine id gibt.
    // ─────────────────────────────────────────────────────────────────────

    final event = widget.existingEvent ??
        CalendarEvent(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          start: _start,
          end: _end,
          createdAt: DateTime.now(),
        );
    event.title = title;
    event.location = _locationCtrl.text.trim();
    event.start = _start;
    event.end = _end;
    event.allDay = _allDay;
    event.repeat = _repeat;
    event.groupKeys = _groupKeys;
    event.notes = _notesCtrl.text.trim();
    event.reminderOptionIds = List<String>.from(_selectedReminderIds);

    widget.onSave([event]);
  }
}