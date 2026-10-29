import 'dart:convert';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/relationship_style.dart';
import '../models/notification_phrases.dart'
    show WeatherCategory, categoryFor, eventReminderTitle, eventReminderBody;
import 'weather_service.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import '../models/calendar_event.dart' show CalendarEventStore;
import 'package:flutter_timezone/flutter_timezone.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION SERVICE
//
// 1) BADGE: _refreshBadge() setzt das App-Icon-Badge auf die Zahl überfälliger,
//    offener Aufgaben (nur iOS).
// 2) TEXTE: stilabhängig über RelationshipTexts (relationship_style.dart).
// 3) TAGESVORSCHAU: plant die nächsten 7 Tage einzeln (Morgen + optional
//    Vorabend), jeweils mit dem Inhalt des Tages, an dem sie feuert.
// 4) DRINGEND: genau eine Erinnerung 24 h nach der Markierung.
//
// IDs: stabiler FNV-1a-Hash statt String.hashCode (der ist über Dart-Versionen
// nicht garantiert stabil → nach Updates ließen sich alte Erinnerungen nicht
// mehr abbrechen → Mehrfach-Benachrichtigungen). Eigene, weit getrennte
// Nummernräume pro Typ.
// ─────────────────────────────────────────────────────────────────────────────

/// Android: ohne diese Details wirft das Plugin beim Anzeigen/Planen eine NPE.
const AndroidNotificationDetails _androidDetails = AndroidNotificationDetails(
  'optimes_default',
  'OpTimes Erinnerungen',
  channelDescription: 'Erinnerungen, Aufgaben und Termine',
  importance: Importance.high,
  priority: Priority.high,
);

/// Liest/schreibt alle Einstellungen rund um die Tagesvorschau aus Hive.
class DailyOverviewSettings {
  static const _kEnabled = 'daily_overview_enabled';
  static const _kMode = 'daily_overview_mode'; // 'fixed_time' | 'app_start'
  static const _kHour = 'daily_overview_hour';
  static const _kMinute = 'daily_overview_minute';
  static const _kOnlyIfRelevant = 'daily_overview_only_if_relevant';
  static const _kEveningEnabled = 'daily_overview_evening_preview';
  static const _kEveningHour = 'daily_overview_evening_hour';
  static const _kEveningMinute = 'daily_overview_evening_minute';
  static const _kLastAppStartCheck = 'daily_overview_last_app_start_check';

  static Box get _box => Hive.box('einstellungen');

  static bool get enabled => _box.get(_kEnabled, defaultValue: true) as bool;
  static set enabled(bool v) => _box.put(_kEnabled, v);

  /// 'fixed_time' = feste Uhrzeit über den OS-Scheduler.
  /// 'app_start'  = keine feste Uhrzeit; stattdessen wird bei jedem
  ///                App-Start einmal pro Kalendertag geprüft und ggf.
  ///                sofort eine lokale Notification gezeigt.
  static String get mode => _box.get(_kMode, defaultValue: 'fixed_time') as String;
  static set mode(String v) => _box.put(_kMode, v);

  static int get hour => _box.get(_kHour, defaultValue: 8) as int;
  static set hour(int v) => _box.put(_kHour, v);

  static int get minute => _box.get(_kMinute, defaultValue: 0) as int;
  static set minute(int v) => _box.put(_kMinute, v);

  /// true = nur senden, wenn an dem Tag ein Dienst ODER eine fällige
  /// Aufgabe vorliegt. false = auch "Heute ist nichts geplant" senden.
  static bool get onlyIfRelevant => _box.get(_kOnlyIfRelevant, defaultValue: true) as bool;
  static set onlyIfRelevant(bool v) => _box.put(_kOnlyIfRelevant, v);

  static bool get eveningPreviewEnabled =>
      _box.get(_kEveningEnabled, defaultValue: false) as bool;
  static set eveningPreviewEnabled(bool v) => _box.put(_kEveningEnabled, v);

  static int get eveningHour => _box.get(_kEveningHour, defaultValue: 20) as int;
  static set eveningHour(int v) => _box.put(_kEveningHour, v);

  static int get eveningMinute => _box.get(_kEveningMinute, defaultValue: 0) as int;
  static set eveningMinute(int v) => _box.put(_kEveningMinute, v);

  static String? get lastAppStartCheckDate =>
      _box.get(_kLastAppStartCheck, defaultValue: null) as String?;
  static set lastAppStartCheckDate(String v) => _box.put(_kLastAppStartCheck, v);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionsRequested = false;

  // Feste IDs: Legacy-Tagesvorschau (nur noch zum Aufräumen / App-Start-Modus)
  // und reiner Badge-Reset.
  static const int _dailyOverviewMorningId = 9000001;
  static const int _dailyOverviewEveningId = 9000002;
  static const int _badgeOnlyNotificationId = 9000099;

