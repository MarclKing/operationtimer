class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  bool _initialized = false;
  bool _permissionsRequested = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    _permissionsRequested = true;
    return true;
  }

  bool get permissionsRequested => _permissionsRequested;

  void scheduleTaskReminder({
    required String taskId,
    required int reminderIndex,
    required String title,
    required DateTime reminderAt,
  }) {
    // Platzhalter — kein-op.
  }

  void cancelTaskReminders(String taskId) {
    // Platzhalter — kein-op.
  }

  void cancelTaskReminder(String taskId, int reminderIndex) {
    // Platzhalter — kein-op.
  }
}