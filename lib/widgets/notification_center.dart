import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/sync_service.dart';
import '../services/sync_token_service.dart';
import '../services/calendar_sync_handshake.dart';
import '../screens/tasks_screen.dart' show TaskStore, Task;
import '../screens/settings_screen.dart' show SyncConflictsScreen;
import '../models/calendar_event.dart';
import '../services/event_group_store.dart';
import '../screens/calendar_view.dart' show ShiftLookup;
import '../services/notification_service.dart';
import '../services/reminder_manager.dart';
import '../widgets/glass_kit.dart';

// ─────────────────────────────────────────────────────────────────────────
// NEU (Punkt 3): Ein Task/Termin taucht im Notification-Center nur auf,
// wenn tatsächlich (mind.) eine echte iOS-Notification dafür fällig wäre —
// exakt dieselbe Logik wie NotificationService (garantierte Erinnerung +
// gewählte "Hinweisen"-Zeitpunkte). Rein "heute" reicht NICHT mehr aus.
// ─────────────────────────────────────────────────────────────────────────

bool _taskNotificationDue(Task t) {
  if (t.dueDate == null) return false;
  final now = DateTime.now();
  final guaranteedFireAt = t.hasTime
      ? t.dueDate!
      : DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day,
          NotificationService.dueTimeDefaultHour, 0);
  if (!now.isBefore(guaranteedFireAt)) return true;
  for (final rt in t.reminderTimes) {
    if (!now.isBefore(rt)) return true;
  }
  return false;
}

