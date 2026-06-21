import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionsRequested = false;

  Future<void> init() async {
    if (_initialized) return;

    // Zeitzonen initialisieren
    tz.initializeTimeZones();

    // iOS-Einstellungen
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // Wir fragen separat
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(iOS: iosSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Optional: Reagieren wenn User auf Noti tippt
        print('Notification tapped: ${details.payload}');
      },
    );

    _initialized = true;
  }

  /// Berechtigung vom User anfragen (einmalig)
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

  /// Erinnerung für einen Task planen
  void scheduleTaskReminder({
    required String taskId,
    required int reminderIndex,
    required String title,
    required DateTime reminderAt,
  }) {
    // Nur in der Zukunft planen
    if (reminderAt.isBefore(DateTime.now())) return;

    final id = _notificationId(taskId, reminderIndex);

    _plugin.zonedSchedule(
      id,
      '📌 $title',           // Titel der Notification
      'Deine Aufgabe steht an!', // Body-Text
      tz.TZDateTime.from(reminderAt, tz.local),
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          sound: 'default',
          badgeNumber: 1,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: taskId, // Wird beim Tippen zurückgegeben
    );
  }

  /// Alle Reminder eines Tasks löschen
  void cancelTaskReminders(String taskId) {
    // Indices 0–9 abdecken (anpassen falls du mehr hast)
    for (int i = 0; i < 10; i++) {
      cancelTaskReminder(taskId, i);
    }
  }

  /// Einzelnen Reminder löschen
  void cancelTaskReminder(String taskId, int reminderIndex) {
    _plugin.cancel(_notificationId(taskId, reminderIndex));
  }

  /// Stabile eindeutige ID aus taskId + Index
  int _notificationId(String taskId, int reminderIndex) {
    return (taskId.hashCode.abs() % 100000) * 10 + reminderIndex;
  }
}