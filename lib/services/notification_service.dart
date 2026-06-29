import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/relationship_style.dart';
import '../models/notification_phrases.dart' show WeatherCategory, categoryFor;
import 'weather_service.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION SERVICE
//
// Aufbau:
//
// 1) BADGE-MANAGEMENT: _refreshBadge() zählt überfällige, nicht erledigte
//    Aufgaben und setzt das App-Icon-Badge exakt darauf — aufgerufen bei
//    init() und über notifyTasksChanged() von außen (tasks_screen.dart).
//
// 2) STILABHÄNGIGE TEXTE: Jeder Notification-Case holt Titel/Body/Subtitle
//    aus RelationshipTexts (relationship_style.dart), die wiederum aus
//    notification_phrases.dart zufällige Varianten zieht. Dieser Service
//    kennt selbst keine Text-/Stil-Logik, nur WANN und WORAUS (Dienst,
//    Wetter, Aufgaben-Zahlen) eine Notification besteht.
//
// 3) TAGESVORSCHAU: scheduleDailyOverview() plant eine täglich wiederkeh-
//    rende Notification, die kombiniert: Dienst (Hive-Key schedule_<yyyy-MM>),
//    Notiz-Vorhandensein (Hive-Key schedule_note_<dateKey>), Wetter
//    (WeatherService) und fällige/offene Aufgaben (Hive-Key 'tasks').
//    Konfigurierbar über DailyOverviewSettings (ein/aus, feste Uhrzeit vs.
//    App-Start, nur wenn relevant, zusätzliche Vorabend-Vorschau).
//
// 4) DRINGEND (NEU): Aufgaben, die als dringend (isUrgent == true) markiert
//    werden, erhalten GENAU EINE zusätzliche Erinnerung 24 Stunden nach der
//    Markierung, falls bis dahin nicht erledigt — verwaltet über
//    scheduleUrgentReminder()/cancelUrgentReminder(), aufgerufen von
//    tasks_screen.dart bei Statusänderung. Bewusst einmalig, keine echte
//    Wiederholung alle X Stunden (technisch ohne offene App nicht
//    zuverlässig nativ umsetzbar, s. Kommentar an der Methode selbst).
// ─────────────────────────────────────────────────────────────────────────────

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

  // Feste IDs für die wiederkehrende Tagesvorschau (Morgen/Abend) und für
  // den reinen Badge-Reset — getrennt von den dynamischen Task-Reminder-IDs
  // (siehe _notificationId), damit sie sich nie überschneiden können.
  static const int _dailyOverviewMorningId = 900001;
  static const int _dailyOverviewEveningId = 900002;
  static const int _badgeOnlyNotificationId = 900099;

  // Basis-Offset für die "dringend, alle 6h" wiederkehrenden IDs — eigener
  // Nummernraum, getrennt von den normalen Task-Remindern (_notificationId)
  // und den Tagesvorschau-IDs oben.
  static const int _urgentRecurringIdBase = 800000;

  Future<void> init() async {
    if (_initialized) return;

    // ── Timezone initialisieren ──────────────────────────────────────────────
    tz.initializeTimeZones();
    
    // NEU: lokale Timezone setzen, sonst ist tz.local immer UTC
    final String timeZoneName = await _getLocalTimezoneName();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

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
  }

  /// Holt die lokale Timezone des Geräts.
  Future<String> _getLocalTimezoneName() async {
    try {
      // flutter_timezone package
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return 'Europe/Berlin'; // Fallback für dein Gerät
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

  NotificationDetails _detailsFor(NotificationCopy copy, {required int badgeNumber, bool active = true}) {
    return NotificationDetails(
      iOS: DarwinNotificationDetails(
        subtitle: copy.subtitle,
        sound: 'default',
        badgeNumber: badgeNumber,
        interruptionLevel: active ? InterruptionLevel.active : InterruptionLevel.passive,
      ),
    );
  }

  // ── BADGE-MANAGEMENT ───────────────────────────────────────────────────────

  /// Setzt das App-Icon-Badge auf die Anzahl der aktuell wirklich
  /// relevanten Items — aktuell: überfällige, nicht erledigte Aufgaben.
  Future<void> _refreshBadge() async {
    final count = _countOverdueOpenTasks();
    if (count <= 0) {
      // Eine "stille" Notification (kein Alert, kein Sound, nur Badge),
      // die sofort wieder gecancelt wird — zuverlässigster Weg über
      // flutter_local_notifications, das Badge explizit auf 0 zu setzen.
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
  /// Erledigt-Status, die Frist oder die Existenz einer Aufgabe ändert —
  /// hält das Badge konsistent mit dem echten Zustand.
  Future<void> notifyTasksChanged() => _refreshBadge();

  // ── TASK REMINDER (bestehender Mechanismus, stilabhängig über Phrasen) ───

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
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks() + 1),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: taskId,
    );
  }

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
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: taskId,
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
      _notificationId(taskId, 99),
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
    // Auch eine eventuell laufende Dringend-Erinnerung für diese Aufgabe
    // stoppen — relevant, wenn die Aufgabe erledigt/gelöscht wird.
    cancelUrgentReminder(taskId);
    _refreshBadge();
  }

  void cancelTaskReminder(String taskId, int reminderIndex) {
    _plugin.cancel(_notificationId(taskId, reminderIndex));
  }

  int _notificationId(String taskId, int reminderIndex) {
    return (taskId.hashCode.abs() % 100000) * 10 + reminderIndex;
  }

  // ── DRINGEND, EINMALIGE ERINNERUNG NACH 24H (NEU) ─────────────────────────
  //
  // Aufgaben, die als dringend markiert werden, erhalten GENAU EINE
  // zusätzliche Erinnerung 24 Stunden nach der Markierung, falls sie bis
  // dahin nicht erledigt wurde — unabhängig von eventuell zusätzlich
  // gesetzten normalen Remindern. Bewusst einmalig (keine echte
  // Wiederholung alle 6h): flutter_local_notifications/iOS unterstützen
  // keine native "alle X Stunden, für immer"-Wiederholung ohne dass die
  // App regelmäßig im Vorder- oder Hintergrund läuft, um neu zu planen.
  // Eine einmalige 24h-Erinnerung ist die zuverlässige, einfache Lösung.

  int _urgentRecurringId(String taskId) =>
      _urgentRecurringIdBase + (taskId.hashCode.abs() % 100000);

  /// Plant die einmalige Dringend-Erinnerung für 24h ab jetzt. Aufzurufen
  /// von tasks_screen.dart, sobald eine Aufgabe als dringend markiert wird.
  /// Erneuter Aufruf (z.B. bei Titel-Änderung) ersetzt automatisch den
  /// bisherigen Termin (gleiche ID).
  Future<void> scheduleUrgentReminder({
    required String taskId,
    required String taskTitle,
  }) async {
    final copy = RelationshipTexts.taskUrgentRecurring(
      style: _style,
      taskTitle: taskTitle,
      fullName: _fullName,
    );
    final id = _urgentRecurringId(taskId);
    final fireAt = DateTime.now().add(const Duration(hours: 24));

    await _plugin.zonedSchedule(
      id,
      copy.title,
      copy.body,
      tz.TZDateTime.from(fireAt, tz.local),
      _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'urgent:$taskId',
    );
  }

  /// Stoppt die Dringend-Erinnerung für eine Aufgabe — aufzurufen, wenn die
  /// Aufgabe nicht mehr dringend ist, erledigt oder gelöscht wurde.
  void cancelUrgentReminder(String taskId) {
    _plugin.cancel(_urgentRecurringId(taskId));
  }

  // ── TAGESVORSCHAU ──────────────────────────────────────────────────────────

  /// Liest den Schichtcode für einen bestimmten Tag direkt aus Hive —
  /// exakt derselbe Key wie in ScheduleScreenState.loadScheduleData():
  /// 'schedule_<yyyy-MM>' → Map<'yyyy-MM-dd', shiftCode>. 'X' (= frei/kein
  /// Eintrag laut DienstplanParser) wird als "frei" behandelt, kein Eintrag
  /// als "kein Dienstplan vorhanden".
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

  /// true, wenn für diesen Tag eine Notiz hinterlegt ist (Telefonnummer
  /// oder Text) — identische Hive-Konvention zu _NoteData in
  /// schedule_screen.dart ('schedule_note_<dateKey>').
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

  /// Liefert die Aufgaben-Kennzahlen für die Tagesvorschau eines Tages:
  /// - Anzahl Aufgaben mit Frist GENAU an diesem Tag (dueTodayCount)
  /// - Titel der einzigen solchen Aufgabe, falls dueTodayCount == 1
  /// - Anzahl ANDERER offener Aufgaben (otherOpenCount) — alle nicht
  ///   erledigten Aufgaben, die NICHT an diesem Tag fällig sind (egal ob
  ///   sie eine Frist an einem anderen Tag haben oder gar keine Frist).
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

  /// Holt die aktuell gecachten Wetterdaten (kein aktiver Fetch hier, das
  /// übernimmt der reguläre WeatherService-Aufruf z.B. beim App-Start im
  /// Homescreen) und mappt sie auf eine WeatherCategory. Liefert null, wenn
  /// keine (auch keine veralteten) Wetterdaten vorliegen.
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

  /// Plant die wiederkehrende Tagesvorschau (Modus 'fixed_time'). Plant
  /// IMMER neu (cancel + reschedule), damit Änderungen an Uhrzeit/Optionen
  /// aus den Settings sofort wirksam werden, und damit der Inhalt bei jedem
  /// App-Start mit den aktuellen Daten neu befüllt wird.
  Future<void> scheduleDailyOverview() async {
    await _plugin.cancel(_dailyOverviewMorningId);
    await _plugin.cancel(_dailyOverviewEveningId);

    if (!DailyOverviewSettings.enabled || DailyOverviewSettings.mode != 'fixed_time') {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Frische Wetterdaten einmalig für beide Notifications holen
    final weatherData = await WeatherService.instance.fetchForecastForNotification();

    // ── Morgen-Vorschau für HEUTE ──
    if (!DailyOverviewSettings.onlyIfRelevant || _dayHasRelevantContent(today)) {
      final copy = _buildOverviewCopy(day: today, weatherData: weatherData, forTomorrow: false);
      var fireTime = DateTime(
        now.year, now.month, now.day,
        DailyOverviewSettings.hour, DailyOverviewSettings.minute,
      );
      if (fireTime.isBefore(now)) fireTime = fireTime.add(const Duration(days: 1));

      await _plugin.zonedSchedule(
        _dailyOverviewMorningId,
        copy.title,
        copy.body,
        tz.TZDateTime.from(fireTime, tz.local),
        _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
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
        final copy = _buildOverviewCopy(day: tomorrow, weatherData: weatherData, forTomorrow: true);
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
          _detailsFor(copy, badgeNumber: _countOverdueOpenTasks()),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'daily_overview_evening',
        );
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
      await _plugin.cancel(_dailyOverviewMorningId);
      await _plugin.cancel(_dailyOverviewEveningId);
    }
  }
}