bool _eventNotificationDue(CalendarEvent e) {
  if (e.allDay) return false; // ganztägig läuft separat über den Banner
  final now = DateTime.now();
  if (!now.isBefore(e.start)) return true;
  final options = ReminderManager.optionsFor(ReminderMode.beforeDeadline);
  for (final id in e.reminderOptionIds) {
    final opt = options.firstWhere((o) => o.id == id, orElse: () => options.first);
    if (!now.isBefore(e.start.subtract(opt.duration))) return true;
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────
// STORE — verwaltet Gelesen/Ungelesen-Status & liefert die Badge-Zahl
// ─────────────────────────────────────────────────────────────────────────

class NotificationCenterStore {
  NotificationCenterStore._();
  static final NotificationCenterStore instance = NotificationCenterStore._();

  static const _seenKey = 'notif_seen_reminders';
  static const _dismissedSyncKey = 'notif_dismissed_sync_signature';
  static const _dismissedConflictsKey = 'notif_dismissed_conflict_ids';
  static const _hiddenKey = 'notif_hidden_ids'; // NEU (Punkt 6)

  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  Box get _box => Hive.box('einstellungen');

  Map<String, DateTime> _loadSeenMap() {
    final raw = _box.get(_seenKey);
    final map = <String, DateTime>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final dt = DateTime.tryParse(v.toString());
        if (dt != null) map[k.toString()] = dt;
      });
    }
    return map;
  }

  void _saveSeenMap(Map<String, DateTime> map) {
    _box.put(_seenKey, map.map((k, v) => MapEntry(k, v.toIso8601String())));
  }

  bool isReminderExpired(String id) {
    final seen = _loadSeenMap()[id];
    if (seen == null) return false;
    return DateTime.now().difference(seen) > const Duration(days: 1);
  }

  bool isReminderSeen(String id) => _loadSeenMap().containsKey(id);

  /// Wird beim Öffnen des Panels für jede sichtbare Erinnerung aufgerufen.
  void markReminderSeen(String id) {
    final map = _loadSeenMap();
    if (!map.containsKey(id)) {
      map[id] = DateTime.now();
      _saveSeenMap(map);
    }
  }

  /// Entfernt Einträge zu Aufgaben/Terminen, die es nicht mehr gibt.
  void pruneSeenMap(Set<String> stillExistingIds) {
    final map = _loadSeenMap();
    final before = map.length;
    map.removeWhere((id, _) => !stillExistingIds.contains(id));
    if (map.length != before) _saveSeenMap(map);
  }

  // ── NEU (Punkt 6): Ausblenden per Swipe, ohne den Eintrag zu löschen ────
  Set<String> _loadHiddenSet() {
    final raw = _box.get(_hiddenKey);
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return {};
  }

  bool isHidden(String id) => _loadHiddenSet().contains(id);

  void hideNotification(String id) {
    final set = _loadHiddenSet()..add(id);
    _box.put(_hiddenKey, set.toList());
    recompute();
  }

  String get _currentSyncSignature {
    final token = SyncTokenService.instance.localToken ?? '';
    final state = CalendarSyncHandshake.instance.state.value;
    return '$token::$state';
  }

  bool get isSyncRequestDismissed =>
      (_box.get(_dismissedSyncKey, defaultValue: '') as String) == _currentSyncSignature;

  void dismissSyncRequest() => _box.put(_dismissedSyncKey, _currentSyncSignature);

  Set<String> get _dismissedConflictIds {
    final raw = _box.get(_dismissedConflictsKey);
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return {};
  }

  bool isConflictDismissed(String docId) => _dismissedConflictIds.contains(docId);

  void dismissConflicts(Iterable<String> docIds) {
    final set = _dismissedConflictIds..addAll(docIds);
    _box.put(_dismissedConflictsKey, set.toList());
  }

  static const _pairingEndedDismissedKey = 'notif_pairing_ended_dismissed_ms';

  bool get isPairingEndedDismissed {
    final endedAt = CalendarSyncHandshake.instance.pairingEndedAt.value;
    if (endedAt == null) return true;
    final dismissedMs = _box.get(_pairingEndedDismissedKey, defaultValue: 0) as int;
    return endedAt.millisecondsSinceEpoch <= dismissedMs;
  }

  void dismissPairingEnded() {
    final endedAt = CalendarSyncHandshake.instance.pairingEndedAt.value;
    if (endedAt != null) _box.put(_pairingEndedDismissedKey, endedAt.millisecondsSinceEpoch);
  }

  /// Badge-Zahl neu berechnen — nach jeder relevanten Änderung aufrufen.
  void recompute() {
    int count = 0;
    final role = SyncTokenService.role;

    final token = SyncTokenService.instance.localToken;
    final syncState = CalendarSyncHandshake.instance.state.value;
    if (role == 'original' &&
        token != null &&
        syncState == CalendarSyncState.waitingForApproval &&
        !isSyncRequestDismissed) {
      count += 1;
    }

    if (role == 'original') {
      final dismissed = _dismissedConflictIds;
      count += SyncService.instance
          .listPendingConflicts()
          .where((c) => !dismissed.contains(c.docId))
          .length;
      count += SyncService.instance.loadGroupCollisionHints().length; // NEU
    }

    if (!isPairingEndedDismissed) count += 1;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final seenMap = _loadSeenMap();

    final hidden = _loadHiddenSet(); // NEU (Punkt 6)
    for (final t in TaskStore.loadAll()) {
      if (t.done || t.dueDate == null) continue;
      if (t.dueDate!.isBefore(todayStart) || !t.dueDate!.isBefore(todayEnd)) continue;
      if (hidden.contains('task_${t.id}')) continue;
      if (!_taskNotificationDue(t)) continue; // NEU (Punkt 3)
      if (!seenMap.containsKey('task_${t.id}')) count++;
    }
    final todaysEvents = CalendarEventStore.occurrencesInRange(
        CalendarEventStore.loadAll(), todayStart, todayEnd);
    for (final e in todaysEvents) {
      final key = 'event_${e.id}';
      if (hidden.contains(key)) continue;
      if (!e.allDay && !_eventNotificationDue(e)) continue; // NEU (Punkt 3)
      if (!seenMap.containsKey(key)) count++;
    }

    unreadCount.value = count;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// GLOCKE + BADGE (Trigger)
// ─────────────────────────────────────────────────────────────────────────

class NotificationBellButton extends StatefulWidget {
  final VoidCallback onNavigateToTasksList;
  final VoidCallback onNavigateToCalendar;
  final VoidCallback onOpenSyncConflicts;
  final VoidCallback onOpenCalendarSyncSettings;
  final VoidCallback? onBeforeOpen;

  const NotificationBellButton({
    super.key,
    required this.onNavigateToTasksList,
    required this.onNavigateToCalendar,
    required this.onOpenSyncConflicts,
    required this.onOpenCalendarSyncSettings,
    this.onBeforeOpen,
  });

  @override
  State<NotificationBellButton> createState() => NotificationBellButtonState();
}

class NotificationBellButtonState extends State<NotificationBellButton>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  final _triggerKey = GlobalKey();
  bool _open = false;
  late AnimationController _animCtrl;
  Timer? _dueCheckTimer; // NEU (Punkt 3)

  final _store = NotificationCenterStore.instance;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    TaskStore.changesSignal.addListener(_recompute);
    CalendarEventStore.changesSignal.addListener(_recompute);
    SyncService.instance.pendingConflictsCount.addListener(_recompute);
    CalendarSyncHandshake.instance.state.addListener(_recompute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
    // NEU (Punkt 3): Damit ein Eintrag genau dann erscheint, wenn seine
    // Zeit erreicht ist (z.B. 18-Uhr-Termin), auch ohne dass zwischendurch
    // Tasks/Termine geändert werden.
    _dueCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) => _recompute());
  }

  void _recompute() => _store.recompute();

  @override
  void dispose() {
    TaskStore.changesSignal.removeListener(_recompute);
    CalendarEventStore.changesSignal.removeListener(_recompute);
    SyncService.instance.pendingConflictsCount.removeListener(_recompute);
    CalendarSyncHandshake.instance.state.removeListener(_recompute);
    _dueCheckTimer?.cancel();
    _removeOverlay();
    _animCtrl.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _close() async {
    await _animCtrl.reverse();
    _removeOverlay();
    if (mounted) setState(() => _open = false);
  }

  /// Öffentlich, damit z.B. das Hamburger-Menü diese Overlay vor dem
  /// eigenen Öffnen schließen kann — es darf immer nur eins offen sein.
  void closeOverlay() {
    if (_open) _close();
  }

  void _openOverlay() {
    widget.onBeforeOpen?.call();
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context);
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screenWidth = MediaQuery.of(context).size.width;

    final popupWidth = math.min(340.0, screenWidth - 24.0);
    double popupRight = screenWidth - (offset.dx + size.width);
    if (popupRight < 12) popupRight = 12;
    final maxRight = screenWidth - popupWidth - 12;
    if (popupRight > maxRight) popupRight = maxRight.clamp(12.0, screenWidth);
    final popupTop = offset.dy + size.height + 6;

    _animCtrl.value = 0;
    setState(() => _open = true);

    _overlayEntry = OverlayEntry(
      builder: (_) => _NotificationsOverlay(
        animCtrl: _animCtrl,
        right: popupRight,
        top: popupTop,
        width: popupWidth,
        onDismiss: _close,
        onNavigateToTasksList: () { _close(); widget.onNavigateToTasksList(); },
        onNavigateToCalendar: () { _close(); widget.onNavigateToCalendar(); },
        onOpenSyncConflicts: () { _close(); widget.onOpenSyncConflicts(); },
        onOpenCalendarSyncSettings: () { _close(); widget.onOpenCalendarSyncSettings(); },
      ),
    );
    overlay.insert(_overlayEntry!);
    _animCtrl.forward();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    _open ? _close() : _openOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return GestureDetector(
      key: _triggerKey,
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: ValueListenableBuilder<int>(
            valueListenable: _store.unreadCount,
            builder: (context, badgeCount, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    badgeCount > 0 ? Icons.notifications_rounded : Icons.notifications_outlined,
                    color: skin.textPrimary,
                    size: 22,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -4,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF5B5B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: skin.bgBase, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// OVERLAY-CONTAINER — wächst aus der Glocke heraus, rechtsbündig verankert
// ─────────────────────────────────────────────────────────────────────────

class _NotificationsOverlay extends StatelessWidget {
  final AnimationController animCtrl;
  final double right, top, width;
  final VoidCallback onDismiss;
  final VoidCallback onNavigateToTasksList;
  final VoidCallback onNavigateToCalendar;
  final VoidCallback onOpenSyncConflicts;
  final VoidCallback onOpenCalendarSyncSettings;

  const _NotificationsOverlay({
    required this.animCtrl,
    required this.right,
    required this.top,
    required this.width,
    required this.onDismiss,
    required this.onNavigateToTasksList,
    required this.onNavigateToCalendar,
    required this.onOpenSyncConflicts,
    required this.onOpenCalendarSyncSettings,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final scaleAnim = CurvedAnimation(parent: animCtrl, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    final fadeAnim = CurvedAnimation(parent: animCtrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = (screenHeight * 0.6).clamp(320.0, 520.0);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: animCtrl,
              builder: (_, __) => Container(
                color: Colors.black.withValues(alpha: 0.45 * animCtrl.value.clamp(0.0, 1.0)),
              ),
            ),
          ),
        ),
        Positioned(
          right: right,
          top: top,
          child: AnimatedBuilder(
            animation: animCtrl,
            builder: (_, child) => Transform.scale(
              scale: 0.85 + scaleAnim.value * 0.15,
              alignment: Alignment.topRight,
              child: Opacity(opacity: fadeAnim.value.clamp(0.0, 1.0), child: child),
            ),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Container(
                      width: width,
                      decoration: BoxDecoration(
                        color: skin.isLight
                            ? Colors.white.withValues(alpha: 0.92)
                            : const Color(0xFF2A2A2E).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: skin.isLight ? Colors.white.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 32, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: _NotificationsPanel(
                        onNavigateToTasksList: onNavigateToTasksList,
                        onNavigateToCalendar: onNavigateToCalendar,
                        onOpenSyncConflicts: onOpenSyncConflicts,
                        onOpenCalendarSyncSettings: onOpenCalendarSyncSettings,
                      ),
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

// ─────────────────────────────────────────────────────────────────────────
// PANEL-INHALT
// ─────────────────────────────────────────────────────────────────────────

class _NotificationsPanel extends StatefulWidget {
  final VoidCallback onNavigateToTasksList;
  final VoidCallback onNavigateToCalendar;
  final VoidCallback onOpenSyncConflicts;
  final VoidCallback onOpenCalendarSyncSettings;

  const _NotificationsPanel({
    required this.onNavigateToTasksList,
    required this.onNavigateToCalendar,
    required this.onOpenSyncConflicts,
    required this.onOpenCalendarSyncSettings,
  });

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  final _store = NotificationCenterStore.instance;

  @override
  void initState() {
    super.initState();
    TaskStore.changesSignal.addListener(_refresh);
    CalendarEventStore.changesSignal.addListener(_refresh);
    SyncService.instance.pendingConflictsCount.addListener(_refresh);
    CalendarSyncHandshake.instance.state.addListener(_refresh);

    // Beim Öffnen: alle aktuell sichtbaren Erinnerungen als "gesehen"
    // markieren → 24h später verschwinden sie automatisch aus der Liste.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final t in _todayDueTasks()) {
        _store.markReminderSeen('task_${t.id}');
      }
      for (final e in _todayCalendarEvents()) {
        _store.markReminderSeen('event_${e.id}');
      }
      _store.recompute();
    });
  }

  @override
  void dispose() {
    TaskStore.changesSignal.removeListener(_refresh);
    CalendarEventStore.changesSignal.removeListener(_refresh);
    SyncService.instance.pendingConflictsCount.removeListener(_refresh);
    CalendarSyncHandshake.instance.state.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ── Systembenachrichtigungen ─────────────────────────────────────────

  void _showGroupCollisionHints(BuildContext context, List<Map<String, dynamic>> initialHints) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final hints = SyncService.instance.loadGroupCollisionHints();
            final skin = AppTheme.of(dialogContext);
            return AlertDialog(
              backgroundColor: skin.isLight ? Colors.white : const Color(0xFF2A2A2E),
              title: Text('Gruppen-Zuordnung', style: TextStyle(color: skin.textPrimary, fontSize: 16)),
              content: SizedBox(
                width: double.maxFinite,
                child: hints.isEmpty
                    ? Text('Keine offenen Hinweise mehr.', style: TextStyle(color: skin.textMuted))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: hints.map((h) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Gruppe "${h['groupName']}" wurde neu angelegt (Kollision mit lokaler Gruppe). '
                                    'Bereits synchronisierte Termine dieser Gruppe können vorübergehend noch in der alten lokalen Gruppe erscheinen.',
                                    style: TextStyle(fontSize: 12.5, color: skin.textPrimary, height: 1.35),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    SyncService.instance.dismissGroupCollisionHint(h['id'] as String);
                                    setDialogState(() {});
                                    _store.recompute();
                                    if (mounted) setState(() {});
                                  },
                                  child: const Text('Verstanden'),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Schließen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _buildAnfragen(AppSkin skin) {
    final items = <Widget>[];
    final role = SyncTokenService.role;
    final token = SyncTokenService.instance.localToken;
    final syncState = CalendarSyncHandshake.instance.state.value;

    if (role == 'original' &&
        token != null &&
        syncState == CalendarSyncState.waitingForApproval &&
        !_store.isSyncRequestDismissed) {
      items.add(_NavigationCard(
        skin: skin,
        icon: Icons.sync_rounded,
        color: const Color(0xFF3DD6C8),
        title: 'Kalender-Sync-Anfrage',
        subtitle: 'Lesemodus-Gerät möchte Kalender teilen — in Einstellungen bestätigen',
        onTap: () {
          _store.dismissSyncRequest();
          _store.recompute();
          widget.onOpenCalendarSyncSettings();
        },
      ));
    }

    if (role == 'original') {
      final allConflicts = SyncService.instance.listPendingConflicts();
      final open = allConflicts.where((c) => !_store.isConflictDismissed(c.docId)).toList();
      if (open.isNotEmpty) {
        items.add(_NavigationCard(
          skin: skin,
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFFFB347),
          title: 'Sync-Konflikte',
          subtitle: '${open.length} offene Änderung(en) vom Kopiergerät',
          onTap: () {
            _store.dismissConflicts(open.map((c) => c.docId));
            _store.recompute();
            widget.onOpenSyncConflicts();
          },
        ));
      }
    }

    if (role == 'original') {
      final hints = SyncService.instance.loadGroupCollisionHints();
      if (hints.isNotEmpty) {
        items.add(_NavigationCard(
          skin: skin,
          icon: Icons.rule_folder_outlined,
          color: const Color(0xFF8B5CF6),
          title: 'Gruppen-Zuordnung prüfen',
          subtitle: hints.length == 1
              ? 'Eine synchronisierte Gruppe wurde neu angelegt — Termine prüfen'
              : '${hints.length} synchronisierte Gruppen wurden neu angelegt — Termine prüfen',
          onTap: () => _showGroupCollisionHints(context, hints),
        ));
      }
    }

    if (!_store.isPairingEndedDismissed) {
      items.add(_NavigationCard(
        skin: skin,
        icon: Icons.link_off_rounded,
        color: skin.deleteColor,
        title: 'Kalender-Sync beendet',
        subtitle: 'Die Verbindung wurde getrennt.',
        onTap: () {
          _store.dismissPairingEnded();
          _store.recompute();
        },
      ));
    }

    return items;
  }

  // ── Erinnerungen ─────────────────────────────────────────────────────

  /// NEU: Nur noch das, was HEUTE fällig ist — keine Vorschau auf die
  /// kommenden Tage mehr, das gibt es ja bereits in den jeweiligen
  /// Funktionen (Aufgaben-/Kalender-Screen).
  List<Task> _todayDueTasks() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final result = TaskStore.loadAll().where((t) {
      if (t.done || t.dueDate == null) return false;
      if (_store.isHidden('task_${t.id}')) return false; // NEU (Punkt 6)
      if (!(!t.dueDate!.isBefore(todayStart) && t.dueDate!.isBefore(todayEnd))) return false;
      return _taskNotificationDue(t); // NEU (Punkt 3)
    }).toList();
    result.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return result;
  }

  List<CalendarEvent> _todayCalendarEvents() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final all = CalendarEventStore.loadAll();
    final occ = CalendarEventStore.occurrencesInRange(all, todayStart, todayEnd)
        .where((e) => !_store.isHidden('event_${e.id}')) // NEU (Punkt 6)
        .where((e) => e.allDay || _eventNotificationDue(e)) // NEU (Punkt 3)
        .toList();
    occ.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });
    return occ;
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final anfragen = _buildAnfragen(skin);
    final calendarToday = _todayCalendarEvents();

    // NEU: Einstellung aus "Benachrichtigungen" → "Benachrichtigungscenter".
    // Standard AN. Bei AUS laufen ganztägige Termine als normale Einträge
    // unten im Kalender-Block mit, statt als eigener Balken oben.
    final showAllDayBanner = Hive.box('einstellungen')
        .get('notif_center_show_allday_banner', defaultValue: true) as bool;

    final allDayRaw = calendarToday.where((e) => e.allDay).toList();
    final timedRaw = calendarToday.where((e) => !e.allDay).toList();

    final bannerEvents = showAllDayBanner ? allDayRaw : <CalendarEvent>[];
    final listEvents = showAllDayBanner
        ? timedRaw
        : ([...timedRaw, ...allDayRaw]
          ..sort((a, b) {
            if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
            return a.start.compareTo(b.start);
          }));

    final tasksToday = _todayDueTasks();

    // NEU (Punkt 1): der Balken für ganztägige Termine zählt NICHT als
    // "Benachrichtigung" — sind nur Banner da, gilt das Panel als leer.
    final isTotallyEmpty = anfragen.isEmpty && listEvents.isEmpty && tasksToday.isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Row(
            children: [
              Icon(Icons.notifications_rounded, size: 18, color: skin.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Benachrichtigungen',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary)),
              ),
              const _TodayShiftBadge(),
            ],
          ),
        ),
        Divider(height: 0.5, color: skin.glassBorder),
        if (bannerEvents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: _AllDayBannerStrip(skin: skin, events: bannerEvents),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Container(height: 0.6, color: skin.surface(0.12)),
          ),
        ],
        if (isTotallyEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
            child: Center(
              child: Text('Keine neuen Benachrichtigungen',
                  style: TextStyle(fontSize: 13, color: skin.textMuted, fontWeight: FontWeight.w500)),
            ),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (anfragen.isNotEmpty) ...[
                    _SectionLabel(label: 'SYSTEM', icon: Icons.shield_outlined, skin: skin),
                    const SizedBox(height: 8),
                    ...anfragen.map((w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w)),
                    const SizedBox(height: 14),
                  ],
                  if (listEvents.isNotEmpty) ...[
                    _SectionLabel(label: 'KALENDER', icon: Icons.event_note_rounded, skin: skin),
                    const SizedBox(height: 8),
                    _CalendarStripBlock(
                      skin: skin,
                      events: listEvents,
                      onHideEvent: (e) {
                        _store.hideNotification('event_${e.id}');
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (tasksToday.isNotEmpty) ...[
                    _SectionLabel(label: 'AUFGABEN', icon: Icons.task_alt_rounded, skin: skin),
                    const SizedBox(height: 8),
                    ...tasksToday.map((t) => _TaskTodayRow(
                          skin: skin,
                          task: t,
                          onHide: () {
                            _store.hideNotification('task_${t.id}');
                            setState(() {});
                          },
                        )),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// NEU: Dienst-Badge für heute, im Notification-Overlay-Header rechts
/// neben der Überschrift — dieselbe schmale blaue Kachel wie im Kalender.
class _TodayShiftBadge extends StatelessWidget {
  const _TodayShiftBadge();

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final code = ShiftLookup.codeForDay(DateTime.now());
    if (code == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: skin.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: skin.primary.withValues(alpha: 0.35)),
      ),
      child: Text(code, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: skin.primary)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final AppSkin skin;
  const _SectionLabel({required this.label, required this.icon, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: skin.primary),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 0.8)),
      ],
    );
  }
}

/// NEU: Kalender-Einträge des heutigen Tages als schmaler, Outlook-artiger
/// Balken — jeder Eintrag mit dezentem Farbstrich der zugehörigen Gruppe.
class _CalendarStripBlock extends StatelessWidget {
  final AppSkin skin;
  final List<CalendarEvent> events;
  final void Function(CalendarEvent) onHideEvent; // NEU (Punkt 6)
  const _CalendarStripBlock({required this.skin, required this.events, required this.onHideEvent});

  String _timeLabel(CalendarEvent e) =>
      e.allDay ? 'Ganztägig' : DateFormat('HH:mm').format(e.start);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: skin.surface(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: skin.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: events.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final isLast = i == events.length - 1;
            Color groupColor;
            try {
              groupColor = e.groupKeys.isEmpty
                  ? skin.surface(0.3)
                  : EventGroupStore.byKey(e.groupKeys.first).color;
            } catch (_) {
              groupColor = skin.surface(0.3);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassSwipeCard(
                  height: 34,
                  onDelete: () {},
                  animateDelete: true,
                  onDeleteAnimationDone: () => onHideEvent(e),
                  deleteLabel: 'Archivieren',
                  deleteIcon: Icons.archive_outlined,
                  deleteColorOverride: const Color(0xFF8B5CF6),
                  rightRevealWidth: 76,
                  triggerDeleteOnDragThrough: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: groupColor.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: skin.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        Text(_timeLabel(e), style: TextStyle(fontSize: 11, color: skin.textMuted)),
                      ],
                    ),
                  ),
                ),
                if (!isLast) Divider(height: 0.5, color: skin.glassBorder, indent: 10, endIndent: 10),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Schmaler, edge-to-edge Balken für ganztägige Termine — bewusst OHNE
/// eigene "Kalender"-Überschrift, wird direkt unter dem Panel-Header
/// eingeblendet (siehe _NotificationsPanel).
class _AllDayBannerStrip extends StatelessWidget {
  final AppSkin skin;
  final List<CalendarEvent> events;
  const _AllDayBannerStrip({required this.skin, required this.events});

  Color _colorFor(CalendarEvent e) {
    try {
      return e.groupKeys.isEmpty
          ? skin.primary
          : EventGroupStore.byKey(e.groupKeys.first).color;
    } catch (_) {
      return skin.primary;
    }
  }

  // NEU: jede Kachel bekommt jetzt ihre eigenen abgerundeten Ecken statt
  // Teil eines gemeinsam geclippten Blocks mit Trennstrich zu sein — löst
  // nebenbei das Problem, dass der graue Strich nie exakt kachelbreit war,
  // weil jetzt kein gemeinsamer Strich mehr existiert, nur noch Abstand.
  Widget _tile(CalendarEvent e) {
    final groupColor = _colorFor(e);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: groupColor.withValues(alpha: skin.isLight ? 0.16 : 0.24),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, size: 13, color: groupColor),
          const SizedBox(width: 7),
          Expanded(
            child: Text(e.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: groupColor)),
          ),
          if (e.repeat != RepeatRule.none) ...[
            const SizedBox(width: 6),
            Icon(Icons.repeat_rounded, size: 12, color: groupColor.withValues(alpha: 0.7)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // NEU: bis zu 2 ganztägige Termine pro Zeile (kompakter bei mehreren
    // Einträgen). Bei ungerader Gesamtzahl bleibt der jeweils LETZTE
    // Eintrag über die volle Breite — so wird nie eine halbleere Kachel
    // erzeugt, sondern die "übrig bleibende" Kachel ist immer die unterste.
    final rows = <Widget>[];
    for (var i = 0; i < events.length; i += 2) {
      final isLastOdd = i == events.length - 1;
      if (isLastOdd) {
        rows.add(_tile(events[i]));
      } else {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _tile(events[i])),
            const SizedBox(width: 6),
            Expanded(child: _tile(events[i + 1])),
          ],
        ));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1) const SizedBox(height: 5),
        ],
      ],
    );
  }
}

