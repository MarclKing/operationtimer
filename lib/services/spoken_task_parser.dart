// ─────────────────────────────────────────────────────────────────────────────
// SPOKEN TASK PARSER v6 — Robuste Phrasen + Intelligente Kern-Extraktion
//
// Verbesserungen gegenüber v5:
//   1. Erweiterte Trigger-Phrasen für alle gängigen Formulierungen:
//      "Erinnere mich (daran) [morgen um 14:30] an/dass ...",
//      "Füge/Ergänze/Trage ... ein", "Trage für [Datum] X ein"
//   2. Datum/Uhrzeit-Erkennung ist satzbau-unabhängig — funktioniert auch
//      wenn "für den 24. um 15 Uhr" mit Füllwörtern umgeben ist.
//   3. Intelligentere Titel-Bereinigung: "auto zu waschen" → "Autowaschen",
//      "Martin schreiben" bleibt "Martin schreiben" (kein falsches Kürzen).
//   4. Komposita-Zusammensetzung für typische Verb+Objekt-Paare.
//   5. Zuverlässiger Strip von Zwischen-Präpositionen ("für", "an", "um")
//      die zum Datum/Uhrzeit-Fragment gehören, nicht zum Task-Titel.
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
  const _TimeResult(this.hour, this.minute, this.span,
      {this.endHour, this.endMinute});
}

// ─────────────────────────────────────────────────────────────────────────────

class SpokenTaskParser {
  SpokenTaskParser._();

  // ── Zahlwörter ──────────────────────────────────────────────────────────────
  static final Map<String, int> _numberWords = _buildNumberWords();

  static Map<String, int> _buildNumberWords() {
    final ones = {
      'null': 0,
      'ein': 1,
      'eins': 1,
      'eine': 1,
      'zwei': 2,
      'drei': 3,
      'vier': 4,
      'fünf': 5,
      'sechs': 6,
      'sieben': 7,
      'acht': 8,
      'neun': 9,
      'zehn': 10,
      'elf': 11,
      'zwölf': 12,
      'dreizehn': 13,
      'vierzehn': 14,
      'fünfzehn': 15,
      'sechzehn': 16,
      'siebzehn': 17,
      'achtzehn': 18,
      'neunzehn': 19,
    };
    final tens = {
      'zwanzig': 20,
      'dreißig': 30,
      'vierzig': 40,
      'fünfzig': 50,
    };
    final onesForCompound = {
      1: 'ein',
      2: 'zwei',
      3: 'drei',
      4: 'vier',
      5: 'fünf',
      6: 'sechs',
      7: 'sieben',
      8: 'acht',
      9: 'neun',
    };
    final words = <String, int>{};
    words.addAll(ones);
    for (final entry in tens.entries) {
      words[entry.key] = entry.value;
      for (final val in onesForCompound.keys) {
        final ow = onesForCompound[val]!;
        words['$ow${entry.key}'] = entry.value + val;
        words['${ow}und${entry.key}'] = entry.value + val;
      }
    }
    return words;
  }

