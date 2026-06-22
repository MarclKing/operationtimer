import 'package:hive_flutter/hive_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RELATIONSHIP STYLE
//
// Steuert die "Umgangsform", in der OpTimes mit dem Nutzer spricht —
// aktuell ausschließlich relevant für den Text von Push-Notifications.
// Wird im Onboarding (welcome_screen.dart, 2. Sheet) gesetzt und ist in den
// Einstellungen jederzeit änderbar.
//
// WICHTIG: Der Nachname für RelationshipStyle.familie wird NICHT separat
// abgefragt, sondern aus demselben Namensfeld abgeleitet, das auch für die
// Dienstplan-Erkennung genutzt wird (Hive-Key 'name'). Dort gilt exakt die
// gleiche Konvention wie in DienstplanParser._searchTerms:
//   - kein Komma im Namen  → letztes Wort = Nachname, erstes Wort = Vorname
//   - Komma im Namen       → Teil vor dem Komma = Nachname (Schreibweise
//                             "Nachname, Vorname", falls jemand das so einträgt)
// Siehe lastNameFrom() / firstNameFrom() unten — exakt dieselbe Zerlegung,
// nur als eigenständige, wiederverwendbare Helper statt privat im Parser.
// ─────────────────────────────────────────────────────────────────────────────

enum RelationshipStyle {
  bro,      // ".. hilf mir einfach bei der Arbeit, Bro"
  vorname,  // "Du kannst [Vorname] zu mir sagen"
  familie,  // "Für Dich gehöre ich zur Familie, [Nachname]!"
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
/// Zerlegungs-Logik wie DienstplanParser._searchTerms, damit Anrede und
/// Dienstplan-Erkennung niemals auseinanderlaufen.
String lastNameFrom(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (trimmed.contains(',')) return parts.first;
  return parts.last;
}

/// Vorname nach derselben Konvention (Gegenstück zu lastNameFrom).
String firstNameFrom(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (trimmed.contains(',')) return parts.length > 1 ? parts[1] : '';
  return parts.first;
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION TEXTE — zentrale Stelle für ALLE Stil-abhängigen Texte.
//
// Jeder Notification-"Case" (z.B. "Task fällig heute") bekommt hier eine
// eigene Methode, die für jeden RelationshipStyle einen passenden Titel +
// Body liefert. Neue Cases werden hier als neue Methode ergänzt — der
// NotificationService ruft nur noch diese Methoden auf und kennt selbst
// keine Stil-Logik mehr.
//
// {name} im Body wird je Case durch den Aufgaben-/Inhalt-Titel ersetzt.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationCopy {
  final String title;
  final String body;
  const NotificationCopy(this.title, this.body);
}

class RelationshipTexts {
  /// Liefert den passenden Anrede-Zusatz für den jeweiligen Stil — wird
  /// nur in den 3 Auswahlkarten im Onboarding direkt angezeigt, NICHT in
  /// den Notifications selbst (die formulieren ganzheitlich, s.u.).
  static String onboardingDescription(RelationshipStyle style, String fullName) {
    switch (style) {
      case RelationshipStyle.bro:
        return 'Hilf mir einfach bei der Arbeit, Bro!';
      case RelationshipStyle.vorname:
        final vorname = firstNameFrom(fullName);
        return 'Du kannst ${vorname.isEmpty ? "meinen Vornamen" : vorname} zu mir sagen!';
      case RelationshipStyle.familie:
        final nachname = lastNameFrom(fullName);
        return 'Für Dich gehöre ich zur Familie, ${nachname.isEmpty ? "" : nachname}!';
    }
  }

  // ── CASE: Task-Reminder (Erinnerung vor einer gesetzten Frist) ───────────
  static NotificationCopy taskReminder({
    required RelationshipStyle style,
    required String taskTitle,
    required String fullName,
  }) {
    switch (style) {
      case RelationshipStyle.bro:
        return NotificationCopy(
          '🔥 Yo, nicht vergessen!',
          '"$taskTitle" steht an, Bro — kümmer dich drum!',
        );
      case RelationshipStyle.vorname:
        final vorname = firstNameFrom(fullName);
        return NotificationCopy(
          '📌 Erinnerung',
          '${vorname.isEmpty ? "Hey" : "Hey $vorname"}, "$taskTitle" steht bald an.',
        );
      case RelationshipStyle.familie:
        final nachname = lastNameFrom(fullName);
        return NotificationCopy(
          '📌 Eine Erinnerung für Sie',
          'Werte${nachname.isEmpty ? "" : "/r"} ${nachname.isEmpty ? "" : nachname}, "$taskTitle" steht bald an.',
        );
    }
  }

  // ── CASE: Aufgabe ist heute fällig ────────────────────────────────────────
  static NotificationCopy taskDueToday({
    required RelationshipStyle style,
    required String taskTitle,
    required String fullName,
  }) {
    switch (style) {
      case RelationshipStyle.bro:
        return NotificationCopy(
          '⏰ Heute ist der Tag, Bro',
          '"$taskTitle" ist heute fällig — ran an die Sache!',
        );
      case RelationshipStyle.vorname:
        final vorname = firstNameFrom(fullName);
        return NotificationCopy(
          '⏰ Heute fällig',
          '${vorname.isEmpty ? "Denk daran" : "$vorname, denk daran"}: "$taskTitle" ist heute fällig.',
        );
      case RelationshipStyle.familie:
        final nachname = lastNameFrom(fullName);
        return NotificationCopy(
          '⏰ Fällig am heutigen Tag',
          '${nachname.isEmpty ? "Zur Erinnerung" : "Zur Erinnerung, $nachname"}: "$taskTitle" ist heute fällig.',
        );
    }
  }

