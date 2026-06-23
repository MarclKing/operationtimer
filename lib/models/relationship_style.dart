import 'package:hive_flutter/hive_flutter.dart';
import 'notification_phrases.dart' as phrases;
import 'notification_phrases.dart' show WeatherCategory, pick;

// ─────────────────────────────────────────────────────────────────────────────
// RELATIONSHIP STYLE
//
// Steuert die "Umgangsform", in der OpTimes mit dem Nutzer spricht — wirkt
// sich auf JEDE Notification der App aus (Tagesvorschau, Task-Reminder,
// fällig/überfällig, dringend-wiederkehrend). Wird im Onboarding
// (welcome_screen.dart, 2. Sheet) gesetzt und ist in den Einstellungen
// jederzeit änderbar.
//
// WICHTIG — ANREDE-KONVENTION:
// Alle drei Stile sprechen mit dem VORNAMEN an (nie Nachname + Anrede-
// Titel wie "Werter/Werte", das hätte ein Genus-Problem). Der Unterschied
// zwischen den Stilen liegt NICHT im verwendeten Namen, sondern im Sie/Du
// und in der Wortwahl:
//   - bro:     Du, locker/kumpelhaft  ("Hey, nicht vergessen, Bro!")
//   - vorname: Du, neutral-freundlich ("Olaf, denk daran...")
//   - familie: Sie, aber mit Vornamen ("Guten Morgen Olaf, Sie haben...")
//
// Die eigentlichen Textvarianten liegen NICHT hier, sondern in
// notification_phrases.dart — diese Datei ist nur die dünne Schicht, die
// Platzhalter einsetzt und eine zufällige Variante auswählt. Neue Sätze
// fügst du direkt in notification_phrases.dart zu den jeweiligen Listen
// hinzu, hier muss dafür nichts geändert werden.
// ─────────────────────────────────────────────────────────────────────────────

enum RelationshipStyle {
  bro,      // ".. hilf mir einfach bei der Arbeit, Bro"
  vorname,  // "Du kannst [Vorname] zu mir sagen"
  familie,  // "Für Dich gehöre ich zur Familie, [Vorname]!" (siezt, Vorname)
}

class RelationshipStyleStore {
  static const String hiveKey = 'relationship_style';

  static RelationshipStyle load() {
    final box = Hive.box('einstellungen');
    final raw = box.get(hiveKey, defaultValue: 'vorname') as String;
    return RelationshipStyle.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => RelationshipStyle.vorname,
    );
  }

  static void save(RelationshipStyle style) {
    Hive.box('einstellungen').put(hiveKey, style.name);
  }

  /// true, sobald der Nutzer die Wahl im Onboarding (oder den Settings)
  /// einmal getroffen hat. Genutzt, um das 2. Onboarding-Sheet nur dann
  /// zu zeigen, wenn noch keine Wahl vorliegt.
  static bool get hasChosen => Hive.box('einstellungen').containsKey(hiveKey);
}

/// Liefert den Nachnamen aus dem gespeicherten Namensfeld — exakt dieselbe
/// Zerlegungs-Logik wie DienstplanParser._searchTerms, damit Dienstplan-
/// Erkennung und Namensfeld niemals auseinanderlaufen. Wird weiterhin für
/// die Dienstplan-Erkennung selbst benötigt (NICHT mehr für die Anrede in
/// Notifications — dort wird ausschließlich der Vorname verwendet, s.o.).
String lastNameFrom(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (trimmed.contains(',')) return parts.first;
  return parts.last;
}

/// Vorname nach derselben Konvention (Gegenstück zu lastNameFrom). Dies ist
/// der Name, der in JEDER Notification-Anrede verwendet wird, unabhängig
/// vom RelationshipStyle.
String firstNameFrom(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (trimmed.contains(',')) return parts.length > 1 ? parts[1] : '';
  return parts.first;
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION TEXTE — dünne Schicht über notification_phrases.dart.
//
// Jede Methode hier entspricht einem Notification-"Case". Sie holt sich die
// passende Phrasen-Liste aus notification_phrases.dart, wählt zufällig eine
// Variante (pick()) und setzt die Platzhalter ein. Der NotificationService
// kennt selbst keine Stil-Logik mehr und ruft nur diese Methoden auf.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationCopy {
  final String title;
  final String body;
  final String? subtitle;
  const NotificationCopy(this.title, this.body, {this.subtitle});
}

class RelationshipTexts {
  /// Liefert den passenden Anrede-Zusatz für den jeweiligen Stil — wird
  /// nur in den 3 Auswahlkarten im Onboarding direkt angezeigt, NICHT in
  /// den Notifications selbst (die formulieren ganzheitlich, s.u.).
  static String onboardingDescription(RelationshipStyle style, String fullName) {
    final vorname = firstNameFrom(fullName);
    switch (style) {
      case RelationshipStyle.bro:
        return 'Hilf mir einfach bei der Arbeit, Bro!';
      case RelationshipStyle.vorname:
        return 'Du kannst ${vorname.isEmpty ? "meinen Vornamen" : vorname} zu mir sagen!';
      case RelationshipStyle.familie:
        return vorname.isEmpty
            ? 'Für Dich gehöre ich zur Familie!'
            : 'Für Dich gehöre ich zur Familie, $vorname!';
    }
  }

