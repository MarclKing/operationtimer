// ─────────────────────────────────────────────────────────────────────────────
// SPOKEN TASK PARSER v2 — Erweiterte, robuste Heuristik zur Umwandlung von
// transkribiertem Freitext in strukturierte Aufgaben.
//
// NEU in v2:
//  • ~40 neue Trigger-Phrasen (Frage-Form, Selbstgespräch, App-direkt, …)
//  • Wiederholungs-Muster: "jeden Montag", "jede Woche", "täglich"
//  • Priorität: "dringend", "wichtig", "asap", "so schnell wie möglich"
//  • Dauer-Angaben: "für 2 Stunden", "ca. 30 Minuten"
//  • Uhrzeiten: "gegen 10", "gegen Mittag/Abend/Morgen", "morgens", "abends",
//    "nachmittags", "mittags", Zeitspannen "von 9 bis 11"
//  • Robustere Titel-Bereinigung: mehr Füllwörter am Rand
//  • Neue Monate: Abkürzungen mit Punkt ("jan.", "feb.")
//  • Wochentage mit Großschreibung (Sprachvarianzen aus STT)
//  • Kein leerer Titel — Fallback auf sinnvollen Ausschnitt
// ─────────────────────────────────────────────────────────────────────────────

class ParsedSpokenTask {
  final String title;
  final DateTime? date;
  final DateTimeComponents? time;
  final DateTimeComponents? endTime;   // NEU: Zeitspannen "von X bis Y"
  final RecurrenceRule? recurrence;   // NEU: Wiederholungen
  final TaskPriority priority;        // NEU: dringend / normal
  final Duration? estimatedDuration; // NEU: "für 2 Stunden"
  final String rawText;

  const ParsedSpokenTask({
    required this.title,
    required this.rawText,
    this.date,
    this.time,
    this.endTime,
    this.recurrence,
    this.priority = TaskPriority.normal,
    this.estimatedDuration,
  });

  DateTime? get combinedDateTime {
    if (date == null && time == null) return null;
    final d = date ?? DateTime.now();
    if (time == null) return DateTime(d.year, d.month, d.day);
    return DateTime(d.year, d.month, d.day, time!.hour, time!.minute);
  }

  bool get hasTime => time != null;
  bool get isUrgent => priority == TaskPriority.urgent;
}

enum TaskPriority { normal, urgent }

class DateTimeComponents {
  final int hour;
  final int minute;
  const DateTimeComponents(this.hour, this.minute);

  @override
  String toString() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class RecurrenceRule {
  final RecurrenceFrequency frequency;
  final int? weekday; // DateTime.monday … DateTime.sunday, oder null für täglich/wöchentlich
  const RecurrenceRule(this.frequency, {this.weekday});
}

enum RecurrenceFrequency { daily, weekly, monthly }

// ─────────────────────────────────────────────────────────────────────────────

class SpokenTaskParser {
  SpokenTaskParser._();

  // ── Wochentage ──────────────────────────────────────────────────────────────
  static const _weekdays = {
    'montag': DateTime.monday,
    'dienstag': DateTime.tuesday,
    'mittwoch': DateTime.wednesday,
    'donnerstag': DateTime.thursday,
    'freitag': DateTime.friday,
    'samstag': DateTime.saturday,
    'sonnabend': DateTime.saturday,
    'sonntag': DateTime.sunday,
    // Kurzformen aus STT-Transkripten
    'mo': DateTime.monday,
    'di': DateTime.tuesday,
    'mi': DateTime.wednesday,
    'do': DateTime.thursday,
    'fr': DateTime.friday,
    'sa': DateTime.saturday,
    'so': DateTime.sunday,
  };

  // ── Monate ──────────────────────────────────────────────────────────────────
  static const _months = {
    'januar': 1, 'jan': 1, 'jan.': 1,
    'februar': 2, 'feb': 2, 'feb.': 2,
    'märz': 3, 'maerz': 3, 'mär': 3, 'mär.': 3,
    'april': 4, 'apr': 4, 'apr.': 4,
    'mai': 5,
    'juni': 6, 'jun': 6, 'jun.': 6,
    'juli': 7, 'jul': 7, 'jul.': 7,
    'august': 8, 'aug': 8, 'aug.': 8,
    'september': 9, 'sep': 9, 'sep.': 9, 'sept': 9,
    'oktober': 10, 'okt': 10, 'okt.': 10,
    'november': 11, 'nov': 11, 'nov.': 11,
    'dezember': 12, 'dez': 12, 'dez.': 12,
  };

