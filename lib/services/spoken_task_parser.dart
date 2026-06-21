// ─────────────────────────────────────────────────────────────────────────────
// SPOKEN TASK PARSER v3
//
// Kernänderungen gegenüber v2:
//
//  1) DUAL-TRACK: `w` (lowercase) wird NUR zum Erkennen verwendet.
//     Alle erkannten Spannen werden als _Span(start, end) gesammelt.
//     Der Titel wird am Ende aus dem ORIGINAL-String gebaut, indem alle
//     erkannten Spannen ausgeblendet werden → STT-Großschreibung bleibt
//     vollständig erhalten ("TÜV-Termin" bleibt "TÜV-Termin").
//
//  2) Uhrzeit-Bug gefixt: "um 14 Uhr" wurde wegen der angehängten
//     Präposition "an" nicht korrekt aus dem Titel entfernt. Jetzt wird
//     die Spanne der gesamten Uhrzeit-Phrase (inkl. "um"/"gegen" etc.)
//     exakt getrackt und ausgeblendet.
//
//  3) "an den/die/das/…" nach Trigger korrekt mitentfernt, sodass
//     "Erinnere mich morgen um 14 Uhr AN DEN TÜV-Termin" sauber
//     → "TÜV-Termin" ergibt.
//
//  4) Präzisere Titel-Bereinigung: nur noch gezielte Präpositionen, die
//     nachweislich von Datum/Zeit-Parsern übrig bleiben, werden entfernt —
//     keine blinden globalen replaceAll mehr, die sinnvolle Wörter im Titel
//     killen können.
// ─────────────────────────────────────────────────────────────────────────────