  // ── CASE: Aufgabe ist überfällig ──────────────────────────────────────────
  static NotificationCopy taskOverdue({
    required RelationshipStyle style,
    required String taskTitle,
    required String fullName,
  }) {
    switch (style) {
      case RelationshipStyle.bro:
        return NotificationCopy(
          '🚨 Läuft schon, Bro!',
          '"$taskTitle" ist überfällig — schieb das nicht weiter auf!',
        );
      case RelationshipStyle.vorname:
        final vorname = firstNameFrom(fullName);
        return NotificationCopy(
          '🚨 Überfällig',
          '${vorname.isEmpty ? "Achtung" : "$vorname, Achtung"}: "$taskTitle" ist bereits überfällig.',
        );
      case RelationshipStyle.familie:
        final nachname = lastNameFrom(fullName);
        return NotificationCopy(
          '🚨 Frist bereits verstrichen',
          '${nachname.isEmpty ? "Bitte beachten Sie" : "Bitte beachten Sie, $nachname"}: "$taskTitle" ist überfällig.',
        );
    }
  }

  // ── CASE: Tägliche Zusammenfassung offener Aufgaben (optional nutzbar) ───
  static NotificationCopy dailyOpenTasksSummary({
    required RelationshipStyle style,
    required int openCount,
    required String fullName,
  }) {
    switch (style) {
      case RelationshipStyle.bro:
        return NotificationCopy(
          '📋 Dein Stand, Bro',
          openCount == 1
              ? 'Eine Aufgabe wartet noch auf dich!'
              : '$openCount Aufgaben warten noch auf dich!',
        );
      case RelationshipStyle.vorname:
        final vorname = firstNameFrom(fullName);
        return NotificationCopy(
          '📋 Offene Aufgaben',
          openCount == 1
              ? '${vorname.isEmpty ? "Du hast" : "$vorname, du hast"} noch eine offene Aufgabe.'
              : '${vorname.isEmpty ? "Du hast" : "$vorname, du hast"} noch $openCount offene Aufgaben.',
        );
      case RelationshipStyle.familie:
        final nachname = lastNameFrom(fullName);
        return NotificationCopy(
          '📋 Ihre offenen Aufgaben',
          openCount == 1
              ? '${nachname.isEmpty ? "Es liegt" : "$nachname, es liegt"} noch eine Aufgabe vor.'
              : '${nachname.isEmpty ? "Es liegen" : "$nachname, es liegen"} noch $openCount Aufgaben vor.',
        );
    }
  }

  // ── CASE: Tagesvorschau — kombiniert Dienst (aus dem Schedule) + Aufgaben
  // mit Frist am selben Tag. `dayLabel` ist z.B. "heute" oder "morgen" (für
  // die Vorabend-Vorschau), `shift` ist der Schichtcode oder null, `taskCount`
  // ist die Anzahl der für diesen Tag fälligen Aufgaben (kann 0 sein).
  static NotificationCopy dailyOverview({
    required RelationshipStyle style,
    required String fullName,
    required String dayLabel, // "heute" / "morgen"
    String? shift,
    required int taskCount,
  }) {
    final hasShift = shift != null && shift.trim().isNotEmpty;
    final hasTasks = taskCount > 0;

    // Nichts los an diesem Tag — wird nur genutzt, wenn
    // daily_overview_only_if_relevant == false.
    if (!hasShift && !hasTasks) {
      switch (style) {
        case RelationshipStyle.bro:
          return NotificationCopy('☕️ Ruhiger Tag, Bro', 'Für $dayLabel steht nichts an. Genieß die Zeit!');
        case RelationshipStyle.vorname:
          final vorname = firstNameFrom(fullName);
          return NotificationCopy(
            '☕️ Nichts geplant',
            '${vorname.isEmpty ? "Für $dayLabel steht" : "$vorname, für $dayLabel steht"} nichts an.',
          );
        case RelationshipStyle.familie:
          final nachname = lastNameFrom(fullName);
          return NotificationCopy(
            '☕️ Ein ruhiger Tag',
            '${nachname.isEmpty ? "Für $dayLabel ist" : "Für $dayLabel ist, $nachname,"} nichts vorgesehen.',
          );
      }
    }

    final shiftPart = hasShift ? 'Dienst: $shift' : null;
    final taskPart = hasTasks
        ? (taskCount == 1 ? '1 Aufgabe fällig' : '$taskCount Aufgaben fällig')
        : null;
    final combined = [shiftPart, taskPart].whereType<String>().join(' · ');

    switch (style) {
      case RelationshipStyle.bro:
        return NotificationCopy('📅 Dein Tag, Bro', 'Für $dayLabel: $combined.');
      case RelationshipStyle.vorname:
        final vorname = firstNameFrom(fullName);
        return NotificationCopy(
          '📅 Vorschau für $dayLabel',
          '${vorname.isEmpty ? "" : "$vorname: "}$combined.',
        );
      case RelationshipStyle.familie:
        final nachname = lastNameFrom(fullName);
        return NotificationCopy(
          '📅 Übersicht für $dayLabel',
          '${nachname.isEmpty ? "" : "$nachname: "}$combined.',
        );
    }
  }
}