  // ── Trigger-Phrasen ──────────────────────────────────────────────────────────
  // Geordnet von spezifisch → allgemein; erste Übereinstimmung gewinnt.
  static final List<RegExp> _triggerPhrases = [
    // ── Klassische Erinnerungs-Befehle ──
    RegExp(r'^erinnere\s+mich\s+(daran[,\s]*)?(bitte\s+)?(dass\s+|an\s+)?', caseSensitive: false),
    RegExp(r'^kannst\s+du\s+mich\s+(daran\s+)?erinnern[,\s]*(bitte\s+)?(dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^ich\s+brauche\s+eine\s+erinnerung\s+(an\s+|für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^setz\s+(mir\s+)?eine?\s+erinnerung\s+(für\s+|an\s+)?', caseSensitive: false),
    RegExp(r'^stell\s+(mir\s+)?eine?\s+erinnerung\s+(für\s+|auf\s+|ein\s+)?', caseSensitive: false),
    RegExp(r'^leg\s+(mir\s+)?eine?\s+erinnerung\s+an\s+', caseSensitive: false),

    // ── Aufgaben-Befehle ──
    RegExp(r'^neue?\s+(aufgabe|todo|aufgabe|task)\s*(anlegen\s+)?(für\s+)?:?\s*', caseSensitive: false),
    RegExp(r'^(erstell|erzeuge|mach)\s+(mir\s+)?(eine?\s+)?(neue?\s+)?(aufgabe|todo|task|eintrag)\s*(für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^(füg|füge)\s+(eine?\s+)?(neue?\s+)?(aufgabe|todo|task)\s+hinzu[:\s]*(für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^trag\s+(mir\s+)?ein[:\s]*(dass\s+)?', caseSensitive: false),
    RegExp(r'^(notiere|notier)\s+(dir\s+|bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^(schreib|schreibe)\s+(dir\s+|bitte\s+)?(das\s+)?auf[:\s]*(dass\s+)?', caseSensitive: false),
    RegExp(r'^(schreib|schreibe)\s+(bitte\s+)?(auf\s+)?(dass\s+|folgendes[:\s]+)?', caseSensitive: false),
    RegExp(r'^(halt|halte)\s+(das\s+|es\s+)?fest[:\s]*(dass\s+)?', caseSensitive: false),
    RegExp(r'^merk\s+dir\s+(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^(speicher|speichere)\s+(das\s+|bitte\s+)?(ab\s*)?[:\s]*(dass\s+)?', caseSensitive: false),

    // ── Selbstgespräch / innerer Monolog ──
    RegExp(r'^ich\s+(muss|müss?te|sollte|will|möchte|wollte)\s+(noch\s+|unbedingt\s+|dringend\s+|heute\s+|morgen\s+)?', caseSensitive: false),
    RegExp(r'^ich\s+hab(e)?\s+(noch\s+)?nicht\s+vergessen\s+(zu\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^nicht\s+vergessen[:\s]*(dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^vergiss\s+nicht[,\s]*(bitte\s+)?(dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^auf\s+keinen\s+fall\s+vergessen[:\s]*(zu\s+)?', caseSensitive: false),
    RegExp(r'^denk\s+(daran|dran)[,\s]*(bitte\s+)?(dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^das\s+darf\s+ich\s+nicht\s+vergessen[:\s]*(zu\s+)?', caseSensitive: false),
    RegExp(r'^unbedingt\s+(noch\s+|dringend\s+)?', caseSensitive: false),

    // ── App direkt ansprechen ──
    RegExp(r'^(hey\s+)?app[,:]?\s*(bitte\s+)?', caseSensitive: false),
    RegExp(r'^(hey\s+)?assistant[,:]?\s*(bitte\s+)?', caseSensitive: false),
    RegExp(r'^(ok|okay|hey)\s+(google|siri|alexa|app)[,:]?\s*(bitte\s+)?', caseSensitive: false),
    RegExp(r'^(bitte\s+)?(trag\s+ein|notier|merk|erinner\s+mich)\s*[,:]?\s*(dass\s+|zu\s+|an\s+)?', caseSensitive: false),

    // ── Kalender-/Termin-Sprache ──
    RegExp(r'^(trag|block|reservier)\s+(mir\s+)?(den\s+|einen?\s+)?(termin|slot|zeitraum|zeit|tag|abend|morgen)\s+(ein\s+)?(für\s+|am\s+)?', caseSensitive: false),
    RegExp(r'^(ich\s+hab(e)?\s+|habe\s+)?(einen?\s+)?termin\s+(für|am|am)\s+', caseSensitive: false),
    RegExp(r'^termin\s*[:\-]?\s*', caseSensitive: false),

    // ── Frage-Form ──
    RegExp(r'^(kannst|könntest)\s+du\s+(bitte\s+)?(mir\s+)?(eine?\s+)?(aufgabe|erinnerung|todo|notiz)\s+(erstellen|anlegen|hinzufügen|eintragen)\s*(dass\s+|für\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^(kannst|könntest)\s+du\s+(bitte\s+)?aufschreiben[,\s]*(dass\s+)?', caseSensitive: false),
    RegExp(r'^(wäre\s+es\s+möglich|bitte)\s*(notier|merk|schreib)\s*', caseSensitive: false),

    // ── Kurzform ──
    RegExp(r'^todo[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^aufgabe[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^notiz[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^task[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^reminder[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),

    // ── Wiederholung am Anfang (damit "jeden Montag …" nicht als Titel landet) ──
    // (Wiederholung wird separat geparst, aber die Phrase hier wird nicht entfernt —
    //  sie wird NACH der Wiederholungserkennung bereinigt. Deshalb kein Eintrag hier.)
  ];

  // ── Priorität-Phrasen ────────────────────────────────────────────────────────
  static final _priorityUrgent = RegExp(
    r'\b(dringend|dringendst|asap|so\s+schnell\s+wie\s+möglich|sofort|wichtig|prio\s*1|priorität\s*1|notfall|eilig)\b',
    caseSensitive: false,
  );

  // ── Wiederholungs-Phrasen ────────────────────────────────────────────────────
  static final List<(RegExp, RecurrenceRule)> _recurrencePatterns = [
    (RegExp(r'\btäglich\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.daily)),
    (RegExp(r'\bjeden\s+tag\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.daily)),
    (RegExp(r'\bjede\s+woche\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.weekly)),
    (RegExp(r'\bwöchentlich\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.weekly)),
    (RegExp(r'\bmonatlich\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.monthly)),
    (RegExp(r'\bjeden\s+monat\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.monthly)),
    // "jeden Montag" etc. werden dynamisch unten geparst
  ];

  // ── Dauer-Phrasen ────────────────────────────────────────────────────────────
  static final _durationPattern = RegExp(
    r'\b(für|ca\.?|circa|etwa|ungefähr)\s+(\d+(?:[.,]\d+)?)\s*(stunden?|std\.?|h\b|minuten?|min\.?)\b',
    caseSensitive: false,
  );

  // ── Füllwörter am Rand nach der Bereinigung ──────────────────────────────────
  static final List<RegExp> _fillerEdges = [
    RegExp(r'^(dass|daran|dran|an den?|an die|an das|zu dem|zum|zur|zu|an)\s+', caseSensitive: false),
    RegExp(r'\s+(daran|dran|bitte|dass)$', caseSensitive: false),
    RegExp(r'^(bitte\s+)+', caseSensitive: false),
    RegExp(r'^(noch\s+)+', caseSensitive: false),
    RegExp(r'^(mal\s+)+', caseSensitive: false),
    RegExp(r'\s*\.\s*$', caseSensitive: false),
  ];

  // ────────────────────────────────────────────────────────────────────────────
  // HAUPTFUNKTION
  // ────────────────────────────────────────────────────────────────────────────
  static ParsedSpokenTask parse(String rawText) {
    final original = rawText.trim();
    String w = original.toLowerCase();

    // 1) Trigger-Phrase am Anfang entfernen
    for (final trigger in _triggerPhrases) {
      final m = trigger.firstMatch(w);
      if (m != null) {
        w = w.substring(m.end);
        break;
      }
    }

    // 2) Priorität erkennen & entfernen
    final priority = _priorityUrgent.hasMatch(w) ? TaskPriority.urgent : TaskPriority.normal;
    if (priority == TaskPriority.urgent) {
      w = w.replaceAll(_priorityUrgent, ' ');
    }

    // 3) Dauer erkennen & entfernen
    Duration? estimatedDuration;
    final durMatch = _durationPattern.firstMatch(w);
    if (durMatch != null) {
      final amount = double.tryParse((durMatch.group(2) ?? '').replaceAll(',', '.')) ?? 0;
      final unit = (durMatch.group(3) ?? '').toLowerCase();
      if (unit.startsWith('h') || unit.startsWith('std') || unit.startsWith('stu')) {
        estimatedDuration = Duration(minutes: (amount * 60).round());
      } else {
        estimatedDuration = Duration(minutes: amount.round());
      }
      w = w.replaceRange(durMatch.start, durMatch.end, ' ');
    }

    // 4) Wiederholung erkennen & entfernen
    RecurrenceRule? recurrence;
    for (final (pattern, rule) in _recurrencePatterns) {
      if (pattern.hasMatch(w)) {
        recurrence = rule;
        w = w.replaceAll(pattern, ' ');
        break;
      }
    }
    // "jeden Montag" etc.
    if (recurrence == null) {
      for (final entry in _weekdays.entries) {
        final jedenPattern = RegExp('\\bjeden\\s+${entry.key}\\b', caseSensitive: false);
        if (jedenPattern.hasMatch(w)) {
          recurrence = RecurrenceRule(RecurrenceFrequency.weekly, weekday: entry.value);
          w = w.replaceAll(jedenPattern, ' ');
          break;
        }
      }
    }

    // 5) Explizites Datum parsen
    DateTime? date;

    // 5a) "am 15. März 2026" / "15. März"
    final explicitMonthNameMatch = RegExp(
      r'(?:am\s+)?(\d{1,2})\.?\s*(januar|jänner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan\.?|feb\.?|mär\.?|apr\.?|jun\.?|jul\.?|aug\.?|sep\.?|sept\.?|okt\.?|nov\.?|dez\.?)\s*\.?\s*(\d{4})?',
      caseSensitive: false,
    ).firstMatch(w);

    // 5b) "am 15.3." / "15.3.2026"
    final explicitDateMatch = RegExp(
      r'(?:am\s+)?(\d{1,2})\.\s*(\d{1,2})\.?\s*(\d{4})?',
    ).firstMatch(w);

    if (explicitMonthNameMatch != null) {
      final day = int.tryParse(explicitMonthNameMatch.group(1) ?? '');
      final rawMonth = (explicitMonthNameMatch.group(2) ?? '').replaceAll('.', '').trim().toLowerCase();
      final month = _months[rawMonth];
      final year = int.tryParse(explicitMonthNameMatch.group(3) ?? '') ?? DateTime.now().year;
      if (day != null && month != null) {
        date = DateTime(year, month, day);
        w = w.replaceRange(explicitMonthNameMatch.start, explicitMonthNameMatch.end, ' ');
      }
    } else if (explicitDateMatch != null && explicitDateMatch.group(2) != null) {
      final day = int.tryParse(explicitDateMatch.group(1) ?? '');
      final month = int.tryParse(explicitDateMatch.group(2) ?? '');
      final year = int.tryParse(explicitDateMatch.group(3) ?? '') ?? DateTime.now().year;
      if (day != null && month != null && month >= 1 && month <= 12) {
        date = DateTime(year, month, day);
        w = w.replaceRange(explicitDateMatch.start, explicitDateMatch.end, ' ');
      }
    }

    // 6) Relative Tagesangaben
    if (date == null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (RegExp(r'\bübermorgen\b', caseSensitive: false).hasMatch(w)) {
        date = today.add(const Duration(days: 2));
        w = w.replaceAll(RegExp(r'\bübermorgen\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bmorgen früh\b', caseSensitive: false).hasMatch(w)) {
        date = today.add(const Duration(days: 1));
        w = w.replaceAll(RegExp(r'\bmorgen früh\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bmorgen\b', caseSensitive: false).hasMatch(w)) {
        date = today.add(const Duration(days: 1));
        w = w.replaceAll(RegExp(r'\bmorgen\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bheute\s+(abend|nacht)\b', caseSensitive: false).hasMatch(w)) {
        date = today;
        w = w.replaceAll(RegExp(r'\bheute\s+(abend|nacht)\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bheute\b', caseSensitive: false).hasMatch(w)) {
        date = today;
        w = w.replaceAll(RegExp(r'\bheute\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bdiesen\s+freitag\b|\bdiesen\s+montag\b|\bdiesen\s+\w+tag\b', caseSensitive: false).hasMatch(w)) {
        // "diesen Montag" → nächster Wochentag diese Woche (oder heute)
        for (final entry in _weekdays.entries) {
          final p = RegExp('\\bdiesen\\s+${entry.key}\\b', caseSensitive: false);
          final m = p.firstMatch(w);
          if (m != null) {
            int diff = (entry.value - today.weekday) % 7;
            date = today.add(Duration(days: diff));
            w = w.replaceRange(m.start, m.end, ' ');
            break;
          }
        }
      } else if (RegExp(r'\bnächste\s+woche\b', caseSensitive: false).hasMatch(w)) {
        date = today.add(Duration(days: 7 - today.weekday + 1)); // nächster Montag
        w = w.replaceAll(RegExp(r'\bnächste\s+woche\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bdieses\s+wochenende\b|\bam\s+wochenende\b', caseSensitive: false).hasMatch(w)) {
        int daysUntilSat = (DateTime.saturday - today.weekday) % 7;
        if (daysUntilSat == 0) daysUntilSat = 7;
        date = today.add(Duration(days: daysUntilSat));
        w = w.replaceAll(RegExp(r'\b(dieses\s+wochenende|am\s+wochenende)\b', caseSensitive: false), ' ');
      } else {
        // "in X Tagen" / "in einer Woche" / "in X Wochen"
        final inDaysMatch = RegExp(r'\bin\s+(\d+)\s+tagen?\b', caseSensitive: false).firstMatch(w);
        final inWeeksMatch = RegExp(r'\bin\s+(einer|\d+)\s+woch\w+\b', caseSensitive: false).firstMatch(w);
        final inMonthsMatch = RegExp(r'\bin\s+(einem?|\d+)\s+monat\w*\b', caseSensitive: false).firstMatch(w);

        if (inDaysMatch != null) {
          final days = int.tryParse(inDaysMatch.group(1) ?? '');
          if (days != null) {
            date = today.add(Duration(days: days));
            w = w.replaceRange(inDaysMatch.start, inDaysMatch.end, ' ');
          }
        } else if (inWeeksMatch != null) {
          final raw = inWeeksMatch.group(1) ?? '1';
          final weeks = raw == 'einer' ? 1 : (int.tryParse(raw) ?? 1);
          date = today.add(Duration(days: weeks * 7));
          w = w.replaceRange(inWeeksMatch.start, inWeeksMatch.end, ' ');
        } else if (inMonthsMatch != null) {
          final raw = inMonthsMatch.group(1) ?? '1';
          final months = (raw == 'einem' || raw == 'eine' || raw == 'einer') ? 1 : (int.tryParse(raw) ?? 1);
          final d = DateTime(today.year, today.month + months, today.day);
          date = d;
          w = w.replaceRange(inMonthsMatch.start, inMonthsMatch.end, ' ');
        } else {
          // Wochentage: "nächsten Montag", "am Montag", einfach "Montag"
          for (final entry in _weekdays.entries) {
            final pattern = RegExp(
              '\\b(nächsten?\\s+|naechsten?\\s+|am\\s+)?${entry.key}\\b',
              caseSensitive: false,
            );
            final m = pattern.firstMatch(w);
            if (m != null) {
              final forceNextWeek = m.group(1) != null &&
                  (m.group(1)!.contains('nächst') || m.group(1)!.contains('naechst'));
              int diff = (entry.value - today.weekday) % 7;
              if (diff == 0 && forceNextWeek) diff = 7;
              if (diff < 0) diff += 7;
              date = today.add(Duration(days: diff));
              w = w.replaceRange(m.start, m.end, ' ');
              break;
            }
          }
        }
      }
    }

    // 7) Uhrzeit parsen
    DateTimeComponents? time;
    DateTimeComponents? endTime;

    // 7a) Zeitspanne "von 9 bis 11" / "von 9 Uhr bis 11 Uhr"
    final vonBisMatch = RegExp(
      r'\bvon\s+(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?\s+bis\s+(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (vonBisMatch != null) {
      final h1 = int.tryParse(vonBisMatch.group(1) ?? '');
      final m1 = int.tryParse(vonBisMatch.group(2) ?? '0') ?? 0;
      final h2 = int.tryParse(vonBisMatch.group(3) ?? '');
      final m2 = int.tryParse(vonBisMatch.group(4) ?? '0') ?? 0;
      if (h1 != null && h2 != null) {
        time = DateTimeComponents(_toPlausibleHour(h1), m1);
        endTime = DateTimeComponents(_toPlausibleHour(h2), m2);
        w = w.replaceRange(vonBisMatch.start, vonBisMatch.end, ' ');
      }
    }

    // 7b) Tageszeiten als Worte
    if (time == null) {
      final tageszeitMatch = RegExp(
        r'\b(morgens?|früh|vormittags?|mittags?|nachmittags?|abends?|nachts?|gegen\s+mitternacht|mitternacht)\b',
        caseSensitive: false,
      ).firstMatch(w);
      if (tageszeitMatch != null) {
        final tz = tageszeitMatch.group(1)!.toLowerCase();
        int h;
        if (tz.startsWith('morgen') || tz == 'früh') h = 8;
        else if (tz.startsWith('vormittag')) h = 10;
        else if (tz.startsWith('mittag')) h = 12;
        else if (tz.startsWith('nachmittag')) h = 15;
        else if (tz.startsWith('abend')) h = 19;
        else if (tz.startsWith('nacht')) h = 21;
        else h = 0; // Mitternacht
        time = DateTimeComponents(h, 0);
        w = w.replaceRange(tageszeitMatch.start, tageszeitMatch.end, ' ');
      }
    }

    // 7c) "gegen 10 (Uhr)"
    if (time == null) {
      final gegenMatch = RegExp(
        r'\bgegen\s+(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?\b',
        caseSensitive: false,
      ).firstMatch(w);
      if (gegenMatch != null) {
        final h = int.tryParse(gegenMatch.group(1) ?? '');
        final m = int.tryParse(gegenMatch.group(2) ?? '0') ?? 0;
        if (h != null) {
          time = DateTimeComponents(_toPlausibleHour(h), m);
          w = w.replaceRange(gegenMatch.start, gegenMatch.end, ' ');
        }
      }
    }

    // 7d) Deutsche Phrasen: halb, viertel nach/vor, kurz nach/vor, punkt
    if (time == null) {
      final halbMatch = RegExp(r'\bhalb\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
      final viertelNachMatch = RegExp(r'\bviertel\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
      final viertelVorMatch = RegExp(r'\bviertel\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
      final dreiViertelMatch = RegExp(r'\bdreiviertel\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
      final kurzNachMatch = RegExp(r'\bkurz\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
      final kurzVorMatch = RegExp(r'\bkurz\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
      final punktMatch = RegExp(r'\bpunkt\s+(\d{1,2})\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
      final genauMatch = RegExp(r'\bgenau\s+(\d{1,2})\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
      final umUhrMatch = RegExp(
        r'\bum\s+(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?(?:\s+(\d{2}))?\b',
        caseSensitive: false,
      ).firstMatch(w);

      int? hour;
      int minute = 0;
      RegExpMatch? consumed;

      if (dreiViertelMatch != null) {
        final h = int.tryParse(dreiViertelMatch.group(1) ?? '');
        if (h != null) { hour = _toPlausibleHour(h - 1); minute = 45; consumed = dreiViertelMatch; }
      } else if (halbMatch != null) {
        final h = int.tryParse(halbMatch.group(1) ?? '');
        if (h != null) { hour = _toPlausibleHour(h - 1); minute = 30; consumed = halbMatch; }
      } else if (viertelNachMatch != null) {
        final h = int.tryParse(viertelNachMatch.group(1) ?? '');
        if (h != null) { hour = _toPlausibleHour(h); minute = 15; consumed = viertelNachMatch; }
      } else if (viertelVorMatch != null) {
        final h = int.tryParse(viertelVorMatch.group(1) ?? '');
        if (h != null) { hour = _toPlausibleHour(h - 1); minute = 45; consumed = viertelVorMatch; }
      } else if (kurzNachMatch != null) {
        final h = int.tryParse(kurzNachMatch.group(1) ?? '');
        if (h != null) { hour = _toPlausibleHour(h); minute = 5; consumed = kurzNachMatch; }
      } else if (kurzVorMatch != null) {
        final h = int.tryParse(kurzVorMatch.group(1) ?? '');
        if (h != null) {
          hour = _toPlausibleHour(h);
          minute = 55;
          if (hour! > 0) hour = hour - 1;
          consumed = kurzVorMatch;
        }
      } else if (punktMatch != null) {
        final h = int.tryParse(punktMatch.group(1) ?? '');
        if (h != null) { hour = _toPlausibleHour(h); minute = 0; consumed = punktMatch; }
      } else if (genauMatch != null) {
        final h = int.tryParse(genauMatch.group(1) ?? '');
        if (h != null) { hour = _toPlausibleHour(h); minute = 0; consumed = genauMatch; }
      } else if (umUhrMatch != null) {
        final h = int.tryParse(umUhrMatch.group(1) ?? '');
        final m = int.tryParse(umUhrMatch.group(2) ?? umUhrMatch.group(3) ?? '0') ?? 0;
        if (h != null) { hour = _toPlausibleHour(h); minute = m; consumed = umUhrMatch; }
      }

      if (hour != null) {
        time = DateTimeComponents(hour.clamp(0, 23), minute.clamp(0, 59));
        if (consumed != null) {
          w = w.replaceRange(consumed.start, consumed.end, ' ');
        }
      }
    }

    // 8) Titel bereinigen
    String title = w;

    // Anhängende Zeit-Präpositionen, die vom Datum/Zeit-Parser übrig blieben
    title = title.replaceAll(RegExp(r'\bum\b', caseSensitive: false), ' ');
    title = title.replaceAll(RegExp(r'\bam\b', caseSensitive: false), ' ');
    title = title.replaceAll(RegExp(r'\bvon\b', caseSensitive: false), ' ');
    title = title.replaceAll(RegExp(r'\bbis\b', caseSensitive: false), ' ');
    title = title.replaceAll(RegExp(r'\bgegen\b', caseSensitive: false), ' ');

    for (final filler in _fillerEdges) {
      title = title.replaceAll(filler, ' ');
    }

    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    } else {
      // Fallback: Originaltitel ohne Trigger bereinigt zurückgeben
      title = original;
    }

    return ParsedSpokenTask(
      title: title,
      rawText: original,
      date: date,
      time: time,
      endTime: endTime,
      recurrence: recurrence,
      priority: priority,
      estimatedDuration: estimatedDuration,
    );
  }

  /// Konvertiert 12h-Werte (1–7) in plausible 24h-Werte (13–19).
  /// Werte >= 8 oder 0 werden unverändert durchgereicht.
  static int _toPlausibleHour(int h) {
    if (h < 0) h += 12;
    if (h >= 1 && h <= 7) return h + 12;
    return h;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REFERENZ-TESTS (als Kommentare — direkt in eine test/ Datei kopierbar)
// ─────────────────────────────────────────────────────────────────────────────
//
// void main() {
//   final cases = [
//     // ── Trigger-Phrasen ──
//     'Erinnere mich morgen um 14 Uhr an den TÜV-Termin',
//     'Kannst du mich daran erinnern, die Steuererklärung abzugeben?',
//     'Ich brauche eine Erinnerung an meinen Arzttermin am 15. März',
//     'Stell mir eine Erinnerung für morgen früh ein: Zahnarzt anrufen',
//     'Leg mir eine Erinnerung an das Meeting nächsten Montag um 9 Uhr an',
//     'Setz eine Erinnerung für Freitag – Elternabend',
//     'Neue Aufgabe: Bericht bis Ende der Woche fertigstellen',
//     'Neue Aufgabe anlegen für übermorgen: Präsentation vorbereiten',
//     'Erstell mir ein Todo: Kühlschrank abtauen',
//     'Füge eine Aufgabe hinzu: Urlaub buchen',
//     'Trag ein: Sporttasche packen morgen Abend',
//     'Notiere, dass ich noch Milch kaufen muss',
//     'Notier bitte: Geburtstag von Mama ist am 3. April',
//     'Schreib auf: Rückruf bei der Bank wegen Kredit',
//     'Schreibe mir bitte auf: Meeting-Protokoll schreiben',
//     'Halt fest: Konzerttickets kaufen',
//     'Merk dir, dass das Auto in die Werkstatt muss',
//     'Speicher ab: Passwort für neuen Server',
//     // ── Selbstgespräch ──
//     'Ich muss morgen die Präsentation fertigmachen',
//     'Ich sollte noch das Paket zur Post bringen',
//     'Ich möchte nächsten Montag mit dem Sport anfangen',
//     'Nicht vergessen: Reisekrankenversicherung verlängern',
//     'Vergiss nicht, die Katze zu füttern heute Abend',
//     'Auf keinen Fall vergessen: Führerschein erneuern',
//     'Denk daran, dass der Vertrag am 1. Juli ausläuft',
//     'Das darf ich nicht vergessen: Hochzeitsgeschenk kaufen',
//     'Unbedingt noch: Strom-Ablesetermin bestätigen',
//     // ── App ansprechen ──
//     'Hey App: Termin mit Dr. Müller am Donnerstag um 11 Uhr',
//     'OK Google, erinnere mich morgen an die Medikamente',
//     'Bitte eintragen: Teambesprechung Freitag 10 Uhr',
//     // ── Kalender ──
//     'Trag den Termin ein: Elternabend am 22. Januar um halb 8',
//     'Block mir Montag von 9 bis 11 Uhr für das Brainstorming',
//     'Termin: Physiotherapie nächsten Dienstag um viertel nach 3',
//     // ── Frage-Form ──
//     'Könntest du mir bitte eine Aufgabe erstellen: Wohnung aufräumen?',
//     'Kannst du aufschreiben, dass ich noch die Heizung warten lassen muss?',
//     // ── Kurzform ──
//     'Todo: Angebot für Kunde Müller schreiben',
//     'Aufgabe: Stromzähler ablesen bis Ende Monat',
//     'Notiz: Idee für neues Feature – Dark Mode',
//     // ── Priorität ──
//     'Dringend: Serverabsturz beheben!',
//     'ASAP: Meeting-Vorbereitung für 14 Uhr',
//     'Wichtig – Angebot abschicken bis heute Mittag',
//     // ── Wiederholung ──
//     'Täglich: Meditation 10 Minuten',
//     'Jeden Tag: Vokabeln lernen',
//     'Jeden Montag um 9: Wochenmeeting',
//     'Jede Woche: Einkaufsliste erstellen',
//     // ── Dauer ──
//     'Für 2 Stunden: Projekt-Doku schreiben morgen Nachmittag',
//     'Ca. 30 Minuten: Mails beantworten',
//     // ── Zeitspanne ──
//     'Meeting von 9 bis 11 Uhr morgen',
//     'Sportstunde von 18 bis 19 Uhr jeden Dienstag',
//     // ── Tageszeiten ──
//     'Morgens: Vitamintabletten nehmen',
//     'Heute Abend: Film mit Sarah schauen',
//     'Nachmittags um 3: Zahnarzt',
//     'Gegen Mittag: Lieferdienst kommt',
//     // ── Uhrzeiten ──
//     'Zahnarzt morgen um 8 Uhr 30',
//     'Halb 3 Physiotherapie',
//     'Viertel vor 5: Kinder abholen',
//     'Viertel nach 9 Frühstück mit Chef',
//     'Dreiviertel 10 Uhr: Videokonferenz',
//     'Kurz nach 10: Paketbote erwartet',
//     'Punkt 12: Mittagessen mit Oma',
//     'Gegen 15 Uhr: Abholung Flughafen',
//     // ── Datum-Varianten ──
//     'Am 15.3. Zahnarzt',
//     'Am 15. März 2026 Urlaub buchen',
//     'In 3 Tagen: Auto zur Inspektion',
//     'In einer Woche: Miete überweisen',
//     'Nächste Woche Montag: Steuerberatung',
//     'Am Wochenende: Keller aufräumen',
//     'Übermorgen um 10 Uhr: Videokonferenz mit New York',
//   ];
//
//   for (final c in cases) {
//     final r = SpokenTaskParser.parse(c);
//     print('IN:  $c');
//     print('OUT: title="${r.title}" date=${r.date?.toIso8601String().substring(0,10)} '
//           'time=${r.time} end=${r.endTime} rec=${r.recurrence?.frequency} '
//           'prio=${r.priority} dur=${r.estimatedDuration}');
//     print('');
//   }
// }