class ParsedSpokenTask {
  final String title;
  final DateTime? date;
  final DateTimeComponents? time;
  final DateTimeComponents? endTime;
  final RecurrenceRule? recurrence;
  final TaskPriority priority;
  final Duration? estimatedDuration;
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
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class RecurrenceRule {
  final RecurrenceFrequency frequency;
  final int? weekday;
  const RecurrenceRule(this.frequency, {this.weekday});
}

enum RecurrenceFrequency { daily, weekly, monthly }

// ─────────────────────────────────────────────────────────────────────────────
// Hilfsdatenstruktur: eine erkannte Spanne im lowercase-String, die im
// Original ausgeblendet werden soll.
// ─────────────────────────────────────────────────────────────────────────────

class _Span {
  final int start;
  final int end;
  const _Span(this.start, this.end);
}

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
  // Alle Trigger matchen am ANFANG des Strings (lowercase).
  // NEU: Jeder Trigger endet mit einem optionalen "an den/die/das/…"-Suffix,
  // damit diese Füllwörter direkt mitgeschluckt werden.
  static final List<RegExp> _triggerPhrases = [
    // ── Erinnerung ──
    RegExp(r'^erinnere\s+mich\s+(daran[,\s]*)?(bitte\s+)?(an\s+(den\s+|die\s+|das\s+|einen?\s+|meine[nm]?\s+)?|dass\s+)?', caseSensitive: false),
    RegExp(r'^kannst\s+du\s+mich\s+(daran\s+)?erinnern[,\s]*(bitte\s+)?(an\s+(den\s+|die\s+|das\s+)?|dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^ich\s+brauche\s+eine\s+erinnerung\s+(an\s+(den\s+|die\s+|das\s+|meine[nm]?\s+)?|für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^setz\s+(mir\s+)?eine?\s+erinnerung\s+(für\s+|an\s+)?', caseSensitive: false),
    RegExp(r'^stell\s+(mir\s+)?eine?\s+erinnerung\s+(für\s+|auf\s+|ein\s+)?', caseSensitive: false),
    RegExp(r'^leg\s+(mir\s+)?eine?\s+erinnerung\s+(an\s+(den\s+|die\s+|das\s+)?)?', caseSensitive: false),
    // ── Aufgaben ──
    RegExp(r'^neue?\s+(aufgabe|todo|task)\s*(anlegen\s+)?(für\s+)?:?\s*', caseSensitive: false),
    RegExp(r'^(erstell|erzeuge|mach)\s+(mir\s+)?(eine?\s+)?(neue?\s+)?(aufgabe|todo|task|eintrag)\s*(für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^(füg|füge)\s+(eine?\s+)?(neue?\s+)?(aufgabe|todo|task)\s+hinzu[:\s]*(für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^trag\s+(mir\s+)?ein[:\s]*(dass\s+)?', caseSensitive: false),
    RegExp(r'^(notiere|notier)\s+(dir\s+|bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^(schreib|schreibe)\s+(dir\s+|bitte\s+)?(das\s+)?auf[:\s]*(dass\s+)?', caseSensitive: false),
    RegExp(r'^(schreib|schreibe)\s+(bitte\s+)?(auf\s+)?(dass\s+|folgendes[:\s]+)?', caseSensitive: false),
    RegExp(r'^(halt|halte)\s+(das\s+|es\s+)?fest[:\s]*(dass\s+)?', caseSensitive: false),
    RegExp(r'^merk\s+dir\s+(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^(speicher|speichere)\s+(das\s+|bitte\s+)?(ab\s*)?[:\s]*(dass\s+)?', caseSensitive: false),
    // ── Selbstgespräch ──
    RegExp(r'^ich\s+(muss|müss?te|sollte|will|möchte|wollte)\s+(noch\s+|unbedingt\s+|dringend\s+|heute\s+|morgen\s+)?', caseSensitive: false),
    RegExp(r'^nicht\s+vergessen[:\s]*(dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^vergiss\s+nicht[,\s]*(bitte\s+)?(dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^auf\s+keinen\s+fall\s+vergessen[:\s]*(zu\s+)?', caseSensitive: false),
    RegExp(r'^denk\s+(daran|dran)[,\s]*(bitte\s+)?(dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^das\s+darf\s+ich\s+nicht\s+vergessen[:\s]*(zu\s+)?', caseSensitive: false),
    RegExp(r'^unbedingt\s+(noch\s+|dringend\s+)?', caseSensitive: false),
    // ── App ──
    RegExp(r'^(hey\s+)?app[,:]?\s*(bitte\s+)?', caseSensitive: false),
    RegExp(r'^(ok|okay|hey)\s+(google|siri|alexa|app)[,:]?\s*(bitte\s+)?', caseSensitive: false),
    RegExp(r'^(bitte\s+)?(trag\s+ein|notier|merk|erinner\s+mich)\s*[,:]?\s*(dass\s+|zu\s+|an\s+(den\s+|die\s+|das\s+)?)?', caseSensitive: false),
    // ── Kalender ──
    RegExp(r'^(trag|block|reservier)\s+(mir\s+)?(den\s+|einen?\s+)?(termin|slot|zeitraum|zeit|tag|abend)\s+(ein\s+)?(für\s+|am\s+)?', caseSensitive: false),
    RegExp(r'^termin\s*[:\-]?\s*', caseSensitive: false),
    // ── Frage ──
    RegExp(r'^(kannst|könntest)\s+du\s+(bitte\s+)?(mir\s+)?(eine?\s+)?(aufgabe|erinnerung|todo|notiz)\s+(erstellen|anlegen|hinzufügen|eintragen)\s*(dass\s+|für\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^(kannst|könntest)\s+du\s+(bitte\s+)?aufschreiben[,\s]*(dass\s+)?', caseSensitive: false),
    // ── Kurzform ──
    RegExp(r'^todo[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^aufgabe[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^notiz[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^task[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^reminder[:\s]*(bitte\s+)?(dass\s+)?', caseSensitive: false),
  ];

  // ── Priorität ────────────────────────────────────────────────────────────────
  static final _priorityUrgent = RegExp(
    r'\b(dringend|dringendst|asap|so\s+schnell\s+wie\s+möglich|sofort|wichtig|prio\s*1|priorität\s*1|notfall|eilig)\b',
    caseSensitive: false,
  );