  // ── CASE: Task-Reminder (Erinnerung vor einer gesetzten Frist) ───────────
  static NotificationCopy taskReminder({
    required RelationshipStyle style,
    required String taskTitle,
    required String fullName,
  }) {
    final name = firstNameFrom(fullName);
    final title = pick(phrases.taskReminderTitle(style));
    var body = pick(phrases.taskReminderBody(style));
    body = phrases.applyTask(body, taskTitle);
    body = phrases.applyName(body, name);
    return NotificationCopy(title, body);
  }

  // ── CASE: Aufgabe ist heute fällig ────────────────────────────────────────
  static NotificationCopy taskDueToday({
    required RelationshipStyle style,
    required String taskTitle,
    required String fullName,
  }) {
    final name = firstNameFrom(fullName);
    final title = pick(phrases.taskDueTodayTitle(style));
    var body = pick(phrases.taskDueTodayBody(style));
    body = phrases.applyTask(body, taskTitle);
    body = phrases.applyName(body, name);
    return NotificationCopy(title, body);
  }

  // ── CASE: Aufgabe ist überfällig ──────────────────────────────────────────
  static NotificationCopy taskOverdue({
    required RelationshipStyle style,
    required String taskTitle,
    required String fullName,
  }) {
    final name = firstNameFrom(fullName);
    final title = pick(phrases.taskOverdueTitle(style));
    var body = pick(phrases.taskOverdueBody(style));
    body = phrases.applyTask(body, taskTitle);
    body = phrases.applyName(body, name);
    return NotificationCopy(title, body);
  }

  // ── CASE: Aufgabe weiterhin dringend (wiederkehrend, alle 6h) ────────────
  static NotificationCopy taskUrgentRecurring({
    required RelationshipStyle style,
    required String taskTitle,
    required String fullName,
  }) {
    final name = firstNameFrom(fullName);
    final title = pick(phrases.taskUrgentRecurringTitle(style));
    var body = pick(phrases.taskUrgentRecurringBody(style));
    body = phrases.applyTask(body, taskTitle);
    body = phrases.applyName(body, name);
    return NotificationCopy(title, body);
  }

  // ── CASE: Tagesvorschau — Begrüßung + Subtitle + Dienst + Notiz-Hinweis
  // + Wetter + Aufgaben, alles stilabhängig formuliert.
  //
  // `hasShift`/`isFree`/`shiftCode` beschreiben den Dienst am Tag.
  // `hasNote` true, wenn eine Notiz für den Tag hinterlegt ist.
  // `weatherCategory`/`weatherTempC` — null, wenn kein Wetter verfügbar ist
  // (z.B. kein Netz) — die Zeile entfällt dann einfach.
  // `dueTodayCount`/`dueTodayTaskTitle`/`otherOpenCount` — siehe
  // notification_phrases.taskLine() für die genaue Fallunterscheidung.
  static NotificationCopy dailyOverview({
    required RelationshipStyle style,
    required String fullName,
    required bool hasShift,
    required bool isFree,
    String? shiftCode,
    required bool hasNote,
    WeatherCategory? weatherCategory,
    double? weatherTempC,
    required int dueTodayCount,
    String? dueTodayTaskTitle,
    required int otherOpenCount,
  }) {
    final name = firstNameFrom(fullName);

    final title = phrases.applyName(pick(phrases.greeting(style)), name);
    final subtitleText = pick(phrases.subtitle(style));

    final lines = <String>[];

    // 1) Dienst
    var shiftLine = pick(phrases.shiftLine(style, hasShift: hasShift, isFree: isFree));
    if (hasShift && !isFree && shiftCode != null) {
      shiftLine = phrases.applyShift(shiftLine, shiftCode);
    }
    shiftLine = phrases.applyName(shiftLine, name);
    lines.add(shiftLine);

    // 2) Notiz-Hinweis (nur falls vorhanden)
    if (hasNote) {
      lines.add(pick(phrases.noteHintLine(style)));
    }

    // 3) Wetter (nur falls Daten verfügbar)
    if (weatherCategory != null && weatherTempC != null) {
      final tempStr = '${weatherTempC.round()}°';
      var weatherLine = pick(phrases.weatherLine(style, weatherCategory));
      weatherLine = phrases.applyTemp(weatherLine, tempStr);
      lines.add(weatherLine);
    }

    // 4) Aufgaben
    final taskOptions = phrases.taskLine(
      style,
      dueTodayCount: dueTodayCount,
      otherOpenCount: otherOpenCount,
    );
    if (taskOptions != null) {
      var taskLineText = pick(taskOptions);
      if (dueTodayCount == 1 && dueTodayTaskTitle != null) {
        taskLineText = phrases.applyTask(taskLineText, dueTodayTaskTitle);
      }
      if (dueTodayCount > 1) {
        taskLineText = phrases.applyCount(taskLineText, dueTodayCount);
      }
      lines.add(taskLineText);
    }

    return NotificationCopy(title, lines.join('\n'), subtitle: subtitleText);
  }
}