/// NEU: heute fällige Aufgabe — kein Icon mehr, nur Titel links, Zeit rechts.
class _TaskTodayRow extends StatelessWidget {
  final AppSkin skin;
  final Task task;
  final VoidCallback onHide;
  const _TaskTodayRow({required this.skin, required this.task, required this.onHide});

  @override
  Widget build(BuildContext context) {
    final timeLabel = task.hasTime && task.dueDate != null
        ? DateFormat('HH:mm').format(task.dueDate!)
        : '';
    return GlassSwipeCard(
      height: 34,
      onDelete: () {},
      animateDelete: true,
      onDeleteAnimationDone: onHide,
      deleteLabel: 'Archivieren',
      deleteIcon: Icons.archive_outlined,
      deleteColorOverride: const Color(0xFF8B5CF6),
      rightRevealWidth: 76,
      triggerDeleteOnDragThrough: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(task.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: skin.textPrimary)),
            ),
            if (timeLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(timeLabel, style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String acceptLabel;
  final String declineLabel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCardTap;

  const _RequestCard({
    required this.skin,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.acceptLabel,
    required this.declineLabel,
    required this.onAccept,
    required this.onDecline,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCardTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary))),
              Icon(Icons.chevron_right_rounded, size: 16, color: skin.surface(0.3)),
            ]),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11.5, color: skin.textMuted, height: 1.35)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: onDecline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: skin.surface(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: skin.borderSubtle),
                    ),
                    child: Center(child: Text(declineLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.textMuted))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Center(child: Text(acceptLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavigationCard({
    required this.skin,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.3)),
          ],
        ),
      ),
    );
  }
}