  // ── Wiederholung ─────────────────────────────────────────────────────────────
  static final List<(RegExp, RecurrenceRule)> _recurrencePatterns = [
    (RegExp(r'\btäglich\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.daily)),
    (RegExp(r'\bjeden\s+tag\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.daily)),
    (RegExp(r'\bjede\s+woche\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.weekly)),
    (RegExp(r'\bwöchentlich\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.weekly)),
    (RegExp(r'\bmonatlich\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.monthly)),
    (RegExp(r'\bjeden\s+monat\b', caseSensitive: false), const RecurrenceRule(RecurrenceFrequency.monthly)),
  ];

  // ── Dauer ────────────────────────────────────────────────────────────────────
  static final _durationPattern = RegExp(
    r'\b(für|ca\.?|circa|etwa|ungefähr)\s+(\d+(?:[.,]\d+)?)\s*(stunden?|std\.?|h\b|minuten?|min\.?)\b',
    caseSensitive: false,
  );

  // ── Titel-Füllwörter am Rand (nach Bereinigung der Spannen) ─────────────────
  // NUR Wörter, die nachweislich als Artefakt der Zeit-/Datum-Extraktion
  // übrig bleiben — keine blinden Ersetzungen mehr.
  static final List<RegExp> _titleEdgeFiller = [
    // Übrig gebliebene Präpositionen AM ANFANG
    RegExp(r'^(an\s+(den|die|das|dem|einen?|meine[nm]?)\s+)', caseSensitive: false),
    RegExp(r'^(zu\s+(dem|der|den)\s+|zum\s+|zur\s+)', caseSensitive: false),
    RegExp(r'^(dass\s+|daran\s+|dran\s+)', caseSensitive: false),
    RegExp(r'^(bitte\s+)+', caseSensitive: false),
    RegExp(r'^(noch\s+)+', caseSensitive: false),
    RegExp(r'^(mal\s+)+', caseSensitive: false),
    RegExp(r'^(den\s+|die\s+|das\s+|einen?\s+)', caseSensitive: false),
    // Artefakte AM ENDE
    RegExp(r'\s+(daran|dran|bitte|dass|an)$', caseSensitive: false),
    RegExp(r'\s*[.,!?]\s*$'),
  ];

  // ────────────────────────────────────────────────────────────────────────────
  // HAUPTFUNKTION
  // ────────────────────────────────────────────────────────────────────────────
  static ParsedSpokenTask parse(String rawText) {
    final original = rawText.trim();
    // w = lowercase für alle Erkennungs-Regex. original bleibt unberührt.
    final String w = original.toLowerCase();

    // Alle zu entfernenden Spannen sammeln (bezogen auf w / original, da
    // beide identische Länge haben — toLowerCase ändert keine Länge).
    final spans = <_Span>[];

    // ── 1) Trigger-Phrase am Anfang ─────────────────────────────────────────
    for (final trigger in _triggerPhrases) {
      final m = trigger.firstMatch(w);
      if (m != null) {
        spans.add(_Span(0, m.end));
        break;
      }
    }

    // ── 2) Priorität ─────────────────────────────────────────────────────────
    final priority = _priorityUrgent.hasMatch(w) ? TaskPriority.urgent : TaskPriority.normal;
    if (priority == TaskPriority.urgent) {
      for (final m in _priorityUrgent.allMatches(w)) {
        spans.add(_Span(m.start, m.end));
      }
    }

    // ── 3) Dauer ─────────────────────────────────────────────────────────────
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
      spans.add(_Span(durMatch.start, durMatch.end));
    }

    // ── 4) Wiederholung ──────────────────────────────────────────────────────
    RecurrenceRule? recurrence;
    for (final (pattern, rule) in _recurrencePatterns) {
      final m = pattern.firstMatch(w);
      if (m != null) {
        recurrence = rule;
        spans.add(_Span(m.start, m.end));
        break;
      }
    }
    // "jeden Montag" etc.
    if (recurrence == null) {
      for (final entry in _weekdays.entries) {
        final jedenPat = RegExp('\\bjeden\\s+${entry.key}\\b', caseSensitive: false);
        final m = jedenPat.firstMatch(w);
        if (m != null) {
          recurrence = RecurrenceRule(RecurrenceFrequency.weekly, weekday: entry.value);
          spans.add(_Span(m.start, m.end));
          break;
        }
      }
    }

    // ── 5) Explizites Datum ──────────────────────────────────────────────────
    DateTime? date;

    // 5a) "am 15. März 2026" / "15. März"
    final explicitMonthMatch = RegExp(
      r'(?:am\s+)?(\d{1,2})\.?\s*(januar|jänner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan\.?|feb\.?|mär\.?|apr\.?|jun\.?|jul\.?|aug\.?|sep\.?|sept\.?|okt\.?|nov\.?|dez\.?)\s*\.?\s*(\d{4})?',
      caseSensitive: false,
    ).firstMatch(w);

    // 5b) "am 15.3." / "15.3.2026"
    final explicitDateMatch = RegExp(
      r'(?:am\s+)?(\d{1,2})\.\s*(\d{1,2})\.?\s*(\d{4})?',
    ).firstMatch(w);

    if (explicitMonthMatch != null) {
      final day = int.tryParse(explicitMonthMatch.group(1) ?? '');
      final rawMonth = (explicitMonthMatch.group(2) ?? '').replaceAll('.', '').trim().toLowerCase();
      final month = _months[rawMonth];
      final year = int.tryParse(explicitMonthMatch.group(3) ?? '') ?? DateTime.now().year;
      if (day != null && month != null) {
        date = DateTime(year, month, day);
        spans.add(_Span(explicitMonthMatch.start, explicitMonthMatch.end));
      }
    } else if (explicitDateMatch != null && explicitDateMatch.group(2) != null) {
      final day = int.tryParse(explicitDateMatch.group(1) ?? '');
      final month = int.tryParse(explicitDateMatch.group(2) ?? '');
      final year = int.tryParse(explicitDateMatch.group(3) ?? '') ?? DateTime.now().year;
      if (day != null && month != null && month >= 1 && month <= 12) {
        date = DateTime(year, month, day);
        spans.add(_Span(explicitDateMatch.start, explicitDateMatch.end));
      }
    }

    // ── 6) Relative Tagesangaben ─────────────────────────────────────────────
    if (date == null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      _RelResult? rel;

      // Prüfungen in absteigender Spezifität
      if ((rel = _matchRelative(w, RegExp(r'\bübermorgen\b', caseSensitive: false), today.add(const Duration(days: 2)))) != null) {}
      else if ((rel = _matchRelative(w, RegExp(r'\bmorgen\s+früh\b', caseSensitive: false), today.add(const Duration(days: 1)))) != null) {}
      else if ((rel = _matchRelative(w, RegExp(r'\bmorgen\b', caseSensitive: false), today.add(const Duration(days: 1)))) != null) {}
      else if ((rel = _matchRelative(w, RegExp(r'\bheute\s+(?:abend|nacht)\b', caseSensitive: false), today)) != null) {}
      else if ((rel = _matchRelative(w, RegExp(r'\bheute\b', caseSensitive: false), today)) != null) {}
      else if ((rel = _matchRelative(w, RegExp(r'\bnächste\s+woche\b', caseSensitive: false), today.add(Duration(days: 8 - today.weekday)))) != null) {}
      else if ((rel = _matchRelative(w, RegExp(r'\b(?:dieses\s+wochenende|am\s+wochenende)\b', caseSensitive: false), () {
        int d = (DateTime.saturday - today.weekday) % 7;
        return today.add(Duration(days: d == 0 ? 7 : d));
      }())) != null) {}
      else {
        // "in X Tagen" / "in einer Woche" / "in X Monaten"
        final inDays = RegExp(r'\bin\s+(\d+)\s+tagen?\b', caseSensitive: false).firstMatch(w);
        final inWeeks = RegExp(r'\bin\s+(einer|\d+)\s+woch\w+\b', caseSensitive: false).firstMatch(w);
        final inMonths = RegExp(r'\bin\s+(einem?|\d+)\s+monat\w*\b', caseSensitive: false).firstMatch(w);
        if (inDays != null) {
          final days = int.tryParse(inDays.group(1) ?? '');
          if (days != null) { date = today.add(Duration(days: days)); spans.add(_Span(inDays.start, inDays.end)); }
        } else if (inWeeks != null) {
          final raw = inWeeks.group(1) ?? '1';
          final weeks = raw == 'einer' ? 1 : (int.tryParse(raw) ?? 1);
          date = today.add(Duration(days: weeks * 7));
          spans.add(_Span(inWeeks.start, inWeeks.end));
        } else if (inMonths != null) {
          final raw = inMonths.group(1) ?? '1';
          final months = (raw.startsWith('ein')) ? 1 : (int.tryParse(raw) ?? 1);
          date = DateTime(today.year, today.month + months, today.day);
          spans.add(_Span(inMonths.start, inMonths.end));
        } else {
          // "diesen Montag" / "nächsten Montag" / "am Montag" / einfach "Montag"
          for (final entry in _weekdays.entries) {
            final pat = RegExp(
              '\\b((?:nächste[nm]?|naechste[nm]?)\\s+|diesen\\s+|am\\s+)?${entry.key}\\b',
              caseSensitive: false,
            );
            final m = pat.firstMatch(w);
            if (m != null) {
              final qualifier = (m.group(1) ?? '').toLowerCase();
              final forceNext = qualifier.contains('nächst') || qualifier.contains('naechst');
              int diff = (entry.value - today.weekday) % 7;
              if (diff == 0 && forceNext) diff = 7;
              if (diff < 0) diff += 7;
              date = today.add(Duration(days: diff));
              spans.add(_Span(m.start, m.end));
              break;
            }
          }
        }
      }

      if (rel != null) {
        date = rel.date;
        spans.add(rel.span);
      }
    }

    // ── 7) Uhrzeit ───────────────────────────────────────────────────────────
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
        spans.add(_Span(vonBisMatch.start, vonBisMatch.end));
      }
    }

    // 7b) Tageszeiten als Wort (nur wenn noch keine Uhrzeit erkannt)
    if (time == null) {
      final tzMatch = RegExp(
        r'\b(morgens?|früh|vormittags?|mittags?|nachmittags?|abends?|nachts?|mitternacht|gegen\s+mitternacht)\b',
        caseSensitive: false,
      ).firstMatch(w);
      if (tzMatch != null) {
        final tz = tzMatch.group(1)!.toLowerCase();
        int h;
        if (tz.startsWith('morgen') || tz == 'früh') h = 8;
        else if (tz.startsWith('vormittag')) h = 10;
        else if (tz.startsWith('mittag')) h = 12;
        else if (tz.startsWith('nachmittag')) h = 15;
        else if (tz.startsWith('abend')) h = 19;
        else if (tz.startsWith('nacht')) h = 21;
        else h = 0;
        time = DateTimeComponents(h, 0);
        spans.add(_Span(tzMatch.start, tzMatch.end));
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
          spans.add(_Span(gegenMatch.start, gegenMatch.end));
        }
      }
    }

    // 7d) Deutsche Zeitangaben: halb, viertel, kurz, punkt, genau, um X Uhr
    if (time == null) {
      _TimeResult? tr;

      tr = _tryHalf(w) ?? _tryDreiViertel(w) ?? _tryViertelNach(w) ??
           _tryViertelVor(w) ?? _tryKurzNach(w) ?? _tryKurzVor(w) ??
           _tryPunkt(w) ?? _tryGenau(w) ?? _tryUmUhr(w);

      if (tr != null) {
        time = DateTimeComponents(tr.hour.clamp(0, 23), tr.minute.clamp(0, 59));
        spans.add(tr.span);
      }
    }

    // ── 8) Titel aus Original-String zusammenbauen ───────────────────────────
    //
    // Spannen normalisieren: überlappende/angrenzende zusammenfassen,
    // dann die Lücken zwischen den Spannen aus `original` nehmen.
    final sortedSpans = List<_Span>.from(spans)..sort((a, b) => a.start.compareTo(b.start));
    final mergedSpans = <_Span>[];
    for (final s in sortedSpans) {
      if (mergedSpans.isEmpty) {
        mergedSpans.add(s);
      } else {
        final last = mergedSpans.last;
        if (s.start <= last.end + 1) {
          mergedSpans[mergedSpans.length - 1] = _Span(last.start, s.end > last.end ? s.end : last.end);
        } else {
          mergedSpans.add(s);
        }
      }
    }

    // Lücken = alles, was NICHT in einer Spanne liegt
    final parts = <String>[];
    int cursor = 0;
    for (final s in mergedSpans) {
      if (s.start > cursor) parts.add(original.substring(cursor, s.start));
      cursor = s.end;
    }
    if (cursor < original.length) parts.add(original.substring(cursor));

    String title = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    // Rand-Füllwörter iterativ entfernen (mehrere Passes, da manche
    // Muster erst nach vorherigen Entfernungen am Rand auftauchen).
    bool changed = true;
    while (changed) {
      changed = false;
      for (final filler in _titleEdgeFiller) {
        final cleaned = title.replaceFirst(filler, '').trim();
        if (cleaned != title) {
          title = cleaned;
          changed = true;
        }
      }
    }

    // Leerzeichen normalisieren
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Großschreibung: Original-Großschreibung bleibt erhalten (da wir aus
    // `original` gebaut haben). Nur sicherstellen, dass der erste Buchstabe
    // großgeschrieben ist, falls der Titel mit Kleinbuchstaben beginnt
    // (kann passieren wenn der erste erkannte Teil ein lowercase-Wort war).
    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    }

    // Fallback: leerer Titel → ursprünglichen Text verwenden
    if (title.isEmpty) title = original;

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

  // ── Hilfsmethoden ────────────────────────────────────────────────────────────

  static _RelResult? _matchRelative(String w, RegExp pattern, DateTime targetDate) {
    final m = pattern.firstMatch(w);
    if (m == null) return null;
    return _RelResult(targetDate, _Span(m.start, m.end));
  }

  static int _toPlausibleHour(int h) {
    if (h < 0) h += 12;
    if (h >= 1 && h <= 7) return h + 12;
    return h;
  }

  // Einzelne Zeitparser — geben null zurück wenn kein Match
  static _TimeResult? _tryHalf(String w) {
    final m = RegExp(r'\bhalb\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    return _TimeResult(_toPlausibleHour(h - 1), 30, _Span(m.start, m.end));
  }

  static _TimeResult? _tryDreiViertel(String w) {
    final m = RegExp(r'\bdreiviertel\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    return _TimeResult(_toPlausibleHour(h - 1), 45, _Span(m.start, m.end));
  }

  static _TimeResult? _tryViertelNach(String w) {
    final m = RegExp(r'\bviertel\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    return _TimeResult(_toPlausibleHour(h), 15, _Span(m.start, m.end));
  }

  static _TimeResult? _tryViertelVor(String w) {
    final m = RegExp(r'\bviertel\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    return _TimeResult(_toPlausibleHour(h - 1), 45, _Span(m.start, m.end));
  }

  static _TimeResult? _tryKurzNach(String w) {
    final m = RegExp(r'\bkurz\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    return _TimeResult(_toPlausibleHour(h), 5, _Span(m.start, m.end));
  }

  static _TimeResult? _tryKurzVor(String w) {
    final m = RegExp(r'\bkurz\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    final base = _toPlausibleHour(h);
    return _TimeResult(base > 0 ? base - 1 : 23, 55, _Span(m.start, m.end));
  }

  static _TimeResult? _tryPunkt(String w) {
    final m = RegExp(r'\bpunkt\s+(\d{1,2})\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    return _TimeResult(_toPlausibleHour(h), 0, _Span(m.start, m.end));
  }

  static _TimeResult? _tryGenau(String w) {
    final m = RegExp(r'\bgenau\s+(\d{1,2})\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    return _TimeResult(_toPlausibleHour(h), 0, _Span(m.start, m.end));
  }

  // "um 14 Uhr" / "um 14:30" / "um 8 Uhr 30"
  // Matcht das vollständige Muster inkl. "um" für präzise Span-Erfassung.
  static _TimeResult? _tryUmUhr(String w) {
    final m = RegExp(
      r'\bum\s+(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?(?:\s+(\d{2}))?\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    if (h == null) return null;
    final min = int.tryParse(m.group(2) ?? m.group(3) ?? '0') ?? 0;
    return _TimeResult(_toPlausibleHour(h), min, _Span(m.start, m.end));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interne Hilfsdatentypen
// ─────────────────────────────────────────────────────────────────────────────

class _RelResult {
  final DateTime date;
  final _Span span;
  const _RelResult(this.date, this.span);
}

class _TimeResult {
  final int hour;
  final int minute;
  final _Span span;
  const _TimeResult(this.hour, this.minute, this.span);
}