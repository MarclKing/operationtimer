// ─────────────────────────────────────────────────────────────────────────────
// SPOKEN TASK PARSER v4 (Fix)
//
// Vollständig überarbeitete Architektur. Kernprinzipien:
//
//  A) DUAL-TRACK: `w` (lowercase) nur zum Erkennen. Alle Treffer als
//     _Span(start,end) gesammelt. Titel aus Original-String gebaut →
//     STT-Großschreibung ("TÜV-Termin", "Dr. Müller") bleibt erhalten.
//
//  B) STRIKTE PARSING-REIHENFOLGE:
//     1. Trigger-Phrase entfernen
//     2. Datum erkennen (explizit → relativ → Wochentag)
//     3. Uhrzeit erkennen — ERST explizite Uhr-Formate ("um 14 Uhr",
//        "halb 3", "viertel nach 9", …), DANN Tageszeit-Wörter ("Abend",
//        "Morgen", "Mittag"). Tageszeit IMMER sekundär zu expliziter Uhr.
//     4. Sonstiges (Priorität, Dauer, Wiederholung)
//     5. Titel aus Lücken zusammenbauen + Bereinigung
//
//  C) TAGESZEIT-MAPPING: "Dienstag Morgen", "morgen Abend", "heute Mittag",
//     "Freitag Nachmittag", "morgen früh" → konkrete Uhrzeit.
//     "morgen" allein = Datum, NICHT Tageszeit.
//
//  D) KERNAUFGABEN-EXTRAKTION: Infinitiv-Konstruktionen, Artikel,
//     "zu + Infinitiv", trennbare Verben werden auf das Wesentliche
//     reduziert. "das Auto zum TÜV zu bringen" → "Auto zum TÜV bringen".
//
//  E) ROBUSTE EDGE-FILLER: iterativer Strip von Füllwörtern die als
//     Artefakt nach Span-Extraktion am Rand des Titels übrig bleiben.
//     "an den", "daran,", "noch:", "zum" etc.
//
// ── FIXES gegenüber der ursprünglichen v4-Fassung ──────────────────────────
//
//  FIX 1 (Compile-Fehler): `String.replaceFirst()` akzeptiert in Dart NUR
//  einen String als Ersatz, keine Callback-Funktion. Für Callbacks gibt es
//  die separate Methode `replaceFirstMapped()`. Beide betroffenen Stellen in
//  `_extractCoreTask()` wurden entsprechend umgestellt.
//
//  FIX 2 (stiller Logikfehler, kein Compile-Fehler, aber falsches
//  Verhalten): Die Wochentags-Abkürzungen "mo", "di", "mi", "do", "fr",
//  "sa", "so" wurden komplett entfernt. Das ist ein Diktier-Parser für
//  gesprochene Sprache (STT) — niemand sagt "mo" oder "do", wenn er
//  "Montag"/"Donnerstag" meint. Diese Kürzel sind aus der Schriftform
//  übernommen worden, wo sie sinnvoll sind, in gesprochener Sprache aber
//  hochriskant: "so" ist eines der häufigsten deutschen Füllwörter
//  überhaupt ("...so schnell wie möglich", "...mach das so") und hätte
//  in jedem zweiten Satz fälschlich ein Datum (Sonntag) eingetragen,
//  weil die Wochentags-Erkennung nur eine Wortgrenze prüft, kein "am"
//  davor verlangt. Mit den vollen Wochentagsnamen (die in der
//  gesprochenen Sprache tatsächlich verwendet werden) bleibt die
//  Erkennung bestehen, ohne dieses Risiko.
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

class _Span {
  final int start;
  final int end;
  const _Span(this.start, this.end);
}

class _TimeResult {
  final int hour;
  final int minute;
  final _Span span;
  final int? endHour;
  final int? endMinute;
  const _TimeResult(this.hour, this.minute, this.span, {this.endHour, this.endMinute});
}

// ─────────────────────────────────────────────────────────────────────────────

class SpokenTaskParser {
  SpokenTaskParser._();

