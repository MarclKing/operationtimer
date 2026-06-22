import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/relationship_style.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION SERVICE
//
// Änderungen gegenüber der Vorversion:
//
// 1) BADGE-FIX: Vorher stand in der Task-Reminder-Notification ein fest
//    codiertes `badgeNumber: 1`. iOS SETZT das Badge exakt auf den
//    übergebenen Wert (zählt nicht selbst hoch) — da nirgends ein Reset
//    auf 0 erfolgte, blieb die "1" für immer am App-Icon kleben, auch
//    nachdem die Aufgabe erledigt war. Fix: `_refreshBadge()` zählt die
//    tatsächlich relevanten offenen Items (aktuell: überfällige, nicht
//    erledigte Aufgaben) und setzt das Badge GENAU darauf — aufgerufen bei
//    init() und über `notifyTasksChanged()` von außen (tasks_screen.dart),
//    sobald sich der Aufgaben-Status ändert.
//
// 2) STILABHÄNGIGE TEXTE: Jeder Notification-Case holt sich Titel/Body aus
//    RelationshipTexts (relationship_style.dart) statt eigene Strings zu
//    bauen — der Service selbst kennt keine Stil-Logik mehr.
//
// 3) NEU — TAGESVORSCHAU: scheduleDailyOverview() plant eine täglich
//    wiederkehrende Notification, die Dienst (aus dem Hive-Key
//    schedule_<yyyy-MM>, identisch zu ScheduleScreenState.loadScheduleData)
//    UND fällige Aufgaben (aus dem Hive-Key 'tasks') kombiniert anzeigt.
//    Vollständig über DailyOverviewSettings (Hive) konfigurierbar, damit
//    settings_screen.dart eigene Schalter dafür anbieten kann:
//      - ein/aus
//      - feste Uhrzeit ODER "bei App-Start einmal täglich prüfen"
//      - nur senden wenn etwas anliegt, oder auch "nichts geplant"
//      - zusätzliche Vorabend-Vorschau auf den nächsten Tag
// ─────────────────────────────────────────────────────────────────────────────