  static int? _toNum(String token) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(t)) return int.parse(t);
    return _numberWords[t];
  }

  static String get _numTok {
    final keys = _numberWords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return r'\d{1,2}|' + keys.map(RegExp.escape).join('|');
  }

  // ── Wochentage ──────────────────────────────────────────────────────────────
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
  // WICHTIG: Reihenfolge zählt — spezifischere Patterns zuerst!
  // Jede Phrase schneidet nur den Befehlsteil weg, NICHT Datum/Zeit.
  // Datum/Zeit wird separat über Spans entfernt, nicht per Trigger.
  static final List<RegExp> _triggers = [
    // ── "Erinnere mich"-Gruppe ──
    // "erinnere mich [morgen] [um 14 Uhr] [daran|bitte] an/dass ..."
    RegExp(
      r'^erinnere\s+mich\s+'
      r'(?:daran[,\s]+)?'
      r'(?:bitte\s+)?',
      caseSensitive: false,
    ),
    // "kannst du mich [daran] erinnern [,] [bitte] [an|zu|dass] ..."
    RegExp(
      r'^kannst\s+du\s+mich\s+(?:daran\s+)?erinnern[,\s]*(?:bitte\s+)?'
      r'(?:an\s+(?:den\s+|die\s+|das\s+)?|zu\s+|dass\s+)?',
      caseSensitive: false,
    ),
    // "ich brauche eine erinnerung [an|für|dass] ..."
    RegExp(
      r'^ich\s+brauche\s+eine\s+erinnerung\s+'
      r'(?:an\s+(?:den\s+|die\s+|das\s+|meine[nm]?\s+)?|für\s+|dass\s+)?',
      caseSensitive: false,
    ),
    // "setz/stell/leg mir eine erinnerung [für|an|auf] ..."
    RegExp(r'^(?:setz|stell|leg)\s+(?:mir\s+)?eine?\s+erinnerung\s+(?:für\s+|an\s+|auf\s+)?', caseSensitive: false),

    // ── "Füge/Ergänze/Trage ein"-Gruppe ──
    // "füge die aufgabe X ein" / "füge X als aufgabe ein"
    RegExp(
      r'^(?:füg|füge)\s+'
      r'(?:(?:die|eine?|meine)\s+)?'
      r'(?:aufgabe|todo|task|erinnerung)?\s*'
      r'(?:für\s+)?',
      caseSensitive: false,
    ),
    // "ergänze die aufgabe X" / "ergänze X"
    RegExp(
      r'^ergänze\s+'
      r'(?:(?:die|eine?)\s+)?'
      r'(?:aufgabe|todo|task)?\s*',
      caseSensitive: false,
    ),
    // "trage [für mich] [die aufgabe] X ein"
    RegExp(
      r'^trage?\s+'
      r'(?:(?:für\s+mich|mir)\s+)?'
      r'(?:(?:die|eine?)\s+)?'
      r'(?:aufgabe|todo|task|erinnerung)?\s*'
      r'(?:für\s+)?',
      caseSensitive: false,
    ),
    // "trag ein: X" / "trag mir ein dass ..."
    RegExp(r'^trag\s+(?:mir\s+)?ein[:\s]*(?:dass\s+)?', caseSensitive: false),
    // "hinzufügen: X" / "füge ... hinzu"
    RegExp(r'^hinzufügen[:\s]*', caseSensitive: false),
    // "neue aufgabe: X" / "neuer task ..."
    RegExp(r'^neue?\s+(?:aufgabe|todo|task|erinnerung)\s*(?:anlegen\s+)?[:\s]*(?:für\s+)?', caseSensitive: false),
    // "erstell/erzeuge/mach [mir] [eine] [neue] aufgabe [für] ..."
    RegExp(
      r'^(?:erstell|erzeuge|mach)\s+(?:mir\s+)?(?:eine?\s+)?(?:neue?\s+)?'
      r'(?:aufgabe|todo|task|eintrag)\s*(?:für\s+|dass\s+)?',
      caseSensitive: false,
    ),

    // ── "Notiz/Selbstgespräch"-Gruppe ──
    RegExp(r'^(?:notiere|notier)\s+(?:dir\s+|bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:schreib|schreibe)\s+(?:dir\s+|bitte\s+)?(?:das\s+)?auf[:\s]*(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:schreib|schreibe)\s+(?:auf\s+)?(?:bitte\s+)?(?:dass\s+|folgendes[:\s]+)?', caseSensitive: false),
    RegExp(r'^(?:halt|halte)\s+(?:das\s+|es\s+)?fest[:\s]*(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^merk\s+dir\s+(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^(?:speicher|speichere)\s+(?:das\s+|bitte\s+)?(?:ab\s*)?[:\s]*(?:dass\s+)?', caseSensitive: false),

    // ── Selbstgespräch ──
    RegExp(r'^ich\s+(?:muss|müss?te|sollte|will|möchte|wollte)\s+(?:noch\s+|unbedingt\s+|dringend\s+)?', caseSensitive: false),
    RegExp(r'^nicht\s+vergessen[:\s]*(?:dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^vergiss\s+nicht[,\s]*(?:bitte\s+)?(?:dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^auf\s+keinen\s+fall\s+vergessen[:\s]*(?:zu\s+)?', caseSensitive: false),
    RegExp(r'^denk\s+(?:daran|dran)[,\s]*(?:bitte\s+)?(?:dass\s+|zu\s+)?', caseSensitive: false),
    RegExp(r'^daran\s+denken[:\s]*(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^das\s+darf\s+ich\s+nicht\s+vergessen[:\s]*(?:zu\s+)?', caseSensitive: false),
    RegExp(r'^unbedingt\s+(?:noch\s+|dringend\s+)?', caseSensitive: false),

    // ── App/Assistent ──
    RegExp(r'^(?:hey\s+)?app[,:]?\s*(?:bitte\s+)?', caseSensitive: false),
    RegExp(r'^(?:ok|okay|hey)\s+(?:google|siri|alexa|app)[,:]?\s*(?:bitte\s+)?', caseSensitive: false),
    RegExp(r'^(?:bitte\s+)?(?:trag\s+ein|notier|merk|erinner\s+mich)\s*[,:]?\s*(?:dass\s+|zu\s+|an\s+(?:den\s+|die\s+|das\s+)?)?', caseSensitive: false),

    // ── Termin/Kalender ──
    RegExp(r'^(?:trag|block|reservier)\s+(?:mir\s+)?(?:den\s+|einen?\s+)?(?:termin|slot|zeitraum|zeit|tag|abend)\s+ein\s+(?:für\s+|am\s+)?', caseSensitive: false),
    RegExp(r'^termin\s*[:\-]?\s*', caseSensitive: false),

    // ── Kurzform ──
    RegExp(r'^todo[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^aufgabe[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^notiz[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^task[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^reminder[:\s]*(?:bitte\s+)?(?:dass\s+)?', caseSensitive: false),
  ];

  // ── Post-Trigger: Datum/Zeit-einleitende Phrasen die dem Trigger folgen ──
  // z.B. "erinnere mich [morgen um 14 Uhr] an mein Auto zu waschen"
  // Das Datum/Zeit wird via Spans entfernt. Aber "an" als Brücke zum Task
  // muss ebenfalls wegfallen. Diese Patterns matchen am ANFANG des
  // verbleibenden Strings nach Trigger-Strip (nach Datum/Uhrzeit-Entfernung).
  static final List<RegExp> _postDateBridge = [
    RegExp(r'^an\s+(?:den\s+|die\s+|das\s+|meine[nm]?\s+|meinen?\s+)?', caseSensitive: false),
    RegExp(r'^an\s+', caseSensitive: false),
    RegExp(r'^dass\s+ich\s+', caseSensitive: false),
    RegExp(r'^dass\s+', caseSensitive: false),
    RegExp(r'^daran[,\s]+(?:dass\s+)?', caseSensitive: false),
    RegExp(r'^zu\s+(?:dem|der|den)\s+', caseSensitive: false),
    RegExp(r'^zum\s+', caseSensitive: false),
    RegExp(r'^zur\s+', caseSensitive: false),
    RegExp(r'^für\s+(?:den\s+|die\s+|das\s+|mein\w*\s+)?', caseSensitive: false),
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
  static String get _durationNumTok => _numTok;
  static final RegExp _durationRx = RegExp(
    r'\b(?:für|ca\.?|circa|etwa|ungefähr)\s+(\d{1,2}(?:[.,]\d)?)\s*(stunden?|std\.?|h\b|minuten?|min\.?)\b',
    caseSensitive: false,
  );

  // ── Edge-Filler (iterativer Strip am Rand des Titels) ──────────────────────
  static final List<RegExp> _edgeStart = [
    RegExp(r'^an\s+(?:den|die|das|dem|einen?|meine[nm]?|meinem|meiner)\s+', caseSensitive: false),
    RegExp(r'^an\s+', caseSensitive: false),
    RegExp(r'^daran[,\s]+', caseSensitive: false),
    RegExp(r'^dran[,\s]+', caseSensitive: false),
    RegExp(r'^zu\s+(?:dem|der|den)\s+', caseSensitive: false),
    RegExp(r'^zum\s+', caseSensitive: false),
    RegExp(r'^zur\s+', caseSensitive: false),
    RegExp(r'^dass\s+(?:ich\s+)?', caseSensitive: false),
    RegExp(r'^(?:bitte\s+)+', caseSensitive: false),
    RegExp(r'^(?:noch\s*[:\-]?\s*)+', caseSensitive: false),
    RegExp(r'^(?:mal\s+)+', caseSensitive: false),
    RegExp(r'^den\s+', caseSensitive: false),
    RegExp(r'^die\s+', caseSensitive: false),
    RegExp(r'^das\s+', caseSensitive: false),
    RegExp(r'^einen?\s+', caseSensitive: false),
    RegExp(r'^für\s+(?:den|die|das|mich|mein\w+)\s+', caseSensitive: false),
    RegExp(r'^um\s+', caseSensitive: false),
  ];
  static final List<RegExp> _edgeEnd = [
    RegExp(r'\s+(?:daran|dran|bitte|dass|an|ein|hinzufügen)$', caseSensitive: false),
    RegExp(r'\s*[.,!?]\s*$'),
    // Trennbares "ein" am Ende (von "eintragen", "einzufügen" etc.)
    RegExp(r'\s+ein\s*$', caseSensitive: false),
  ];

  // ── Komposita-Normalisierung: "auto zu waschen" → "Autowaschen" ──────────────
  // Bekannte Verb+Objekt-Paare, die als Kompositum geschrieben werden sollten.
  // Weitere Paare können einfach ergänzt werden.
  static final List<(RegExp, String)> _compositaRules = [
    (RegExp(r'^auto\s+(?:zu\s+)?waschen$', caseSensitive: false), 'Autowaschen'),
    (RegExp(r'^auto\s+(?:zu\s+)?tanken$', caseSensitive: false), 'Tanken'),
    (RegExp(r'^auto\s+(?:zu\s+)?reinigen$', caseSensitive: false), 'Auto reinigen'),
    (RegExp(r'^(?:zum\s+)?zahnarzt\s+(?:zu\s+)?(?:gehen|termin)$', caseSensitive: false), 'Zahnarzt'),
    (RegExp(r'^(?:zum\s+)?arzt\s+(?:zu\s+)?(?:gehen|termin)$', caseSensitive: false), 'Arzttermin'),
    (RegExp(r'^einkaufen\s+(?:zu\s+)?gehen$', caseSensitive: false), 'Einkaufen'),
    (RegExp(r'^sport\s+(?:zu\s+)?machen$', caseSensitive: false), 'Sport machen'),
    (RegExp(r'^hausaufgaben\s+(?:zu\s+)?machen$', caseSensitive: false), 'Hausaufgaben'),
    (RegExp(r'^müll\s+(?:raus)?(?:zu\s+)?(?:bringen|tragen)$', caseSensitive: false), 'Müll rausbringen'),
    (RegExp(r'^wäsche\s+(?:zu\s+)?(?:waschen|machen)$', caseSensitive: false), 'Wäsche waschen'),
    (RegExp(r'^steuererklärung\s+(?:zu\s+)?machen$', caseSensitive: false), 'Steuererklärung'),
  ];

  // ────────────────────────────────────────────────────────────────────────────
  // HAUPTFUNKTION
  // ────────────────────────────────────────────────────────────────────────────
  static ParsedSpokenTask parse(String rawText) {
    final original = rawText.trim();
    final w = original.toLowerCase();
    final spans = <_Span>[];

    // ══ 1) TRIGGER ══════════════════════════════════════════════════════════
    _Span? triggerSpan;
    for (final rx in _triggers) {
      final m = rx.firstMatch(w);
      if (m != null) {
        triggerSpan = _Span(0, m.end);
        spans.add(triggerSpan);
        break;
      }
    }

    // ══ 2) PRIORITÄT ════════════════════════════════════════════════════════
    final priority =
        _priorityRx.hasMatch(w) ? TaskPriority.urgent : TaskPriority.normal;
    if (priority == TaskPriority.urgent) {
      for (final m in _priorityRx.allMatches(w)) {
        spans.add(_Span(m.start, m.end));
      }
    }

    // ══ 3) DAUER ════════════════════════════════════════════════════════════
    Duration? estimatedDuration;
    final durM = _durationRx.firstMatch(w);
    if (durM != null) {
      final amount =
          double.tryParse((durM.group(1) ?? '').replaceAll(',', '.')) ?? 0;
      final unit = (durM.group(2) ?? '').toLowerCase();
      estimatedDuration =
          unit.startsWith('h') || unit.startsWith('std') || unit.startsWith('stu')
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
        final m =
            RegExp('\\bjeden\\s+${e.key}\\b', caseSensitive: false).firstMatch(w);
        if (m != null) {
          recurrence =
              RecurrenceRule(RecurrenceFrequency.weekly, weekday: e.value);
          spans.add(_Span(m.start, m.end));
          break;
        }
      }
    }

    // ══ 5) DATUM ════════════════════════════════════════════════════════════
    DateTime? date;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 5a) Explizit mit Monatsname: "am 15. März 2026" / "den 15. März"
    final expMonthM = RegExp(
      r'(?:(?:am|den|für\s+den|zum)\s+)?($numTok)\.?\s*(januar|jänner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan\.?|feb\.?|mär\.?|apr\.?|jun\.?|jul\.?|aug\.?|sep\.?|sept\.?|okt\.?|nov\.?|dez\.?)\s*\.?\s*(\d{4})?',
      caseSensitive: false,
    ).firstMatch(w);

    // 5b) Explizit numerisch: "am 15.3." / "15.3.2026" / "den 24."
    final expDateM = RegExp(
            r'(?:(?:am|den|für\s+den|zum)\s+)?($numTok)\.\s*($numTok)\.?\s*(\d{4})?')
        .firstMatch(w);

    // 5c) Nur Tag-Zahl: "den 24." (ohne Monat) → aktueller Monat
    final onlyDayM = RegExp(r'\b(?:den|am|für\s+den|zum)\s+(\d{1,2})\.\b')
        .firstMatch(w);

    if (expMonthM != null) {
      final day = _toNum(expMonthM.group(1) ?? '');
      final rawM =
          (expMonthM.group(2) ?? '').replaceAll('.', '').trim().toLowerCase();
      final month = _months[rawM];
      final year = int.tryParse(expMonthM.group(3) ?? '') ?? now.year;
      if (day != null && month != null) {
        var d = DateTime(year, month, day);
        // Wenn das Datum schon vorbei ist und kein Jahr angegeben: nächstes Jahr
        if (d.isBefore(today) && expMonthM.group(3) == null) {
          d = DateTime(year + 1, month, day);
        }
        date = d;
        spans.add(_Span(expMonthM.start, expMonthM.end));
      }
    } else if (expDateM != null && expDateM.group(2) != null) {
      final day = _toNum(expDateM.group(1) ?? '');
      final month = _toNum(expDateM.group(2) ?? '');
      final year = int.tryParse(expDateM.group(3) ?? '') ?? now.year;
      if (day != null && month != null && month >= 1 && month <= 12) {
        var d = DateTime(year, month, day);
        if (d.isBefore(today) && expDateM.group(3) == null) {
          d = DateTime(year + 1, month, day);
        }
        date = d;
        spans.add(_Span(expDateM.start, expDateM.end));
      }
    } else if (onlyDayM != null) {
      final day = int.tryParse(onlyDayM.group(1) ?? '');
      if (day != null && day >= 1 && day <= 31) {
        var d = DateTime(now.year, now.month, day);
        if (d.isBefore(today)) d = DateTime(now.year, now.month + 1, day);
        date = d;
        spans.add(_Span(onlyDayM.start, onlyDayM.end));
      }
    }

    // 5d) Relative Tagesangaben
    if (date == null) {
      final relPatterns = <(RegExp, DateTime)>[
        (RegExp(r'\bübermorgen\b', caseSensitive: false),
            today.add(const Duration(days: 2))),
        (RegExp(r'\bmorgen\s+früh\b', caseSensitive: false),
            today.add(const Duration(days: 1))),
        (RegExp(r'\bmorgen\b', caseSensitive: false),
            today.add(const Duration(days: 1))),
        (RegExp(r'\bheute\s+(?:abend|nacht)\b', caseSensitive: false), today),
        (RegExp(r'\bheute\b', caseSensitive: false), today),
        (
          RegExp(r'\bnächste\s+woche\b', caseSensitive: false),
          today.add(Duration(days: 8 - today.weekday))
        ),
        (
          RegExp(r'\b(?:dieses\s+wochenende|am\s+wochenende)\b',
              caseSensitive: false),
          () {
            int d = (DateTime.saturday - today.weekday) % 7;
            return today.add(Duration(days: d == 0 ? 7 : d));
          }()
        ),
        (
          RegExp(r'\bende\s+(?:des|diesen|dieses)\s+monats?\b',
              caseSensitive: false),
          DateTime(now.year, now.month + 1, 0)
        ),
        (
          RegExp(r'\banfang\s+nächster\s+woche\b', caseSensitive: false),
          () {
            final daysUntilMonday =
                (DateTime.monday - now.weekday).clamp(0, 6);
            return today.add(Duration(days: daysUntilMonday + 7));
          }()
        ),
        // "in der nächsten woche" synonym
        (
          RegExp(r'\bin\s+der\s+nächsten\s+woche\b', caseSensitive: false),
          today.add(Duration(days: 8 - today.weekday))
        ),
        // kommenden X
        ..._weekdays.keys.map((day) {
          final targetWeekday = _weekdays[day]!;
          return (
            RegExp(r'\bkommenden\s+' + day + r'\b', caseSensitive: false),
            () {
              var daysUntil = targetWeekday - today.weekday;
              if (daysUntil <= 0) daysUntil += 7;
              return today.add(Duration(days: daysUntil + 7));
            }()
          );
        }),
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

    // 5e) "in X Tagen/Wochen/Monaten"
    if (date == null) {
      final numTokStr = _numTok;
      final inDaysM =
          RegExp(r'\bin\s+($numTok)\s+tagen?\b', caseSensitive: false)
              .firstMatch(w);
      final inWeeksM =
          RegExp(r'\bin\s+(einer|$numTokStr)\s+woch\w+\b', caseSensitive: false)
              .firstMatch(w);
      final inMonsM =
          RegExp(r'\bin\s+(einem?|$numTokStr)\s+monat\w*\b', caseSensitive: false)
              .firstMatch(w);
      if (inDaysM != null) {
        final d = _toNum(inDaysM.group(1) ?? '');
        if (d != null) {
          date = today.add(Duration(days: d));
          spans.add(_Span(inDaysM.start, inDaysM.end));
        }
      } else if (inWeeksM != null) {
        final raw = inWeeksM.group(1) ?? '1';
        final weeks = raw == 'einer' ? 1 : (_toNum(raw) ?? 1);
        date = today.add(Duration(days: weeks * 7));
        spans.add(_Span(inWeeksM.start, inWeeksM.end));
      } else if (inMonsM != null) {
        final raw = inMonsM.group(1) ?? '1';
        final months = raw.startsWith('ein') ? 1 : (_toNum(raw) ?? 1);
        date = DateTime(today.year, today.month + months, today.day);
        spans.add(_Span(inMonsM.start, inMonsM.end));
      }
    }

    // 5f) Wochentage: "nächsten/kommenden/am Dienstag" / einfach "Freitag"
    if (date == null) {
      for (final e in _weekdays.entries) {
        final rx = RegExp(
          '\\b((?:nächste[nm]?|naechste[nm]?|diesen|am|kommende[nm]?|für\s+(?:den\s+)?)?\\s*)?${e.key}\\b',
          caseSensitive: false,
        );
        final m = rx.firstMatch(w);
        if (m != null) {
          final qualifier = (m.group(1) ?? '').toLowerCase().trim();
          final forceNext = qualifier.contains('nächst') ||
              qualifier.contains('naechst') ||
              qualifier.contains('kommend');
          int diff = (e.value - today.weekday) % 7;
          if (diff == 0 && forceNext) diff = 7;
          // Ohne Qualifier: wenn der Tag schon heute ist → nächste Woche
          if (diff == 0 && qualifier.isEmpty) diff = 7;
          if (diff < 0) diff += 7;
          date = today.add(Duration(days: diff));
          spans.add(_Span(m.start, m.end));
          break;
        }
      }
    }

    // ══ 6) UHRZEIT ══════════════════════════════════════════════════════════
    DateTimeComponents? time;
    DateTimeComponents? endTime;

    final clkResult = _parseClockTime(w);
    if (clkResult != null) {
      time = DateTimeComponents(
          clkResult.hour.clamp(0, 23), clkResult.minute.clamp(0, 59));
      spans.add(clkResult.span);
      if (clkResult.endHour != null) {
        endTime = DateTimeComponents(clkResult.endHour!.clamp(0, 23),
            clkResult.endMinute!.clamp(0, 59));
      }
    }

    if (time == null) {
      final todResult = _parseTimeOfDay(w);
      if (todResult != null) {
        time = DateTimeComponents(
            todResult.hour.clamp(0, 23), todResult.minute.clamp(0, 59));
        spans.add(todResult.span);
      }
    }

    // ══ 7) PRÄPOSITIONS-BRÜCKEN vor Datum/Zeit entfernen ═══════════════════
    // Wenn direkt vor einem Datum-Span ein "für", "am", "den" steht
    // (das nicht schon zum Trigger gehört), fügen wir diesen Bereich
    // ebenfalls als Span ein, damit er aus dem Titel verschwindet.
    _addPrepositionSpans(w, spans);

    // ══ 8) TITEL AUFBAUEN ═══════════════════════════════════════════════════
    final sortedSpans = List<_Span>.from(spans)
      ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <_Span>[];
    for (final s in sortedSpans) {
      if (merged.isEmpty) {
        merged.add(s);
      } else {
        final last = merged.last;
        if (s.start <= last.end + 1) {
          merged[merged.length - 1] =
              _Span(last.start, s.end > last.end ? s.end : last.end);
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

    // Post-Date-Bridge entfernen (Brückenworte nach Datum-Entfernung)
    title = _stripPostDateBridge(title);

    // Edge-Filler iterativ entfernen
    title = _stripEdgeFiller(title);

    // Kernaufgaben-Extraktion
    title = _extractCoreTask(title);

    // Kompositum-Normalisierung
    title = _normalizeComposita(title);

    // Ersten Buchstaben großschreiben
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

  // ── Präpositions-Brücken vor erkannten Spans entfernen ──────────────────────
  // Sucht nach "für", "am", "den", "um" die DIREKT (max. 1 Wort) vor einem
  // erkannten Datum/Zeit-Span stehen und noch nicht Teil eines Spans sind.
  static void _addPrepositionSpans(String w, List<_Span> spans) {
    final bridgeRx = RegExp(
      r'\b(für\s+(?:den\s+|die\s+|das\s+)?|am\s+|den\s+|zum\s+|um\s+|ab\s+|bis\s+(?:zum?\s+)?)',
      caseSensitive: false,
    );
    final toAdd = <_Span>[];
    for (final m in bridgeRx.allMatches(w)) {
      // Liegt dieser Match direkt (mit Whitespace) vor einem existierenden Span?
      final afterEnd = m.end;
      final isBeforeSpan = spans.any((s) => s.start >= afterEnd && s.start <= afterEnd + 2);
      final alreadyCovered = spans.any((s) => s.start <= m.start && s.end >= m.end);
      if (isBeforeSpan && !alreadyCovered) {
        toAdd.add(_Span(m.start, m.end));
      }
    }
    spans.addAll(toAdd);
  }

  // ── Post-Date-Bridge Strip ───────────────────────────────────────────────────
  static String _stripPostDateBridge(String t) {
    for (final rx in _postDateBridge) {
      final n = t.replaceFirst(rx, '').trim();
      if (n != t) return _stripPostDateBridge(n); // rekursiv für Ketten
    }
    return t;
  }

  // ── Kompositum-Normalisierung ────────────────────────────────────────────────
  static String _normalizeComposita(String t) {
    for (final (rx, replacement) in _compositaRules) {
      if (rx.hasMatch(t.trim())) return replacement;
    }
    return t;
  }

  // ── Explizite Uhrzeit erkennen ───────────────────────────────────────────────
  static _TimeResult? _parseClockTime(String w) {
    final numTok = _numTok;

    // Zeitspanne: "von 9 bis 11 Uhr"
    final vonBis = RegExp(
      r'\bvon\s+($numTok)(?:[:.h]($numTok))?\s*(?:uhr)?\s+bis\s+($numTok)(?:[:.h]($numTok))?\s*(?:uhr)?\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (vonBis != null) {
      final h1 = _toNum(vonBis.group(1) ?? '');
      if (h1 == null) return null;
      final m1 = _toNum(vonBis.group(2) ?? '0') ?? 0;
      final h2 = _toNum(vonBis.group(3) ?? '');
      if (h2 == null) return null;
      final m2 = _toNum(vonBis.group(4) ?? '0') ?? 0;
      return _TimeResult(_ph(h1), m1, _Span(vonBis.start, vonBis.end),
          endHour: _ph(h2), endMinute: m2);
    }

    // "um HH:MM Uhr" / "um HH.MM"
    final umHHMM = RegExp(
            r'\bum\s+($numTok)[:.h]($numTok)\s*(?:uhr)?\b',
            caseSensitive: false)
        .firstMatch(w);
    if (umHHMM != null) {
      final h = _toNum(umHHMM.group(1)!);
      final m = _toNum(umHHMM.group(2)!);
      if (h == null || m == null) return null;
      return _TimeResult(_ph(h), m, _Span(umHHMM.start, umHHMM.end));
    }

    // "um X Uhr Y" / "um 8 Uhr 30"
    final umUhrMM = RegExp(
            r'\bum\s+($numTok)\s+uhr\s+($numTok)\b',
            caseSensitive: false)
        .firstMatch(w);
    if (umUhrMM != null) {
      final h = _toNum(umUhrMM.group(1)!);
      final m = _toNum(umUhrMM.group(2)!);
      if (h == null || m == null) return null;
      return _TimeResult(_ph(h), m, _Span(umUhrMM.start, umUhrMM.end));
    }

    // "um 14 Uhr"
    final umUhr = RegExp(r'\bum\s+($numTok)\s*uhr\b', caseSensitive: false)
        .firstMatch(w);
    if (umUhr != null) {
      final h = _toNum(umUhr.group(1)!);
      if (h == null) return null;
      return _TimeResult(_ph(h), 0, _Span(umUhr.start, umUhr.end));
    }

    // "um 14" (ohne Uhr — nur wenn Zahl ≥ 7 um Fehlzuordnungen zu meiden)
    final umBare = RegExp(
            r'\bum\s+($numTok)\b(?!\s*(?:stück|mal|euro|uhr\s+\d))',
            caseSensitive: false)
        .firstMatch(w);
    if (umBare != null) {
      final h = _toNum(umBare.group(1)!);
      if (h == null) return null;
      return _TimeResult(_ph(h), 0, _Span(umBare.start, umBare.end));
    }

    // "gegen 14 Uhr" / "gegen 10"
    final gegen = RegExp(
            r'\bgegen\s+($numTok)(?:[:.h]($numTok))?\s*(?:uhr)?\b',
            caseSensitive: false)
        .firstMatch(w);
    if (gegen != null) {
      final h = _toNum(gegen.group(1)!);
      if (h == null) return null;
      final m = _toNum(gegen.group(2) ?? '0') ?? 0;
      return _TimeResult(_ph(h), m, _Span(gegen.start, gegen.end));
    }

    // "punkt 14" / "genau 14 Uhr"
    final punkt = RegExp(
            r'\b(?:punkt|genau)\s+($numTok)(?:[:.h]($numTok))?\s*(?:uhr)?\b',
            caseSensitive: false)
        .firstMatch(w);
    if (punkt != null) {
      final h = _toNum(punkt.group(1)!);
      if (h == null) return null;
      final m = _toNum(punkt.group(2) ?? '0') ?? 0;
      return _TimeResult(_ph(h), m, _Span(punkt.start, punkt.end));
    }

    // "halb 3" → 2:30
    final halb =
        RegExp(r'\bhalb\s+($numTok)\b', caseSensitive: false).firstMatch(w);
    if (halb != null) {
      final num = _toNum(halb.group(1)!);
      if (num == null) return null;
      return _TimeResult(_ph(num - 1), 30, _Span(halb.start, halb.end));
    }

    // "dreiviertel 10" → 9:45
    final dreiV =
        RegExp(r'\bdreiviertel\s+($numTok)\b', caseSensitive: false)
            .firstMatch(w);
    if (dreiV != null) {
      final num = _toNum(dreiV.group(1)!);
      if (num == null) return null;
      return _TimeResult(_ph(num - 1), 45, _Span(dreiV.start, dreiV.end));
    }

    // "viertel nach 9" → 9:15
    final viertelN =
        RegExp(r'\bviertel\s+nach\s+($numTok)\b', caseSensitive: false)
            .firstMatch(w);
    if (viertelN != null) {
      final num = _toNum(viertelN.group(1)!);
      if (num == null) return null;
      return _TimeResult(_ph(num), 15, _Span(viertelN.start, viertelN.end));
    }

    // "viertel vor 10" → 9:45
    final viertelV =
        RegExp(r'\bviertel\s+vor\s+($numTok)\b', caseSensitive: false)
            .firstMatch(w);
    if (viertelV != null) {
      final num = _toNum(viertelV.group(1)!);
      if (num == null) return null;
      final h = _ph(num) - 1;
      return _TimeResult(h < 0 ? 23 : h, 45, _Span(viertelV.start, viertelV.end));
    }

    // "kurz nach 10" → 10:05
    final kurzN =
        RegExp(r'\bkurz\s+nach\s+($numTok)\b', caseSensitive: false)
            .firstMatch(w);
    if (kurzN != null) {
      final num = _toNum(kurzN.group(1)!);
      if (num == null) return null;
      return _TimeResult(_ph(num), 5, _Span(kurzN.start, kurzN.end));
    }

    // "kurz vor 10" → 9:55
    final kurzV =
        RegExp(r'\bkurz\s+vor\s+($numTok)\b', caseSensitive: false)
            .firstMatch(w);
    if (kurzV != null) {
      final num = _toNum(kurzV.group(1)!);
      if (num == null) return null;
      final h = _ph(num) - 1;
      return _TimeResult(h < 0 ? 23 : h, 55, _Span(kurzV.start, kurzV.end));
    }

    // "14:30 Uhr" / "14.30"
    final hhmm = RegExp(r'\b($numTok)[:.h]($numTok)\s*(?:uhr)?\b',
            caseSensitive: false)
        .firstMatch(w);
    if (hhmm != null) {
      final h = _toNum(hhmm.group(1)!);
      final m = _toNum(hhmm.group(2)!);
      if (h == null || m == null) return null;
      return _TimeResult(_ph(h), m, _Span(hhmm.start, hhmm.end));
    }

    // "8 Uhr 30"
    final hUhrMM = RegExp(r'\b($numTok)\s+uhr\s+($numTok)\b',
            caseSensitive: false)
        .firstMatch(w);
    if (hUhrMM != null) {
      final h = _toNum(hUhrMM.group(1)!);
      final m = _toNum(hUhrMM.group(2)!);
      if (h == null || m == null) return null;
      return _TimeResult(_ph(h), m, _Span(hUhrMM.start, hUhrMM.end));
    }

    // "14 Uhr"
    final hUhr =
        RegExp(r'\b($numTok)\s*uhr\b', caseSensitive: false).firstMatch(w);
    if (hUhr != null) {
      final h = _toNum(hUhr.group(1)!);
      if (h == null) return null;
      return _TimeResult(_ph(h), 0, _Span(hUhr.start, hUhr.end));
    }

    return null;
  }

  // ── Tageszeit-Wörter ─────────────────────────────────────────────────────────
  static _TimeResult? _parseTimeOfDay(String w) {
    final dayWords =
        r'(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|heute|morgen|übermorgen)';
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
    final standalone = <(String, int, int)>[
      (r'morgens', 8, 0),
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

  // ── Kernaufgabe extrahieren ───────────────────────────────────────────────────
  static String _extractCoreTask(String raw) {
    String t = raw.trim();

    // "das Auto zum TÜV zu bringen" → "Auto zum TÜV bringen"
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
    t = t.replaceFirst(
        RegExp(r'^(?:den|die|das|einen?|meine[nm]?|meiner|mein)\s+',
            caseSensitive: false),
        '');

    // "noch" am Anfang
    t = t.replaceFirst(RegExp(r'^noch\s+', caseSensitive: false), '');

    // "aufzugeben", "abzuholen" etc. → "aufgeben", "abholen"
    t = t.replaceAllMapped(
      RegExp(r'\b(\w{1,6})zu(\w+(?:en|ern|eln))\b', caseSensitive: false),
      (m) => '${m.group(1)}${m.group(2)}',
    );

    // "zu kaufen" am Ende → "kaufen"
    t = t.replaceFirstMapped(
      RegExp(r'\bzu\s+(\w+(?:en|ern|eln))\s*$', caseSensitive: false),
      (m) => m.group(1) ?? '',
    );

    // "Kühlschrank zu reinigen" → "Kühlschrank reinigen"
    t = t.replaceFirstMapped(
      RegExp(r'\s+zu\s+(\w+(?:en|ern|eln))\s*$', caseSensitive: false),
      (m) => ' ${m.group(1)}',
    );

    // "hinzufügen" am Ende entfernen
    t = t.replaceFirst(RegExp(r'\s+hinzufügen\s*$', caseSensitive: false), '');
    // "eintragen" am Ende entfernen  
    t = t.replaceFirst(RegExp(r'\s+eintragen\s*$', caseSensitive: false), '');

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
  // Wandelt Uhrzeiten 1–6 in 13–18 um (nachmittags-Annahme ohne AM/PM).
  // 7–12 bleiben unverändert (Morgen/Mittag). 13–23 bleiben unverändert.
  static int _ph(int h) => (h >= 1 && h <= 6) ? h + 12 : h;
}