  // ── Wochentage ──────────────────────────────────────────────────────────────
  // FIX 2: KEINE 2-Buchstaben-Kürzel mehr ("mo","di","mi","do","fr","sa","so")
  // — siehe Erklärung im Datei-Kopf. Nur volle, gesprochene Formen.
  static const Map<String, int> _weekdays = {
    'montag': DateTime.monday,
    'dienstag': DateTime.tuesday,
    'mittwoch': DateTime.wednesday,
    'donnerstag': DateTime.thursday,
    'freitag': DateTime.friday,
    'samstag': DateTime.saturday,
    'sonnabend': DateTime.saturday,
    'sonntag': DateTime.sunday,
  };

  // ── Monate ──────────────────────────────────────────────────────────────────
  static const Map<String, int> _months = {
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
  static final List<RegExp> _triggers = [
    // Erinnerungs-Befehle (mit optionalem "an den/die/das" direkt danach)
    RegExp(r'^erinnere\s+mich\s+(?:daran[,\s]*)?(?:bitte\s+)?(?:an\s+(?:den\s+|die\s+|das\s+|einen?\s+|meine[nm]?\s+)?|dass\s+)?', caseSensitive: false),
    RegExp(r'^kannst\s+du\s+mich\s+(?:daran\s+)?erinnern[,\s]*(?:bitte\s+)?(?:an\s+(?:den\s+|die\s+|das\s+)?|dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^ich\s+brauche\s+eine\s+erinnerung\s+(?:an\s+(?:den\s+|die\s+|das\s+|meine[nm]?\s+)?|für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^setz\s+(?:mir\s+)?eine?\s+erinnerung\s+(?:für\s+|an\s+)?', caseSensitive: false),
    RegExp(r'^stell\s+(?:mir\s+)?eine?\s+erinnerung\s+(?:für\s+|auf\s+|ein\s+)?', caseSensitive: false),
    RegExp(r'^leg\s+(?:mir\s+)?eine?\s+erinnerung\s+(?:an\s+(?:den\s+|die\s+|das\s+)?)?', caseSensitive: false),
    // Aufgaben-Befehle
    RegExp(r'^neue?\s+(?:aufgabe|todo|task)\s*(?:anlegen\s+)?(?:für\s+)?:?\s*', caseSensitive: false),
    RegExp(r'^(?:erstell|erzeuge|mach)\s+(?:mir\s+)?(?:eine?\s+)?(?:neue?\s+)?(?:aufgabe|todo|task|eintrag)\s*(?:für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:füg|füge)\s+(?:eine?\s+)?(?:neue?\s+)?(?:aufgabe|todo|task)\s+hinzu[:\s]*(?:für\s+|dass\s+)?', caseSensitive: false),
    RegExp(r'^trag\s+(?:mir\s+)?ein[:\s]*(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:notiere|notier)\s+(?:dir\s+|bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:schreib|schreibe)\s+(?:dir\s+|bitte\s+)?(?:das\s+)?auf[:\s]*(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:schreib|schreibe)\s+(?:bitte\s+)?(?:auf\s+)?(?:dass\s+|folgendes[:\s]+)?', caseSensitive: false),
    RegExp(r'^(?:halt|halte)\s+(?:das\s+|es\s+)?fest[:\s]*(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^merk\s+dir\s+(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:speicher|speichere)\s+(?:das\s+|bitte\s+)?(?:ab\s*)?[:\s]*(?:dass\s+)?', caseSensitive: false),
    // Selbstgespräch
    RegExp(r'^ich\s+(?:muss|müss?te|sollte|will|möchte|wollte)\s+(?:noch\s+|unbedingt\s+|dringend\s+)?', caseSensitive: false),
    RegExp(r'^nicht\s+vergessen[:\s]*(?:dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^vergiss\s+nicht[,\s]*(?:bitte\s+)?(?:dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^auf\s+keinen\s+fall\s+vergessen[:\s]*(?:zu\s+)?', caseSensitive: false),
    RegExp(r'^denk\s+(?:daran|dran)[,\s]*(?:bitte\s+)?(?:dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^daran\s+denken[:\s]*(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^das\s+darf\s+ich\s+nicht\s+vergessen[:\s]*(?:zu\s+)?', caseSensitive: false),
    RegExp(r'^unbedingt\s+(?:noch\s+|dringend\s+)?', caseSensitive: false),
    // App
    RegExp(r'^(?:hey\s+)?app[,:]?\s*(?:bitte\s+)?', caseSensitive: false),
    RegExp(r'^(?:ok|okay|hey)\s+(?:google|siri|alexa|app)[,:]?\s*(?:bitte\s+)?', caseSensitive: false),
    RegExp(r'^(?:bitte\s+)?(?:trag\s+ein|notier|merk|erinner\s+mich)\s*[,:]?\s*(?:dass\s+|zu\s+|an\s+(?:den\s+|die\s+|das\s+)?)?', caseSensitive: false),
    // Kalender
    RegExp(r'^(?:trag|block|reservier)\s+(?:mir\s+)?(?:den\s+|einen?\s+)?(?:termin|slot|zeitraum|zeit|tag|abend)\s+ein\s+(?:für\s+|am\s+)?', caseSensitive: false),
    RegExp(r'^termin\s*[:\-]?\s*', caseSensitive: false),
    // Frage-Form
    RegExp(r'^(?:kannst|könntest)\s+du\s+(?:bitte\s+)?(?:mir\s+)?(?:eine?\s+)?(?:aufgabe|erinnerung|todo|notiz)\s+(?:erstellen|anlegen|hinzufügen|eintragen)\s*(?:dass\s+|für\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^(?:kannst|könntest)\s+du\s+(?:bitte\s+)?aufschreiben[,\s]*(?:dass\s+)?', caseSensitive: false),
    // Kurzform
    RegExp(r'^todo[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^aufgabe[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^notiz[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^task[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^reminder[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
  ];

  // ── Priorität ────────────────────────────────────────────────────────────────
  static final _priorityRx = RegExp(
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
  static final _durationRx = RegExp(
    r'\b(?:für|ca\.?|circa|etwa|ungefähr)\s+(\d+(?:[.,]\d+)?)\s*(stunden?|std\.?|h\b|minuten?|min\.?)\b',
    caseSensitive: false,
  );

  // ── Edge-Filler (iterativer Strip am Rand des Titels) ────────────────────────
  // Nur Wörter, die nachweislich als Artefakt der Extraktion übrig bleiben.
  static final List<RegExp> _edgeStart = [
    RegExp(r'^an\s+(?:den|die|das|dem|einen?|meine[nm]?|meinem|meiner)\s+', caseSensitive: false),
    RegExp(r'^an\s+', caseSensitive: false), // "an Konzerttickets"
    RegExp(r'^daran[,\s]+', caseSensitive: false),
    RegExp(r'^dran[,\s]+', caseSensitive: false),
    RegExp(r'^zu\s+(?:dem|der|den)\s+', caseSensitive: false),
    RegExp(r'^zum\s+', caseSensitive: false),
    RegExp(r'^zur\s+', caseSensitive: false),
    RegExp(r'^dass\s+', caseSensitive: false),
    RegExp(r'^(?:bitte\s+)+', caseSensitive: false),
    RegExp(r'^(?:noch\s*[:\-]?\s*)+', caseSensitive: false),
    RegExp(r'^(?:mal\s+)+', caseSensitive: false),
    RegExp(r'^den\s+', caseSensitive: false),
    RegExp(r'^die\s+', caseSensitive: false),
    RegExp(r'^das\s+', caseSensitive: false),
    RegExp(r'^einen?\s+', caseSensitive: false),
  ];
  static final List<RegExp> _edgeEnd = [
    RegExp(r'\s+(?:daran|dran|bitte|dass|an)$', caseSensitive: false),
    RegExp(r'\s*[.,!?]\s*$'),
  ];

  // ────────────────────────────────────────────────────────────────────────────
  // HAUPTFUNKTION
  // ────────────────────────────────────────────────────────────────────────────
  static ParsedSpokenTask parse(String rawText) {
    final original = rawText.trim();
    final w = original.toLowerCase();
    final spans = <_Span>[];

    // ══ 1) TRIGGER ══════════════════════════════════════════════════════════
    for (final rx in _triggers) {
      final m = rx.firstMatch(w);
      if (m != null) {
        spans.add(_Span(0, m.end));
        break;
      }
    }

    // ══ 2) PRIORITÄT ════════════════════════════════════════════════════════
    final priority = _priorityRx.hasMatch(w) ? TaskPriority.urgent : TaskPriority.normal;
    if (priority == TaskPriority.urgent) {
      for (final m in _priorityRx.allMatches(w)) {
        spans.add(_Span(m.start, m.end));
      }
    }

    // ══ 3) DAUER ════════════════════════════════════════════════════════════
    Duration? estimatedDuration;
    final durM = _durationRx.firstMatch(w);
    if (durM != null) {
      final amount = double.tryParse((durM.group(1) ?? '').replaceAll(',', '.')) ?? 0;
      final unit = (durM.group(2) ?? '').toLowerCase();
      estimatedDuration = unit.startsWith('h') || unit.startsWith('std') || unit.startsWith('stu')
          ? Duration(minutes: (amount * 60).round())
          : Duration(minutes: amount.round());
      spans.add(_Span(durM.start, durM.end));
    }

    // ══ 4) WIEDERHOLUNG ═════════════════════════════════════════════════════
    RecurrenceRule? recurrence;
    for (final (rx, rule) in _recurrencePatterns) {
      final m = rx.firstMatch(w);
      if (m != null) {
        recurrence = rule;
        spans.add(_Span(m.start, m.end));
        break;
      }
    }
    if (recurrence == null) {
      for (final e in _weekdays.entries) {
        final m = RegExp('\\bjeden\\s+${e.key}\\b', caseSensitive: false).firstMatch(w);
        if (m != null) {
          recurrence = RecurrenceRule(RecurrenceFrequency.weekly, weekday: e.value);
          spans.add(_Span(m.start, m.end));
          break;
        }
      }
    }

    // ══ 5) DATUM ════════════════════════════════════════════════════════════
    DateTime? date;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 5a) Explizit mit Monatsname: "am 15. März 2026"
    final expMonthM = RegExp(
      r'(?:am\s+)?(\d{1,2})\.?\s*(januar|jänner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan\.?|feb\.?|mär\.?|apr\.?|jun\.?|jul\.?|aug\.?|sep\.?|sept\.?|okt\.?|nov\.?|dez\.?)\s*\.?\s*(\d{4})?',
      caseSensitive: false,
    ).firstMatch(w);

    // 5b) Explizit numerisch: "am 15.3." / "15.3.2026"
    final expDateM = RegExp(r'(?:am\s+)?(\d{1,2})\.\s*(\d{1,2})\.?\s*(\d{4})?').firstMatch(w);

    if (expMonthM != null) {
      final day = int.tryParse(expMonthM.group(1) ?? '');
      final rawM = (expMonthM.group(2) ?? '').replaceAll('.', '').trim().toLowerCase();
      final month = _months[rawM];
      final year = int.tryParse(expMonthM.group(3) ?? '') ?? now.year;
      if (day != null && month != null) {
        date = DateTime(year, month, day);
        spans.add(_Span(expMonthM.start, expMonthM.end));
      }
    } else if (expDateM != null && expDateM.group(2) != null) {
      final day = int.tryParse(expDateM.group(1) ?? '');
      final month = int.tryParse(expDateM.group(2) ?? '');
      final year = int.tryParse(expDateM.group(3) ?? '') ?? now.year;
      if (day != null && month != null && month >= 1 && month <= 12) {
        date = DateTime(year, month, day);
        spans.add(_Span(expDateM.start, expDateM.end));
      }
    }

    // 5c) Relative Tagesangaben (wenn noch kein explizites Datum)
    if (date == null) {
      final relPatterns = <(RegExp, DateTime)>[
        (RegExp(r'\bübermorgen\b', caseSensitive: false), today.add(const Duration(days: 2))),
        (RegExp(r'\bmorgen\s+früh\b', caseSensitive: false), today.add(const Duration(days: 1))),
        (RegExp(r'\bmorgen\b', caseSensitive: false), today.add(const Duration(days: 1))),
        (RegExp(r'\bheute\s+(?:abend|nacht)\b', caseSensitive: false), today),
        (RegExp(r'\bheute\b', caseSensitive: false), today),
        (RegExp(r'\bnächste\s+woche\b', caseSensitive: false), today.add(Duration(days: 8 - today.weekday))),
        (RegExp(r'\b(?:dieses\s+wochenende|am\s+wochenende)\b', caseSensitive: false), () {
          int d = (DateTime.saturday - today.weekday) % 7;
          return today.add(Duration(days: d == 0 ? 7 : d));
        }()),
      ];
      for (final (rx, target) in relPatterns) {
        final m = rx.firstMatch(w);
        if (m != null) {
          date = target;
          spans.add(_Span(m.start, m.end));
          break;
        }
      }
    }

    // 5d) "in X Tagen/Wochen/Monaten"
    if (date == null) {
      final inDaysM = RegExp(r'\bin\s+(\d+)\s+tagen?\b', caseSensitive: false).firstMatch(w);
      final inWeeksM = RegExp(r'\bin\s+(einer|\d+)\s+woch\w+\b', caseSensitive: false).firstMatch(w);
      final inMonsM = RegExp(r'\bin\s+(einem?|\d+)\s+monat\w*\b', caseSensitive: false).firstMatch(w);
      if (inDaysM != null) {
        final d = int.tryParse(inDaysM.group(1) ?? '');
        if (d != null) {
          date = today.add(Duration(days: d));
          spans.add(_Span(inDaysM.start, inDaysM.end));
        }
      } else if (inWeeksM != null) {
        final raw = inWeeksM.group(1) ?? '1';
        final weeks = raw == 'einer' ? 1 : (int.tryParse(raw) ?? 1);
        date = today.add(Duration(days: weeks * 7));
        spans.add(_Span(inWeeksM.start, inWeeksM.end));
      } else if (inMonsM != null) {
        final raw = inMonsM.group(1) ?? '1';
        final months = raw.startsWith('ein') ? 1 : (int.tryParse(raw) ?? 1);
        date = DateTime(today.year, today.month + months, today.day);
        spans.add(_Span(inMonsM.start, inMonsM.end));
      }
    }

    // 5e) Wochentage: "nächsten Montag" / "am Dienstag" / "Freitag"
    // WICHTIG: Wird auch erkannt wenn Tageszeit-Wort folgt ("Dienstag Morgen")
    if (date == null) {
      for (final e in _weekdays.entries) {
        final rx = RegExp(
          '\\b((?:nächste[nm]?|naechste[nm]?|diesen|am)\\s+)?${e.key}\\b',
          caseSensitive: false,
        );
        final m = rx.firstMatch(w);
        if (m != null) {
          final qualifier = (m.group(1) ?? '').toLowerCase();
          final forceNext = qualifier.contains('nächst') || qualifier.contains('naechst');
          int diff = (e.value - today.weekday) % 7;
          if (diff == 0 && forceNext) diff = 7;
          if (diff < 0) diff += 7;
          date = today.add(Duration(days: diff));
          spans.add(_Span(m.start, m.end));
          break;
        }
      }
    }

    // ══ 6) UHRZEIT (explizit > Tageszeit) ══════════════════════════════════
    DateTimeComponents? time;
    DateTimeComponents? endTime;

    // 6a) Explizite Uhrzeit — Reihenfolge: spezifischste zuerst
    final clkResult = _parseClockTime(w);
    if (clkResult != null) {
      time = DateTimeComponents(clkResult.hour.clamp(0, 23), clkResult.minute.clamp(0, 59));
      spans.add(clkResult.span);
      if (clkResult.endHour != null) {
        endTime = DateTimeComponents(clkResult.endHour!.clamp(0, 23), clkResult.endMinute!.clamp(0, 59));
      }
    }

    // 6b) Tageszeit-Wort — NUR wenn keine explizite Uhrzeit gefunden
    if (time == null) {
      final todResult = _parseTimeOfDay(w);
      if (todResult != null) {
        time = DateTimeComponents(todResult.hour.clamp(0, 23), todResult.minute.clamp(0, 59));
        spans.add(todResult.span);
      }
    }

    // ══ 7) TITEL AUFBAUEN ═══════════════════════════════════════════════════
    // Alle Spannen zusammenführen und aus Original-String ausblenden
    final sortedSpans = List<_Span>.from(spans)..sort((a, b) => a.start.compareTo(b.start));
    final merged = <_Span>[];
    for (final s in sortedSpans) {
      if (merged.isEmpty) {
        merged.add(s);
      } else {
        final last = merged.last;
        if (s.start <= last.end + 1) {
          merged[merged.length - 1] = _Span(last.start, s.end > last.end ? s.end : last.end);
        } else {
          merged.add(s);
        }
      }
    }

    final parts = <String>[];
    int cursor = 0;
    for (final s in merged) {
      if (s.start > cursor) parts.add(original.substring(cursor, s.start));
      cursor = s.end;
    }
    if (cursor < original.length) parts.add(original.substring(cursor));

    String title = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    // Edge-Filler iterativ entfernen
    title = _stripEdgeFiller(title);

    // Kernaufgaben-Extraktion
    title = _extractCoreTask(title);

    // Großschreibung ersten Buchstaben sichern (STT-Schreibung aus Original bleibt)
    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    }
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

  // ── Explizite Uhrzeit erkennen ───────────────────────────────────────────────
  // Reihenfolge: spezifischste Muster zuerst — verhindert Partial-Matches.
  static _TimeResult? _parseClockTime(String w) {
    // Zeitspanne: "von 9 bis 11 Uhr"
    final vonBis = RegExp(
      r'\bvon\s+(\d{1,2})(?:[:.h](\d{2}))?\s*(?:uhr)?\s+bis\s+(\d{1,2})(?:[:.h](\d{2}))?\s*(?:uhr)?\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (vonBis != null) {
      final h1 = int.tryParse(vonBis.group(1) ?? '');
      if (h1 == null) return null;
      final m1 = int.tryParse(vonBis.group(2) ?? '0') ?? 0;
      final h2 = int.tryParse(vonBis.group(3) ?? '');
      if (h2 == null) return null;
      final m2 = int.tryParse(vonBis.group(4) ?? '0') ?? 0;
      return _TimeResult(_ph(h1), m1, _Span(vonBis.start, vonBis.end), endHour: _ph(h2), endMinute: m2);
    }

    // "um HH:MM Uhr" / "um HH.MM"
    final umHHMM = RegExp(r'\bum\s+(\d{1,2})[:.h](\d{2})\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
    if (umHHMM != null) return _tr(_ph(int.parse(umHHMM.group(1)!)), int.parse(umHHMM.group(2)!), umHHMM);

    // "um 8 Uhr 30"
    final umUhrMM = RegExp(r'\bum\s+(\d{1,2})\s+uhr\s+(\d{2})\b', caseSensitive: false).firstMatch(w);
    if (umUhrMM != null) return _tr(_ph(int.parse(umUhrMM.group(1)!)), int.parse(umUhrMM.group(2)!), umUhrMM);

    // "um 14 Uhr"
    final umUhr = RegExp(r'\bum\s+(\d{1,2})\s*uhr\b', caseSensitive: false).firstMatch(w);
    if (umUhr != null) return _tr(_ph(int.parse(umUhr.group(1)!)), 0, umUhr);

    // "um 14" (ohne Uhr — nur wenn isoliert, nicht Teil von "um 14 Stück" etc.)
    final umBare = RegExp(r'\bum\s+(\d{1,2})\b(?!\s*(?:stück|mal|euro|uhr\s+\d))', caseSensitive: false).firstMatch(w);
    if (umBare != null) return _tr(_ph(int.parse(umBare.group(1)!)), 0, umBare);

    // "gegen 14 Uhr" / "gegen 10"
    final gegen = RegExp(r'\bgegen\s+(\d{1,2})(?:[:.h](\d{2}))?\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
    if (gegen != null) return _tr(_ph(int.parse(gegen.group(1)!)), int.tryParse(gegen.group(2) ?? '0') ?? 0, gegen);

    // "punkt 14" / "genau 14 Uhr"
    final punkt = RegExp(r'\b(?:punkt|genau)\s+(\d{1,2})(?:[:.h](\d{2}))?\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
    if (punkt != null) return _tr(_ph(int.parse(punkt.group(1)!)), int.tryParse(punkt.group(2) ?? '0') ?? 0, punkt);

    // "halb 3" → 2:30
    final halb = RegExp(r'\bhalb\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (halb != null) return _tr(_ph(int.parse(halb.group(1)!) - 1), 30, halb);

    // "dreiviertel 10" → 9:45
    final dreiV = RegExp(r'\bdreiviertel\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (dreiV != null) return _tr(_ph(int.parse(dreiV.group(1)!) - 1), 45, dreiV);

    // "viertel nach 9" → 9:15
    final viertelN = RegExp(r'\bviertel\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (viertelN != null) return _tr(_ph(int.parse(viertelN.group(1)!)), 15, viertelN);

    // "viertel vor 10" → 9:45
    final viertelV = RegExp(r'\bviertel\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (viertelV != null) {
      final h = _ph(int.parse(viertelV.group(1)!)) - 1;
      return _tr(h < 0 ? 23 : h, 45, viertelV);
    }

    // "kurz nach 10" → 10:05
    final kurzN = RegExp(r'\bkurz\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (kurzN != null) return _tr(_ph(int.parse(kurzN.group(1)!)), 5, kurzN);

    // "kurz vor 10" → 9:55
    final kurzV = RegExp(r'\bkurz\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(w);
    if (kurzV != null) {
      final h = _ph(int.parse(kurzV.group(1)!)) - 1;
      return _tr(h < 0 ? 23 : h, 55, kurzV);
    }

    // "14:30 Uhr" / "14.30"
    final hhmm = RegExp(r'\b(\d{1,2})[:.h](\d{2})\s*(?:uhr)?\b', caseSensitive: false).firstMatch(w);
    if (hhmm != null) return _tr(_ph(int.parse(hhmm.group(1)!)), int.parse(hhmm.group(2)!), hhmm);

    // "8 Uhr 30"
    final hUhrMM = RegExp(r'\b(\d{1,2})\s+uhr\s+(\d{2})\b', caseSensitive: false).firstMatch(w);
    if (hUhrMM != null) return _tr(_ph(int.parse(hUhrMM.group(1)!)), int.parse(hUhrMM.group(2)!), hUhrMM);

    // "14 Uhr"
    final hUhr = RegExp(r'\b(\d{1,2})\s*uhr\b', caseSensitive: false).firstMatch(w);
    if (hUhr != null) return _tr(_ph(int.parse(hUhr.group(1)!)), 0, hUhr);

    return null;
  }

  // ── Tageszeit-Wörter erkennen ────────────────────────────────────────────────
  // "morgen" allein = Datum. "morgen Abend", "Dienstag morgen" = Tageszeit.
  static _TimeResult? _parseTimeOfDay(String w) {
    // Kombinationen: "X morgen/abend/mittag/…"
    const dayWords = r'(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|heute|morgen|übermorgen)';

    final combos = <(String, int, int)>[
      (r'früh\s*morgens?|morgens?\s*früh', 7, 0),
      ('$dayWords\\s+(?:morgen[s]?|früh)', 8, 0),
      ('$dayWords\\s+mittags?', 12, 0),
      ('$dayWords\\s+nachmittags?', 15, 0),
      ('$dayWords\\s+abends?', 19, 0),
      ('$dayWords\\s+(?:nacht|nachts)', 21, 0),
    ];
    for (final (pat, h, mi) in combos) {
      final m = RegExp('\\b($pat)\\b', caseSensitive: false).firstMatch(w);
      if (m != null) return _TimeResult(h, mi, _Span(m.start, m.end));
    }

    // Standalone — "morgen" allein wird NICHT erkannt (ist Datum-Wort)
    final standalone = <(String, int, int)>[
      (r'morgens', 8, 0), // "morgens" mit s = Tageszeit
      (r'vormittags?', 10, 0),
      (r'mittags?', 12, 0),
      (r'nachmittags?', 15, 0),
      (r'abends?', 19, 0),
      (r'nachts?', 21, 0),
      (r'mitternacht', 0, 0),
      (r'früh', 8, 0),
    ];
    for (final (pat, h, mi) in standalone) {
      final m = RegExp('\\b$pat\\b', caseSensitive: false).firstMatch(w);
      if (m != null) return _TimeResult(h, mi, _Span(m.start, m.end));
    }

    return null;
  }

  // ── Kernaufgabe aus Titel-Rest extrahieren ───────────────────────────────────
  static String _extractCoreTask(String raw) {
    String t = raw.trim();

    // "das Auto zum TÜV zu bringen" → "Auto zum TÜV bringen"
    // (greift in der Praxis selten, weil der Edge-Filler den führenden
    // Artikel meist schon vorher entfernt hat — bleibt als Sicherheitsnetz
    // für den Fall, dass der Edge-Filler NICHT vorher lief.)
    final infConstr = RegExp(
      r'^(?:den|die|das|einen?|meine[nm]?|meiner|mein)\s+(.+?)\s+zu\s+(\w+(?:en|ern|eln))\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (infConstr != null) {
      t = '${infConstr.group(1)} ${infConstr.group(2)}';
      if (t.isNotEmpty) t = t[0].toUpperCase() + t.substring(1);
      return t.trim();
    }

    // Artikel am Anfang entfernen
    t = t.replaceFirst(RegExp(r'^(?:den|die|das|einen?|meine[nm]?|meiner|mein)\s+', caseSensitive: false), '');

    // "noch" am Anfang
    t = t.replaceFirst(RegExp(r'^noch\s+', caseSensitive: false), '');

    // "aufzugeben", "abzuholen" etc. → "aufgeben", "abholen"
    t = t.replaceAllMapped(
      RegExp(r'\b(\w{1,6})zu(\w+(?:en|ern|eln))\b', caseSensitive: false),
      (m) => '${m.group(1)}${m.group(2)}',
    );

    // FIX 1: replaceFirst() akzeptiert in Dart keine Callback-Funktion als
    // Ersatz-Parameter — dafür gibt es replaceFirstMapped(). Beide Stellen
    // unten waren vorher fälschlich als replaceFirst(...) geschrieben.

    // "zu kaufen" am Ende → "kaufen"
    t = t.replaceFirstMapped(
      RegExp(r'\bzu\s+(\w+(?:en|ern|eln))\s*$', caseSensitive: false),
      (m) => m.group(1) ?? '',
    );

    // "Infinitiv mit zu" am Ende: "Kühlschrank zu reinigen" → "Kühlschrank reinigen"
    // (Sicherheitsnetz, falls obiger Schritt aus irgendeinem Grund nicht griff.)
    t = t.replaceFirstMapped(
      RegExp(r'\s+zu\s+(\w+(?:en|ern|eln))\s*$', caseSensitive: false),
      (m) => ' ${m.group(1)}',
    );

    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  // ── Edge-Filler Strip ────────────────────────────────────────────────────────
  static String _stripEdgeFiller(String t) {
    bool changed = true;
    while (changed) {
      changed = false;
      for (final rx in _edgeStart) {
        final n = t.replaceFirst(rx, '').trim();
        if (n != t) {
          t = n;
          changed = true;
        }
      }
      for (final rx in _edgeEnd) {
        final n = t.replaceFirst(rx, '').trim();
        if (n != t) {
          t = n;
          changed = true;
        }
      }
    }
    return t;
  }

  // ── Hilfsfunktionen ─────────────────────────────────────────────────────────
  /// Konvertiert kleine Stundenangaben (1–7) → nachmittags (13–19).
  static int _ph(int h) => (h >= 1 && h <= 7) ? h + 12 : h;

  static _TimeResult _tr(int h, int mi, RegExpMatch m) => _TimeResult(h, mi, _Span(m.start, m.end));
}