/// Liest/schreibt alle Einstellungen rund um die Tagesvorschau aus Hive.
/// Eigene kleine Klasse, damit settings_screen.dart sauber dagegen
/// programmieren kann, ohne überall einzelne Hive-Keys direkt anzufassen.
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

  // Feste IDs für die wiederkehrende Tagesvorschau (Morgen/Abend) und für
  // den reinen Badge-Reset — getrennt von den dynamischen Task-Reminder-IDs
  // (siehe _notificationId), damit sie sich nie überschneiden können.
  static const int _dailyOverviewMorningId = 900001;
  static const int _dailyOverviewEveningId = 900002;
  static const int _badgeOnlyNotificationId = 900099;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(iOS: iosSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('Notification tapped: ${details.payload}');
      },
    );

    _initialized = true;

    // Badge beim Start IMMER auf den korrekten, aktuellen Stand bringen —
    // behebt das Problem, dass eine alte "1" sonst ewig kleben bleibt.
    await _refreshBadge();

    // Modus 'app_start': einmal pro Kalendertag die Tagesvorschau direkt
    // anzeigen, sobald die App geöffnet wird.
    await _maybeShowAppStartOverview();

    // Modus 'fixed_time': wiederkehrende Planung sicherstellen (z.B. nach
    // App-Update oder erstem Start).
    if (DailyOverviewSettings.enabled && DailyOverviewSettings.mode == 'fixed_time') {
      await scheduleDailyOverview();
    }
  }

  Future<bool> requestPermissions() async {
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

  // ── BADGE-MANAGEMENT ───────────────────────────────────────────────────────

  /// Setzt das App-Icon-Badge auf die Anzahl der aktuell wirklich
  /// relevanten Items — aktuell: überfällige, nicht erledigte Aufgaben.
  /// Wird bei init() aufgerufen und sollte zusätzlich von außen über
  /// notifyTasksChanged() getriggert werden, sobald sich der Aufgaben-
  /// Status ändert (erledigt, gelöscht, neue Frist gesetzt, ...).
  Future<void> _refreshBadge() async {
    final count = _countOverdueOpenTasks();
    if (count <= 0) {
      // Eine "stille" Notification (kein Alert, kein Sound, nur Badge),
      // die sofort wieder gecancelt wird — das ist der zuverlässigste Weg
      // über flutter_local_notifications, das App-Icon-Badge explizit auf
      // 0 zurückzusetzen (es gibt keine direkte "clearBadge()"-Methode).
      await _plugin.show(
        _badgeOnlyNotificationId,
        null,
        null,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: true,
            presentSound: false,
            badgeNumber: 0,
          ),
        ),
      );
      await _plugin.cancel(_badgeOnlyNotificationId);
    }
    // Ist count > 0, wird das Badge bereits durch die jeweils zuletzt
    // angezeigte/geplante Notification (badgeNumber: count) korrekt
    // gesetzt — siehe scheduleTaskReminder/showTaskOverdueNow unten.
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
  /// tasks_screen.dart, um einen zyklischen Import zu vermeiden (dort wird
  /// bereits dieser Service importiert).
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
  /// Erledigt-Status, die Frist oder die Existenz einer Aufgabe ändert —
  /// hält das Badge konsistent mit dem echten Zustand.
  Future<void> notifyTasksChanged() => _refreshBadge();

  // ── TASK REMINDER (bestehender Mechanismus, jetzt stilabhängig) ──────────

  /// Erinnerung für einen Task planen — Text wird je nach gewähltem
  /// RelationshipStyle aus relationship_style.dart gewählt.
  void scheduleTaskReminder({
    required String taskId,
    required int reminderIndex,
    required String title,
    required DateTime reminderAt,
  }) {
    if (reminderAt.isBefore(DateTime.now())) return;

    final copy = RelationshipTexts.taskReminder(
      style: _style,
      taskTitle: title,
      fullName: _fullName,
    );

    final id = _notificationId(taskId, reminderIndex);

    _plugin.zonedSchedule(
      id,
      copy.title,
      copy.body,
      tz.TZDateTime.from(reminderAt, tz.local),
      NotificationDetails(
        iOS: DarwinNotificationDetails(
          sound: 'default',
          // +1, weil diese Notification selbst beim Feuern ein weiteres
          // (potenziell überfälliges) Item repräsentieren kann; der exakte
          // Wert wird ohnehin beim nächsten App-Start über _refreshBadge()
          // korrigiert, das hier ist nur die Anzeige zum Feuerzeitpunkt.
          badgeNumber: _countOverdueOpenTasks() + 1,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: taskId,
    );
  }

  /// Direkt aufrufbar, falls eine Aufgabe HEUTE fällig ist (z.B. von einem
  /// eigenen Scheduling-Aufruf in tasks_screen.dart, sobald due == heute).
  void scheduleTaskDueToday({
    required String taskId,
    required int reminderIndex,
    required String taskTitle,
    required DateTime fireAt,
  }) {
    if (fireAt.isBefore(DateTime.now())) return;
    final copy = RelationshipTexts.taskDueToday(
      style: _style,
      taskTitle: taskTitle,
      fullName: _fullName,
    );
    _plugin.zonedSchedule(
      _notificationId(taskId, reminderIndex),
      copy.title,
      copy.body,
      tz.TZDateTime.from(fireAt, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(sound: 'default', interruptionLevel: InterruptionLevel.active),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: taskId,
    );
  }

  /// Sofortige (nicht geplante) Notification für eine überfällige Aufgabe —
  /// z.B. nutzbar bei einer eigenen Prüfung, falls eine Aufgabe gerade erst
  /// überfällig geworden ist.
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
      _notificationId(taskId, 99),
      copy.title,
      copy.body,
      NotificationDetails(
        iOS: DarwinNotificationDetails(
          sound: 'default',
          badgeNumber: _countOverdueOpenTasks(),
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      payload: taskId,
    );
  }

  void cancelTaskReminders(String taskId) {
    for (int i = 0; i < 10; i++) {
      cancelTaskReminder(taskId, i);
    }
    // Badge nach dem Entfernen der Reminder gleich neu berechnen.
    _refreshBadge();
  }

  void cancelTaskReminder(String taskId, int reminderIndex) {
    _plugin.cancel(_notificationId(taskId, reminderIndex));
  }

  int _notificationId(String taskId, int reminderIndex) {
    return (taskId.hashCode.abs() % 100000) * 10 + reminderIndex;
  }

  // ── TAGESVORSCHAU (NEU) ───────────────────────────────────────────────────

  /// Liest den Schichtcode für einen bestimmten Tag direkt aus Hive —
  /// exakt derselbe Key wie in ScheduleScreenState.loadScheduleData():
  /// 'schedule_<yyyy-MM>' → Map<'yyyy-MM-dd', shiftCode>. 'X' (= frei/kein
  /// Eintrag laut DienstplanParser) wird wie "kein Dienst" behandelt.
  String? _shiftForDay(DateTime day) {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(day);
    final dayKey = DateFormat('yyyy-MM-dd').format(day);
    final raw = box.get('schedule_$monthKey');
    if (raw is Map) {
      final shift = raw[dayKey];
      if (shift is String && shift.trim().isNotEmpty && shift.trim().toUpperCase() != 'X') {
        return shift.trim();
      }
    }
    return null;
  }

  /// Zählt offene (nicht erledigte) Aufgaben mit Frist exakt an diesem Tag —
  /// identische Logik zu TaskStore.hasOpenTaskOnDay() in tasks_screen.dart,
  /// nur als Zähler statt bool und direkt auf dem Hive-Key 'tasks'.
  int _openTaskCountForDay(DateTime day) {
    final tasks = _loadTasksRaw();
    int count = 0;
    for (final t in tasks) {
      final done = t['done'] as bool? ?? false;
      if (done) continue;
      final dueRaw = t['dueDate'] as String?;
      if (dueRaw == null) continue;
      final due = DateTime.tryParse(dueRaw);
      if (due == null) continue;
      if (due.year == day.year && due.month == day.month && due.day == day.day) count++;
    }
    return count;
  }

  /// Baut Titel+Body für die Tagesvorschau eines bestimmten Tages.
  NotificationCopy _buildOverviewCopy({required DateTime day, required String dayLabel}) {
    final shift = _shiftForDay(day);
    final taskCount = _openTaskCountForDay(day);
    return RelationshipTexts.dailyOverview(
      style: _style,
      fullName: _fullName,
      dayLabel: dayLabel,
      shift: shift,
      taskCount: taskCount,
    );
  }

  bool _dayHasRelevantContent(DateTime day) {
    return _shiftForDay(day) != null || _openTaskCountForDay(day) > 0;
  }

  /// Plant die wiederkehrende Tagesvorschau (Modus 'fixed_time'). Plant
  /// IMMER neu (cancel + reschedule), damit Änderungen an Uhrzeit/Optionen
  /// aus den Settings sofort wirksam werden, und damit der Inhalt (Dienst +
  /// Aufgaben-Anzahl) bei jedem App-Start mit den aktuellen Daten neu
  /// befüllt wird. Nutzt `matchDateTimeComponents: DateTimeComponents.time`
  /// für die tägliche Wiederholung durch das Betriebssystem.
  Future<void> scheduleDailyOverview() async {
    await _plugin.cancel(_dailyOverviewMorningId);
    await _plugin.cancel(_dailyOverviewEveningId);

    if (!DailyOverviewSettings.enabled || DailyOverviewSettings.mode != 'fixed_time') {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ── Morgen-Vorschau für HEUTE ──
    if (!DailyOverviewSettings.onlyIfRelevant || _dayHasRelevantContent(today)) {
      final copy = _buildOverviewCopy(day: today, dayLabel: 'heute');
      var fireTime = DateTime(
        now.year, now.month, now.day,
        DailyOverviewSettings.hour, DailyOverviewSettings.minute,
      );
      // Falls die Zeit heute schon vorbei ist, für den Erstlauf auf morgen
      // verschieben — die tägliche Wiederholung übernimmt danach automatisch.
      if (fireTime.isBefore(now)) fireTime = fireTime.add(const Duration(days: 1));

      await _plugin.zonedSchedule(
        _dailyOverviewMorningId,
        copy.title,
        copy.body,
        tz.TZDateTime.from(fireTime, tz.local),
        const NotificationDetails(
          iOS: DarwinNotificationDetails(sound: 'default', interruptionLevel: InterruptionLevel.active),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'daily_overview',
      );
    }

    // ── Vorabend-Vorschau für MORGEN (optional) ──
    if (DailyOverviewSettings.eveningPreviewEnabled) {
      final tomorrow = today.add(const Duration(days: 1));
      if (!DailyOverviewSettings.onlyIfRelevant || _dayHasRelevantContent(tomorrow)) {
        final copy = _buildOverviewCopy(day: tomorrow, dayLabel: 'morgen');
        var fireTime = DateTime(
          now.year, now.month, now.day,
          DailyOverviewSettings.eveningHour, DailyOverviewSettings.eveningMinute,
        );
        if (fireTime.isBefore(now)) fireTime = fireTime.add(const Duration(days: 1));

        await _plugin.zonedSchedule(
          _dailyOverviewEveningId,
          copy.title,
          copy.body,
          tz.TZDateTime.from(fireTime, tz.local),
          const NotificationDetails(
            iOS: DarwinNotificationDetails(sound: 'default', interruptionLevel: InterruptionLevel.active),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'daily_overview_evening',
        );
      }
    }
  }

  /// Modus 'app_start': wird in init() aufgerufen. Zeigt höchstens einmal
  /// pro Kalendertag eine sofortige Notification mit der Tagesvorschau,
  /// sobald die App geöffnet wird — keine feste Uhrzeit nötig.
  Future<void> _maybeShowAppStartOverview() async {
    if (!DailyOverviewSettings.enabled || DailyOverviewSettings.mode != 'app_start') return;

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (DailyOverviewSettings.lastAppStartCheckDate == todayStr) return; // heute schon gezeigt
    DailyOverviewSettings.lastAppStartCheckDate = todayStr;

    final today = DateTime.now();
    final dayOnly = DateTime(today.year, today.month, today.day);
    if (DailyOverviewSettings.onlyIfRelevant && !_dayHasRelevantContent(dayOnly)) return;

    final copy = _buildOverviewCopy(day: dayOnly, dayLabel: 'heute');
    await _plugin.show(
      _dailyOverviewMorningId,
      copy.title,
      copy.body,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(sound: 'default', interruptionLevel: InterruptionLevel.active),
      ),
      payload: 'daily_overview',
    );
  }

  /// Von den Settings aufzurufen, nachdem der Nutzer irgendeine
  /// Tagesvorschau-Option geändert hat — sorgt dafür, dass alles
  /// (Scheduling oder Deaktivierung) sofort konsistent ist.
  Future<void> applyDailyOverviewSettingsChanged() async {
    if (DailyOverviewSettings.mode == 'fixed_time') {
      await scheduleDailyOverview();
    } else {
      await _plugin.cancel(_dailyOverviewMorningId);
      await _plugin.cancel(_dailyOverviewEveningId);
    }
  }
}