  // Tagesvorschau: eine ID pro Tag (0..6) für Morgen und Vorabend.
  static const int _overviewMorningBase = 9001000;
  static const int _overviewEveningBase = 9002000;
  static const int _overviewDays = 7; // Maximum (zum Aufräumen)

  /// iOS hält nur 64 geplante Benachrichtigungen → dort weniger Tage vorplanen.
  int get _overviewPlanDays =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ? 3 : _overviewDays;

  // Nummernräume (je 90 Mio. breit, alle < 2^31). Die alten Bereiche
  // 1.000.000–4.999.999 gelten als "Legacy" und werden gezielt aufgeräumt.
  static const int _taskIdBase = 100000000;
  static const int _urgentIdBase = 200000000;
  static const int _eventIdBase = 300000000;
  static const String _iosScheduledAtKey = '_ios_notification_scheduled_at';
  static const int _iosPendingLimit = 64;
  static const int _legacyIdMin = 1000000;
  static const int _legacyIdMax = 5000000;

  static const int _overdueNowIndex = 99;

  /// Stabiler FNV-1a-Hash (32 Bit).
  static int _stableHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static int _idIn(int base, String key) => base + _stableHash(key) % 90000000;

  Future<void> init() async {
    if (_initialized) return;

    // ── Timezone initialisieren ──────────────────────────────────────────────
    tz.initializeTimeZones();

    // Lokale Timezone setzen, sonst ist tz.local immer UTC
    final String timeZoneName = await _getLocalTimezoneName();
    try {
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
    }

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('Notification tapped: ${details.payload}');
      },
    );

    await _refreshScheduleMode();
    _initialized = true;

    // Badge beim Start IMMER auf den korrekten, aktuellen Stand bringen.
    await _refreshBadge();

    // Modus 'app_start': einmal pro Kalendertag die Tagesvorschau direkt
    // anzeigen, sobald die App geöffnet wird.
    await _maybeShowAppStartOverview();

    // Modus 'fixed_time': wiederkehrende Planung sicherstellen (z.B. nach
    // App-Update oder erstem Start).
    if (DailyOverviewSettings.enabled && DailyOverviewSettings.mode == 'fixed_time') {
      await scheduleDailyOverview();
    }

    _lastRefresh = DateTime.now();
    await CalendarEventStore.rescheduleAllNotifications();
    _startLifecycleRefresh();

    await debugLogPending();
  }

  /// Debug: listet alle geplanten Benachrichtigungen und meldet Duplikate
  /// (gleicher Titel + Text + Payload). Läuft nur im Debug-Modus.
  Future<void> debugLogPending() async {
    if (!kDebugMode) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final counts = <String, int>{};
      for (final r in pending) {
        final k = '${r.title}|${r.body}|${r.payload}';
        counts[k] = (counts[k] ?? 0) + 1;
      }
      print('Notifications pending: ${pending.length}');
      counts.forEach((k, n) {
        if (n > 1) print('  DUPLIKAT x$n: $k');
      });
    } catch (e) {
      print('debugLogPending: $e');
    }
  }

  /// Holt die lokale Timezone des Geräts.
  Future<String> _getLocalTimezoneName() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'Europe/Berlin';
    }
  }

  /// Exakt nur, wenn Android es erlaubt. Sonst ungefähr, damit nichts abbricht.
  AndroidScheduleMode _scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;

  Future<void> _refreshScheduleMode() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      _scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
      return;
    }
    final canExact = await android.canScheduleExactNotifications();
    _scheduleMode = canExact == true
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<bool> requestPermissions() async {
    // Android: Benachrichtigungen (13+) und exakte Alarme (14+) anfragen.
    // Auf iOS ist android == null, dort läuft der bisherige Code weiter.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final notifOk = await android.requestNotificationsPermission();
      final canExact = await android.canScheduleExactNotifications();
      if (canExact != true) {
        // Nur EINMAL pro Installation nachfragen — sonst öffnet jeder App-Start
        // die Systemeinstellungen.
        final box = Hive.box('einstellungen');
        if (box.get('notif_exact_alarm_asked', defaultValue: false) != true) {
          await box.put('notif_exact_alarm_asked', true);
          await android.requestExactAlarmsPermission();
        }
      }
      await _refreshScheduleMode();
      return notifOk ?? false;
    }

    if (_permissionsRequested) return true;
    _permissionsRequested = true;

    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

    final granted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    return granted ?? false;
  }

  bool get permissionsRequested => _permissionsRequested;

  // ── Hilfsfunktionen: Stil + Name aus Hive lesen ───────────────────────────

  RelationshipStyle get _style => RelationshipStyleStore.load();
  String get _fullName => (Hive.box('einstellungen').get('name', defaultValue: '') as String).trim();

  NotificationDetails _detailsFor(NotificationCopy copy, {required int badgeNumber, bool active = true}) {
    return NotificationDetails(
      android: _androidDetails,
      iOS: DarwinNotificationDetails(
        subtitle: copy.subtitle,
        sound: 'default',
        badgeNumber: badgeNumber,
        interruptionLevel: active ? InterruptionLevel.active : InterruptionLevel.passive,
      ),
    );
  }

  // ── Planen mit Absicherung ────────────────────────────────────────────────

  /// Plant eine Notification. Fehler (z.B. fehlende Exact-Alarm-Berechtigung
  /// auf Android) werden abgefangen; dann folgt ein zweiter Versuch ungefähr.
  Future<void> _zoned(
    int id,
    String title,
    String body,
    DateTime at,
    NotificationDetails details,
    String payload,
  ) {
    if (!_isIos) {
      return _scheduleZoned(id, title, body, at, details, payload);
    }

    final next = _zonedQueue.then(
      (_) => _scheduleZoned(id, title, body, at, details, payload),
    ).catchError((Object e) {
      print('Notification schedule failed (id $id): $e');
    });
    _zonedQueue = next;
    return next;
  }

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _zonedQueue = Future<void>.value();

  Map<int, int> _loadIosScheduledAt() {
    final raw = Hive.box('einstellungen').get(_iosScheduledAtKey);
    if (raw is! String || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            if (int.tryParse(entry.key.toString()) != null && entry.value is num)
              int.parse(entry.key.toString()): (entry.value as num).toInt(),
        };
      }
    } catch (e) {
      debugPrint('Invalid iOS notification schedule registry: $e');
    }
    return {};
  }

  Future<void> _saveIosScheduledAt(Map<int, int> scheduledAt) =>
      Hive.box('einstellungen').put(
        _iosScheduledAtKey,
        jsonEncode({
          for (final entry in scheduledAt.entries)
            '${entry.key}': entry.value,
        }),
      );

  Future<void> _scheduleZoned(
    int id,
    String title,
    String body,
    DateTime at,
    NotificationDetails details,
    String payload,
  ) async {
    Map<int, int>? scheduledAt;
    if (_isIos) {
      final pending = await _plugin.pendingNotificationRequests();
      final pendingIds = pending.map((request) => request.id).toSet();
      scheduledAt = _loadIosScheduledAt()
        ..removeWhere((scheduledId, _) => !pendingIds.contains(scheduledId));

      if (!pendingIds.contains(id)) {
        var pendingCount = pending.length;
        while (pendingCount >= _iosPendingLimit) {
          final managed = scheduledAt.entries
              .where((entry) => pendingIds.contains(entry.key))
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          if (managed.isEmpty) {
            debugPrint(
              'Notification skipped: iOS pending limit ($_iosPendingLimit) reached.',
            );
            return;
          }
          final farthest = managed.first;
          if (!at.isBefore(DateTime.fromMillisecondsSinceEpoch(farthest.value))) {
            debugPrint(
              'Notification skipped: iOS already has $_iosPendingLimit earlier notifications.',
            );
            return;
          }
          await _plugin.cancel(farthest.key);
          pendingIds.remove(farthest.key);
          scheduledAt.remove(farthest.key);
          pendingCount--;
        }
      }
    }

    final when = tz.TZDateTime.from(at, tz.local);
    for (final mode in [_scheduleMode, AndroidScheduleMode.inexactAllowWhileIdle]) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
        if (scheduledAt != null) {
          scheduledAt[id] = at.millisecondsSinceEpoch;
          await _saveIosScheduledAt(scheduledAt);
        }
        return;
      } catch (e) {
        print('Notification schedule failed (id $id, $mode): $e');
      }
    }
  }

  /// Bricht Altlasten aus dem alten ID-Schema (1–5 Mio.) mit diesem Payload ab.
  /// Fasst NIE neue IDs an, kann also nicht mit frisch geplanten kollidieren.
  Future<void> _cancelLegacyByPayload(String payload) async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final r in pending) {
        if (r.payload == payload && r.id >= _legacyIdMin && r.id < _legacyIdMax) {
          await _plugin.cancel(r.id);
        }
      }
    } catch (e) {
      print('_cancelLegacyByPayload: $e');
    }
  }

  final Map<String, Future<void>> _legacyPurged = {};

  /// Einmal pro App-Lauf und Payload: alte, nicht mehr abbrechbare Einträge
  /// entfernen, bevor neu geplant wird.
  Future<void> _purgeLegacyOnce(String payload) =>
      _legacyPurged.putIfAbsent(payload, () => _cancelLegacyByPayload(payload));

  // ── BADGE-MANAGEMENT ───────────────────────────────────────────────────────

  /// Setzt das App-Icon-Badge auf die Anzahl überfälliger, offener Aufgaben.
  /// Nur iOS: auf Android würde die "stille" Notification kurz sichtbar sein.
  Future<void> _refreshBadge() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final count = _countOverdueOpenTasks();
    try {
      await _plugin.show(
        _badgeOnlyNotificationId,
        null,
        null,
        NotificationDetails(
          android: _androidDetails,
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: true,
            presentSound: false,
            badgeNumber: count,
          ),
        ),
      );
      await _plugin.cancel(_badgeOnlyNotificationId);
    } catch (e) {
      print('_refreshBadge: $e');
    }
  }

  int _countOverdueOpenTasks() {
    final tasks = _loadTasksRaw();
    final now = DateTime.now();
    int count = 0;
    for (final t in tasks) {
      final done = t['done'] as bool? ?? false;
      if (done) continue;
      final dueRaw = t['dueDate'] as String?;
      if (dueRaw == null) continue;
      final due = DateTime.tryParse(dueRaw);
      if (due == null) continue;
      final hasTime = t['hasTime'] as bool? ?? false;
      final isOverdue = hasTime
          ? due.isBefore(now)
          : DateTime(due.year, due.month, due.day).isBefore(DateTime(now.year, now.month, now.day));
      if (isOverdue) count++;
    }
    return count;
  }

  /// Liest die rohe Task-Liste direkt aus Hive (Key 'tasks', identisch zu
  /// TaskStore.loadAll() in tasks_screen.dart). Bewusst ohne Import von
  /// tasks_screen.dart, um einen zyklischen Import zu vermeiden.
  List<Map<String, dynamic>> _loadTasksRaw() {
    final box = Hive.box('einstellungen');
    final raw = box.get('tasks');
    if (raw is! String || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Von außen (z.B. tasks_screen.dart) aufzurufen, sobald sich der
  /// Erledigt-Status, die Frist oder die Existenz einer Aufgabe ändert.
  Future<void> notifyTasksChanged() => _refreshBadge();

  // ── TASK REMINDER ─────────────────────────────────────────────────────────

  Future<void> scheduleTaskReminder({
    required String taskId,
    required int reminderIndex,
    required String title,
    required DateTime reminderAt,
  }) async {
    if (reminderAt.isBefore(DateTime.now())) return;
    await _purgeLegacyOnce(taskId);

    final copy = RelationshipTexts.taskReminder(
      style: _style,
      taskTitle: title,
      fullName: _fullName,
    );

    await _zoned(
      _notificationId(taskId, reminderIndex),
      copy.title,
      copy.body,
      reminderAt,
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks() + 1),
      taskId,
    );
  }

  Future<void> scheduleTaskDueToday({
    required String taskId,
    required int reminderIndex,
    required String taskTitle,
    required DateTime fireAt,
  }) async {
    if (fireAt.isBefore(DateTime.now())) return;
    await _purgeLegacyOnce(taskId);
    final copy = RelationshipTexts.taskDueToday(
      style: _style,
      taskTitle: taskTitle,
      fullName: _fullName,
    );
    await _zoned(
      _notificationId(taskId, reminderIndex),
      copy.title,
      copy.body,
      fireAt,
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
      taskId,
    );
  }

  Future<void> showTaskOverdueNow({
    required String taskId,
    required String taskTitle,
  }) async {
    final copy = RelationshipTexts.taskOverdue(
      style: _style,
      taskTitle: taskTitle,
      fullName: _fullName,
    );
    await _plugin.show(
      _notificationId(taskId, _overdueNowIndex),
      copy.title,
      copy.body,
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
      payload: taskId,
    );
  }

  void cancelTaskReminders(String taskId) {
    for (int i = 0; i < 10; i++) {
      cancelTaskReminder(taskId, i);
    }
    _plugin.cancel(_notificationId(taskId, _overdueNowIndex));
    cancelGuaranteedDueReminder(taskId);
    // Auch eine eventuell laufende Dringend-Erinnerung stoppen.
    cancelUrgentReminder(taskId);
    _cancelLegacyByPayload(taskId);
    _cancelLegacyByPayload('urgent:$taskId');
    _refreshBadge();
  }

  void cancelTaskReminder(String taskId, int reminderIndex) {
    _plugin.cancel(_notificationId(taskId, reminderIndex));
  }

  int _notificationId(String taskId, int reminderIndex) =>
      _idIn(_taskIdBase, 'task|$taskId|$reminderIndex');

  // ── DRINGEND, EINMALIGE ERINNERUNG NACH 24H ───────────────────────────────
  //
  // Genau eine zusätzliche Erinnerung 24 Stunden nach der Markierung, falls
  // die Aufgabe bis dahin nicht erledigt wurde. Bewusst einmalig: iOS/
  // flutter_local_notifications kennen keine native "alle X Stunden"-
  // Wiederholung ohne laufende App.

  int _urgentRecurringId(String taskId) => _idIn(_urgentIdBase, 'urgent|$taskId');

  Future<void> scheduleUrgentReminder({
    required String taskId,
    required String taskTitle,
  }) async {
    await _purgeLegacyOnce('urgent:$taskId');
    final copy = RelationshipTexts.taskUrgentRecurring(
      style: _style,
      taskTitle: taskTitle,
      fullName: _fullName,
    );
    final fireAt = DateTime.now().add(const Duration(hours: 24));
    await _zoned(
      _urgentRecurringId(taskId),
      copy.title,
      copy.body,
      fireAt,
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
      'urgent:$taskId',
    );
  }

  void cancelUrgentReminder(String taskId) {
    _plugin.cancel(_urgentRecurringId(taskId));
  }

  // ── GARANTIERTE FÄLLIG-ERINNERUNG ─────────────────────────────────────────
  //
  // Unabhängig von "X vorher"-Chips MUSS bei Fälligkeit eine Notification
  // kommen. Eigener Index (50), kollidiert dank Hash-IDs nicht mehr.
  static const int _dueReminderIndex = 50;
  /// Öffentlich, damit das Notification-Center denselben Standard-Uhrzeit-
  /// Wert nutzt wie der echte iOS-Reminder.
  static const int dueTimeDefaultHour = 9; // Uhrzeit für Aufgaben ohne Uhrzeit

  Future<void> scheduleGuaranteedDueReminder({
    required String taskId,
    required String taskTitle,
    required DateTime dueDate,
    required bool hasTime,
  }) async {
    final now = DateTime.now();
    final fireAt = hasTime
        ? dueDate
        : DateTime(dueDate.year, dueDate.month, dueDate.day, dueTimeDefaultHour, 0);

    if (fireAt.isBefore(now)) {
      // Zeitpunkt liegt in der Vergangenheit. Nur wenn die Aufgabe WIRKLICH
      // überfällig ist, einmal pro Frist sofort melden — nicht bei jedem
      // erneuten Planen und nicht für "heute fällig, 9 Uhr schon vorbei".
      final overdue = hasTime
          ? dueDate.isBefore(now)
          : DateTime(dueDate.year, dueDate.month, dueDate.day)
              .isBefore(DateTime(now.year, now.month, now.day));
      if (overdue) {
        final box = Hive.box('einstellungen');
        final sig = dueDate.toIso8601String();
        if (box.get('notif_overdue_$taskId') != sig) {
          await box.put('notif_overdue_$taskId', sig);
          await showTaskOverdueNow(taskId: taskId, taskTitle: taskTitle);
        }
      }
      return;
    }

    await _purgeLegacyOnce(taskId);
    final copy = RelationshipTexts.taskDueToday(
      style: _style,
      taskTitle: taskTitle,
      fullName: _fullName,
    );

    await _zoned(
      _notificationId(taskId, _dueReminderIndex),
      copy.title,
      copy.body,
      fireAt,
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks() + 1),
      taskId,
    );
  }

  void cancelGuaranteedDueReminder(String taskId) {
    _plugin.cancel(_notificationId(taskId, _dueReminderIndex));
  }

  // ── KALENDER-TERMIN REMINDER ──────────────────────────────────────────────
  //
  // Die ID entsteht aus Titel + Terminstart + Erinnerungszeit (nicht aus dem
  // reminderIndex): dieselbe Erinnerung hat IMMER dieselbe ID, egal von
  // welcher Stelle sie geplant wird → doppelte Benachrichtigungen sind
  // unmöglich. Stornieren läuft über den Payload 'event:<id>' und räumt damit
  // auch Altlasten mit beliebigem Index ab.

  /// Alle Termin-Aufträge laufen nacheinander, damit ein Neuplanen nie vor
  /// dem vorherigen Stornieren ausgeführt wird.
  Future<void> _eventQueue = Future.value();

  Future<void> _enqueue(Future<void> Function() job) {
    final next = _eventQueue.then((_) => job()).catchError((Object e) {
      print('Notification queue: $e');
    });
    _eventQueue = next;
    return next;
  }

  int _eventNotificationId(
    String eventId,
    String title,
    DateTime start,
    DateTime at,
  ) => _idIn(
      _eventIdBase,
      'event|$eventId|$title|${start.millisecondsSinceEpoch ~/ 60000}|${at.millisecondsSinceEpoch ~/ 60000}');

  /// Plant eine Erinnerung für einen Kalender-Termin. [reminderAt] ist der
  /// bereits berechnete Zeitpunkt (Termin-Start minus Vorlaufzeit).
  /// [reminderIndex] bleibt aus Kompatibilität in der Signatur, wird aber
  /// nicht mehr für die ID verwendet.
  Future<void> scheduleEventReminder({
    required String eventId,
    required int reminderIndex,
    required String eventTitle,
    required DateTime eventStart,
    required DateTime reminderAt,
  }) =>
      _enqueue(() async {
        if (reminderAt.isBefore(DateTime.now())) return;
        await _purgeLegacyOnce('event:$eventId');
        final timeLabel = DateFormat('HH:mm').format(eventStart);
        await _zoned(
          _eventNotificationId(eventId, eventTitle, eventStart, reminderAt),
          eventReminderTitle,
          eventReminderBody(eventTitle, timeLabel),
          reminderAt,
          const NotificationDetails(
            android: _androidDetails,
            iOS: DarwinNotificationDetails(sound: 'default', interruptionLevel: InterruptionLevel.active),
          ),
          'event:$eventId',
        );
      });

  /// Storniert ALLE Erinnerungen eines Termins (auch die garantierte und
  /// Altlasten) über den Payload.
  void cancelEventReminders(String eventId) {
    _enqueue(() async {
      final payload = 'event:$eventId';
      try {
        final pending = await _plugin.pendingNotificationRequests();
        for (final r in pending) {
          if (r.payload == payload) await _plugin.cancel(r.id);
        }
      } catch (e) {
        print('cancelEventReminders: $e');
      }
    });
  }

  // ── GARANTIERTE TERMIN-ERINNERUNG ─────────────────────────────────────────
  //
  // Jeder Termin bekommt zusätzlich GENAU EINE Erinnerung exakt zum Start.

  Future<void> scheduleGuaranteedEventReminder({
    required String eventId,
    required String eventTitle,
    required DateTime eventStart,
  }) =>
      _enqueue(() async {
        if (eventStart.isBefore(DateTime.now())) return;
        // Ganztägige Termine beginnen um 00:00 — keine Mitternachts-Meldung.
        if (eventStart.hour == 0 && eventStart.minute == 0) return;
        await _purgeLegacyOnce('event:$eventId');
        await _zoned(
          _eventNotificationId(eventId, eventTitle, eventStart, eventStart),
          eventReminderTitle,
          eventReminderBody(eventTitle, DateFormat('HH:mm').format(eventStart)),
          eventStart,
          const NotificationDetails(
            android: _androidDetails,
            iOS: DarwinNotificationDetails(sound: 'default', interruptionLevel: InterruptionLevel.active),
          ),
          'event:$eventId',
        );
      });

  void cancelGuaranteedEventReminder(String eventId) => cancelEventReminders(eventId);

  // ── ROLLENDES FENSTER FÜR TERMINE (Serien inklusive) ─────────────────────
  //
  // Baut ALLE Termin-Benachrichtigungen neu auf: erst alles mit Payload
  // 'event:' abbrechen (auch Altlasten), dann die zeitlich nächsten planen.
  // iOS hält nur die 64 nächsten → dort 40 Plätze für Termine; Android
  // kennt diese Grenze nicht.

  DateTime? _lastRefresh;
  _LifecycleHook? _hook;

  void _startLifecycleRefresh() {
    if (_hook != null) return;
    _hook = _LifecycleHook(() => _onResume());
    WidgetsBinding.instance.addObserver(_hook!);
  }

  /// Beim Zurückkehren in die App: Planungsmodus neu lesen (Nutzer kann
  /// gerade die Berechtigung für exakte Alarme erteilt haben). Hat sich der
  /// Modus geändert, wird sofort neu geplant.
  Future<void> _onResume() async {
    final before = _scheduleMode;
    await _refreshScheduleMode();
    await refreshAll(force: before != _scheduleMode);
  }

  /// Termine + Tagesvorschau neu planen (gedrosselt auf alle 20 Minuten).
  Future<void> refreshAll({bool force = false}) async {
    final last = _lastRefresh;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 20)) {
      return;
    }
    _lastRefresh = DateTime.now();
    try {
      await CalendarEventStore.rescheduleAllNotifications();
      if (DailyOverviewSettings.enabled && DailyOverviewSettings.mode == 'fixed_time') {
        await scheduleDailyOverview();
      }
      await _refreshBadge();
    } catch (e) {
      print('refreshAll: $e');
    }
  }

  Future<void> rescheduleAllEvents(List<EventOccurrencePlan> plans) => _enqueue(() async {
        final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
        final budget = isIos ? 40 : 400;

        try {
          final pending = await _plugin.pendingNotificationRequests();
          for (final r in pending) {
            final p = r.payload;
            if (p != null && p.startsWith('event:')) await _plugin.cancel(r.id);
          }
        } catch (e) {
          print('rescheduleAllEvents cancel: $e');
        }

        final now = DateTime.now();
        final byId = <int, ({DateTime at, String eventId, String title, DateTime start})>{};
        for (final p in plans) {
          final times = <DateTime>{p.start, for (final l in p.leads) p.start.subtract(l)};
          for (final at in times) {
            if (!at.isAfter(now)) continue;
            final id = _eventNotificationId(p.eventId, p.title, p.start, at);
            byId[id] = (at: at, eventId: p.eventId, title: p.title, start: p.start);
          }
        }
        final list = byId.entries.toList()..sort((a, b) => a.value.at.compareTo(b.value.at));
        for (final e in list.take(budget)) {
          final v = e.value;
          await _zoned(
            e.key,
            eventReminderTitle,
            eventReminderBody(v.title, DateFormat('HH:mm').format(v.start)),
            v.at,
            const NotificationDetails(
              android: _androidDetails,
              iOS: DarwinNotificationDetails(sound: 'default', interruptionLevel: InterruptionLevel.active),
            ),
            'event:${v.eventId}',
          );
        }
      });

  // ── TAGESVORSCHAU ──────────────────────────────────────────────────────────

  /// Liest den Schichtcode für einen bestimmten Tag direkt aus Hive —
  /// 'schedule_<yyyy-MM>' → Map<'yyyy-MM-dd', shiftCode>. 'X' = frei,
  /// kein Eintrag = "kein Dienstplan vorhanden".
  ({bool hasShift, bool isFree, String? code, String? resolvedShift}) _shiftInfoForDay(DateTime day) {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(day);
    final dayKey = DateFormat('yyyy-MM-dd').format(day);
    final raw = box.get('schedule_$monthKey');
    if (raw is Map) {
      final shift = raw[dayKey];
      if (shift is String && shift.trim().isNotEmpty) {
        final trimmed = shift.trim().toUpperCase();
        if (trimmed == 'X') {
          return (hasShift: true, isFree: true, code: null, resolvedShift: null);
        }
        return (
          hasShift: true,
          isFree: false,
          code: trimmed,
          resolvedShift: _resolveShift(trimmed),
        );
      }
    }
    return (hasShift: false, isFree: false, code: null, resolvedShift: null);
  }

  /// Löst Dienstcodes in die gewünschten Anzeigestrings auf.
  String _resolveShift(String code) {
    switch (code) {
      case 'T':  return 'Tagdienst';
      case 'U':  return 'Urlaub';
      case 'X':  return 'einen freien Tag'; // wird nur in isFree-Zweig genutzt
      // P/F: Kürzel beibehalten
      case 'P':  return 'P';
      case 'P1': return 'P1';
      case 'P2': return 'P2';
      case 'F':  return 'F';
      case 'F1': return 'F1';
      case 'F2': return 'F2';
      // Weitere Kürzel
      case 'DA': return 'DA';
      case 'VK': return 'VK';
      case 'IS': return 'IS';
      default:   return code; // unbekannte Codes einfach zeigen
    }
  }

  /// true, wenn für diesen Tag eine Notiz hinterlegt ist ('schedule_note_<dateKey>').
  bool _hasNoteForDay(DateTime day) {
    final box = Hive.box('einstellungen');
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    final raw = box.get('schedule_note_$dateKey');
    if (raw is Map) {
      final phone = (raw['phone'] ?? '') as String;
      final text = (raw['text'] ?? '') as String;
      return phone.trim().isNotEmpty || text.trim().isNotEmpty;
    }
    return false;
  }

  /// Aufgaben-Kennzahlen für die Tagesvorschau eines Tages:
  /// Anzahl mit Frist GENAU an diesem Tag, Titel falls genau eine, Anzahl
  /// ANDERER offener Aufgaben.
  ({int dueTodayCount, String? dueTodayTaskTitle, int otherOpenCount}) _taskInfoForDay(DateTime day) {
    final tasks = _loadTasksRaw();
    int dueToday = 0;
    String? dueTodayTitle;
    int otherOpen = 0;
    for (final t in tasks) {
      final done = t['done'] as bool? ?? false;
      if (done) continue;
      final dueRaw = t['dueDate'] as String?;
      final due = dueRaw != null ? DateTime.tryParse(dueRaw) : null;
      final isDueToday = due != null && due.year == day.year && due.month == day.month && due.day == day.day;
      if (isDueToday) {
        dueToday++;
        dueTodayTitle = t['title'] as String?;
      } else {
        otherOpen++;
      }
    }
    return (
      dueTodayCount: dueToday,
      dueTodayTaskTitle: dueToday == 1 ? dueTodayTitle : null,
      otherOpenCount: otherOpen,
    );
  }

  /// Mappt gecachte Wetterdaten auf eine WeatherCategory (null = keine Daten).
  ({WeatherCategory category, double tempC})? _weatherInfoFrom(
      WeatherData? data, {required bool forTomorrow}) {
    if (data == null) return null;
    final tempC = forTomorrow
        ? (data.tomorrowMaxTempC ?? data.forecastTempC)
        : data.forecastTempC;
    final code = forTomorrow
        ? (data.tomorrowWeatherCode ?? data.forecastWeatherCode)
        : data.forecastWeatherCode;
    final category = categoryFor(code, tempC, isDay: true);
    return (category: category, tempC: tempC);
  }

  /// Baut Titel+Subtitle+Body für die Tagesvorschau eines bestimmten Tages.
  NotificationCopy _buildOverviewCopy({
    required DateTime day,
    required WeatherData? weatherData,
    required bool forTomorrow,
  }) {
    final shiftInfo = _shiftInfoForDay(day);
    final hasNote = _hasNoteForDay(day);
    final weather = _weatherInfoFrom(weatherData, forTomorrow: forTomorrow);
    final taskInfo = _taskInfoForDay(day);

    return RelationshipTexts.dailyOverview(
      style: _style,
      fullName: _fullName,
      hasShift: shiftInfo.hasShift,
      isFree: shiftInfo.isFree,
      shiftCode: shiftInfo.resolvedShift ?? shiftInfo.code,
      hasNote: hasNote,
      weatherCategory: weather?.category,
      weatherTempC: weather?.tempC,
      dueTodayCount: taskInfo.dueTodayCount,
      dueTodayTaskTitle: taskInfo.dueTodayTaskTitle,
      otherOpenCount: taskInfo.otherOpenCount,
    );
  }

  bool _dayHasRelevantContent(DateTime day) {
    final shiftInfo = _shiftInfoForDay(day);
    final taskInfo = _taskInfoForDay(day);
    return (shiftInfo.hasShift && !shiftInfo.isFree) || taskInfo.dueTodayCount > 0;
  }

  Future<void> _cancelAllOverviews() async {
    await _plugin.cancel(_dailyOverviewMorningId);
    await _plugin.cancel(_dailyOverviewEveningId);
    for (int i = 0; i < _overviewDays; i++) {
      await _plugin.cancel(_overviewMorningBase + i);
      await _plugin.cancel(_overviewEveningBase + i);
    }
  }

  /// Plant die Tagesvorschau (Modus 'fixed_time') für die nächsten 7 Tage,
  /// jeweils mit dem Inhalt des Tages, an dem sie feuert. Plant IMMER neu
  /// (cancel + reschedule). Wetter gibt es nur für heute und morgen.
  Future<void> scheduleDailyOverview() async {
    await _cancelAllOverviews();

    if (!DailyOverviewSettings.enabled || DailyOverviewSettings.mode != 'fixed_time') {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Frische Wetterdaten einmalig für alle Notifications holen
    final weatherData = await WeatherService.instance.fetchForecastForNotification();

    for (int i = 0; i < _overviewPlanDays; i++) {
      final day = DateTime(today.year, today.month, today.day + i);

      // ── Morgen-Vorschau für diesen Tag ──
      final morning = DateTime(
        day.year, day.month, day.day,
        DailyOverviewSettings.hour, DailyOverviewSettings.minute,
      );
      if (morning.isAfter(now) &&
          (!DailyOverviewSettings.onlyIfRelevant || _dayHasRelevantContent(day))) {
        final copy = _buildOverviewCopy(
          day: day,
          weatherData: i <= 1 ? weatherData : null,
          forTomorrow: i == 1,
        );
        await _zoned(
          _overviewMorningBase + i,
          copy.title,
          copy.body,
          morning,
          _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
          'daily_overview',
        );
      }

      // ── Vorabend-Vorschau (optional) für den FOLGETAG ──
      if (DailyOverviewSettings.eveningPreviewEnabled) {
        final next = DateTime(day.year, day.month, day.day + 1);
        final evening = DateTime(
          day.year, day.month, day.day,
          DailyOverviewSettings.eveningHour, DailyOverviewSettings.eveningMinute,
        );
        if (evening.isAfter(now) &&
            (!DailyOverviewSettings.onlyIfRelevant || _dayHasRelevantContent(next))) {
          final copy = _buildOverviewCopy(
            day: next,
            weatherData: i == 0 ? weatherData : null,
            forTomorrow: true,
          );
          await _zoned(
            _overviewEveningBase + i,
            copy.title,
            copy.body,
            evening,
            _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
            'daily_overview_evening',
          );
        }
      }
    }
  }

  /// Modus 'app_start': wird in init() aufgerufen. Zeigt höchstens einmal
  /// pro Kalendertag eine sofortige Notification mit der Tagesvorschau.
  Future<void> _maybeShowAppStartOverview() async {
    if (!DailyOverviewSettings.enabled || DailyOverviewSettings.mode != 'app_start') return;

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (DailyOverviewSettings.lastAppStartCheckDate == todayStr) return;
    DailyOverviewSettings.lastAppStartCheckDate = todayStr;

    final today = DateTime.now();
    final dayOnly = DateTime(today.year, today.month, today.day);
    if (DailyOverviewSettings.onlyIfRelevant && !_dayHasRelevantContent(dayOnly)) return;

    final weatherData = await WeatherService.instance.fetchForecastForNotification();
    final copy = _buildOverviewCopy(day: dayOnly, weatherData: weatherData, forTomorrow: false);
    await _plugin.show(
      _dailyOverviewMorningId,
      copy.title,
      copy.body,
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
      payload: 'daily_overview',
    );
  }

  /// Von den Settings aufzurufen, nachdem der Nutzer irgendeine
  /// Tagesvorschau-Option geändert hat.
  Future<void> applyDailyOverviewSettingsChanged() async {
    if (DailyOverviewSettings.mode == 'fixed_time') {
      await scheduleDailyOverview();
    } else {
      await _cancelAllOverviews();
    }
  }
}

/// Ein Termin-Vorkommen samt Vorlaufzeiten für die Planung.
class EventOccurrencePlan {
  final String eventId;
  final String title;
  final DateTime start;
  final List<Duration> leads;
  const EventOccurrencePlan({
    required this.eventId,
    required this.title,
    required this.start,
    required this.leads,
  });
}

class _LifecycleHook with WidgetsBindingObserver {
  final void Function() onResume;
  _LifecycleHook(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
